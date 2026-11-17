-- Apply once after 027. Read-only, current corrected history with scoped exports.
begin;
create function private.pp_operational_types(org uuid) returns text[]
language plpgsql stable security definer set search_path='' as $$
declare result text[]:='{}'; stock boolean;
begin
 if private.pp_reference_price_read(org) or private.pp_inventory_access(org) then result:=result||array['PO','GRN']; end if;
 if private.pp_reference_price_read(org) then result:=result||array['INVOICE']; end if;
 if private.pp_sales_read(org) then result:=result||array['SALES']; end if;
 select exists(select 1 from public.organisation_memberships m join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id
  where m.organisation_id=org and m.user_id=auth.uid() and m.status='active' and r.role_code in
  ('ceo','restaurant_admin','finance','inventory_manager','inventory','operations','stock_department','stock_receiver','stock_dispatcher')) into stock;
 if stock then result:=result||array['REQUISITIONS','WASTE','COUNTS','CONSUMPTION','PRODUCTION','STOCK_RECEIPTS','MOVEMENTS']; end if;
 return result;
end $$;

create function public.operational_report_options(p_organisation_id uuid,p_type text default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare types text[]:=private.pp_operational_types(p_organisation_id); chosen text; stock boolean;
begin
 if cardinality(types)=0 then raise exception 'Historical report access denied.' using errcode='42501'; end if;
 chosen:=coalesce(p_type,types[1]);
 if not chosen=any(types) then raise exception 'This report is not available to your assigned roles.' using errcode='42501'; end if;
 stock:=chosen not in ('PO','GRN','INVOICE','SALES');
 return jsonb_build_object('types',to_jsonb(types),'selected',chosen,'financial',private.pp_reference_price_read(p_organisation_id),
  'outlets',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'name',l.name,'active',l.is_active) order by l.name,l.id)
   from public.locations l where l.organisation_id=p_organisation_id and
   (case when stock then exists(select 1 from public.stock_locations s where s.organisation_id=l.organisation_id and s.outlet_id=l.id and private.pp_stock_site(s.organisation_id,s.id,'read'))
    when chosen in ('PO','GRN') then private.pp_reference_price_read(p_organisation_id) or private.pp_inventory_access(p_organisation_id,l.id)
    else private.pp_reference_price_read(p_organisation_id) end)),'[]'::jsonb),
  'stock_locations',case when stock then coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'outlet_id',s.outlet_id,'active',s.is_active) order by s.name,s.id)
    from public.stock_locations s where s.organisation_id=p_organisation_id and private.pp_stock_site(p_organisation_id,s.id,'read')),'[]'::jsonb) else '[]'::jsonb end);
end $$;

create function private.pp_operational_rows(org uuid,report_type text,day_from date,day_to date,outlet uuid,site uuid)
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
   where d.organisation_id=org and d.document_date between day_from and day_to and private.pp_stock_doc_read(org,d.id)
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

create function public.operational_report(p_organisation_id uuid,p_type text,p_from date,p_to date,p_outlet_id uuid,p_stock_location_id uuid,p_status text,p_search text,p_page integer,p_export boolean default false)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare options jsonb; allowed text[]; result jsonb; row_count integer; page_size integer:=case when p_export then 5000 else 10 end;
begin
 options:=public.operational_report_options(p_organisation_id,p_type);
 p_type:=options->>'selected';
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>365 or p_to>(select(now() at time zone time_zone)::date from public.organisations where id=p_organisation_id)
  or p_page is null or p_page not between 1 and 100000 or p_search is null or length(p_search)>80 or p_export is null then
  raise exception 'Choose valid dates (up to 366 days), a search up to 80 characters and an available page. Future dates are unavailable.' using errcode='22023'; end if;
 if p_outlet_id is not null and not exists(select 1 from jsonb_array_elements(options->'outlets')o where o->>'id'=p_outlet_id::text) then raise exception 'Report outlet unavailable.' using errcode='42501'; end if;
 if p_stock_location_id is not null and not exists(select 1 from jsonb_array_elements(options->'stock_locations')s where s->>'id'=p_stock_location_id::text) then raise exception 'Report stock location unavailable.' using errcode='42501'; end if;
 allowed:=case p_type when 'PO' then array['ALL','DRAFT','ISSUED','PENDING','PARTIAL','COMPLETED'] when 'GRN' then array['ALL','ACTIVE','VOIDED','VOID_PENDING']
  when 'INVOICE' then array['ALL','ACTIVE','VOIDED','CORRECTION_PENDING'] when 'SALES' then array['ALL','RECORDED']
  when 'REQUISITIONS' then array['ALL','REQUESTED','APPROVED','DISPATCHED','RECEIVED','PARTIAL','REJECTED','CANCELLED','FOLLOW_UP']
  when 'MOVEMENTS' then array['ALL','REQUESTED','APPROVED','DISPATCHED','RECEIVED','PARTIAL','REJECTED','POSTED','CANCELLED','FOLLOW_UP']
  else array['ALL','REQUESTED','APPROVED','POSTED','REJECTED','CANCELLED'] end;
 if p_status is null or not p_status=any(allowed) then raise exception 'Choose a valid report status.' using errcode='22023'; end if;
 with filtered as materialized (
  select r from private.pp_operational_rows(p_organisation_id,p_type,p_from,p_to,p_outlet_id,p_stock_location_id)r
  where(p_status='ALL' or r->>'state'=p_status or(p_type='PO' and p_status='ISSUED' and r->>'order_state'='ISSUED')
   or(p_status='FOLLOW_UP' and r->>'state' in ('PARTIAL','REJECTED') and not coalesce((r->>'resolved')::boolean,false)))
   and(trim(p_search)='' or position(lower(trim(p_search)) in lower(concat_ws(' ',r->>'reference',r->>'related_reference',r->>'party',r->>'item',r->>'outlet',r->>'source',r->>'destination',r->>'notes',r->>'actor')))>0)
 ), paged as(select r from filtered order by r->>'date' desc,r->>'reference',r->>'id' limit page_size offset case when p_export then 0 else(p_page-1)*page_size end), totals as (
  select r->>'currency' currency,sum((r->>'amount')::numeric)::text amount from filtered where r->>'amount' is not null and r->>'state'<>'VOIDED' group by r->>'currency'
 ) select jsonb_build_object('total',(select count(*) from filtered),'documents',(select count(distinct r->>'document_id') from filtered),'page_size',page_size,
  'rows',coalesce((select jsonb_agg(r order by r->>'date' desc,r->>'reference',r->>'id') from paged),'[]'::jsonb),
  'totals',coalesce((select jsonb_agg(to_jsonb(t) order by currency) from totals t),'[]'::jsonb),
  'unpriced',(select count(*) from filtered where p_type='WASTE' and r->>'kind'='WASTE' and r->>'state'='POSTED' and r->>'amount' is null),
  'refreshed_at',statement_timestamp(),'export',p_export) into result;
 row_count:=(result->>'total')::integer;
 if p_export and row_count>5000 then raise exception 'This export exceeds 5,000 rows. Narrow the dates, location, status or search before exporting. No partial file was created.' using errcode='22023'; end if;
 return result;
end $$;

revoke all on function private.pp_operational_types(uuid),private.pp_operational_rows(uuid,text,date,date,uuid,uuid) from public,anon,authenticated;
revoke all on function public.operational_report_options(uuid,text),public.operational_report(uuid,text,date,date,uuid,uuid,text,text,integer,boolean) from public,anon;
grant execute on function public.operational_report_options(uuid,text),public.operational_report(uuid,text,date,date,uuid,uuid,text,text,integer,boolean) to authenticated;
create or replace function public.workspace_navigation_access(p_organisation_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('overview',private.pp_sales_read(p_organisation_id),'expenses',private.pp_sales_read(p_organisation_id),
 'sales',private.pp_sales_read(p_organisation_id),'purchases',private.pp_reference_price_read(p_organisation_id),
 'orders',private.pp_reference_price_read(p_organisation_id) or private.pp_inventory_access(p_organisation_id),'inventory',private.pp_stock_read(p_organisation_id),
 'menus',private.pp_reference_price_read(p_organisation_id),'recipes',private.pp_catalogue_read(p_organisation_id),
 'catalogue',private.pp_catalogue_read(p_organisation_id),'team',private.pp_team_manage(p_organisation_id),'history',cardinality(private.pp_operational_types(p_organisation_id))>0);
$$;
create index pp_stock_history_dates on public.stock_documents(organisation_id,document_date desc,id);
create index pp_grn_history_dates on public.goods_receipts(organisation_id,received_on desc,id);
notify pgrst,'reload schema';
commit;
