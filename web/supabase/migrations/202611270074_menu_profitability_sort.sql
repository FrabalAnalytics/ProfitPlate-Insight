-- Sort the full filtered menu result before pagination; keep existing report callers unchanged.
begin;
create function public.selling_menu_profitability_sorted(p_organisation_id uuid,p_location_id uuid,p_channel text,p_as_of date,p_search text,p_page integer,p_status text default 'ALL',p_major text default 'ALL',p_subcategory text default '',p_sort text default 'PRIORITY')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare outlet public.locations; currency text; business_day date; result jsonb; eligible_count integer;
begin
 if not private.pp_operations_menu_scope(p_organisation_id,p_location_id) then
  raise exception 'Menu financial access denied.' using errcode='42501'; end if;
 select * into outlet from public.locations where organisation_id=p_organisation_id and id=p_location_id and is_active;
 if not found then raise exception 'Choose an active outlet in this business.' using errcode='22023'; end if;
 select currency_code,(now() at time zone time_zone)::date into currency,business_day
 from public.organisations where id=p_organisation_id;
 if p_as_of is null or p_as_of>business_day or p_channel is null or not private.pp_sales_channel_exists(p_organisation_id,p_channel,true)
  or p_page is null or p_page not between 1 and 100000 or p_search is null or length(p_search)>80 then
  raise exception 'Choose a valid date, channel, menu search and page. Future dates are unavailable.' using errcode='22023'; end if;
 if p_status is null or p_status not in ('ALL','AT_RISK','WITHIN_TARGET','INCOMPLETE','TARGET_NOT_SET') then raise exception 'Choose a valid menu status.' using errcode='22023';end if;
 if p_major is null or p_major not in('ALL','FOOD','DRINK','UNCLASSIFIED') or p_subcategory is null or length(p_subcategory)>60 then raise exception 'Choose a valid category.' using errcode='22023';end if;
 if p_sort is null or p_sort not in('PRIORITY','GROSS_DESC','GROSS_ASC') then raise exception 'Choose a valid profitability sort order.' using errcode='22023';end if;
 select count(*) into eligible_count from public.menu_items m left join lateral(select v.name from public.menu_item_versions v where v.organisation_id=m.organisation_id and v.menu_item_id=m.id and v.effective_from<=p_as_of order by v.effective_from desc,v.version desc limit 1)v on true
 where m.organisation_id=p_organisation_id and m.is_active and m.brand_id=outlet.brand_id and(m.location_id is null or m.location_id=p_location_id)
 and(p_major='ALL' or m.primary_category=p_major or(p_major='UNCLASSIFIED' and coalesce(m.primary_category,'') not in('FOOD','DRINK'))) and(p_subcategory='' or lower(m.subcategory)=lower(p_subcategory)) and(trim(p_search)='' or position(lower(trim(p_search)) in lower(coalesce(v.name,m.name)||' '||m.code))>0);
 if eligible_count>5000 then
  raise exception 'Narrow the menu search or category to compare up to 5,000 selling items.' using errcode='22023';end if;
 with eligible as materialized (
  select m.id,m.code,p_channel channel_code,m.primary_category,m.subcategory,private.pp_cost_target(p_organisation_id,p_location_id,m.primary_category) target,coalesce(v.name,m.name) as name,v.id as version_id,v.version,v.recipe_quantity,v.effective_from
  from public.menu_items m
  left join lateral (
   select id,name,version,recipe_quantity,effective_from from public.menu_item_versions
   where organisation_id=p_organisation_id and menu_item_id=m.id and effective_from<=p_as_of
   order by effective_from desc,version desc limit 1
  ) v on true
  where m.organisation_id=p_organisation_id and m.is_active and m.brand_id=outlet.brand_id and(m.location_id is null or m.location_id=p_location_id)
  and(p_major='ALL' or m.primary_category=p_major or(p_major='UNCLASSIFIED' and coalesce(m.primary_category,'') not in('FOOD','DRINK'))) and(p_subcategory='' or lower(m.subcategory)=lower(p_subcategory)) and (trim(p_search)='' or position(lower(trim(p_search)) in lower(coalesce(v.name,m.name)||' '||m.code))>0)
 ), estimates as materialized (
  select e.*,case when version_id is null then null else public.menu_margin_for_scope(p_organisation_id,version_id,p_location_id,e.channel_code,p_as_of) end estimate from eligible e
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
  select * from matching order by case when p_sort='PRIORITY' then case target_state when 'LOSS' then 0 when 'ABOVE_TARGET' then 1 when 'INCOMPLETE' then 2 when 'TARGET_NOT_SET' then 3 else 4 end end,
   case when p_sort='PRIORITY' then target_gap_pp end desc nulls last,
   case when p_sort='GROSS_DESC' then (estimate->>'food_margin_percent')::numeric end desc nulls last,
   case when p_sort='GROSS_ASC' then (estimate->>'food_margin_percent')::numeric end asc nulls last,name,id,channel_code limit 25 offset(p_page-1)*25
 )
 select jsonb_build_object('total',(select count(*) from matching),'currency_code',currency,
  'unassigned_menu_count',(select count(*) from public.menu_items where organisation_id=p_organisation_id and is_active and brand_id is null),
  'summary',(select jsonb_build_object('total',count(*),'at_risk',count(*) filter(where target_state in ('LOSS','ABOVE_TARGET')),
   'within_target',count(*) filter(where target_state='WITHIN_TARGET'),'incomplete',count(*) filter(where target_state='INCOMPLETE'),
   'target_not_set',count(*) filter(where target_state='TARGET_NOT_SET')) from scored),
  'rows',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('target',p.target::text,'target_gap_pp',p.target_gap_pp::text,'recipe_quantity',p.recipe_quantity::text) order by case when p_sort='PRIORITY' then case target_state when 'LOSS' then 0 when 'ABOVE_TARGET' then 1 when 'INCOMPLETE' then 2 when 'TARGET_NOT_SET' then 3 else 4 end end,
   case when p_sort='PRIORITY' then target_gap_pp end desc nulls last,
   case when p_sort='GROSS_DESC' then (estimate->>'food_margin_percent')::numeric end desc nulls last,
   case when p_sort='GROSS_ASC' then (estimate->>'food_margin_percent')::numeric end asc nulls last,name,id,channel_code) from paged p),'[]'::jsonb)) into result;
 return result;
end; $$;
revoke all on function public.selling_menu_profitability_sorted(uuid,uuid,text,date,text,integer,text,text,text,text) from public,anon;
grant execute on function public.selling_menu_profitability_sorted(uuid,uuid,text,date,text,integer,text,text,text,text) to authenticated;
commit;
