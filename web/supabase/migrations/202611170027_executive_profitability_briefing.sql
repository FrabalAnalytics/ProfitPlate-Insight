-- Apply once after 026. Read-only executive evidence, not inventory valuation.
begin;
create function public.executive_profitability_briefing(p_organisation_id uuid,p_from date,p_to date,p_location_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare overview jsonb; previous jsonb; prices jsonb; waste jsonb; movements jsonb; menus jsonb;
 currency text; prior_from date; prior_to date; invoice_count integer;
begin
 -- Reuse business-wide financial authorisation and date/outlet/volume checks.
 overview:=public.executive_overview(p_organisation_id,p_from,p_to,p_location_id);
 currency:=overview->'summary'->>'currency_code';
 prior_from:=(overview->'comparison'->>'from')::date; prior_to:=p_from-1;
 if overview->'comparison'->>'reason' is null then
  previous:=public.sales_period_summary(p_organisation_id,prior_from,prior_to,p_location_id);
 end if;
 select count(*) into invoice_count from public.purchase_headers where organisation_id=p_organisation_id;
 if invoice_count>10000 then
  prices:=jsonb_build_object('unavailable','Purchase comparison exceeds 10,000 invoices. Narrowing the reporting dates cannot reduce the corrected-invoice history required.','rows','[]'::jsonb);
 else
  -- Corrections may move dates/outlets or void invoices. Never use stale source lines.
  with invoices as materialized (
   select h.id,private.pp_current_invoice(p_organisation_id,h.id) v from public.purchase_headers h where h.organisation_id=p_organisation_id
  ), lines as (
   select h.id,(v->'header'->>'date')::date as purchase_day,(v->'header'->>'location_id')::uuid outlet,
    v->'header'->>'location_name' outlet_name,v->'header'->>'supplier_name' supplier,
    (l->>'item_id')::uuid item_id,l->>'item_name' item_name,(l->>'net_amount')::numeric net,(l->>'base_quantity')::numeric qty
   from invoices h cross join lateral jsonb_array_elements(v->'lines') l
   where not coalesce((v->>'voided')::boolean,false) and v->'header'->>'currency'=currency
    and (v->'header'->>'date')::date between prior_from and p_to
    and(p_location_id is null or v->'header'->>'location_id'=p_location_id::text)
  ), grouped as (
   select item_id,min(item_name) name,outlet,min(outlet_name) outlet_name,
    string_agg(distinct supplier,', ' order by supplier) suppliers,
    sum(net) filter(where purchase_day between p_from and p_to) current_net,sum(qty) filter(where purchase_day between p_from and p_to) current_qty,
    sum(net) filter(where purchase_day between prior_from and prior_to) prior_net,sum(qty) filter(where purchase_day between prior_from and prior_to) prior_qty
   from lines group by item_id,outlet
  ), priced as (
   select g.*,i.base_uom_id,u.code unit,current_net/current_qty current_price,prior_net/prior_qty prior_price,
    current_qty*(current_net/current_qty-prior_net/prior_qty) impact
   from grouped g join public.items i on i.organisation_id=p_organisation_id and i.id=g.item_id
   join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id
   where current_qty>0 and prior_qty>0
  ), rising as(select * from priced where impact>0)
  select jsonb_build_object('unavailable',null,'total',count(*),'impact',coalesce(sum(impact),0)::text,
   'rows',coalesce((select jsonb_agg(to_jsonb(r) order by r.impact::numeric desc,r.name,r.outlet) from (
    select item_id,name,outlet,outlet_name,suppliers,unit,current_price::text,prior_price::text,impact::text,
     round((current_price/prior_price-1)*100,6)::text change_percent from rising order by rising.impact desc,name,outlet limit 5
   )r),'[]'::jsonb),'unmatched',(select count(*) from grouped where current_qty>0 and prior_qty is null),
   'excluded_currency_invoices',(select count(*) from invoices where not coalesce((v->>'voided')::boolean,false)
    and(v->'header'->>'date')::date between prior_from and p_to and v->'header'->>'currency'<>currency
    and(p_location_id is null or v->'header'->>'location_id'=p_location_id::text))) into prices from rising;
 end if;

 -- Only posted negative WASTE/COUNT ledger entries; never pending requests or transfers.
 with entries as (
  select l.id,l.location_id,l.item_id,-l.quantity quantity,l.occurred_on,d.id document_id,d.reference,d.kind,
   s.name location_name,coalesce(o.name,'Central / shared store') outlet_name,i.name item_name,u.code unit,
   case when p.currency_code=currency and p.base_uom_id=i.base_uom_id then -l.quantity*p.cost_per_base_unit end value
  from public.stock_ledger l join public.stock_documents d on d.organisation_id=l.organisation_id and d.id=l.document_id
  join public.stock_locations s on s.organisation_id=l.organisation_id and s.id=l.location_id
  left join public.locations o on o.organisation_id=s.organisation_id and o.id=s.outlet_id
  join public.items i on i.organisation_id=l.organisation_id and i.id=l.item_id
  join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id
  left join lateral(select p.* from public.material_reference_prices p where p.organisation_id=l.organisation_id and p.item_id=l.item_id
   and p.price_date<=l.occurred_on order by p.price_date desc,p.version desc limit 1)p on true
  where l.organisation_id=p_organisation_id and l.occurred_on between prior_from and p_to and l.quantity<0
   and d.kind in ('WASTE','COUNT') and d.state='POSTED' and(p_location_id is null or s.outlet_id=p_location_id)
 ), current_rows as(select * from entries where occurred_on between p_from and p_to)
 select jsonb_build_object('lines',count(*),'unpriced',count(*) filter(where value is null),
  'known_value',coalesce(sum(value),0)::text,'waste_value',coalesce(sum(value) filter(where kind='WASTE'),0)::text,
  'shortage_value',coalesce(sum(value) filter(where kind='COUNT'),0)::text,
  'prior_lines',(select count(*) from entries where occurred_on between prior_from and prior_to),
  'prior_unpriced',(select count(*) from entries where occurred_on between prior_from and prior_to and value is null),
  'prior_value',(select coalesce(sum(value),0)::text from entries where occurred_on between prior_from and prior_to),
  'change_value',(coalesce(sum(value),0)-(select coalesce(sum(value),0) from entries where occurred_on between prior_from and prior_to))::text,
  'rows',coalesce((select jsonb_agg(to_jsonb(r) order by r.value::numeric desc nulls last,r.id) from (
   select id,document_id,reference,kind,location_id,location_name,outlet_name,item_name,unit,quantity::text,value::text
   from current_rows order by current_rows.value desc nulls last,id limit 5)r),'[]'::jsonb)) into waste from current_rows;

 -- Current unresolved accountability, deliberately independent of historical period.
 with unresolved as (
  select d.id,d.reference,d.state,d.created_at,d.created_by,d.dispatched_by,
   s.name source_name,t.name destination_name,coalesce(so.name,'Central / shared store') source_outlet,
   coalesce(ta.name,'Central / shared store') destination_outlet,
   case when d.state='REQUESTED' then 'Inventory Manager: review request'
    when d.state='APPROVED' then 'Inventory Manager: authorise dispatch'
    when d.state='DISPATCHED' then t.name||': accept or reject'
    else 'Inventory Manager: resolve rejected / incomplete handover' end next_action,
   coalesce(d.dispatched_at,d.approved_at,d.created_at) waiting_since,
   d.dispatched_at is not null and d.state in ('DISPATCHED','PARTIAL','REJECTED') handover
  from public.stock_documents d
  join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id
  join public.stock_locations t on t.organisation_id=d.organisation_id and t.id=d.destination_id
  left join public.locations so on so.organisation_id=s.organisation_id and so.id=s.outlet_id
  left join public.locations ta on ta.organisation_id=t.organisation_id and ta.id=t.outlet_id
  where d.organisation_id=p_organisation_id and d.kind in ('ISSUE','TRANSFER')
   and(d.state in ('REQUESTED','APPROVED','DISPATCHED') or(d.state in ('PARTIAL','REJECTED') and d.resolved_at is null))
   and(p_location_id is null or s.outlet_id=p_location_id or t.outlet_id=p_location_id)
 ) select jsonb_build_object('open',count(*),'handover',count(*) filter(where handover),
  'overdue',count(*) filter(where waiting_since<now()-interval '24 hours'),
  'exceptions',count(*) filter(where state in ('PARTIAL','REJECTED')),
  'rows',coalesce((select jsonb_agg(to_jsonb(r) order by case when r.state in ('PARTIAL','REJECTED') then 0 when r.overdue then 1 else 2 end,r.waiting_since,r.id) from (
   select id,reference,state,source_name,destination_name,source_outlet,destination_outlet,next_action,waiting_since,
    waiting_since<now()-interval '24 hours' overdue from unresolved
   order by case when state in ('PARTIAL','REJECTED') then 0 when waiting_since<now()-interval '24 hours' then 1 else 2 end,waiting_since,id limit 5
  )r),'[]'::jsonb)) into movements from unresolved;

 with risks as (
  select v,(v->>'estimated_food_cost')::numeric cost,(v->>'net_revenue')::numeric revenue,
   (v->>'estimated_food_margin')::numeric margin from jsonb_array_elements(overview->'summary'->'menus')v
 ), flagged as(select * from risks where margin<0 or(cost/nullif(revenue,0)*100)>40)
 select jsonb_build_object('total',count(*),'rows',coalesce((select jsonb_agg(v||jsonb_build_object(
  'food_cost_percent',round(cost/nullif(revenue,0)*100,6)::text,'margin_percent',round(margin/nullif(revenue,0)*100,6)::text,
  'locations',(select string_agg(distinct o.name,', ' order by o.name) from public.sales_headers h
   join public.sales_lines l on l.organisation_id=h.organisation_id and l.sale_id=h.id
   join public.locations o on o.organisation_id=h.organisation_id and o.id=h.location_id
   where h.organisation_id=p_organisation_id and l.menu_item_id=(v->>'menu_item_id')::uuid
   and h.sale_date between p_from and p_to and(p_location_id is null or h.location_id=p_location_id)))
  order by margin,revenue desc) from(select * from flagged order by margin,revenue desc limit 5)f),'[]'::jsonb)) into menus from flagged;
 return jsonb_build_object('from',p_from,'to',p_to,'prior_from',prior_from,'prior_to',prior_to,'currency',currency,
  'summary',overview->'summary','comparison',overview->'comparison','previous',previous,
  'food_cost_percent',round((overview->'summary'->>'estimated_food_cost')::numeric/nullif((overview->'summary'->>'net_revenue')::numeric,0)*100,6)::text,
  'food_cost_change_pp',round(((overview->'summary'->>'estimated_food_cost')::numeric/nullif((overview->'summary'->>'net_revenue')::numeric,0)
   -(previous->>'estimated_food_cost')::numeric/nullif((previous->>'net_revenue')::numeric,0))*100,6)::text,
  'food_margin_change_pp',((overview->'summary'->>'food_margin_percent')::numeric-(previous->>'food_margin_percent')::numeric)::text,
  'outlets',overview->'outlets','prices',prices,'waste',waste,'movements',movements,'menus',menus,
  'recorded_days',(select count(*) from jsonb_array_elements(overview->'daily')d where(d->>'lines')::integer>0),'refreshed_at',statement_timestamp());
end; $$;
revoke all on function public.executive_profitability_briefing(uuid,date,date,uuid) from public,anon;
grant execute on function public.executive_profitability_briefing(uuid,date,date,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
