-- Same-page Menu / Recipes / All comparison, filtered before summaries and pagination.
begin;
create or replace function public.profitability_items_dashboard(p_organisation_id uuid,p_location_id uuid,p_channel text,p_as_of date,p_search text,p_page integer,p_status text default 'ALL',p_kind text default 'MENU')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare outlet public.locations; currency text; business_day date; result jsonb; eligible_count integer; recipe_count integer;
begin
 if not private.pp_reference_price_read(p_organisation_id) then
  raise exception 'Menu financial access denied.' using errcode='42501'; end if;
 select * into outlet from public.locations where organisation_id=p_organisation_id and id=p_location_id and is_active;
 if not found then raise exception 'Choose an active outlet in this business.' using errcode='22023'; end if;
 select currency_code,(now() at time zone time_zone)::date into currency,business_day
 from public.organisations where id=p_organisation_id;
 if p_as_of is null or p_as_of>business_day or p_channel is null or (p_channel<>'ALL' and not private.pp_sales_channel_exists(p_organisation_id,p_channel,true))
  or p_page is null or p_page not between 1 and 100000 or p_search is null or length(p_search)>80 then
  raise exception 'Choose a valid date, channel, menu search and page. Future dates are unavailable.' using errcode='22023'; end if;
 if p_status is null or p_status not in ('ALL','AT_RISK','WITHIN_TARGET','INCOMPLETE','TARGET_NOT_SET','COSTED') then raise exception 'Choose a valid menu status.' using errcode='22023';end if;
 if p_kind is null or p_kind not in ('ALL','MENU','RECIPE') then raise exception 'Choose All, Menu or Recipes.' using errcode='22023';end if;
 select count(*) into eligible_count from public.menu_items m left join lateral(select v.name from public.menu_item_versions v where v.organisation_id=m.organisation_id and v.menu_item_id=m.id and v.effective_from<=p_as_of order by v.effective_from desc,v.version desc limit 1)v on true
 where p_kind<>'RECIPE' and m.organisation_id=p_organisation_id and m.is_active and m.brand_id=outlet.brand_id and(m.location_id is null or m.location_id=p_location_id)
 and(trim(p_search)='' or position(lower(trim(p_search)) in lower(coalesce(v.name,m.name)||' '||m.code))>0);
 select count(*) into recipe_count from public.recipes r left join lateral(select v.name from public.recipe_versions v where v.organisation_id=r.organisation_id and v.recipe_id=r.id and v.effective_from<=p_as_of order by v.effective_from desc,v.version desc limit 1)v on true
 where p_kind<>'MENU' and r.organisation_id=p_organisation_id and(r.location_id is null or r.location_id=p_location_id)
 and(trim(p_search)='' or position(lower(trim(p_search)) in lower(coalesce(v.name,r.name)||' '||r.code))>0);
 if recipe_count+eligible_count*(case when p_channel='ALL' then(select count(*) from public.restaurant_sales_channels where organisation_id=p_organisation_id and is_active) else 1 end)>5000 then
  raise exception 'Narrow the search or choose one type or channel to compare up to 5,000 rows.' using errcode='22023';end if;
 with eligible as materialized (
  select 'MENU'::text item_kind,null::text recipe_type,null::text output_unit,m.id,m.code,c.code channel_code,c.name channel_name,m.primary_category,private.pp_cost_target(p_organisation_id,p_location_id,m.primary_category) target,coalesce(v.name,m.name) as name,v.id as version_id,v.version,v.recipe_quantity,v.effective_from
  from public.menu_items m cross join public.restaurant_sales_channels c
  left join lateral (
   select id,name,version,recipe_quantity,effective_from from public.menu_item_versions
   where organisation_id=p_organisation_id and menu_item_id=m.id and effective_from<=p_as_of
   order by effective_from desc,version desc limit 1
  ) v on true
  where p_kind<>'RECIPE' and m.organisation_id=p_organisation_id and c.organisation_id=p_organisation_id and((p_channel='ALL' and c.is_active) or c.code=p_channel) and m.is_active and m.brand_id=outlet.brand_id and(m.location_id is null or m.location_id=p_location_id)
  and (trim(p_search)='' or position(lower(trim(p_search)) in lower(coalesce(v.name,m.name)||' '||m.code))>0)

  union all
  select 'RECIPE',r.recipe_type,u.code,r.id,r.code,null,null,null,null,coalesce(v.name,r.name),v.id,v.version,null,v.effective_from
  from public.recipes r
  left join lateral(select id,name,version,effective_from from public.recipe_versions where organisation_id=r.organisation_id and recipe_id=r.id and effective_from<=p_as_of order by effective_from desc,version desc limit 1)v on true
  left join public.recipe_outputs o on o.organisation_id=r.organisation_id and o.recipe_version_id=v.id
  left join public.units_of_measure u on u.organisation_id=r.organisation_id and u.id=o.uom_id
  where p_kind<>'MENU' and r.organisation_id=p_organisation_id and(r.location_id is null or r.location_id=p_location_id)
  and(trim(p_search)='' or position(lower(trim(p_search)) in lower(coalesce(v.name,r.name)||' '||r.code))>0)
 ), estimates as materialized (
  select e.*,case when version_id is null then null
   when item_kind='RECIPE' then public.recipe_reference_cost_estimate(p_organisation_id,version_id,p_as_of,1)
   else public.menu_food_margin_estimate(p_organisation_id,version_id,p_location_id,e.channel_code,p_as_of) end estimate from eligible e
 ), scored as materialized (
  select e.*,case
   when estimate is null or estimate->>'cost_state'<>'ESTIMATED' then 'INCOMPLETE'
   when item_kind='RECIPE' then 'COSTED'
   when estimate->>'food_cost_percent' is null then 'INCOMPLETE'
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
   target_gap_pp desc nulls last,name,item_kind,id,channel_code limit 25 offset(p_page-1)*25
 )
 select jsonb_build_object('total',(select count(*) from matching),'currency_code',currency,
  'unassigned_menu_count',(select count(*) from public.menu_items where organisation_id=p_organisation_id and is_active and brand_id is null),
  'summary',(select jsonb_build_object('total',count(*),'at_risk',count(*) filter(where target_state in ('LOSS','ABOVE_TARGET')),
   'within_target',count(*) filter(where target_state='WITHIN_TARGET'),'incomplete',count(*) filter(where target_state='INCOMPLETE'),
   'target_not_set',count(*) filter(where target_state='TARGET_NOT_SET'),'recipes_costed',count(*) filter(where target_state='COSTED')) from scored),
  'rows',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('target',p.target::text,'target_gap_pp',p.target_gap_pp::text,'recipe_quantity',p.recipe_quantity::text) order by case target_state when 'LOSS' then 0 when 'ABOVE_TARGET' then 1 when 'INCOMPLETE' then 2 when 'TARGET_NOT_SET' then 3 else 4 end,
   target_gap_pp desc nulls last,name,item_kind,id,channel_code) from paged p),'[]'::jsonb)) into result;
 return result;
end; $$;
revoke all on function public.profitability_items_dashboard(uuid,uuid,text,date,text,integer,text,text) from public,anon;
grant execute on function public.profitability_items_dashboard(uuid,uuid,text,date,text,integer,text,text) to authenticated;

notify pgrst,'reload schema';
commit;
