-- Apply once after 021. Read-only menu comparison; existing costing policy is reused.
begin;
create index pp_menu_versions_effective on public.menu_item_versions
 (organisation_id,menu_item_id,effective_from desc,version desc);

create function public.menu_profitability(p_organisation_id uuid,p_location_id uuid,p_channel text,p_as_of date,p_search text,p_page integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare outlet public.locations; currency text; business_day date; result jsonb;
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
 with eligible as materialized (
  select m.id,m.code,coalesce(v.name,m.name) as name,v.id as version_id,v.version,v.recipe_quantity,v.effective_from
  from public.menu_items m
  left join lateral (
   select id,name,version,recipe_quantity,effective_from from public.menu_item_versions
   where organisation_id=p_organisation_id and menu_item_id=m.id and effective_from<=p_as_of
   order by effective_from desc,version desc limit 1
  ) v on true
  where m.organisation_id=p_organisation_id and m.is_active and m.brand_id=outlet.brand_id
  and (trim(p_search)='' or position(lower(trim(p_search)) in lower(coalesce(v.name,m.name)||' '||m.code))>0)
 ), paged as (
  select * from eligible order by name,id limit 25 offset (p_page-1)*25
 )
 select jsonb_build_object('total',(select count(*) from eligible),'currency_code',currency,
  'unassigned_menu_count',(select count(*) from public.menu_items where organisation_id=p_organisation_id and is_active and brand_id is null),
  'rows',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.code,'name',p.name,
   'version_id',p.version_id,'version',p.version,'effective_from',p.effective_from,'recipe_quantity',p.recipe_quantity::text,
   'estimate',case when p.version_id is null then null else public.menu_food_margin_estimate(
    p_organisation_id,p.version_id,p_location_id,p_channel,p_as_of) end) order by p.name,p.id) from paged p),'[]'::jsonb)) into result;
 return result;
end; $$;
revoke all on function public.menu_profitability(uuid,uuid,text,date,text,integer) from public,anon;
grant execute on function public.menu_profitability(uuid,uuid,text,date,text,integer) to authenticated;
notify pgrst,'reload schema';
commit;
