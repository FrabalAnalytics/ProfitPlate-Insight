-- Apply after 019. Procurement buys; Inventory confirms delivery.
-- Existing procurement assignments stay procurement-only. No automatic receiving grants.
begin;
insert into public.roles(code,name) values ('inventory','Inventory / Receiving') on conflict(code) do update set name=excluded.name;
update public.roles set name='Procurement' where code='procurement';
create or replace function private.pp_inventory_access(target_org uuid,target_location uuid default null) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisation_memberships m join public.membership_roles r
 on r.organisation_id=m.organisation_id and r.membership_id=m.id
 where m.organisation_id=target_org and m.user_id=auth.uid() and m.status='active' and r.role_code='inventory'
 and (target_location is null or r.location_id is null or r.location_id=target_location));
$$;
create or replace function private.pp_order_read(target_org uuid,target_order uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.purchase_orders o where o.organisation_id=target_org and o.id=target_order
 and (private.pp_reference_price_read(target_org) or (o.status='ISSUED' and private.pp_inventory_access(target_org,o.location_id))));
$$;
revoke all on function private.pp_inventory_access(uuid,uuid),private.pp_order_read(uuid,uuid) from public,anon,authenticated;
create or replace function public.purchase_order_access(p_organisation_id uuid,p_order_id uuid default null) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
 'read',case when p_order_id is null then private.pp_reference_price_read(p_organisation_id) or private.pp_inventory_access(p_organisation_id) else private.pp_order_read(p_organisation_id,p_order_id) end,
 'write',private.pp_purchase_write(p_organisation_id),
 'receive',exists(select 1 from public.purchase_orders o where o.organisation_id=p_organisation_id and o.id=p_order_id and o.status='ISSUED'
 and private.pp_inventory_access(p_organisation_id,o.location_id) and o.created_by<>auth.uid() and o.issued_by<>auth.uid()),
 'request_receipt_void',exists(select 1 from public.purchase_orders o where o.organisation_id=p_organisation_id and o.id=p_order_id and o.status='ISSUED' and private.pp_inventory_access(p_organisation_id,o.location_id)),
 'invoices',private.pp_reference_price_read(p_organisation_id),'approve_corrections',private.pp_finance(p_organisation_id));
$$;
revoke all on function public.purchase_order_access(uuid,uuid) from public,anon;
grant execute on function public.purchase_order_access(uuid,uuid) to authenticated;


create or replace function private.pp_team_assignments(target_org uuid, input jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if input is null or jsonb_typeof(input)<>'array' or jsonb_array_length(input) not between 1 and 20 then
  raise exception 'Choose between 1 and 20 role assignments.' using errcode='22023'; end if;
 if exists(select 1 from jsonb_array_elements(input) e where jsonb_typeof(e)<>'object'
  or coalesce(e->>'role_code','') not in ('ceo','finance','procurement','inventory','operations','restaurant_admin')
  or (e->>'location_id' is not null and not exists(select 1 from public.locations l
    where l.organisation_id=target_org and l.id::text=e->>'location_id' and l.is_active))) then
  raise exception 'Choose recognised roles and active locations in this business.' using errcode='22023'; end if;
 select jsonb_agg(v order by v->>'role_code',v->>'location_id') into result from
 (select distinct jsonb_build_object('role_code',e->>'role_code','location_id',e->>'location_id') v
  from jsonb_array_elements(input) e) s;
 return result;
end; $$;

create or replace function public.record_goods_receipt(p_organisation_id uuid,p_order_id uuid,p_request_id uuid,p_document jsonb,p_lines jsonb,p_confirmed boolean)
returns uuid language plpgsql security definer set search_path='' as $$
declare doc public.purchase_orders;prior public.goods_receipts;line jsonb;ordered public.purchase_order_lines;result uuid:=gen_random_uuid();digest text;day date;accepted numeric;rejected numeric;previous_qty numeric;seen uuid[]:='{}';
begin
 if not private.pp_inventory_access(p_organisation_id) then raise exception 'Inventory / Receiving access is required.' using errcode='42501';end if;
 if p_request_id is null or p_confirmed is distinct from true or jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) not between 1 and 50 or octet_length(p_lines::text)>65536 or length(trim(coalesce(p_document->>'delivery_reference',''))) not between 1 and 100 or length(coalesce(p_document->>'notes',''))>1000 then raise exception 'Confirm delivery and enter a delivery reference with up to 50 lines.' using errcode='22023';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into doc from public.purchase_orders where organisation_id=p_organisation_id and id=p_order_id and status='ISSUED';
 if not found then raise exception 'Choose an issued order in this business.' using errcode='42501';end if;
 if not private.pp_inventory_access(p_organisation_id,doc.location_id) then raise exception 'Receiving access is required for this delivery location.' using errcode='42501';end if;
 if doc.created_by=auth.uid() or doc.issued_by=auth.uid() then raise exception 'A different Inventory colleague must confirm delivery of an order you prepared or issued.' using errcode='42501';end if;
 digest:=md5(jsonb_build_array(p_order_id,p_document,p_lines)::text);
 select * into prior from public.goods_receipts where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then if prior.input_hash<>digest or prior.created_by<>auth.uid() then raise exception 'This delivery request was already used.' using errcode='22023';end if;return prior.id;end if;
 begin day:=(p_document->>'date')::date;exception when others then raise exception 'Choose a valid received date.' using errcode='22023';end;
 if day is null or day<doc.document_date or day>(select(now() at time zone time_zone)::date from public.organisations where id=p_organisation_id) then raise exception 'Delivery date must be from the order date through the current business date.' using errcode='22023';end if;
 if exists(select 1 from public.goods_receipts where organisation_id=p_organisation_id and order_id=p_order_id and lower(delivery_reference)=lower(trim(p_document->>'delivery_reference'))) then raise exception 'This delivery reference is already recorded for this order.' using errcode='22023';end if;
 insert into public.goods_receipts(id,organisation_id,order_id,request_id,reference,received_on,delivery_reference,notes,input_hash,created_by,created_label)
 values(result,p_organisation_id,p_order_id,p_request_id,'GRN-'||upper(substr(replace(result::text,'-',''),1,12)),day,trim(p_document->>'delivery_reference'),coalesce(p_document->>'notes',''),digest,auth.uid(),coalesce((select email from auth.users where id=auth.uid()),auth.uid()::text));
 for line in select value from jsonb_array_elements(p_lines) loop
  if coalesce(line->>'accepted','')!~'^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' or coalesce(line->>'rejected','')!~'^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' then raise exception 'Enter accepted and rejected quantities with up to six decimal places.' using errcode='22023';end if;
  accepted:=(line->>'accepted')::numeric;rejected:=(line->>'rejected')::numeric;
  begin select * into ordered from public.purchase_order_lines where organisation_id=p_organisation_id and order_id=p_order_id and id=(line->>'order_line_id')::uuid;exception when invalid_text_representation then raise exception 'Choose a valid order line.' using errcode='22023';end;
  if ordered.id is null or ordered.id=any(seen) then raise exception 'Each delivery line must refer to a different line of this order.' using errcode='22023';end if;seen:=array_append(seen,ordered.id);
  if accepted+rejected<=0 or length(coalesce(line->>'reason',''))>500 or(rejected>0 and trim(coalesce(line->>'reason',''))='') then raise exception 'Enter a received quantity and explain rejected goods.' using errcode='22023';end if;
  select coalesce(sum(l.accepted),0) into previous_qty from public.goods_receipt_lines l where l.organisation_id=p_organisation_id and l.order_line_id=ordered.id and not private.pp_receipt_voided(p_organisation_id,l.receipt_id);
  if accepted+previous_qty>ordered.quantity then raise exception 'Accepted quantities exceed the remaining ordered quantity. Record excess goods as rejected, with a reason.' using errcode='22023';end if;
  insert into public.goods_receipt_lines(organisation_id,receipt_id,order_id,order_line_id,accepted,rejected,rejection_reason) values(p_organisation_id,result,p_order_id,ordered.id,accepted,rejected,coalesce(line->>'reason',''));
 end loop;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'GOODS_RECEIPT_CONFIRMED',auth.uid(),result,jsonb_build_object('order_id',p_order_id));return result;
end;$$;

create or replace function public.review_goods_receipt_void(p_organisation_id uuid,p_receipt_id uuid,p_request_id uuid,p_reason text,p_decision text,p_note text)
returns uuid language plpgsql security definer set search_path='' as $$
declare prior public.goods_receipt_void_requests;result uuid;
begin
 if p_decision='REQUEST' then
  if not exists(select 1 from public.goods_receipts g join public.purchase_orders o on o.organisation_id=g.organisation_id and o.id=g.order_id where g.organisation_id=p_organisation_id and g.id=p_receipt_id and private.pp_inventory_access(p_organisation_id,o.location_id)) then raise exception 'Inventory / Receiving access is required for this GRN.' using errcode='42501';end if;
 else if not private.pp_finance(p_organisation_id) then raise exception 'Finance must decide delivery corrections.' using errcode='42501';end if;end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if not exists(select 1 from public.goods_receipts where organisation_id=p_organisation_id and id=p_receipt_id) then raise exception 'GRN unavailable.' using errcode='42501';end if;
 if p_decision='REQUEST' then
  if p_request_id is null or length(trim(coalesce(p_reason,''))) not between 1 and 1000 then raise exception 'Enter a reason for voiding the GRN.' using errcode='22023';end if;
  select * into prior from public.goods_receipt_void_requests where organisation_id=p_organisation_id and request_id=p_request_id;
  if found then if prior.receipt_id<>p_receipt_id or prior.reason<>trim(p_reason) or prior.created_by<>auth.uid() then raise exception 'This request was already used.' using errcode='22023';end if;return prior.id;end if;
  if exists(select 1 from public.goods_receipt_void_requests where organisation_id=p_organisation_id and receipt_id=p_receipt_id and state in ('PENDING','APPROVED')) then raise exception 'This GRN is already voided or awaiting a void decision.' using errcode='22023';end if;
  insert into public.goods_receipt_void_requests(organisation_id,receipt_id,request_id,reason,created_by,created_label) values(p_organisation_id,p_receipt_id,p_request_id,trim(p_reason),auth.uid(),coalesce((select email from auth.users where id=auth.uid()),auth.uid()::text)) returning id into result;
 else
  if p_decision is null or p_decision not in ('APPROVE','REJECT') or length(trim(coalesce(p_note,''))) not between 1 and 1000 then raise exception 'Choose a decision and enter its reason.' using errcode='22023';end if;
  select * into prior from public.goods_receipt_void_requests where organisation_id=p_organisation_id and receipt_id=p_receipt_id and id=p_request_id for update;
  if not found then raise exception 'GRN correction unavailable.' using errcode='42501';end if;
  if prior.state<>'PENDING' then
   if prior.decided_by=auth.uid() and prior.state=(case when p_decision='APPROVE' then 'APPROVED' else 'REJECTED' end) and prior.decision_note=trim(p_note) then return prior.id;end if;
   raise exception 'This GRN correction was already decided. Refresh to review its status.' using errcode='22023';end if;
  update public.goods_receipt_void_requests set state=case when p_decision='APPROVE' then 'APPROVED' else 'REJECTED' end,decided_by=auth.uid(),decided_label=coalesce((select email from auth.users where id=auth.uid()),auth.uid()::text),decided_at=clock_timestamp(),decision_note=trim(p_note) where id=prior.id;result:=prior.id;
 end if;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'GRN_VOID_REVIEW',auth.uid(),p_receipt_id,jsonb_build_object('request_id',result,'decision',p_decision));return result;
end;$$;

create or replace function public.get_purchase_order(p_organisation_id uuid,p_order_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare doc jsonb;lines jsonb;receipts jsonb;
begin
 if not private.pp_order_read(p_organisation_id,p_order_id) then raise exception 'Purchase access denied.' using errcode='42501';end if;
 select to_jsonb(o)-'input_hash'-'request_id' into doc from public.purchase_orders o where organisation_id=p_organisation_id and id=p_order_id;
 if doc is null then raise exception 'Order unavailable.' using errcode='42501';end if;
 select coalesce(jsonb_agg(l.payload||jsonb_build_object('id',l.id,'accepted',coalesce((select sum(r.accepted) from public.goods_receipt_lines r where r.organisation_id=p_organisation_id and r.order_line_id=l.id and not private.pp_receipt_voided(p_organisation_id,r.receipt_id)),0)::text,'remaining',(l.quantity-coalesce((select sum(r.accepted) from public.goods_receipt_lines r where r.organisation_id=p_organisation_id and r.order_line_id=l.id and not private.pp_receipt_voided(p_organisation_id,r.receipt_id)),0))::text) order by l.position),'[]') into lines from public.purchase_order_lines l where l.organisation_id=p_organisation_id and l.order_id=p_order_id;
 select coalesce(jsonb_agg(to_jsonb(g)||jsonb_build_object('voided',private.pp_receipt_voided(p_organisation_id,g.id),'void_requests',coalesce((select jsonb_agg(to_jsonb(v) order by v.created_at desc,v.id) from public.goods_receipt_void_requests v where v.organisation_id=p_organisation_id and v.receipt_id=g.id),'[]'),
  'lines',(select jsonb_agg(to_jsonb(r)||jsonb_build_object('item_name',l.payload->>'item_name','unit_code',l.payload->>'unit_code') order by l.position) from public.goods_receipt_lines r join public.purchase_order_lines l on l.organisation_id=r.organisation_id and l.order_id=r.order_id and l.id=r.order_line_id where r.organisation_id=p_organisation_id and r.receipt_id=g.id)) order by g.created_at desc,g.id),'[]') into receipts from public.goods_receipts g where g.organisation_id=p_organisation_id and g.order_id=p_order_id;
 return jsonb_build_object('order',doc,'lines',lines,'receipts',receipts);
end;$$;

create or replace function public.list_purchase_orders(p_organisation_id uuid,p_page integer) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;
begin
 if not (private.pp_reference_price_read(p_organisation_id) or private.pp_inventory_access(p_organisation_id)) then raise exception 'Purchase access denied.' using errcode='42501';end if;
 if p_page is null or p_page not between 1 and 100000 then raise exception 'Choose a valid order page.' using errcode='22023';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'reference',reference,'status',status,'date',document_date,'header',payload->'header') order by created_at desc,id),'[]') into rows from (select * from public.purchase_orders where organisation_id=p_organisation_id and private.pp_order_read(p_organisation_id,id) order by created_at desc,id limit 20 offset(p_page-1)*20)s;
 return jsonb_build_object('total',(select count(*) from public.purchase_orders where organisation_id=p_organisation_id and private.pp_order_read(p_organisation_id,id)),'orders',rows);
end;$$;

create or replace function public.workspace_navigation_access(p_organisation_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('overview',private.pp_sales_read(p_organisation_id),'expenses',private.pp_sales_read(p_organisation_id),
 'sales',private.pp_sales_read(p_organisation_id),'purchases',private.pp_reference_price_read(p_organisation_id),
 'orders',private.pp_reference_price_read(p_organisation_id) or private.pp_inventory_access(p_organisation_id),
 'menus',private.pp_reference_price_read(p_organisation_id),'recipes',private.pp_catalogue_read(p_organisation_id),
 'catalogue',private.pp_catalogue_read(p_organisation_id),'team',private.pp_team_manage(p_organisation_id));
$$;
notify pgrst,'reload schema';
commit;
