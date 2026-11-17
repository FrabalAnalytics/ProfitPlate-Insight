-- Apply once after 029. Separate order/receipt registers, material reports and reconciliation.
begin;
create function public.purchasing_report_options(p_organisation_id uuid,p_type text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare base jsonb;
begin
 if p_type is null or p_type not in ('PO','GRN') then raise exception 'Choose Purchase Orders or Goods Received Notes.' using errcode='22023'; end if;
 base:=public.operational_report_options(p_organisation_id,p_type);
 return base||jsonb_build_object('comparison',private.pp_reference_price_read(p_organisation_id),
  'suppliers',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name,s.id) from public.suppliers s
   where s.organisation_id=p_organisation_id and exists(select 1 from public.purchase_orders o where o.organisation_id=s.organisation_id and o.supplier_id=s.id and private.pp_order_read(s.organisation_id,o.id))),'[]'::jsonb),
  'materials',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',i.name,'code',i.code) order by i.name,i.id) from public.items i
   where i.organisation_id=p_organisation_id and exists(select 1 from public.purchase_order_lines l join public.purchase_orders o on o.organisation_id=l.organisation_id and o.id=l.order_id
    where l.organisation_id=i.organisation_id and l.item_id=i.id and private.pp_order_read(i.organisation_id,o.id))),'[]'::jsonb),
  'users',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.label) order by a.label,a.id) from(
   select o.created_by id,min(o.created_label) label from public.purchase_orders o where p_type='PO' and o.organisation_id=p_organisation_id and private.pp_order_read(p_organisation_id,o.id) group by o.created_by
   union all select g.created_by,min(g.created_label) from public.goods_receipts g join public.purchase_orders o on o.organisation_id=g.organisation_id and o.id=g.order_id
    where p_type='GRN' and g.organisation_id=p_organisation_id and private.pp_order_read(p_organisation_id,o.id) group by g.created_by
  )a),'[]'::jsonb));
end $$;

create function private.pp_po_billing(org uuid,po uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 with latest as materialized (
  select c.*,private.pp_current_invoice(org,c.purchase_id) invoice from public.invoice_procurement_contexts c
  where c.organisation_id=org and c.order_id=po and c.route='PO'
   and c.version=(select max(x.version) from public.invoice_procurement_contexts x where x.organisation_id=org and x.purchase_id=c.purchase_id)
 ), live as materialized(select * from latest where not(invoice->>'voided')::boolean),
 checks as (
  select c.*,c.invoice_revision<>(c.invoice->>'revision')::integer or c.invoice->'header'->>'supplier_id'<>o.supplier_id::text
   or c.invoice->'header'->>'location_id'<>o.location_id::text or c.invoice->'header'->>'currency'<>o.payload->'header'->>'currency'
   or exists(select 1 from jsonb_array_elements(c.invoice->'lines') with ordinality li(value,n)
    left join lateral(select m.value from jsonb_array_elements(c.mappings)m where(m.value->>'line')::integer=li.n)map on true
    left join public.purchase_order_lines p on p.organisation_id=org and p.order_id=po and p.id=(map.value->>'order_line_id')::uuid
    where p.id is null or li.value->>'item_id'<>p.item_id::text) invalid,
   exists(select 1 from public.purchase_corrections x where x.organisation_id=org and x.purchase_id=c.purchase_id and x.state='PENDING') pending
  from live c join public.purchase_orders o on o.organisation_id=org and o.id=po
 ), mapped as (
  select p.id,sum((li.value->>'base_quantity')::numeric)/max((p.payload->>'conversion_factor')::numeric) quantity,
   sum((li.value->>'base_quantity')::numeric) base_quantity,
   sum((li.value->>'net_amount')::numeric) net_amount,jsonb_agg(distinct jsonb_build_object('id',c.purchase_id,'reference',c.invoice->'header'->>'reference')) links
  from checks c cross join lateral jsonb_array_elements(c.invoice->'lines') with ordinality li(value,n)
  cross join lateral jsonb_array_elements(c.mappings)m
  join public.purchase_order_lines p on p.organisation_id=org and p.order_id=po and p.id=(m.value->>'order_line_id')::uuid
  where(m.value->>'line')::integer=li.n and not c.invalid group by p.id
 ) select jsonb_build_object('invoices',(select count(*) from live),'invalid',coalesce((select bool_or(invalid) from checks),false),
  'pending',coalesce((select bool_or(pending) from checks),false) or exists(select 1 from public.goods_receipt_void_requests v join public.goods_receipts g on g.organisation_id=v.organisation_id and g.id=v.receipt_id where g.organisation_id=org and g.order_id=po and v.state='PENDING'),
  'lines',coalesce((select jsonb_object_agg(id::text,jsonb_build_object('quantity',quantity::text,'base_quantity',base_quantity::text,'net_amount',net_amount::text,'links',links)) from mapped),'{}'::jsonb),
  'links',coalesce((select jsonb_agg(jsonb_build_object('id',purchase_id,'reference',invoice->'header'->>'reference') order by purchase_id) from live),'[]'::jsonb));
$$;

create function private.pp_purchasing_rows(org uuid,report_type text,report_view text,day_from date,day_to date,outlet uuid,supplier uuid,material uuid,actor uuid)
returns setof jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if report_type='PO' then
  return query with orders as materialized (
   select o.*,coalesce(o.payload->'header'->>'location_name',l.name) outlet_name,coalesce(o.payload->'header'->>'supplier_name',s.name) supplier_name from public.purchase_orders o
   join public.locations l on l.organisation_id=org and l.id=o.location_id join public.suppliers s on s.organisation_id=org and s.id=o.supplier_id
   where o.organisation_id=org and o.document_date between day_from and day_to and private.pp_order_read(org,o.id)
    and(outlet is null or o.location_id=outlet) and(supplier is null or o.supplier_id=supplier) and(actor is null or o.created_by=actor)
    and(material is null or exists(select 1 from public.purchase_order_lines x where x.organisation_id=org and x.order_id=o.id and x.item_id=material))
  ), lines as materialized (
   select p.*,coalesce((select sum(r.accepted) from public.goods_receipt_lines r where r.organisation_id=org and r.order_line_id=p.id and not private.pp_receipt_voided(org,r.receipt_id)),0) accepted
   from public.purchase_order_lines p join orders o on o.id=p.order_id where p.organisation_id=org
  ), progress as (
   select order_id,bool_and(accepted>=quantity) complete,bool_or(accepted>0) started,count(*) material_lines,
    sum((payload->>'net_amount')::numeric) net_amount,sum((payload->>'tax')::numeric) tax,sum((payload->>'line_discount')::numeric) discount,string_agg(concat_ws(' ',payload->>'item_name',i.code),' ') material_search
   from lines l join public.items i on i.organisation_id=org and i.id=l.item_id group by order_id
  ), prepared as materialized (
   select o.*,p.*,case when o.status='DRAFT' then 'NOT_ISSUED' when p.complete then 'COMPLETED' when p.started then 'PARTIAL' else 'PENDING' end receiving,
    case when report_view='COMPARISON' then private.pp_po_billing(org,o.id) end billing
   from orders o join progress p on p.order_id=o.id
  ), rows as (
   select jsonb_build_object('id',o.id,'document_id',o.id,'reference',o.reference,'date',o.document_date,'kind','PO','state',o.status,'order_state',o.status,'receiving_state',o.receiving,
    'outlet',o.outlet_name,'party',o.supplier_name,'supplier_id',o.supplier_id,'actor',o.created_label,'material_lines',o.material_lines,'materials_search',o.material_search,
    'amount',o.payload->'header'->>'total','net_amount',o.net_amount::text,'tax',o.tax::text,'discount',o.discount::text,'currency',o.payload->'header'->>'currency',
    'notes',o.notes,'path','/workspace/purchases/orders','params',jsonb_build_object('order',o.id)) r
   from prepared o where report_view='REGISTER'
   union all
   select jsonb_build_object('id',p.id,'document_id',o.id,'reference',o.reference,'date',o.document_date,'kind','PO','state',o.status,'order_state',o.status,'receiving_state',o.receiving,
    'outlet',o.outlet_name,'party',o.supplier_name,'supplier_id',o.supplier_id,'actor',o.created_label,'position',p.position,'item',p.payload->>'item_name','item_code',i.code,'item_id',p.item_id,
    'unit',p.payload->>'unit_code','quantity',p.quantity::text,'accepted',p.accepted::text,'remaining',(p.quantity-p.accepted)::text,
    'unit_price',p.payload->>'unit_price','price_basis',o.payload->'header'->>'price_basis','net_amount',p.payload->>'net_amount','discount',p.payload->>'line_discount','tax',p.payload->>'tax',
    'amount',case when report_view='DETAIL' then p.payload->>'invoice_amount' end,'currency',o.payload->'header'->>'currency',
    'quoted_net_unit_price',((p.payload->>'net_amount')::numeric/p.quantity)::text,
    'billed',case when o.billing is not null and not(o.billing->>'invalid')::boolean and(o.billing->>'invoices')::integer>0 then coalesce(o.billing->'lines'->p.id::text->>'quantity','0') end,
    'billed_net_amount',case when o.billing is not null and not(o.billing->>'invalid')::boolean and(o.billing->>'invoices')::integer>0 then coalesce(o.billing->'lines'->p.id::text->>'net_amount','0') end,
    'billed_base',case when o.billing is not null and not(o.billing->>'invalid')::boolean and(o.billing->>'invoices')::integer>0 then coalesce(o.billing->'lines'->p.id::text->>'base_quantity','0') end,
    'quoted_base_quantity',p.payload->>'base_quantity',
    'billing_invalid',o.billing->'invalid','billing_pending',o.billing->'pending','invoice_count',o.billing->'invoices','invoices',case when(o.billing->>'invalid')::boolean then o.billing->'links' else coalesce(o.billing->'lines'->p.id::text->'links','[]'::jsonb) end,
    'notes',o.notes,'path','/workspace/purchases/orders','params',jsonb_build_object('order',o.id)) r
   from prepared o join lines p on p.order_id=o.id join public.items i on i.organisation_id=org and i.id=p.item_id
   where report_view in ('DETAIL','COMPARISON') and(material is null or p.item_id=material)
  ), calculated as (
   select r,(r->>'billed')::numeric billed,(r->>'billed_net_amount')::numeric billed_net,(r->>'quoted_net_unit_price')::numeric quoted_price,
    (r->>'billed_base')::numeric billed_base,(r->>'quoted_base_quantity')::numeric quoted_base,
    (r->>'quoted_base_quantity')::numeric/nullif((r->>'quantity')::numeric,0) factor from rows
  ) select r||case when report_view='COMPARISON' then jsonb_build_object(
   'billed_net_unit_price',(billed_net*factor/nullif(billed_base,0))::text,'unit_price_variance',round(billed_net*factor/nullif(billed_base,0)-quoted_price,12)::text,
   'price_impact',case when billed>0 then round(billed_net-billed_base*(r->>'net_amount')::numeric/quoted_base,12)::text end,
   'billing_gap',((billed_base-(r->>'accepted')::numeric*factor)/factor)::text,
   'comparison_state',case when(r->>'billing_invalid')::boolean then 'LINK_REVIEW' when(r->>'invoice_count')::integer=0 or billed=0 then 'NO_INVOICES'
    when(r->>'billing_pending')::boolean then 'CORRECTION_PENDING'
    when billed_base>(r->>'accepted')::numeric*factor and billed_net*quoted_base<>billed_base*(r->>'net_amount')::numeric then 'QUANTITY_AND_PRICE'
    when billed_base>(r->>'accepted')::numeric*factor then 'QUANTITY_EXCEPTION'
    when billed>0 and billed_net*quoted_base<>billed_base*(r->>'net_amount')::numeric then 'PRICE_EXCEPTION' else 'ALIGNED' end) else '{}'::jsonb end from calculated;
 else
  return query with receipts as materialized (
   select g.*,o.reference po_reference,o.supplier_id,o.location_id,o.document_date po_date,coalesce(o.payload->'header'->>'location_name',l.name) outlet_name,coalesce(o.payload->'header'->>'supplier_name',s.name) supplier_name,
    case when private.pp_receipt_voided(org,g.id) then 'VOIDED' when exists(select 1 from public.goods_receipt_void_requests v where v.organisation_id=org and v.receipt_id=g.id and v.state='PENDING') then 'VOID_PENDING' else 'ACTIVE' end receipt_state
   from public.goods_receipts g join public.purchase_orders o on o.organisation_id=g.organisation_id and o.id=g.order_id
   join public.locations l on l.organisation_id=org and l.id=o.location_id join public.suppliers s on s.organisation_id=org and s.id=o.supplier_id
   where g.organisation_id=org and g.received_on between day_from and day_to and private.pp_order_read(org,o.id)
    and(outlet is null or o.location_id=outlet) and(supplier is null or o.supplier_id=supplier) and(actor is null or g.created_by=actor)
    and(material is null or exists(select 1 from public.goods_receipt_lines x join public.purchase_order_lines p on p.organisation_id=x.organisation_id and p.id=x.order_line_id where x.organisation_id=org and x.receipt_id=g.id and p.item_id=material))
  ) select jsonb_build_object('id',g.id,'document_id',g.id,'reference',g.reference,'date',g.received_on,'kind','GRN','state',g.receipt_state,
   'order_id',g.order_id,'related_reference',g.po_reference,'outlet',g.outlet_name,'party',g.supplier_name,'actor',g.created_label,
   'materials_search',(select string_agg(concat_ws(' ',p.payload->>'item_name',i.code),' ') from public.goods_receipt_lines r join public.purchase_order_lines p on p.organisation_id=org and p.id=r.order_line_id join public.items i on i.organisation_id=org and i.id=p.item_id where r.organisation_id=org and r.receipt_id=g.id),'delivery_reference',g.delivery_reference,'material_lines',(select count(*) from public.goods_receipt_lines r where r.organisation_id=org and r.receipt_id=g.id),
   'notes',g.notes,'path','/workspace/purchases/orders','params',jsonb_build_object('order',g.order_id,'receipt',g.id))
   from receipts g where report_view='REGISTER'
   union all
   select jsonb_build_object('id',r.id,'document_id',g.id,'reference',g.reference,'date',g.received_on,'kind','GRN','state',g.receipt_state,
    'order_id',g.order_id,'related_reference',g.po_reference,'outlet',g.outlet_name,'party',g.supplier_name,'actor',g.created_label,'position',p.position,
    'item',p.payload->>'item_name','item_code',i.code,'item_id',p.item_id,'unit',p.payload->>'unit_code','quantity',p.quantity::text,'accepted',r.accepted::text,'rejected',r.rejected::text,'rejection_reason',r.rejection_reason,
    'delivery_reference',g.delivery_reference,'notes',g.notes,'path','/workspace/purchases/orders','params',jsonb_build_object('order',g.order_id,'receipt',g.id))
   from receipts g join public.goods_receipt_lines r on r.organisation_id=org and r.receipt_id=g.id
   join public.purchase_order_lines p on p.organisation_id=org and p.id=r.order_line_id join public.items i on i.organisation_id=org and i.id=p.item_id
   where report_view='DETAIL' and(material is null or p.item_id=material);
 end if;
end $$;

create function public.purchasing_history_report(p_organisation_id uuid,p_type text,p_view text,p_from date,p_to date,p_outlet_id uuid,p_supplier_id uuid,p_item_id uuid,p_user_id uuid,p_status text,p_receiving text,p_search text,p_page integer,p_export boolean default false)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare opts jsonb; allowed text[]; packet jsonb; size integer:=case when p_export then 5000 else 10 end;
begin
 opts:=public.purchasing_report_options(p_organisation_id,p_type);
 if p_view is null or p_view not in ('REGISTER','DETAIL','COMPARISON') or(p_view='COMPARISON' and(p_type<>'PO' or not private.pp_reference_price_read(p_organisation_id))) then raise exception 'This report view is unavailable for your role.' using errcode='42501'; end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>365 or p_to>(select(now() at time zone time_zone)::date from public.organisations where id=p_organisation_id)
  or p_page is null or p_page not between 1 and 100000 or p_search is null or length(p_search)>80 or p_export is null then raise exception 'Choose valid reporting dates (up to 366 days), search and page.' using errcode='22023'; end if;
 if p_outlet_id is not null and not exists(select 1 from jsonb_array_elements(opts->'outlets')r where r->>'id'=p_outlet_id::text) then raise exception 'Report outlet unavailable.' using errcode='42501'; end if;
 if p_supplier_id is not null and not exists(select 1 from jsonb_array_elements(opts->'suppliers')r where r->>'id'=p_supplier_id::text) then raise exception 'Report supplier unavailable.' using errcode='42501'; end if;
 if p_item_id is not null and not exists(select 1 from jsonb_array_elements(opts->'materials')r where r->>'id'=p_item_id::text) then raise exception 'Report material unavailable.' using errcode='42501'; end if;
 if p_user_id is not null and not exists(select 1 from jsonb_array_elements(opts->'users')r where r->>'id'=p_user_id::text) then raise exception 'Report user unavailable.' using errcode='42501'; end if;
 allowed:=case when p_type='PO' then array['ALL','DRAFT','ISSUED'] else array['ALL','ACTIVE','VOID_PENDING','VOIDED'] end;
 if p_status is null or not p_status=any(allowed) or p_receiving is null or p_receiving not in ('ALL','NOT_ISSUED','PENDING','PARTIAL','COMPLETED') or(p_type='GRN' and p_receiving<>'ALL') then raise exception 'Choose a valid order, receiving or GRN status.' using errcode='22023'; end if;
 with filtered as materialized (
  select r from private.pp_purchasing_rows(p_organisation_id,p_type,p_view,p_from,p_to,p_outlet_id,p_supplier_id,p_item_id,p_user_id)r
  where(p_status='ALL' or r->>'state'=p_status) and(p_receiving='ALL' or r->>'receiving_state'=p_receiving)
   and(trim(p_search)='' or position(lower(trim(p_search)) in lower(concat_ws(' ',r->>'reference',r->>'related_reference',r->>'party',r->>'item',r->>'item_code',r->>'outlet',r->>'notes',r->>'actor',r->>'delivery_reference',r->>'rejection_reason',r->>'materials_search')))>0)
 ), paged as(select r from filtered order by r->>'date' desc,r->>'reference',coalesce((r->>'position')::integer,0),r->>'id' limit size offset case when p_export then 0 else(p_page-1)*size end),
 totals as(select r->>'currency' currency,sum((r->>'amount')::numeric)::text amount from filtered where r->>'amount' is not null group by r->>'currency')
 select jsonb_build_object('total',(select count(*) from filtered),'documents',(select count(distinct r->>'document_id') from filtered),'page_size',size,'unpriced',0,
  'rows',coalesce((select jsonb_agg(r order by r->>'date' desc,r->>'reference',coalesce((r->>'position')::integer,0),r->>'id') from paged),'[]'::jsonb),
  'totals',coalesce((select jsonb_agg(to_jsonb(t) order by currency) from totals t),'[]'::jsonb),'refreshed_at',statement_timestamp(),'export',p_export,'view',p_view) into packet;
 if p_export and(packet->>'total')::integer>5000 then raise exception 'This export exceeds 5,000 rows. Narrow the report filters; no partial file was created.' using errcode='22023'; end if;
 return packet;
end $$;
revoke all on function private.pp_po_billing(uuid,uuid),private.pp_purchasing_rows(uuid,text,text,date,date,uuid,uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.purchasing_report_options(uuid,text),public.purchasing_history_report(uuid,text,text,date,date,uuid,uuid,uuid,uuid,text,text,text,integer,boolean) from public,anon;
grant execute on function public.purchasing_report_options(uuid,text),public.purchasing_history_report(uuid,text,text,date,date,uuid,uuid,uuid,uuid,text,text,text,integer,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
