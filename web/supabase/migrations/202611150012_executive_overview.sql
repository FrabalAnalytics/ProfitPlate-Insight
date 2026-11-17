-- Apply ONCE after 011. Read-only executive view; reuses the approved live estimate.
begin;
create function public.workspace_navigation_access(p_organisation_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('overview',private.pp_sales_read(p_organisation_id),
 'sales',private.pp_sales_read(p_organisation_id),'purchases',private.pp_reference_price_read(p_organisation_id),
 'menus',private.pp_reference_price_read(p_organisation_id),'recipes',private.pp_catalogue_read(p_organisation_id),
 'catalogue',private.pp_catalogue_read(p_organisation_id),'team',private.pp_team_manage(p_organisation_id));
$$;

create function public.executive_overview(p_organisation_id uuid,p_from date,p_to date,p_location_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare summary jsonb; daily jsonb; outlets jsonb; channels jsonb; receipt_rows jsonb; ranked jsonb;
 prior_from date:=p_from-(p_to-p_from+1); prior_to date:=p_from-1;
 prior_count integer; prior_receipts integer; prior_days integer; prior_revenue numeric;
 comparison jsonb; invalid_currency boolean; previous_reason text;
begin
 -- Authorisation, dates, same-tenant location, currency and 1,000-line cap are
 -- enforced by the same routine used on Sales & summary, before any other reads.
 summary:=public.sales_period_summary(p_organisation_id,p_from,p_to,p_location_id);
 with daily_totals as (
  select h.sale_date,count(*)::integer as lines,count(distinct h.id)::integer as receipts,sum(l.net_revenue) as revenue
  from public.sales_lines l join public.sales_headers h on h.organisation_id=l.organisation_id and h.id=l.sale_id
  where l.organisation_id=p_organisation_id and h.sale_date between p_from and p_to
   and(p_location_id is null or h.location_id=p_location_id) group by h.sale_date
 ) select jsonb_agg(jsonb_build_object('date',d.day::date,'lines',coalesce(t.lines,0),
  'receipts',coalesce(t.receipts,0),'net_revenue',t.revenue::text) order by d.day) into daily
 from generate_series(p_from::timestamp,p_to::timestamp,interval '1 day') d(day)
 left join daily_totals t on t.sale_date=d.day::date;

 with grouped as (
  select h.location_id,min(o.name) as name,min(o.code) as code,sum(l.net_revenue) as revenue,
   sum(l.quantity) as quantity,count(distinct h.id)::integer as receipts
  from public.sales_lines l join public.sales_headers h on h.organisation_id=l.organisation_id and h.id=l.sale_id
  join public.locations o on o.organisation_id=h.organisation_id and o.id=h.location_id
  where l.organisation_id=p_organisation_id and h.sale_date between p_from and p_to
   and(p_location_id is null or h.location_id=p_location_id) group by h.location_id
 ) select coalesce(jsonb_agg(jsonb_build_object('id',location_id,'name',name,'code',code,
  'net_revenue',revenue::text,'quantity',quantity::text,'receipts',receipts) order by revenue desc,name),'[]') into outlets from grouped;

 with grouped as (
  select h.channel_code,sum(l.net_revenue) as revenue,sum(l.quantity) as quantity
  from public.sales_lines l join public.sales_headers h on h.organisation_id=l.organisation_id and h.id=l.sale_id
  where l.organisation_id=p_organisation_id and h.sale_date between p_from and p_to
   and(p_location_id is null or h.location_id=p_location_id) group by h.channel_code
 ) select coalesce(jsonb_agg(jsonb_build_object('code',channel_code,'net_revenue',revenue::text,
  'quantity',quantity::text,'share_percent',round(revenue/nullif((summary->>'net_revenue')::numeric,0)*100,6)::text)
  order by revenue desc,channel_code),'[]') into channels from grouped;

 select coalesce(jsonb_agg(v order by sale_date desc,created_at desc,id),'[]') into receipt_rows from (
  select h.sale_date,h.created_at,h.id,jsonb_build_object('id',h.id,'reference',h.transaction_ref,'source',h.source_system,
   'date',h.sale_date,'location_name',min(o.name),'batch_id',h.import_batch_id,
   'net_revenue',sum(l.net_revenue)::text,'customer_total',h.receipt_total::text) v
  from public.sales_headers h join public.sales_lines l on l.organisation_id=h.organisation_id and l.sale_id=h.id
  join public.locations o on o.organisation_id=h.organisation_id and o.id=h.location_id
  where h.organisation_id=p_organisation_id and h.sale_date between p_from and p_to
   and(p_location_id is null or h.location_id=p_location_id)
  group by h.id order by h.sale_date desc,h.created_at desc,h.id limit 10) s;

 select coalesce(jsonb_agg(v order by(v->>'net_revenue')::numeric desc,v->>'code'),'[]') into ranked
 from jsonb_array_elements(summary->'menus') v;

 select count(*)::integer,count(distinct h.id)::integer,count(distinct h.sale_date)::integer,sum(l.net_revenue),
  coalesce(bool_or(h.currency_code<>summary->>'currency_code'),false)
 into prior_count,prior_receipts,prior_days,prior_revenue,invalid_currency
 from public.sales_lines l join public.sales_headers h on h.organisation_id=l.organisation_id and h.id=l.sale_id
 where l.organisation_id=p_organisation_id and h.sale_date between prior_from and prior_to
 and(p_location_id is null or h.location_id=p_location_id);
 previous_reason:=case when prior_count>1000 then 'The comparison exceeds 1,000 lines.'
  when invalid_currency then 'The comparison contains a different recorded currency.'
  when prior_count=0 then 'No sales have been recorded in the preceding period.' else null end;
 comparison:=jsonb_build_object('from',prior_from,'to',prior_to,'reason',previous_reason,
  'recorded_days',prior_days,'net_revenue',case when previous_reason is null then prior_revenue::text else null end,
  'change_percent',case when previous_reason is null and prior_revenue>0 and(summary->>'lines')::integer>0
   then round(((summary->>'net_revenue')::numeric-prior_revenue)/prior_revenue*100,6)::text else null end);
 return jsonb_build_object('summary',summary,'daily',daily,'outlets',outlets,'channels',channels,
  'recent_receipts',receipt_rows,'ranked_menus',ranked,
  'negative_menus',coalesce((select jsonb_agg(v order by(v->>'estimated_food_margin')::numeric,v->>'code') from jsonb_array_elements(summary->'menus') v where(v->>'estimated_food_margin')::numeric<0),'[]'::jsonb),
  'comparison',comparison,'refreshed_at',statement_timestamp());
end; $$;
revoke all on function public.workspace_navigation_access(uuid),public.executive_overview(uuid,date,date,uuid) from public,anon;
grant execute on function public.workspace_navigation_access(uuid),public.executive_overview(uuid,date,date,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
