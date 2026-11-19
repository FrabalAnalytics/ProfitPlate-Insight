-- Waste histories and review responsibilities follow the Inventory Manager's owned centres.
-- Other stock oversight and receiver-confirmed transfers retain their existing permissions.
begin;
alter table public.stock_member_locations add column can_review_waste boolean not null default false;

create function private.pp_waste_own_centres(org uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.pp_inventory_manager(org) and not(private.pp_stock_role(org,'restaurant_admin',null) or private.pp_stock_role(org,'ceo',null) or private.pp_stock_role(org,'finance',null));
$$;
create function private.pp_waste_site(org uuid,site uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.pp_stock_site(org,site,'read') and (not private.pp_waste_own_centres(org) or exists(select 1 from public.stock_locations s join public.organisation_memberships m on m.organisation_id=s.organisation_id and m.id=s.responsible_membership_id where s.organisation_id=org and s.id=site and m.user_id=auth.uid() and m.status='active'));
$$;
revoke all on function private.pp_waste_own_centres(uuid),private.pp_waste_site(uuid,uuid) from public,anon,authenticated;


create or replace function public.processing_setup(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock setup access required.' using errcode='42501';end if;
 select jsonb_build_object('waste_own_centres',private.pp_waste_own_centres(p_organisation_id),'waste_sites',coalesce((select jsonb_agg(jsonb_build_object('id',ws.id,'name',ws.name,'outlet_id',ws.outlet_id,'is_active',ws.is_active) order by ws.name,ws.id) from public.stock_locations ws where ws.organisation_id=p_organisation_id and private.pp_waste_site(p_organisation_id,ws.id)),'[]'::jsonb),'processing_centre_id',(select centre_id from public.stock_processing_settings where organisation_id=p_organisation_id),'manage',private.pp_stock_manager(p_organisation_id),'sites',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('responsible_name',private.pp_member_label(m.organisation_id,m.id),'responsible_active',m.status='active','request',private.pp_stock_site(s.organisation_id,s.id,'request')) order by s.name) from public.stock_locations s left join public.organisation_memberships m on m.organisation_id=s.organisation_id and m.id=s.responsible_membership_id left join auth.users u on u.id=m.user_id where s.organisation_id=p_organisation_id and private.pp_stock_site(s.organisation_id,s.id,'read')),'[]'::jsonb),
 'members',case when private.pp_stock_manager(p_organisation_id) then coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'name',private.pp_member_label(m.organisation_id,m.id)) order by u.email) from public.organisation_memberships m join auth.users u on u.id=m.user_id where m.organisation_id=p_organisation_id and m.status='active'),'[]'::jsonb) else '[]'::jsonb end,
 'standards',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('recipe_name',v.name,'output_name',i.name,'output_unit',u.code,'primary_name',p.name,'primary_unit',pu.code,'site_ids',(select jsonb_agg(site_id) from public.processing_standard_sites where organisation_id=s.organisation_id and standard_id=s.id)) order by v.name,s.revision desc)
 from public.processing_standards s join public.recipe_versions v on v.organisation_id=s.organisation_id and v.id=s.recipe_version_id join public.items i on i.organisation_id=s.organisation_id and i.id=s.output_item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id join public.items p on p.organisation_id=s.organisation_id and p.id=s.primary_item_id join public.units_of_measure pu on pu.organisation_id=p.organisation_id and pu.id=p.base_uom_id
 where s.organisation_id=p_organisation_id and s.is_active and(private.pp_stock_manager(p_organisation_id) or exists(select 1 from public.processing_standard_sites ss where ss.organisation_id=s.organisation_id and ss.standard_id=s.id and private.pp_stock_site(p_organisation_id,ss.site_id,'read')))),'[]'::jsonb)) into result;return result;
end $$;

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
 select d.id,d.reference,d.document_date,d.state,s.id site_id,s.name site,i.id item_id,i.name material,u.code unit,w.quantity::text quantity,w.reason,true included_in_production from public.processing_waste w join public.stock_documents d on d.organisation_id=w.organisation_id and d.id=w.document_id join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id join public.items i on i.organisation_id=w.organisation_id and i.id=w.item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id
 where p_kind='WASTE' and d.organisation_id=p_organisation_id and d.document_date between p_from and p_to and(p_state='ALL' or d.state=p_state) and(p_site_id is null or d.source_id=p_site_id) and private.pp_stock_doc_read(p_organisation_id,d.id) and private.pp_waste_site(p_organisation_id,d.source_id)
 union all
 select d.id,d.reference,d.document_date,d.state,s.id,s.name,i.id,i.name,u.code,l->>'quantity',d.note,false from public.stock_documents d cross join lateral jsonb_array_elements(d.lines) l join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id join public.items i on i.organisation_id=d.organisation_id and i.id=(l->>'item_id')::uuid join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id
 where d.organisation_id=p_organisation_id and d.kind='WASTE' and d.document_date between p_from and p_to and(p_state='ALL' or d.state=p_state) and(p_site_id is null or d.source_id=p_site_id) and private.pp_stock_doc_read(p_organisation_id,d.id) and private.pp_waste_site(p_organisation_id,d.source_id)),paged as(select * from rows order by document_date desc,id,item_id limit 10 offset(p_page-1)*10)
 select jsonb_build_object('total',(select count(*) from rows),'rows',coalesce((select jsonb_agg(to_jsonb(p) order by document_date desc,id,item_id) from paged p),'[]'::jsonb)) into result;
 end if;return result;
end $$;

create or replace function public.operational_report_options(p_organisation_id uuid,p_type text default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare types text[]:=private.pp_operational_types(p_organisation_id); chosen text; stock boolean;
begin
 if cardinality(types)=0 then raise exception 'Historical report access denied.' using errcode='42501'; end if;
 chosen:=coalesce(p_type,types[1]);
 if not chosen=any(types) then raise exception 'This report is not available to your assigned roles.' using errcode='42501'; end if;
 stock:=chosen not in ('PO','GRN','INVOICE','SALES');
 return jsonb_build_object('types',to_jsonb(types),'selected',chosen,'financial',private.pp_reference_price_read(p_organisation_id),'waste_own_centres',private.pp_waste_own_centres(p_organisation_id),
  'outlets',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'name',l.name,'active',l.is_active) order by l.name,l.id)
   from public.locations l where l.organisation_id=p_organisation_id and
   (case when stock then exists(select 1 from public.stock_locations s where s.organisation_id=l.organisation_id and s.outlet_id=l.id and private.pp_stock_site(s.organisation_id,s.id,'read') and(chosen<>'WASTE' or private.pp_waste_site(p_organisation_id,s.id)))
    when chosen in ('PO','GRN') then private.pp_reference_price_read(p_organisation_id) or private.pp_inventory_access(p_organisation_id,l.id)
    else private.pp_reference_price_read(p_organisation_id) end)),'[]'::jsonb),
  'stock_locations',case when stock then coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'outlet_id',s.outlet_id,'active',s.is_active) order by s.name,s.id)
    from public.stock_locations s where s.organisation_id=p_organisation_id and private.pp_stock_site(p_organisation_id,s.id,'read') and(chosen<>'WASTE' or private.pp_waste_site(p_organisation_id,s.id))),'[]'::jsonb) else '[]'::jsonb end);
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
   'stock_change',case when d.state='POSTED' then coalesce(ledger.quantity,0)::text else ledger.quantity::text end,'posted_on',ledger.posted_on,'actor',coalesce(u.email,d.created_by::text),'approved_by',coalesce(a.email,d.approved_by::text),'completed_by',coalesce(c.email,d.completed_by::text),
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

create function private.pp_waste_review(org uuid,site uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.pp_waste_site(org,site) and exists(select 1 from public.stock_locations s where s.organisation_id=org and s.id=site and s.is_active and (
 (private.pp_inventory_manager(org) and exists(select 1 from public.organisation_memberships m where m.organisation_id=org and m.id=s.responsible_membership_id and m.user_id=auth.uid() and m.status='active')) or
 exists(select 1 from public.stock_member_locations g join public.stock_member_access a on a.organisation_id=g.organisation_id and a.membership_id=g.membership_id and a.mode='ASSIGNED' join public.organisation_memberships m on m.organisation_id=g.organisation_id and m.id=g.membership_id and m.status='active' and m.user_id=auth.uid() join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id and r.role_code in ('inventory','operations','stock_department','kitchen_manager','bar_lead') and(r.location_id is null or r.location_id=s.outlet_id) where g.organisation_id=org and g.location_id=site and g.can_review_waste)));
$$;
revoke all on function private.pp_waste_review(uuid,uuid) from public,anon,authenticated;

create or replace function private.pp_stock_doc_read(org uuid, doc uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.stock_documents d where d.organisation_id=org and d.id=doc and(d.kind<>'WASTE' or private.pp_waste_site(org,d.source_id))
 and (private.pp_stock_site(org,d.source_id,'read') or private.pp_stock_site(org,d.destination_id,'read')));
$$;

create or replace function public.save_stock_member_access(p_organisation_id uuid,p_membership_id uuid,p_revision integer,p_mode text,p_assignments jsonb) returns integer
language plpgsql security definer set search_path='' as $$
declare version integer; entry jsonb; site public.stock_locations; seen uuid[]:='{}'; prior jsonb; roles text[];
begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'Inventory Manager or business-wide Restaurant Administrator access is required.' using errcode='42501'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if not exists(select 1 from public.organisation_memberships where organisation_id=p_organisation_id and id=p_membership_id and status='active') then raise exception 'Choose an active member in this business.' using errcode='42501'; end if;
 select array_agg(role_code) into roles from public.membership_roles where organisation_id=p_organisation_id and membership_id=p_membership_id and role_code in ('inventory','operations','stock_department','kitchen_manager','bar_lead','stock_receiver','stock_dispatcher');
 if roles is null then raise exception 'Choose a department or stock-process member.' using errcode='42501'; end if;
 if p_mode is null or p_mode not in ('OUTLET','ASSIGNED') or jsonb_typeof(p_assignments) is distinct from 'array' or jsonb_array_length(p_assignments)>100 or octet_length(p_assignments::text)>32768 or (p_mode='OUTLET' and jsonb_array_length(p_assignments)>0) then raise exception 'Choose up to 100 explicit stock locations.' using errcode='22023'; end if;
 if p_mode='OUTLET' and not (roles&&array['inventory','operations']) then raise exception 'Department and delegated process roles require selected stock locations.' using errcode='22023'; end if;
 select a.revision,to_jsonb(a) into version,prior from public.stock_member_access a where a.organisation_id=p_organisation_id and a.membership_id=p_membership_id;
 version:=coalesce(version,0);if version is distinct from p_revision then raise exception 'Department access changed. Refresh and review the latest assignments before saving.' using errcode='22023'; end if;
 prior:=coalesce(prior,'{}')||jsonb_build_object('assignments',coalesce((select jsonb_agg(to_jsonb(g)) from public.stock_member_locations g where g.organisation_id=p_organisation_id and g.membership_id=p_membership_id),'[]'));
 for entry in select value from jsonb_array_elements(p_assignments) loop
  if jsonb_typeof(entry) is distinct from 'object' or jsonb_typeof(entry->'can_request') is distinct from 'boolean' or jsonb_typeof(entry->'can_handle') is distinct from 'boolean' or jsonb_typeof(entry->'can_approve') is distinct from 'boolean' or (entry?'can_dispatch' and jsonb_typeof(entry->'can_dispatch') is distinct from 'boolean') or (entry?'can_receive' and jsonb_typeof(entry->'can_receive') is distinct from 'boolean') or (entry?'can_review_waste' and jsonb_typeof(entry->'can_review_waste') is distinct from 'boolean') then raise exception 'Choose explicit stock-process permissions.' using errcode='22023'; end if;
  begin select * into site from public.stock_locations where organisation_id=p_organisation_id and id=(entry->>'location_id')::uuid and is_active;exception when invalid_text_representation then raise exception 'Choose a valid stock location.' using errcode='22023';end;
  if site.id is null or site.id=any(seen) then raise exception 'Choose distinct active stock locations in this business.' using errcode='22023'; end if;
  select array_agg(role_code) into roles from public.membership_roles where organisation_id=p_organisation_id and membership_id=p_membership_id and role_code in ('inventory','operations','stock_department','kitchen_manager','bar_lead','stock_receiver','stock_dispatcher') and (location_id is null or (site.outlet_id is not null and location_id=site.outlet_id));
  if roles is null then raise exception 'Stock assignments cannot exceed the current role/outlet scope.' using errcode='22023'; end if;
  if (entry->>'can_request')::boolean and not (roles&&array['inventory','operations','stock_department','kitchen_manager','bar_lead']) then raise exception 'This process role cannot initiate requisitions.' using errcode='22023';end if;
  if (entry->>'can_handle')::boolean and not ('inventory'=any(roles)) then raise exception 'Department/process roles cannot post arbitrary stock adjustments; the Inventory Manager handles posting.' using errcode='22023';end if;
  if (entry->>'can_approve')::boolean and not (roles&&array['inventory','operations']) then raise exception 'Approval authority belongs to the Inventory Manager or the configured source approver.' using errcode='22023';end if;
  if coalesce((entry->>'can_dispatch')::boolean,(entry->>'can_handle')::boolean) and not (roles&&array['inventory','stock_dispatcher']) then raise exception 'Dispatch permission requires a dispatcher process role.' using errcode='22023';end if;
  if coalesce((entry->>'can_receive')::boolean,(entry->>'can_handle')::boolean) and not (roles&&array['inventory','stock_department','kitchen_manager','bar_lead','stock_receiver']) then raise exception 'Receiving permission requires a department or receiver role.' using errcode='22023';end if;
  if coalesce((entry->>'can_review_waste')::boolean,false) and not(roles&&array['inventory','operations','stock_department','kitchen_manager','bar_lead']) then raise exception 'Waste review requires a department or operational stock role at this centre.' using errcode='22023';end if;
  seen:=array_append(seen,site.id);
 end loop;
 insert into public.stock_member_access(organisation_id,membership_id,mode,revision,updated_by) values(p_organisation_id,p_membership_id,p_mode,version+1,auth.uid()) on conflict(organisation_id,membership_id) do update set mode=excluded.mode,revision=excluded.revision,updated_by=excluded.updated_by,updated_at=clock_timestamp();
 delete from public.stock_member_locations where organisation_id=p_organisation_id and membership_id=p_membership_id;
 insert into public.stock_member_locations(organisation_id,membership_id,location_id,can_request,can_handle,can_approve,can_dispatch,can_receive,can_review_waste)
 select p_organisation_id,p_membership_id,(g->>'location_id')::uuid,(g->>'can_request')::boolean,(g->>'can_handle')::boolean,(g->>'can_approve')::boolean,coalesce((g->>'can_dispatch')::boolean,(g->>'can_handle')::boolean),coalesce((g->>'can_receive')::boolean,(g->>'can_handle')::boolean),coalesce((g->>'can_review_waste')::boolean,false) from jsonb_array_elements(p_assignments) g;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_DEPARTMENT_ACCESS_CHANGED',auth.uid(),p_membership_id,jsonb_build_object('previous',prior,'mode',p_mode,'assignments',p_assignments,'revision',version+1));return version+1;
end $$;

create or replace function private.pp_stock_packet(org uuid, doc uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select to_jsonb(d)||jsonb_build_object('source_name',s.name,'destination_name',t.name,'manager_return',(private.pp_stock_receive_allowed(org,d.id) and d.dispatched_by=auth.uid()),'created_label',a.email,'approved_label',b.email,'dispatched_label',c.email,'completed_label',e.email,
 'actions',jsonb_strip_nulls(jsonb_build_object(
 'approve',case when d.state='REQUESTED' and d.created_by<>auth.uid() and (case when d.kind='WASTE' then private.pp_waste_review(org,d.source_id) when d.kind in ('TRANSFER','ISSUE') then r.is_active and private.pp_stock_route_approver(org,d.source_id,r.approval_role) else private.pp_stock_manager(org) or private.pp_stock_role(org,'finance',null) end) then true end,
 'decline',case when d.state='REQUESTED' and d.created_by<>auth.uid() and(case when d.kind='WASTE' then private.pp_waste_review(org,d.source_id) else private.pp_stock_manager(org) end) then true end,
 'post',case when d.state='APPROVED' and d.kind not in ('TRANSFER','ISSUE') and(case when d.kind='WASTE' then d.created_by<>auth.uid() and private.pp_waste_review(org,d.source_id) else private.pp_stock_site(org,coalesce(d.source_id,d.destination_id),'inventory') end) then true end,
 'dispatch',case when d.state='APPROVED' and d.kind in ('TRANSFER','ISSUE') and private.pp_stock_site(org,d.source_id,'dispatch') then true end,
 'receive',case when private.pp_stock_receive_allowed(org,d.id) then true end,'reject',case when private.pp_stock_receive_allowed(org,d.id) then true end,
 'cancel',case when d.state in ('REQUESTED','APPROVED') and (d.created_by=auth.uid() or private.pp_stock_manager(org)) then true end,
 'resolve',case when d.state in ('PARTIAL','REJECTED') and d.resolved_at is null and private.pp_stock_manager(org) then true end)))
 from public.stock_documents d left join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id left join public.stock_locations t on t.organisation_id=d.organisation_id and t.id=d.destination_id
 left join public.stock_routes r on r.organisation_id=d.organisation_id and r.id=d.route_id left join auth.users a on a.id=d.created_by left join auth.users b on b.id=d.approved_by left join auth.users c on c.id=d.dispatched_by left join auth.users e on e.id=d.completed_by
 where d.organisation_id=org and d.id=doc and private.pp_stock_doc_read(org,doc);
$$;

create or replace function public.request_stock_document(p_organisation_id uuid,p_request_id uuid,p_document jsonb,p_lines jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid:=gen_random_uuid(); prior public.stock_documents; src public.stock_locations; dst public.stock_locations; route public.stock_routes;
 kind text:=p_document->>'kind'; day date; digest text; lines jsonb; output jsonb; rec public.goods_receipts; po public.purchase_orders;
 r record; qty numeric; planned numeric; actual numeric; base_factor numeric; bound uuid; out_qty numeric; expected numeric; fingerprint text; standard public.processing_standards; actual_lines jsonb; waste jsonb; entry jsonb; primary_actual numeric; expected_base numeric; deviation numeric; outside boolean; reason text; usable numeric; input_mass numeric; waste_mass numeric; mass_balance numeric; measurable boolean;
begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock access is required.' using errcode='42501'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if p_request_id is null or octet_length(coalesce(p_document::text,''))>65536 then raise exception 'Refresh and enter a valid stock request.' using errcode='22023'; end if;
 digest:=md5(jsonb_build_array(p_document,p_lines)::text);
 select * into prior from public.stock_documents where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then
  if prior.input_hash<>digest or prior.created_by<>auth.uid() then raise exception 'This request was already used. Refresh before creating another.' using errcode='22023'; end if;
  return prior.id;
 end if;
 if kind not in ('OPENING','GRN','DIRECT_RECEIPT','TRANSFER','ISSUE','COUNT','WASTE','CONSUMPTION','PRODUCTION') or kind is null then raise exception 'Choose a stock movement type.' using errcode='22023'; end if;
 begin day:=(p_document->>'date')::date; exception when others then raise exception 'Choose a valid movement date.' using errcode='22023'; end;
 if day is null or day>(select(now() at time zone time_zone)::date from public.organisations where id=p_organisation_id) or length(trim(coalesce(p_document->>'note',''))) not between 1 and 1000 then raise exception 'Choose a date that is not in the future and enter the source/reason.' using errcode='22023'; end if;
 select * into src from public.stock_locations where organisation_id=p_organisation_id and id=nullif(p_document->>'source_id','')::uuid and is_active;
 select * into dst from public.stock_locations where organisation_id=p_organisation_id and id=nullif(p_document->>'destination_id','')::uuid and is_active;
 if kind in ('TRANSFER','ISSUE') then
  select * into route from public.stock_routes where organisation_id=p_organisation_id and id=nullif(p_document->>'route_id','')::uuid and is_active;
  if route.id is null or route.kind<>kind then raise exception 'Choose a configured active route for this movement type.' using errcode='22023'; end if;
  select * into src from public.stock_locations where organisation_id=p_organisation_id and id=route.source_id and is_active;
  select * into dst from public.stock_locations where organisation_id=p_organisation_id and id=route.destination_id and is_active;
  if src.id is null or dst.id is null or not (private.pp_stock_site(p_organisation_id,dst.id,'request') or private.pp_stock_site(p_organisation_id,src.id,'request')) then raise exception 'Request access is required at the receiving department, or Inventory access at the source.' using errcode='42501'; end if;
 elsif kind in ('OPENING','GRN','DIRECT_RECEIPT') then
  src.id:=null;
  if dst.id is null or not (private.pp_stock_site(p_organisation_id,dst.id,'inventory') and private.pp_stock_site(p_organisation_id,dst.id,'request')) then raise exception 'Inventory access is required at the receiving stock location.' using errcode='42501'; end if;
 else
  dst.id:=null;
  if src.id is null or not private.pp_stock_site(p_organisation_id,src.id,'request') then raise exception 'Inventory or Operations access is required at this stock location.' using errcode='42501'; end if;
 end if;
 if kind='WASTE' and not private.pp_waste_site(p_organisation_id,src.id) then raise exception 'Record waste only for your responsible stock centre.' using errcode='42501';end if;
 if kind='GRN' then
  select * into rec from public.goods_receipts where organisation_id=p_organisation_id and id=nullif(p_document->>'receipt_id','')::uuid;
  select * into po from public.purchase_orders where organisation_id=p_organisation_id and id=rec.order_id;
  if rec.id is null or private.pp_receipt_voided(p_organisation_id,rec.id) or exists(select 1 from public.goods_receipt_void_requests where organisation_id=p_organisation_id and receipt_id=rec.id and state='PENDING')
   or not private.pp_inventory_access(p_organisation_id,po.location_id) or (dst.outlet_id is not null and dst.outlet_id<>po.location_id) or day<rec.received_on then raise exception 'Choose an active GRN for this outlet (or a central store), with no pending void, on or before the stock date.' using errcode='22023'; end if;
  if exists(select 1 from public.stock_documents where organisation_id=p_organisation_id and receipt_id=rec.id and state not in ('CANCELLED','REJECTED')) then raise exception 'This GRN already has a stock request.' using errcode='22023'; end if;
  select jsonb_agg(jsonb_build_object('item_id',q.item_id,'quantity',q.qty::text)) into lines from (
   select l.item_id,sum(g.accepted*(l.payload->>'conversion_factor')::numeric) qty from public.goods_receipt_lines g join public.purchase_order_lines l on l.organisation_id=g.organisation_id and l.order_id=g.order_id and l.id=g.order_line_id
   where g.organisation_id=p_organisation_id and g.receipt_id=rec.id and g.accepted>0 group by l.item_id
  ) q;
  lines:=private.pp_stock_lines(p_organisation_id,lines);
 elsif kind='PRODUCTION' then
  if nullif(p_document->>'processing_standard_id','') is not null then
   select * into standard from public.processing_standards where organisation_id=p_organisation_id and id=(p_document->>'processing_standard_id')::uuid and is_active;
   if not found or standard.recipe_version_id is distinct from nullif(p_document->>'recipe_version_id','')::uuid or not exists(select 1 from public.recipe_versions where organisation_id=p_organisation_id and id=standard.recipe_version_id and effective_from<=day) then raise exception 'Choose an active processing standard for this recipe version.' using errcode='22023';end if;
   if not exists(select 1 from public.processing_standard_sites ss join public.stock_locations s on s.organisation_id=ss.organisation_id and s.id=ss.site_id join public.organisation_memberships m on m.organisation_id=s.organisation_id and m.id=s.responsible_membership_id and m.status='active' where ss.organisation_id=p_organisation_id and ss.standard_id=standard.id and ss.site_id=src.id and s.processing_enabled and s.is_active) then raise exception 'This centre is not enabled for the selected processing standard.' using errcode='22023';end if;
   actual_lines:=private.pp_stock_lines(p_organisation_id,p_lines);
   if exists(select 1 from jsonb_array_elements(actual_lines) l where not exists(select 1 from jsonb_array_elements(standard.inputs) s where s->>'item_id'=l->>'item_id')) or exists(select 1 from jsonb_array_elements(standard.inputs) s where not exists(select 1 from jsonb_array_elements(actual_lines) l where l->>'item_id'=s->>'item_id')) then raise exception 'Record actual consumption for every input in the standard, including explicit zero where unused.' using errcode='22023';end if;
   select (value->>'quantity')::numeric into primary_actual from jsonb_array_elements(actual_lines) where value->>'item_id'=standard.primary_item_id::text;
   if primary_actual is null or primary_actual<=0 then raise exception 'Enter a positive measured main input quantity.' using errcode='22023';end if;
   actual:=private.pp_stock_number(p_document->>'actual_output',true);
   select ou.canonical_factor/iu.canonical_factor into base_factor from public.recipe_outputs ro join public.units_of_measure ou on ou.organisation_id=ro.organisation_id and ou.id=ro.uom_id join public.items i on i.organisation_id=ro.organisation_id and i.id=standard.output_item_id join public.units_of_measure iu on iu.organisation_id=i.organisation_id and iu.id=i.base_uom_id where ro.organisation_id=p_organisation_id and ro.recipe_version_id=standard.recipe_version_id;
   expected_base:=round(standard.expected_output*primary_actual/standard.primary_quantity,12);qty:=actual;
   if expected_base<=0 or expected_base>=1e26 or qty>=1e26 then raise exception 'Batch quantities exceed supported precision.' using errcode='22023';end if;
   deviation:=100*(qty-expected_base)/expected_base;outside:=abs(deviation)>standard.tolerance_percent;
   reason:=trim(coalesce(p_document->>'variance_reason',''));
   if length(reason)>1000 or(outside and length(reason)=0) then raise exception 'Explain the output variance outside the approved tolerance.' using errcode='22023';end if;
   usable:=case when nullif(p_document->>'usable_weight_kg','') is not null then private.pp_stock_number(p_document->>'usable_weight_kg',true) end;
   if usable is not null and usable<>round(usable,6) then raise exception 'Record weight in KG with up to six decimal places.' using errcode='22023';end if;
   waste:=coalesce(p_document->'processing_waste','[]'::jsonb);
   if jsonb_typeof(waste) is distinct from 'array' or jsonb_array_length(waste)>100 then raise exception 'Use up to 100 measured waste lines.' using errcode='22023';end if;
   if (p_document->>'waste_confirmed') is distinct from 'true' then raise exception 'Confirm measured waste, or explicitly confirm no measured waste to record.' using errcode='22023';end if;
   if(select count(*)<>count(distinct value->>'item_id') from jsonb_array_elements(waste)) then raise exception 'Combine waste for each input into one line.' using errcode='22023';end if;
   for entry in select value from jsonb_array_elements(waste) loop
    select (value->>'quantity')::numeric into expected from jsonb_array_elements(actual_lines) where value->>'item_id'=entry->>'item_id';
    if expected is null or private.pp_stock_number(entry->>'quantity')>expected or length(trim(coalesce(entry->>'reason',''))) not between 1 and 500 then raise exception 'Measured waste must refer to a consumed input, not exceed its consumption, and have a reason.' using errcode='22023';end if;
   end loop;
   select coalesce(bool_and(u.dimension='MASS' or(l->>'quantity')::numeric=0),false),sum((l->>'quantity')::numeric*u.canonical_factor/kg.canonical_factor) into measurable,input_mass
   from jsonb_array_elements(actual_lines) l join public.items i on i.organisation_id=p_organisation_id and i.id=(l->>'item_id')::uuid join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id join public.units_of_measure kg on kg.organisation_id=i.organisation_id and kg.code='KG';
   if not measurable then input_mass:=null;end if;
   if input_mass is not null then
    select coalesce(sum((l->>'quantity')::numeric*u.canonical_factor/kg.canonical_factor),0) into waste_mass from jsonb_array_elements(waste) l join public.items i on i.organisation_id=p_organisation_id and i.id=(l->>'item_id')::uuid join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id join public.units_of_measure kg on kg.organisation_id=i.organisation_id and kg.code='KG';
    if usable is not null then
     mass_balance:=input_mass-usable-waste_mass;
     if mass_balance < -0.000001 then raise exception 'Measured usable output and waste exceed the total weight consumed. Check the measurements.' using errcode='22023';end if;
     if mass_balance>0.000001 and length(reason)=0 then raise exception 'Explain the weight not accounted for by measured usable output and recorded waste.' using errcode='22023';end if;
    end if;
   end if;
   if qty=0 and coalesce(usable,0)>0 then raise exception 'Usable output weight requires usable output quantity.' using errcode='22023';end if;
   lines:=actual_lines;
   output:=jsonb_build_object('item_id',standard.output_item_id,'quantity',qty::text,'planned_output',expected_base::text,'actual_output',actual::text,'recipe_version_id',standard.recipe_version_id,'processing_standard_id',standard.id,'expected_output',expected_base::text,'output_variance',(qty-expected_base)::text,'variance_percent',round(deviation,6)::text,'outside_tolerance',outside,'variance_reason',reason,'usable_weight_kg',usable::text,'waste_included_in_inputs',true,'output_unit_basis','STOCK_BASE');
  else raise exception 'Save a processing standard, choose its centre and record actual inputs before requesting production.' using errcode='22023';end if;
  -- Pin child bindings as evidence; future changes cannot rewrite these inputs.
 else lines:=private.pp_stock_lines(p_organisation_id,p_lines); end if;
 if kind<>'COUNT' and not(kind='PRODUCTION' and standard.id is not null) and exists(select 1 from jsonb_array_elements(lines) l where (l->>'quantity')::numeric<=0) then raise exception 'Movement quantities must be positive.' using errcode='22023'; end if;
 if kind='COUNT' then fingerprint:=private.pp_stock_fingerprint(p_organisation_id,src.id); end if;
 if kind='DIRECT_RECEIPT' then
  if nullif(p_document->>'supplier_id','') is null or not exists(select 1 from public.suppliers where organisation_id=p_organisation_id and id=(p_document->>'supplier_id')::uuid and is_active)
   or length(trim(coalesce(p_document->>'delivery_reference',''))) not between 1 and 100 then raise exception 'Choose the supplier and enter its delivery reference.' using errcode='22023'; end if;
  if exists(select 1 from public.stock_documents d where d.organisation_id=p_organisation_id and d.kind='DIRECT_RECEIPT' and d.state not in ('CANCELLED','REJECTED') and d.output->>'supplier_id'=p_document->>'supplier_id' and lower(d.output->>'delivery_reference')=lower(trim(p_document->>'delivery_reference'))) then raise exception 'This supplier delivery reference already has a stock request. Review its existing record.' using errcode='22023'; end if;
 end if;
 if kind='OPENING' and exists(select 1 from public.stock_ledger e join jsonb_array_elements(lines) l on l->>'item_id'=e.item_id::text where e.organisation_id=p_organisation_id and e.location_id=dst.id) then raise exception 'Opening balances must be the first posting for each listed material at that stock location. Use a reviewed count for corrections.' using errcode='22023'; end if;
 insert into public.stock_documents(id,organisation_id,request_id,input_hash,reference,kind,source_id,destination_id,route_id,receipt_id,recipe_version_id,document_date,note,lines,output,count_fingerprint,created_by)
 values(result,p_organisation_id,p_request_id,digest,'STK-'||upper(substr(replace(result::text,'-',''),1,12)),kind,src.id,dst.id,route.id,rec.id,case when kind='PRODUCTION' then (p_document->>'recipe_version_id')::uuid end,day,trim(p_document->>'note'),lines,
 case when kind='DIRECT_RECEIPT' then jsonb_build_object('supplier_id',p_document->>'supplier_id','delivery_reference',trim(p_document->>'delivery_reference')) else output end,fingerprint,auth.uid());
 if standard.id is not null then
  insert into public.processing_batches values(p_organisation_id,result,standard.id,expected_base,(output->>'quantity')::numeric,(output->>'output_variance')::numeric,deviation,outside,usable,reason,primary_actual,coalesce(private.pp_member_label(p_organisation_id,src.responsible_membership_id),'Assigned member'),input_mass,waste_mass,mass_balance);
  insert into public.processing_waste select p_organisation_id,result,(value->>'item_id')::uuid,(value->>'quantity')::numeric,trim(value->>'reason') from jsonb_array_elements(waste);
 end if;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_REQUESTED',auth.uid(),result,jsonb_build_object('kind',kind));
 return result;
end $$;

create or replace function public.stock_document_action(p_organisation_id uuid,p_document_id uuid,p_action text,p_note text,p_received jsonb default null) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;waste_doc public.stock_documents;waste_line jsonb;
begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock access required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into waste_doc from public.stock_documents where organisation_id=p_organisation_id and id=p_document_id and kind='WASTE';
 if found and p_action in ('APPROVE','DECLINE','POST') then
  if not private.pp_stock_doc_read(p_organisation_id,waste_doc.id) or not private.pp_waste_review(p_organisation_id,waste_doc.source_id) then raise exception 'Waste approval and posting require an authorised colleague at this centre.' using errcode='42501';end if;
  if waste_doc.created_by=auth.uid() then raise exception 'A different authorised colleague at this centre must approve and post your waste request.' using errcode='42501';end if;
  if length(trim(coalesce(p_note,''))) not between 1 and 1000 then raise exception 'Enter a decision/source note.' using errcode='22023';end if;
  if p_action='POST' then
   if waste_doc.state<>'APPROVED' then raise exception 'Waste must be approved before posting.' using errcode='22023';end if;
   for waste_line in select value from jsonb_array_elements(waste_doc.lines) loop
    perform private.pp_stock_entry(p_organisation_id,waste_doc.id,waste_doc.source_id,(waste_line->>'item_id')::uuid,-(waste_line->>'quantity')::numeric,waste_doc.document_date);
   end loop;
   update public.stock_documents set state='POSTED',completed_by=auth.uid(),completed_at=clock_timestamp(),decision_note=trim(p_note) where id=waste_doc.id;
  else
   if waste_doc.state<>'REQUESTED' then raise exception 'This waste request is no longer awaiting approval.' using errcode='22023';end if;
   update public.stock_documents set state=case when p_action='APPROVE' then 'APPROVED' else 'REJECTED' end,approved_by=auth.uid(),approved_at=clock_timestamp(),decision_note=trim(p_note),completed_by=case when p_action='DECLINE' then auth.uid() end,completed_at=case when p_action='DECLINE' then clock_timestamp() end where id=waste_doc.id;
  end if;
  insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_'||p_action,auth.uid(),waste_doc.id,jsonb_build_object('kind','WASTE','centre',waste_doc.source_id,'note',trim(p_note)));
  return waste_doc.id;
 end if;
 if p_action='POST' and exists(select 1 from public.processing_batches where organisation_id=p_organisation_id and document_id=p_document_id) then
  if not exists(select 1 from public.stock_documents d join public.processing_batches b on b.organisation_id=d.organisation_id and b.document_id=d.id join public.processing_standard_sites ss on ss.organisation_id=b.organisation_id and ss.standard_id=b.standard_id and ss.site_id=d.source_id join public.stock_locations s on s.organisation_id=ss.organisation_id and s.id=ss.site_id join public.organisation_memberships m on m.organisation_id=s.organisation_id and m.id=s.responsible_membership_id and m.status='active' where d.organisation_id=p_organisation_id and d.id=p_document_id and s.is_active and s.processing_enabled) then raise exception 'This processing centre was disabled or its responsible membership is inactive. Resolve setup before posting.' using errcode='22023';end if;
 end if;
 result:=private.pp_stock_action_before_processing(p_organisation_id,p_document_id,p_action,p_note,p_received);
 if p_action='POST' and exists(select 1 from public.processing_batches where organisation_id=p_organisation_id and document_id=result) then insert into private.processing_batch_costs values(p_organisation_id,result,private.pp_processing_cost_snapshot(p_organisation_id,result),now()) on conflict do nothing;end if;
 return result;
end $$;
create or replace function public.stock_access_directory(p_organisation_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'An Inventory Manager or business-wide Restaurant Administrator must manage department access.' using errcode='42501'; end if;
 select jsonb_build_object('members',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'email',u.email,'display_name',private.pp_member_label(m.organisation_id,m.id),'mode',coalesce(a.mode,case when exists(select 1 from public.membership_roles x where x.organisation_id=m.organisation_id and x.membership_id=m.id and x.role_code in ('stock_department','kitchen_manager','bar_lead','stock_receiver','stock_dispatcher')) then 'ASSIGNED' else 'OUTLET' end),'revision',coalesce(a.revision,0),
  'review_access',exists(select 1 from public.membership_roles r where r.organisation_id=m.organisation_id and r.membership_id=m.id and r.role_code in ('restaurant_admin','inventory_manager','ceo','finance','procurement')),
  'roles',(select jsonb_agg(jsonb_build_object('role_code',r.role_code,'outlet_id',r.location_id,'outlet_name',l.name) order by r.role_code,r.location_id) from public.membership_roles r left join public.locations l on l.organisation_id=r.organisation_id and l.id=r.location_id where r.organisation_id=m.organisation_id and r.membership_id=m.id),
  'assignments',coalesce((select jsonb_agg(jsonb_build_object('location_id',g.location_id,'can_request',g.can_request,'can_handle',g.can_handle,'can_approve',g.can_approve,'can_dispatch',g.can_dispatch,'can_receive',g.can_receive,'can_review_waste',g.can_review_waste) order by g.location_id) from public.stock_member_locations g where g.organisation_id=m.organisation_id and g.membership_id=m.id),'[]'::jsonb)) order by u.email,m.id)
 from public.organisation_memberships m join auth.users u on u.id=m.user_id left join public.stock_member_access a on a.organisation_id=m.organisation_id and a.membership_id=m.id
 where m.organisation_id=p_organisation_id and m.status='active' and exists(select 1 from public.membership_roles r where r.organisation_id=m.organisation_id and r.membership_id=m.id and r.role_code in ('inventory','operations','stock_department','kitchen_manager','bar_lead','stock_receiver','stock_dispatcher'))),'[]'::jsonb)) into result;
 return result;
end $$;
notify pgrst,'reload schema';
commit;
