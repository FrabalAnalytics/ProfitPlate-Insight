-- Profitability first, explicit targets and issued-PO early warning evidence.
begin;
create function public.menu_profitability_dashboard(p_organisation_id uuid,p_location_id uuid,p_channel text,p_as_of date,p_search text,p_page integer,p_status text default 'ALL')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare outlet public.locations; currency text; business_day date; result jsonb; eligible_count integer;
begin
 if not private.pp_reference_price_read(p_organisation_id) then
  raise exception 'Menu financial access denied.' using errcode='42501'; end if;
 select * into outlet from public.locations where organisation_id=p_organisation_id and id=p_location_id and is_active;
 if not found then raise exception 'Choose an active outlet in this business.' using errcode='22023'; end if;
 select currency_code,(now() at time zone time_zone)::date into currency,business_day
 from public.organisations where id=p_organisation_id;
 if p_as_of is null or p_as_of>business_day or p_channel is null or p_channel not in ('DINE_IN','TAKEAWAY','DELIVERY')
  or p_page is null or p_page not between 1 and 100000 or p_search is null or length(p_search)>80 then
  raise exception 'Choose a valid date, channel, menu search and page. Future dates are unavailable.' using errcode='22023'; end if;
 if p_status is null or p_status not in ('ALL','AT_RISK','WITHIN_TARGET','INCOMPLETE','TARGET_NOT_SET') then raise exception 'Choose a valid menu status.' using errcode='22023';end if;
 select count(*) into eligible_count from public.menu_items m where m.organisation_id=p_organisation_id and m.is_active and m.brand_id=outlet.brand_id and(m.location_id is null or m.location_id=p_location_id);
 if eligible_count>1000 and(trim(p_search)='' or (select count(*) from public.menu_items m left join lateral(select v.name from public.menu_item_versions v where v.organisation_id=m.organisation_id and v.menu_item_id=m.id and v.effective_from<=p_as_of order by v.effective_from desc,v.version desc limit 1)v on true where m.organisation_id=p_organisation_id and m.is_active and m.brand_id=outlet.brand_id and(m.location_id is null or m.location_id=p_location_id) and position(lower(trim(p_search)) in lower(coalesce(v.name,m.name)||' '||m.code))>0)>1000) then raise exception 'Use a menu search to compare fewer than 1,000 items at once.' using errcode='22023';end if;
 with eligible as materialized (
  select m.id,m.code,m.primary_category,private.pp_cost_target(p_organisation_id,p_location_id,m.primary_category) target,coalesce(v.name,m.name) as name,v.id as version_id,v.version,v.recipe_quantity,v.effective_from
  from public.menu_items m
  left join lateral (
   select id,name,version,recipe_quantity,effective_from from public.menu_item_versions
   where organisation_id=p_organisation_id and menu_item_id=m.id and effective_from<=p_as_of
   order by effective_from desc,version desc limit 1
  ) v on true
  where m.organisation_id=p_organisation_id and m.is_active and m.brand_id=outlet.brand_id and(m.location_id is null or m.location_id=p_location_id)
  and (trim(p_search)='' or position(lower(trim(p_search)) in lower(coalesce(v.name,m.name)||' '||m.code))>0)
 ), estimates as materialized (
  select e.*,case when version_id is null then null else public.menu_food_margin_estimate(p_organisation_id,version_id,p_location_id,p_channel,p_as_of) end estimate from eligible e
 ), scored as materialized (
  select e.*,case
   when estimate is null or estimate->>'cost_state'<>'ESTIMATED' or estimate->>'food_cost_percent' is null then 'INCOMPLETE'
   when (estimate->>'estimated_food_margin')::numeric<0 then 'LOSS'
   when target is null then 'TARGET_NOT_SET'
   when (estimate->>'food_cost_percent')::numeric>target then 'ABOVE_TARGET'
   else 'WITHIN_TARGET' end target_state,
   case when target is not null then (estimate->>'food_cost_percent')::numeric-target end target_gap_pp
  from estimates e
 ), matching as materialized (
  select * from scored where p_status='ALL' or(p_status='AT_RISK' and target_state in ('LOSS','ABOVE_TARGET')) or target_state=p_status
 ), paged as (
  select * from matching order by case target_state when 'LOSS' then 0 when 'ABOVE_TARGET' then 1 when 'INCOMPLETE' then 2 when 'TARGET_NOT_SET' then 3 else 4 end,
   target_gap_pp desc nulls last,name,id limit 25 offset(p_page-1)*25
 )
 select jsonb_build_object('total',(select count(*) from matching),'currency_code',currency,
  'unassigned_menu_count',(select count(*) from public.menu_items where organisation_id=p_organisation_id and is_active and brand_id is null),
  'summary',(select jsonb_build_object('total',count(*),'at_risk',count(*) filter(where target_state in ('LOSS','ABOVE_TARGET')),
   'within_target',count(*) filter(where target_state='WITHIN_TARGET'),'incomplete',count(*) filter(where target_state='INCOMPLETE'),
   'target_not_set',count(*) filter(where target_state='TARGET_NOT_SET')) from scored),
  'rows',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('target',p.target::text,'target_gap_pp',p.target_gap_pp::text,'recipe_quantity',p.recipe_quantity::text) order by case target_state when 'LOSS' then 0 when 'ABOVE_TARGET' then 1 when 'INCOMPLETE' then 2 when 'TARGET_NOT_SET' then 3 else 4 end,
   target_gap_pp desc nulls last,name,id) from paged p),'[]'::jsonb)) into result;
 return result;
end; $$;
revoke all on function public.menu_profitability_dashboard(uuid,uuid,text,date,text,integer,text) from public,anon;
grant execute on function public.menu_profitability_dashboard(uuid,uuid,text,date,text,integer,text) to authenticated;

create function public.menu_profitability_scope(p_organisation_id uuid,p_location_id uuid default null,p_channel text default null,p_as_of date default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare day date;site uuid;channel text;
begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Menu financial access denied.' using errcode='42501';end if;
 select coalesce(p_as_of,(now() at time zone time_zone)::date) into day from public.organisations where id=p_organisation_id;
 if day>(select(now() at time zone time_zone)::date from public.organisations where id=p_organisation_id) or(p_channel is not null and p_channel not in ('DINE_IN','TAKEAWAY','DELIVERY')) then raise exception 'Choose a valid date and channel.' using errcode='22023';end if;
 select l.id into site from public.locations l where l.organisation_id=p_organisation_id and l.is_active and(p_location_id is null or l.id=p_location_id)
 order by exists(select 1 from(select distinct on(p.menu_item_id,p.channel_code) p.* from public.menu_price_versions p join public.menu_items m on m.organisation_id=p.organisation_id and m.id=p.menu_item_id and m.is_active and m.brand_id=l.brand_id and(m.location_id is null or m.location_id=l.id) where p.organisation_id=p_organisation_id and p.location_id=l.id and p.effective_from<=day and(p_channel is null or p.channel_code=p_channel) order by p.menu_item_id,p.channel_code,p.effective_from desc,p.version desc) prices where prices.effective_to is null or prices.effective_to>=day) desc,l.name,l.id limit 1;
 if site is null then return jsonb_build_object('location_id',null,'channel',coalesce(p_channel,'DINE_IN'));end if;
 with latest as (
  select distinct on(p.menu_item_id,p.channel_code) p.* from public.menu_price_versions p
  join public.menu_items m on m.organisation_id=p.organisation_id and m.id=p.menu_item_id and m.is_active
  where p.organisation_id=p_organisation_id and p.location_id=site and p.effective_from<=day order by p.menu_item_id,p.channel_code,p.effective_from desc,p.version desc
 ) select channel_code into channel from latest where effective_to is null or effective_to>=day group by channel_code
 order by count(*) desc,case channel_code when 'DINE_IN' then 0 when 'TAKEAWAY' then 1 else 2 end limit 1;
 return jsonb_build_object('location_id',site,'channel',coalesce(p_channel,channel,'DINE_IN'));
end $$;
revoke all on function public.menu_profitability_scope(uuid,uuid,text,date) from public,anon;
grant execute on function public.menu_profitability_scope(uuid,uuid,text,date) to authenticated;

-- Freeze the comparable net price at issue time; future invoices cannot rewrite the early warning.
create table private.po_price_baselines (
 organisation_id uuid not null,order_id uuid not null,line_id uuid not null,
 baseline jsonb not null,quote_unit_cost numeric,base_quantity numeric not null,
 primary key(organisation_id,line_id),
 foreign key(organisation_id,order_id,line_id) references public.purchase_order_lines(organisation_id,order_id,id)
);
alter table private.po_price_baselines enable row level security;
revoke all on private.po_price_baselines from public,anon,authenticated;
create function private.pp_po_baseline(org uuid,item uuid,day date,known_before timestamptz) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare price record;reference public.material_reference_prices;currency text;
begin
 select currency_code into currency from public.organisations where id=org;
 with replacements as materialized (
  select distinct on(c.purchase_id) c.purchase_id,c.proposal value from public.purchase_corrections c
  where c.organisation_id=org and c.state='APPROVED' and c.decided_at<=known_before order by c.purchase_id,c.decided_at desc,c.id desc
 ), rows as (
  select h.id,h.purchase_date price_date,h.created_at,p.source_row::bigint position,
   p.net_amount/nullif(p.base_quantity,0) unit_cost,h.currency_code,h.purchase_ref reference
  from public.purchase_headers h join public.purchase_lines p on p.organisation_id=h.organisation_id and p.purchase_id=h.id
  where h.organisation_id=org and p.item_id=item and h.created_at<=known_before and h.purchase_date<=day
   and not exists(select 1 from replacements r where r.purchase_id=h.id)
  union all
  select h.id,(r.value->'header'->>'date')::date,h.created_at,n,(l->>'net_amount')::numeric/nullif((l->>'base_quantity')::numeric,0),
   r.value->'header'->>'currency',r.value->'header'->>'reference'
  from replacements r join public.purchase_headers h on h.organisation_id=org and h.id=r.purchase_id
  cross join lateral jsonb_array_elements(r.value->'lines') with ordinality parts(l,n)
  where h.created_at<=known_before and not coalesce((r.value->>'voided')::boolean,false)
   and l->>'item_id'=item::text and(r.value->'header'->>'date')::date<=day
 ) select * into price from rows where unit_cost is not null and currency_code=currency
 order by price_date desc,created_at desc,id desc,position desc limit 1;
 if found then return jsonb_build_object('source','INVOICE','unit_cost',round(price.unit_cost,12)::text,'date',price.price_date,'reference',price.reference);end if;
 select * into reference from public.material_reference_prices r where r.organisation_id=org and r.item_id=item and r.price_date<=day and r.created_at<=known_before and r.currency_code=currency order by r.price_date desc,r.version desc limit 1;
 if found then return jsonb_build_object('source','INITIAL_PRICE','unit_cost',reference.cost_per_base_unit::text,'date',reference.price_date);end if;
 return jsonb_build_object('source','MISSING','unit_cost',null);
end $$;
revoke all on function private.pp_po_baseline(uuid,uuid,date,timestamptz) from public,anon,authenticated;
create function private.pp_snapshot_po_prices(org uuid,po uuid,backfilled boolean default false) returns void
language plpgsql security definer set search_path='' as $$
declare o public.purchase_orders;line public.purchase_order_lines;day date;
begin
 select * into o from public.purchase_orders where organisation_id=org and id=po and status='ISSUED';
 if not found then return;end if;
 select least(o.document_date,(o.issued_at at time zone time_zone)::date) into day from public.organisations where id=org;
 for line in select * from public.purchase_order_lines where organisation_id=org and order_id=po loop
  insert into private.po_price_baselines values(org,po,line.id,
   private.pp_po_baseline(org,line.item_id,day,o.issued_at)||jsonb_build_object('snapshot_at',o.issued_at,'backfilled',backfilled),
   (line.payload->>'net_amount')::numeric/nullif((line.payload->>'base_quantity')::numeric,0),(line.payload->>'base_quantity')::numeric)
  on conflict do nothing;
 end loop;
end $$;
revoke all on function private.pp_snapshot_po_prices(uuid,uuid,boolean) from public,anon,authenticated;
alter function public.issue_purchase_order(uuid,uuid,integer,boolean) rename to pp_issue_before_price_snapshot;
alter function public.pp_issue_before_price_snapshot(uuid,uuid,integer,boolean) set schema private;
revoke all on function private.pp_issue_before_price_snapshot(uuid,uuid,integer,boolean) from public,anon,authenticated;
create function public.issue_purchase_order(p_organisation_id uuid,p_order_id uuid,p_revision integer,p_confirmed boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform private.pp_issue_before_price_snapshot(p_organisation_id,p_order_id,p_revision,p_confirmed);
 perform private.pp_snapshot_po_prices(p_organisation_id,p_order_id,false);
end $$;
revoke all on function public.issue_purchase_order(uuid,uuid,integer,boolean) from public,anon;
grant execute on function public.issue_purchase_order(uuid,uuid,integer,boolean) to authenticated;
do $$declare o record;begin
 for o in select organisation_id,id from public.purchase_orders where status='ISSUED' loop perform private.pp_snapshot_po_prices(o.organisation_id,o.id,true);end loop;
end $$;

-- Include pinned sub-recipes and recipe-linked processed SKUs in impact traceability.
create function private.pp_recipe_uses_material(org uuid,recipe uuid,item uuid,day date) returns boolean
language sql stable security definer set search_path='' as $$
 with recursive tree(id,path) as (
  select recipe,array[recipe]
  union all
  select edge.id,t.path||edge.id from tree t cross join lateral (
   select c.child_recipe_version_id id from public.recipe_components c where c.organisation_id=org and c.recipe_version_id=t.id and c.child_recipe_version_id is not null
   union
   select b.recipe_version_id from public.recipe_components c join public.items i on i.organisation_id=c.organisation_id and i.id=c.item_id
   join public.stock_recipe_bindings b on b.organisation_id=i.organisation_id and b.item_id=i.id
   join public.recipe_versions v on v.organisation_id=b.organisation_id and v.id=b.recipe_version_id
   where c.organisation_id=org and c.recipe_version_id=t.id and i.supply_class in ('PROCESSED','BOTH') and v.effective_from<=day
    and not exists(select 1 from public.stock_recipe_bindings nb join public.recipe_versions nv on nv.organisation_id=nb.organisation_id and nv.id=nb.recipe_version_id
     where nb.organisation_id=org and nb.item_id=i.id and nv.recipe_id=v.recipe_id and nv.effective_from<=day and(nv.effective_from,nv.version,nv.id)>(v.effective_from,v.version,v.id))
  ) edge where cardinality(t.path)<20 and not edge.id=any(t.path)
 ) select exists(select 1 from tree t join public.recipe_components c on c.organisation_id=org and c.recipe_version_id=t.id where c.item_id=item);
$$;
revoke all on function private.pp_recipe_uses_material(uuid,uuid,uuid,date) from public,anon,authenticated;
create function private.pp_executive_po_exposure(org uuid,from_day date,to_day date,outlet uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;zone text;currency text;day date;volume integer;
begin
 select time_zone,currency_code,(now() at time zone time_zone)::date into zone,currency,day from public.organisations where id=org;
 select count(*) into volume from public.purchase_orders o join public.purchase_order_lines l on l.organisation_id=o.organisation_id and l.order_id=o.id
 where o.organisation_id=org and o.status='ISSUED' and(o.issued_at at time zone zone)::date between from_day and to_day and(outlet is null or o.location_id=outlet);
 if volume>2000 then return jsonb_build_object('unavailable','Narrow the period or outlet to review up to 2,000 issued PO lines.','rows','[]'::jsonb);end if;
 with selected as materialized (
  select o.id order_id,o.reference,o.document_date,o.issued_at,o.location_id,s.name supplier,loc.name outlet_name,
   l.id line_id,l.item_id,i.name item_name,u.code unit,b.baseline,b.quote_unit_cost,b.base_quantity,
   (b.baseline->>'unit_cost')::numeric baseline_unit_cost
  from public.purchase_orders o join public.purchase_order_lines l on l.organisation_id=o.organisation_id and l.order_id=o.id
  join private.po_price_baselines b on b.organisation_id=l.organisation_id and b.line_id=l.id
  join public.items i on i.organisation_id=l.organisation_id and i.id=l.item_id
  join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id
  join public.suppliers s on s.organisation_id=o.organisation_id and s.id=o.supplier_id
  join public.locations loc on loc.organisation_id=o.organisation_id and loc.id=o.location_id
  where o.organisation_id=org and o.status='ISSUED' and(o.issued_at at time zone zone)::date between from_day and to_day
   and(outlet is null or o.location_id=outlet) and o.payload->'header'->>'currency'=currency
 ), contexts as materialized (
  select c.*,private.pp_current_invoice(org,c.purchase_id) invoice from public.invoice_procurement_contexts c
  where c.organisation_id=org and exists(select 1 from selected s where s.order_id=c.order_id)
   and not exists(select 1 from public.invoice_procurement_contexts n where n.organisation_id=org and n.purchase_id=c.purchase_id and n.version>c.version)
 ), quantities as materialized (
  select s.*,
   coalesce((select sum(r.accepted*(pl.payload->>'conversion_factor')::numeric) from public.goods_receipt_lines r
    join public.purchase_order_lines pl on pl.organisation_id=r.organisation_id and pl.id=r.order_line_id
    where r.organisation_id=org and r.order_line_id=s.line_id and not private.pp_receipt_voided(org,r.receipt_id)),0) received_quantity,
   coalesce((select sum((l->>'base_quantity')::numeric) from contexts c
    cross join lateral jsonb_array_elements(c.invoice->'lines') with ordinality rows(l,n)
    join public.invoice_procurement_lines m on m.organisation_id=c.organisation_id and m.context_id=c.id and m.invoice_line=n
    where c.order_id=s.order_id and m.order_line_id=s.line_id and c.invoice_revision=(c.invoice->>'revision')::integer
     and not coalesce((c.invoice->>'voided')::boolean,false) and l->>'item_id'=s.item_id::text),0) billed_quantity,
   exists(select 1 from contexts c where c.order_id=s.order_id and c.invoice_revision<>(c.invoice->>'revision')::integer and not coalesce((c.invoice->>'voided')::boolean,false)) stale_invoice_links
  from selected s
 ), compared as materialized (
  select q.*,greatest(base_quantity-billed_quantity,0) unbilled_quantity,
   (quote_unit_cost-baseline_unit_cost)*greatest(base_quantity-billed_quantity,0) potential_exposure,
   case when baseline_unit_cost>0 then 100*(quote_unit_cost/baseline_unit_cost-1) end change_percent
  from quantities q
 ), warnings as materialized (
  select *,case when stale_invoice_links then 'INVOICE_REVIEW' when billed_quantity>=base_quantity then 'INVOICED'
   when received_quantity>=base_quantity then 'RECEIVED' when received_quantity>0 then 'PART_RECEIVED' else 'ISSUED' end stage
  from compared where quote_unit_cost>baseline_unit_cost
 ), top_rows as (
  select * from warnings order by (unbilled_quantity>0) desc,potential_exposure desc,issued_at desc,line_id limit 5
 ), affected as (
  select r.*,coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'name',m.name) order by m.name) from public.menu_items m
   join public.locations loc on loc.organisation_id=m.organisation_id and loc.id=r.location_id
   join lateral(select v.recipe_version_id from public.menu_item_versions v where v.organisation_id=m.organisation_id and v.menu_item_id=m.id and v.effective_from<=day order by v.effective_from desc,v.version desc limit 1)v on true
   where m.organisation_id=org and m.is_active and m.brand_id=loc.brand_id and(m.location_id is null or m.location_id=loc.id)
    and private.pp_recipe_uses_material(org,v.recipe_version_id,r.item_id,day)),'[]'::jsonb) affected_menus
  from top_rows r
 ) select jsonb_build_object('unavailable',null,'total',(select count(*) from warnings),
  'open',(select count(*) from warnings where unbilled_quantity>0),
  'potential_exposure',(select coalesce(sum(potential_exposure),0)::text from warnings),
  'unmatched',(select count(*) from compared where baseline_unit_cost is null),
  'rows',coalesce((select jsonb_agg(jsonb_build_object('order_id',order_id,'reference',reference,'line_id',line_id,'item_id',item_id,'name',item_name,
   'location_id',location_id,'outlet_name',outlet_name,'supplier',supplier,'unit',unit,'baseline',baseline,
   'quote_unit_cost',round(quote_unit_cost,12)::text,'baseline_unit_cost',baseline_unit_cost::text,'change_percent',round(change_percent,6)::text,
   'ordered_quantity',base_quantity::text,'received_quantity',received_quantity::text,'billed_quantity',billed_quantity::text,'unbilled_quantity',unbilled_quantity::text,
   'potential_exposure',round(potential_exposure,12)::text,'stage',stage,'affected_menus',affected_menus)
   order by (unbilled_quantity>0) desc,potential_exposure desc,issued_at desc,line_id) from affected),'[]'::jsonb)) into result;
 return result;
end $$;
revoke all on function private.pp_executive_po_exposure(uuid,date,date,uuid) from public,anon,authenticated;
alter function public.executive_profitability_briefing(uuid,date,date,uuid) rename to pp_briefing_before_po_exposure;
alter function public.pp_briefing_before_po_exposure(uuid,date,date,uuid) set schema private;
revoke all on function private.pp_briefing_before_po_exposure(uuid,date,date,uuid) from public,anon,authenticated;
create function public.executive_profitability_briefing(p_organisation_id uuid,p_from date,p_to date,p_location_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 result:=private.pp_briefing_before_po_exposure(p_organisation_id,p_from,p_to,p_location_id);
 return result||jsonb_build_object('po_exposure',private.pp_executive_po_exposure(p_organisation_id,p_from,p_to,p_location_id));
end $$;
revoke all on function public.executive_profitability_briefing(uuid,date,date,uuid) from public,anon;
grant execute on function public.executive_profitability_briefing(uuid,date,date,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
