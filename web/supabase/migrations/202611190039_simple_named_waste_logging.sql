-- Standalone waste is recorded directly, with a named submitter and no approval.
-- Existing posted history is preserved. Old pending records need explicit completion.
begin;
alter table public.stock_documents add column submitter_name text
 check (submitter_name is null or (length(trim(submitter_name)) between 1 and 120 and submitter_name !~ '[[:cntrl:]]'));

create function private.pp_record_named_waste(org uuid,doc uuid,submitter text) returns uuid
language plpgsql security definer set search_path='' as $$
declare d public.stock_documents; line jsonb; name text:=trim(submitter);
begin
 if not private.pp_stock_read(org) then raise exception 'Stock access required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=org for update;
 select * into d from public.stock_documents where organisation_id=org and id=doc and kind='WASTE';
 if not found or not private.pp_stock_doc_read(org,doc) or not private.pp_waste_site(org,d.source_id) or not private.pp_stock_site(org,d.source_id,'request') or d.created_by<>auth.uid() then raise exception 'Only the recorder with waste access at this centre can complete this record.' using errcode='42501';end if;
 if name is null or length(name) not between 1 and 120 or name ~ '[[:cntrl:]]' then raise exception 'Enter the submitter name (up to 120 characters).' using errcode='22023';end if;
 if d.state='POSTED' and d.submitter_name=name then return d.id;end if;
 if d.state not in ('REQUESTED','APPROVED') then raise exception 'This waste record is already complete or closed.' using errcode='22023';end if;
 if not exists(select 1 from public.stock_locations where organisation_id=org and id=d.source_id and is_active) then raise exception 'Choose an active stock centre.' using errcode='22023';end if;
 for line in select value from jsonb_array_elements(d.lines) loop
  perform private.pp_stock_entry(org,d.id,d.source_id,(line->>'item_id')::uuid,-(line->>'quantity')::numeric,d.document_date);
 end loop;
 update public.stock_documents set submitter_name=name,state='POSTED',completed_by=auth.uid(),completed_at=clock_timestamp() where id=d.id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(org,'WASTE_RECORDED',auth.uid(),d.id,jsonb_build_object('kind','WASTE','centre',d.source_id,'submitter_name',name,'approval_required',false));
 return d.id;
end $$;
revoke all on function private.pp_record_named_waste(uuid,uuid,text) from public,anon,authenticated;

alter function public.request_stock_document(uuid,uuid,jsonb,jsonb) rename to pp_stock_request_before_named_waste;
alter function public.pp_stock_request_before_named_waste(uuid,uuid,jsonb,jsonb) set schema private;
revoke all on function private.pp_stock_request_before_named_waste(uuid,uuid,jsonb,jsonb) from public,anon,authenticated;
create function public.request_stock_document(p_organisation_id uuid,p_request_id uuid,p_document jsonb,p_lines jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 if p_document->>'kind'='WASTE' then
  if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock access required.' using errcode='42501';end if;
  if jsonb_typeof(p_document->'submitter_name') is distinct from 'string' or length(trim(coalesce(p_document->>'submitter_name',''))) not between 1 and 120 or (p_document->>'submitter_name') ~ '[[:cntrl:]]' then raise exception 'Enter the submitter name (up to 120 characters).' using errcode='22023';end if;
 end if;
 result:=private.pp_stock_request_before_named_waste(p_organisation_id,p_request_id,p_document,p_lines);
 if p_document->>'kind'='WASTE' then return private.pp_record_named_waste(p_organisation_id,result,p_document->>'submitter_name');end if;
 return result;
end $$;
revoke all on function public.request_stock_document(uuid,uuid,jsonb,jsonb) from public,anon;
grant execute on function public.request_stock_document(uuid,uuid,jsonb,jsonb) to authenticated;

create function public.complete_waste_record(p_organisation_id uuid,p_document_id uuid,p_submitter_name text) returns uuid
language sql security definer set search_path='' as $$select private.pp_record_named_waste(p_organisation_id,p_document_id,p_submitter_name)$$;
revoke all on function public.complete_waste_record(uuid,uuid,text) from public,anon;
grant execute on function public.complete_waste_record(uuid,uuid,text) to authenticated;

alter function public.stock_document_action(uuid,uuid,text,text,jsonb) rename to pp_stock_action_before_named_waste;
alter function public.pp_stock_action_before_named_waste(uuid,uuid,text,text,jsonb) set schema private;
revoke all on function private.pp_stock_action_before_named_waste(uuid,uuid,text,text,jsonb) from public,anon,authenticated;
create function public.stock_document_action(p_organisation_id uuid,p_document_id uuid,p_action text,p_note text,p_received jsonb default null) returns uuid
language plpgsql security definer set search_path='' as $$
begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock access required.' using errcode='42501';end if;
 if exists(select 1 from public.stock_documents where organisation_id=p_organisation_id and id=p_document_id and kind='WASTE') then
  if not private.pp_stock_doc_read(p_organisation_id,p_document_id) then raise exception 'Waste record unavailable.' using errcode='42501';end if;
  if p_action in ('APPROVE','DECLINE','POST') then raise exception 'Waste needs no approval. Record it with a submitter name.' using errcode='22023';end if;
 end if;
 return private.pp_stock_action_before_named_waste(p_organisation_id,p_document_id,p_action,p_note,p_received);
end $$;
revoke all on function public.stock_document_action(uuid,uuid,text,text,jsonb) from public,anon;
grant execute on function public.stock_document_action(uuid,uuid,text,text,jsonb) to authenticated;

create or replace function private.pp_stock_packet(org uuid, doc uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select to_jsonb(d)||jsonb_build_object('source_name',s.name,'destination_name',t.name,'manager_return',(private.pp_stock_receive_allowed(org,d.id) and d.dispatched_by=auth.uid()),'created_label',a.email,'approved_label',b.email,'dispatched_label',c.email,'completed_label',e.email,
 'finish_waste',d.kind='WASTE' and d.state in ('REQUESTED','APPROVED') and d.created_by=auth.uid() and private.pp_stock_site(org,d.source_id,'request'),'actions',jsonb_strip_nulls(jsonb_build_object(
 'approve',case when d.kind<>'WASTE' and d.state='REQUESTED' and d.created_by<>auth.uid() and (case when d.kind='WASTE' then private.pp_waste_review(org,d.source_id) when d.kind in ('TRANSFER','ISSUE') then r.is_active and private.pp_stock_route_approver(org,d.source_id,r.approval_role) else private.pp_stock_manager(org) or private.pp_stock_role(org,'finance',null) end) then true end,
 'decline',case when d.kind<>'WASTE' and d.state='REQUESTED' and d.created_by<>auth.uid() and(case when d.kind='WASTE' then private.pp_waste_review(org,d.source_id) else private.pp_stock_manager(org) end) then true end,
 'post',case when d.kind<>'WASTE' and d.state='APPROVED' and d.kind not in ('TRANSFER','ISSUE') and(case when d.kind='WASTE' then d.created_by<>auth.uid() and private.pp_waste_review(org,d.source_id) else private.pp_stock_site(org,coalesce(d.source_id,d.destination_id),'inventory') end) then true end,
 'dispatch',case when d.state='APPROVED' and d.kind in ('TRANSFER','ISSUE') and private.pp_stock_site(org,d.source_id,'dispatch') then true end,
 'receive',case when private.pp_stock_receive_allowed(org,d.id) then true end,'reject',case when private.pp_stock_receive_allowed(org,d.id) then true end,
 'cancel',case when d.state in ('REQUESTED','APPROVED') and (d.created_by=auth.uid() or private.pp_stock_manager(org)) then true end,
 'resolve',case when d.state in ('PARTIAL','REJECTED') and d.resolved_at is null and private.pp_stock_manager(org) then true end)))
 from public.stock_documents d left join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id left join public.stock_locations t on t.organisation_id=d.organisation_id and t.id=d.destination_id
 left join public.stock_routes r on r.organisation_id=d.organisation_id and r.id=d.route_id left join auth.users a on a.id=d.created_by left join auth.users b on b.id=d.approved_by left join auth.users c on c.id=d.dispatched_by left join auth.users e on e.id=d.completed_by
 where d.organisation_id=org and d.id=doc and private.pp_stock_doc_read(org,doc);
$$;

create or replace function public.processing_activity(p_organisation_id uuid,p_site_id uuid,p_from date,p_to date,p_kind text default 'BATCHES',p_page integer default 1,p_state text default 'ALL') returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock history access required.' using errcode='42501';end if;
 if p_site_id is not null and not private.pp_stock_site(p_organisation_id,p_site_id,'read') then raise exception 'Stock centre unavailable.' using errcode='42501';end if;
 if p_kind in ('WASTE','LOSSES') and p_site_id is not null and not private.pp_waste_site(p_organisation_id,p_site_id) then raise exception 'Waste history is limited to your responsible stock centre.' using errcode='42501';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>366 or p_kind is null or p_kind not in ('BATCHES','WASTE','LOSSES') or p_page is null or p_page not between 1 and 100000 or p_state is null or p_state not in ('ALL','REQUESTED','APPROVED','POSTED','CANCELLED','REJECTED') then raise exception 'Choose dates within 367 days, a record type and a valid page.' using errcode='22023';end if;
 if p_kind='BATCHES' then
 with rows as materialized(select d.id,d.reference,d.document_date,d.state,d.source_id,s.name site,v.name recipe_name,i.name output_name,u.code output_unit,b.*,st.inputs standard_inputs,st.primary_quantity,st.expected_output baseline_output,st.output_spec,st.target_piece_weight_kg,st.expected_trim_kg,st.tolerance_percent,d.lines actual_inputs,
 (select jsonb_agg(jsonb_build_object('item_id',w.item_id,'name',wi.name,'unit',wu.code,'quantity',w.quantity::text,'reason',w.reason)) from public.processing_waste w join public.items wi on wi.organisation_id=w.organisation_id and wi.id=w.item_id join public.units_of_measure wu on wu.organisation_id=wi.organisation_id and wu.id=wi.base_uom_id where w.organisation_id=d.organisation_id and w.document_id=d.id) waste,
 creator.email recorded_by,reviewer.email reviewed_by,poster.email posted_by,
 case when private.pp_reference_price_read(p_organisation_id) then cost.value end costs
 from public.stock_documents d join public.processing_batches b on b.organisation_id=d.organisation_id and b.document_id=d.id join public.processing_standards st on st.organisation_id=b.organisation_id and st.id=b.standard_id join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id join public.recipe_versions v on v.organisation_id=st.organisation_id and v.id=st.recipe_version_id join public.items i on i.organisation_id=st.organisation_id and i.id=st.output_item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id
 left join private.processing_batch_costs cost on cost.organisation_id=d.organisation_id and cost.document_id=d.id left join auth.users creator on creator.id=d.created_by left join auth.users reviewer on reviewer.id=d.approved_by left join auth.users poster on poster.id=d.completed_by
 where d.organisation_id=p_organisation_id and d.document_date between p_from and p_to and(p_state='ALL' or d.state=p_state) and(p_site_id is null or d.source_id=p_site_id) and private.pp_stock_doc_read(p_organisation_id,d.id)),paged as(select * from rows order by document_date desc,id limit 10 offset(p_page-1)*10)
 select jsonb_build_object('total',(select count(*) from rows),'outside_tolerance',(select count(*) from rows where state='POSTED' and outside_tolerance),'rows',coalesce((select jsonb_agg(to_jsonb(p) order by document_date desc,id) from paged p),'[]'::jsonb)) into result;
 else
 with rows as materialized(
 select d.id,d.reference,d.document_date,d.state,s.id site_id,s.name site,i.id item_id,i.name material,u.code unit,w.quantity::text quantity,w.reason,true included_in_production,private.pp_member_label(d.organisation_id,(select id from public.organisation_memberships where organisation_id=d.organisation_id and user_id=d.created_by)) submitter_name from public.processing_waste w join public.stock_documents d on d.organisation_id=w.organisation_id and d.id=w.document_id join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id join public.items i on i.organisation_id=w.organisation_id and i.id=w.item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id
 where p_kind='WASTE' and d.organisation_id=p_organisation_id and d.document_date between p_from and p_to and(p_state='ALL' or d.state=p_state) and(p_site_id is null or d.source_id=p_site_id) and private.pp_stock_doc_read(p_organisation_id,d.id) and private.pp_waste_site(p_organisation_id,d.source_id)
 union all
 select d.id,d.reference,d.document_date,d.state,s.id,s.name,i.id,i.name,u.code,l->>'quantity',d.note,false,d.submitter_name from public.stock_documents d cross join lateral jsonb_array_elements(d.lines) l join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id join public.items i on i.organisation_id=d.organisation_id and i.id=(l->>'item_id')::uuid join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id
 where d.organisation_id=p_organisation_id and d.kind='WASTE' and d.document_date between p_from and p_to and(p_state='ALL' or d.state=p_state) and(p_site_id is null or d.source_id=p_site_id) and private.pp_stock_doc_read(p_organisation_id,d.id) and private.pp_waste_site(p_organisation_id,d.source_id)),paged as(select * from rows order by document_date desc,id,item_id limit 10 offset(p_page-1)*10)
 select jsonb_build_object('total',(select count(*) from rows),'rows',coalesce((select jsonb_agg(to_jsonb(p) order by document_date desc,id,item_id) from paged p),'[]'::jsonb)) into result;
 end if;return result;
end $$;

create or replace function private.pp_operational_rows(org uuid,report_type text,day_from date,day_to date,outlet uuid,site uuid)
returns setof jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if report_type='PO' then
  return query select jsonb_build_object('id',o.id,'document_id',o.id,'reference',o.reference,'date',o.document_date,'kind','PO','order_state',o.status,
   'state',case when o.status='DRAFT' then 'DRAFT' when coalesce(progress.complete,false) then 'COMPLETED' when coalesce(progress.started,false) then 'PARTIAL' else 'PENDING' end,
   'outlet',o.payload->'header'->>'location_name','party',o.payload->'header'->>'supplier_name','amount',o.payload->'header'->>'total','currency',o.payload->'header'->>'currency',
   'actor',o.created_label,'notes',o.notes,'path','/workspace/purchases/orders','params',jsonb_build_object('order',o.id))
  from public.purchase_orders o cross join lateral (
   select bool_and(q.accepted>=q.quantity) complete,bool_or(q.accepted>0) started from (
    select l.quantity,coalesce((select sum(r.accepted) from public.goods_receipt_lines r where r.organisation_id=org and r.order_line_id=l.id and not private.pp_receipt_voided(org,r.receipt_id)),0) accepted
    from public.purchase_order_lines l where l.organisation_id=org and l.order_id=o.id)q
  )progress where o.organisation_id=org and o.document_date between day_from and day_to and(outlet is null or o.location_id=outlet) and private.pp_order_read(org,o.id);
 elsif report_type='GRN' then
  return query select jsonb_build_object('id',r.id,'document_id',g.id,'reference',g.reference,'date',g.received_on,'kind','GRN',
   'state',case when private.pp_receipt_voided(org,g.id) then 'VOIDED' when exists(select 1 from public.goods_receipt_void_requests v where v.organisation_id=org and v.receipt_id=g.id and v.state='PENDING') then 'VOID_PENDING' else 'ACTIVE' end,
   'outlet',o.payload->'header'->>'location_name','party',o.payload->'header'->>'supplier_name','related_reference',o.reference,'item',l.payload->>'item_name','unit',l.payload->>'unit_code',
   'accepted',r.accepted::text,'rejected',r.rejected::text,'actor',g.created_label,'notes',concat_ws(' · ',g.delivery_reference,g.notes,r.rejection_reason),
   'path','/workspace/purchases/orders','params',jsonb_build_object('order',o.id,'receipt',g.id))
  from public.goods_receipts g join public.purchase_orders o on o.organisation_id=g.organisation_id and o.id=g.order_id
  join public.goods_receipt_lines r on r.organisation_id=g.organisation_id and r.receipt_id=g.id
  join public.purchase_order_lines l on l.organisation_id=r.organisation_id and l.id=r.order_line_id
  where g.organisation_id=org and g.received_on between day_from and day_to and(outlet is null or o.location_id=outlet) and private.pp_order_read(org,o.id);
 elsif report_type='INVOICE' then
  return query with current_invoices as (
   select h.id,h.created_by,coalesce(c.proposal->'header',jsonb_build_object('reference',h.purchase_ref,'date',h.purchase_date,'location_id',h.location_id,'location_name',l.name,'supplier_name',s.name,'total',h.invoice_total::text,'currency',h.currency_code)) header,
    coalesce((c.proposal->>'voided')::boolean,false) voided
   from public.purchase_headers h join public.locations l on l.organisation_id=h.organisation_id and l.id=h.location_id
   join public.suppliers s on s.organisation_id=h.organisation_id and s.id=h.supplier_id
   left join lateral(select proposal from public.purchase_corrections c where c.organisation_id=org and c.purchase_id=h.id and c.state='APPROVED' order by c.decided_at desc,c.id desc limit 1)c on true
   where h.organisation_id=org
  ) select jsonb_build_object('id',h.id,'document_id',h.id,'reference',header->>'reference','date',header->>'date','kind','INVOICE',
   'state',case when h.voided then 'VOIDED' when exists(select 1 from public.purchase_corrections c where c.organisation_id=org and c.purchase_id=h.id and c.state='PENDING') then 'CORRECTION_PENDING' else 'ACTIVE' end,
   'outlet',header->>'location_name','party',header->>'supplier_name','amount',header->>'total','currency',header->>'currency','actor',coalesce(u.email,h.created_by::text),
   'path','/workspace/purchases/invoices','params',jsonb_build_object('purchase',h.id))
   from current_invoices h left join auth.users u on u.id=h.created_by where(header->>'date')::date between day_from and day_to and(outlet is null or header->>'location_id'=outlet::text);
 elsif report_type='SALES' then
  return query select jsonb_build_object('id',h.id,'document_id',h.id,'reference',h.transaction_ref,'date',h.sale_date,'kind','SALES','state','RECORDED','outlet',o.name,
   'party',h.channel_code,'item',string_agg(distinct v.name,', ' order by v.name),'amount',sum(l.net_revenue)::text,'currency',h.currency_code,'tax',sum(l.tax)::text,'discount',sum(l.discount)::text,
   'customer_total',sum(l.customer_total)::text,'actor',coalesce(u.email,h.created_by::text),'notes',h.source_system,
   'path','/workspace/sales','params',jsonb_build_object('batch',h.import_batch_id,'from',day_from,'to',day_to))
  from public.sales_headers h join public.sales_lines l on l.organisation_id=h.organisation_id and l.sale_id=h.id
  join public.menu_item_versions v on v.organisation_id=l.organisation_id and v.id=l.menu_version_id
  join public.locations o on o.organisation_id=h.organisation_id and o.id=h.location_id left join auth.users u on u.id=h.created_by
  where h.organisation_id=org and h.sale_date between day_from and day_to and(outlet is null or h.location_id=outlet)
  group by h.id,o.name,u.email;
 else
  return query with visible as materialized (
   select d.*,s.name source_name,t.name destination_name,so.name source_outlet,ta.name destination_outlet,
    private.pp_stock_site(org,d.source_id,'read') source_access,private.pp_stock_site(org,d.destination_id,'read') destination_access
   from public.stock_documents d left join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id
   left join public.stock_locations t on t.organisation_id=d.organisation_id and t.id=d.destination_id
   left join public.locations so on so.organisation_id=s.organisation_id and so.id=s.outlet_id left join public.locations ta on ta.organisation_id=t.organisation_id and ta.id=t.outlet_id
   where d.organisation_id=org and d.document_date between day_from and day_to and private.pp_stock_doc_read(org,d.id) and(report_type<>'WASTE' or private.pp_waste_site(org,d.source_id))
    and(site is null or d.source_id=site or d.destination_id=site)
    and(outlet is null or(s.outlet_id=outlet and private.pp_stock_site(org,s.id,'read')) or(t.outlet_id=outlet and private.pp_stock_site(org,t.id,'read')))
    and case report_type when 'REQUISITIONS' then d.kind in ('ISSUE','TRANSFER') when 'STOCK_RECEIPTS' then d.kind in ('GRN','DIRECT_RECEIPT','OPENING')
     when 'MOVEMENTS' then true else d.kind=case report_type when 'COUNTS' then 'COUNT' else report_type end end
  ), expanded as (
   select d.*,line.value line,line.ordinality line_no,false is_output from visible d cross join lateral jsonb_array_elements(d.lines) with ordinality line
   union all
   select d.*,jsonb_build_object('item_id',d.output->>'item_id','quantity',d.output->>'quantity'),1000000::bigint,true from visible d where d.kind='PRODUCTION' and d.output->>'item_id' is not null
  ) select jsonb_build_object('id',d.id::text||'-'||d.line_no,'document_id',d.id,'reference',d.reference,'date',d.document_date,'kind',d.kind,'state',d.state,'resolved',d.resolved_at is not null,
   'outlet',concat_ws(' → ',coalesce(d.source_outlet,case when d.source_id is not null then 'Central / shared store' end),coalesce(d.destination_outlet,case when d.destination_id is not null then 'Central / shared store' end)),
   'source',d.source_name,'destination',d.destination_name,'item',coalesce(d.line->>'name',i.name),'unit',coalesce(d.line->>'unit',unit.code),'quantity',d.line->>'quantity','direction',case when d.is_output then 'Output' when d.kind='PRODUCTION' then 'Input' end,
   'accepted',case when d.kind in ('ISSUE','TRANSFER') and d.completed_at is not null then coalesce(received.value->>'quantity','0') end,
   'rejected',case when d.kind in ('ISSUE','TRANSFER') and d.completed_at is not null and d.dispatched_at is not null then((d.line->>'quantity')::numeric-coalesce((received.value->>'quantity')::numeric,0))::text end,
   'stock_change',case when d.state='POSTED' then coalesce(ledger.quantity,0)::text else ledger.quantity::text end,'posted_on',ledger.posted_on,'submitter_name',d.submitter_name,'actor',coalesce(u.email,d.created_by::text),'approved_by',coalesce(a.email,d.approved_by::text),'completed_by',coalesce(c.email,d.completed_by::text),
   'amount',case when report_type='WASTE' and d.kind='WASTE' and d.state='POSTED' and private.pp_reference_price_read(org) and price.base_uom_id=i.base_uom_id and price.currency_code=currency.currency_code then(-ledger.quantity*price.cost_per_base_unit)::text end,
   'currency',case when report_type='WASTE' and d.kind='WASTE' and private.pp_reference_price_read(org) then currency.currency_code end,
   'notes',concat_ws(' · ',d.note,d.decision_note,d.resolution_note,d.line->>'reason',received.value->>'reason'),
   'path','/workspace/inventory','params',jsonb_build_object('view','movements','document',d.id))
  from expanded d join public.items i on i.organisation_id=org and i.id=(d.line->>'item_id')::uuid
  join public.units_of_measure unit on unit.organisation_id=org and unit.id=i.base_uom_id
  join public.organisations currency on currency.id=org
  left join auth.users u on u.id=d.created_by left join auth.users a on a.id=d.approved_by left join auth.users c on c.id=d.completed_by
  left join lateral(select value from jsonb_array_elements(d.received_lines) r where r.value->>'item_id'=d.line->>'item_id' limit 1)received on true
  left join lateral(select sum(l.quantity) quantity,min(l.occurred_on) posted_on from public.stock_ledger l where l.organisation_id=org and l.document_id=d.id and l.item_id=i.id and l.location_id=case when d.source_access then d.source_id else d.destination_id end)ledger on true
  left join lateral(select p.* from public.material_reference_prices p where p.organisation_id=org and p.item_id=i.id and p.price_date<=ledger.posted_on order by p.price_date desc,p.version desc limit 1)price on true;
 end if;
end $$;
notify pgrst,'reload schema';
commit;
