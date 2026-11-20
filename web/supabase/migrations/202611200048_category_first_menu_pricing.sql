-- Category-first selling menu setup, standard prices and one-row profitability.
begin;
create table public.restaurant_menu_categories(
 organisation_id uuid not null references public.organisations(id),major text not null check(major in('FOOD','DRINK')),
 name text not null check(length(trim(name)) between 1 and 60 and name!~'[[:cntrl:]]'),is_active boolean not null default true,
 primary key(organisation_id,major,name)
);
create unique index menu_category_name on public.restaurant_menu_categories(organisation_id,major,lower(name));
alter table public.restaurant_menu_categories enable row level security;
revoke all on public.restaurant_menu_categories from public,anon,authenticated;
grant select on public.restaurant_menu_categories to authenticated;
create policy menu_category_read on public.restaurant_menu_categories for select to authenticated using(private.pp_active_member(organisation_id));
insert into public.restaurant_menu_categories
 select distinct on(organisation_id,primary_category,lower(trim(subcategory))) organisation_id,primary_category,trim(subcategory),true
 from public.menu_items where primary_category in('FOOD','DRINK') and trim(subcategory)<>'' and subcategory!~'[[:cntrl:]]'
 order by organisation_id,primary_category,lower(trim(subcategory)),id;
create trigger menu_category_active before insert or update or delete on public.restaurant_menu_categories for each row execute function private.pp_require_active_restaurant();
create table private.menu_category_settings(organisation_id uuid primary key references public.organisations(id),revision integer not null default 0);
insert into private.menu_category_settings select id,0 from public.organisations;
revoke all on private.menu_category_settings from public,anon,authenticated;
create function private.pp_check_menu_categories(rows jsonb,allow_empty boolean default false) returns void language plpgsql set search_path='' as $$begin
 if rows is null or jsonb_typeof(rows)<>'array' or jsonb_array_length(rows)>100 or octet_length(rows::text)>32768 then raise exception 'Use up to 100 subcategories.' using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(rows) r where jsonb_typeof(r->'major') is distinct from 'string' or r->>'major' not in('FOOD','DRINK') or jsonb_typeof(r->'name') is distinct from 'string' or length(trim(r->>'name')) not between 1 and 60 or r->>'name'~'[[:cntrl:]]' or(r?'is_active' and jsonb_typeof(r->'is_active')<>'boolean')) then raise exception 'Choose Food or Drink and enter a subcategory name.' using errcode='22023';end if;
 if (select count(*)<>count(distinct (value->>'major',lower(trim(value->>'name')))) from jsonb_array_elements(rows)) then raise exception 'Subcategories must be unique within Food or Drink.' using errcode='22023';end if;
 if not allow_empty and not exists(select 1 from jsonb_array_elements(rows) r where coalesce((r->>'is_active')::boolean,true)) then raise exception 'Add at least one active menu subcategory.' using errcode='22023';end if;
end $$;
revoke all on function private.pp_check_menu_categories(jsonb,boolean) from public,anon,authenticated;
create function public.menu_categories(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.pp_active_member(p_organisation_id) then raise exception 'Restaurant access required.' using errcode='42501';end if;
 return jsonb_build_object('manage',private.pp_menu_write(p_organisation_id),'revision',coalesce((select revision from private.menu_category_settings where organisation_id=p_organisation_id),0),'categories',coalesce((select jsonb_agg(to_jsonb(c)-'organisation_id' order by case major when 'FOOD' then 0 else 1 end,name) from public.restaurant_menu_categories c where organisation_id=p_organisation_id),'[]'));
end $$;
create function public.save_menu_categories(p_organisation_id uuid,p_revision integer,p_categories jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;rev integer;begin
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Restaurant administrator access required.' using errcode='42501';end if;
 perform private.pp_check_menu_categories(p_categories);
 perform 1 from public.organisations o where o.id=p_organisation_id for update;
 insert into private.menu_category_settings values(p_organisation_id,0) on conflict do nothing;
 select revision into rev from private.menu_category_settings where organisation_id=p_organisation_id;
 if p_revision is distinct from rev then raise exception 'Categories changed. Refresh before saving.' using errcode='22023';end if;
 update public.restaurant_menu_categories set is_active=false where organisation_id=p_organisation_id;
 for r in select value from jsonb_array_elements(p_categories) loop
  insert into public.restaurant_menu_categories values(p_organisation_id,r->>'major',trim(r->>'name'),coalesce((r->>'is_active')::boolean,true)) on conflict(organisation_id,major,name) do update set is_active=excluded.is_active;
 end loop;
 update private.menu_category_settings set revision=rev+1 where organisation_id=p_organisation_id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'MENU_CATEGORIES_UPDATED',auth.uid(),p_organisation_id,jsonb_build_object('categories',p_categories));
 return public.menu_categories(p_organisation_id);
end $$;
alter table public.restaurant_setup_drafts add column menu_categories jsonb not null default '[]';
create function public.save_setup_menu_categories(p_categories jsonb) returns void language plpgsql security definer set search_path='' as $$begin
 if auth.uid() is null then raise exception 'Sign in first.' using errcode='42501';end if;
 perform private.pp_check_menu_categories(p_categories,true);
 update public.restaurant_setup_drafts set menu_categories=p_categories where user_id=auth.uid() and completed_organisation_id is null;
 if not found and not exists(select 1 from public.restaurant_setup_drafts where user_id=auth.uid() and completed_organisation_id is not null) then raise exception 'Save business details first.' using errcode='22023';end if;
end $$;
-- Standard prices coexist with immutable channel-specific history.
alter table public.restaurant_sales_channels disable trigger channel_active_restaurant;
do $$declare org uuid;label text;begin
 for org in select id from public.organisations loop
  label:='Standard selling price';
  while exists(select 1 from public.restaurant_sales_channels where organisation_id=org and code<>'STANDARD' and is_active and lower(name)=lower(label)) loop label:=label||' (default)';end loop;
  insert into public.restaurant_sales_channels values(org,'STANDARD',label,true) on conflict(organisation_id,code) do update set name=excluded.name,is_active=true;
 end loop;
end $$;
alter table public.restaurant_sales_channels enable trigger channel_active_restaurant;
-- Keep standard pricing present even when the optional channels are changed.
do $$declare d text;n text;begin
 d:=pg_get_functiondef('public.save_sales_channels(uuid,integer,jsonb)'::regprocedure);
 n:=replace(d,' perform private.pp_check_sales_channels(p_channels);', $x$ p_channels:=(select coalesce(jsonb_agg(value),'[]'::jsonb) from jsonb_array_elements(p_channels) where value->>'code'<>'STANDARD')||jsonb_build_array(jsonb_build_object('code','STANDARD','name',coalesce((select name from public.restaurant_sales_channels where organisation_id=p_organisation_id and code='STANDARD'),'Standard selling price'),'is_active',true));
 perform private.pp_check_sales_channels(p_channels);$x$);
 if n=d then raise exception 'Expected channel validator missing';end if;execute n;
 -- Existing report APIs retain their channel-comparison contract without adding a standard-price row.
 foreach d in array array['public.menu_profitability_dashboard(uuid,uuid,text,date,text,integer,text)','public.profitability_items_dashboard(uuid,uuid,text,date,text,integer,text,text)'] loop
  n:=replace(pg_get_functiondef(d::regprocedure),$x$(p_channel='ALL' and c.is_active)$x$,$x$(p_channel='ALL' and c.is_active and c.code<>'STANDARD')$x$);execute n;
 end loop;
end $$;
create function private.pp_standard_on_new_business() returns trigger language plpgsql security definer set search_path='' as $$begin
 insert into public.restaurant_sales_channels values(new.id,'STANDARD','Standard selling price',true) on conflict do nothing;
 insert into private.menu_category_settings values(new.id,0) on conflict do nothing;return new;
end $$;
revoke all on function private.pp_standard_on_new_business() from public,anon,authenticated;
create trigger standard_menu_price after insert on public.organisations for each row execute function private.pp_standard_on_new_business();
create function public.complete_restaurant_setup_with_categories() returns uuid language plpgsql security definer set search_path='' as $$
declare d public.restaurant_setup_drafts;org uuid;begin
 select * into d from public.restaurant_setup_drafts where user_id=auth.uid() for update;
 if not found then raise exception 'Save setup first.' using errcode='22023';end if;
 if d.completed_organisation_id is not null then return d.completed_organisation_id;end if;
 perform private.pp_check_menu_categories(d.menu_categories);
 org:=public.complete_restaurant_setup_with_channels();
 perform public.save_menu_categories(org,0,d.menu_categories);return org;
end $$;
create function public.menu_margin_for_scope(p_organisation_id uuid,p_version_id uuid,p_location_id uuid,p_channel text,p_as_of date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare chosen text; signatures integer;root uuid;result jsonb;begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Menu financial access denied.' using errcode='42501';end if;
 if not private.pp_sales_channel_exists(p_organisation_id,p_channel,true) then raise exception 'Choose a valid sales channel.' using errcode='22023';end if;
 select menu_item_id into root from public.menu_item_versions where organisation_id=p_organisation_id and id=p_version_id;
 -- An explicit channel override wins; otherwise use the standard price.
 select channel_code into chosen from public.menu_price_versions where organisation_id=p_organisation_id and menu_item_id=root and location_id=p_location_id and channel_code=p_channel and effective_from<=p_as_of order by effective_from desc,version desc limit 1;
 if chosen is null and p_channel<>'STANDARD' then
  select channel_code into chosen from public.menu_price_versions where organisation_id=p_organisation_id and menu_item_id=root and location_id=p_location_id and channel_code='STANDARD' and effective_from<=p_as_of order by effective_from desc,version desc limit 1;
 end if;
 -- Legacy records: show the sole consistent usable price, never average conflicting prices.
 if chosen is null and p_channel='STANDARD' then
  with latest as(select distinct on(p.channel_code) p.* from public.menu_price_versions p join public.restaurant_sales_channels c on c.organisation_id=p.organisation_id and c.code=p.channel_code and c.is_active where p.organisation_id=p_organisation_id and p.menu_item_id=root and p.location_id=p_location_id and p.effective_from<=p_as_of order by p.channel_code,p.effective_from desc,p.version desc)
  select count(distinct(price,tax_setting,tax_percent)),min(channel_code) into signatures,chosen from latest where effective_to is null or effective_to>=p_as_of;
  if signatures>1 then chosen:=null;end if;
 end if;
 result:=public.menu_food_margin_estimate(p_organisation_id,p_version_id,p_location_id,coalesce(chosen,p_channel),p_as_of);
 if coalesce(signatures,0)>1 then result:=result||jsonb_build_object('price_issue','CHANNEL_PRICES_DIFFER','cost_state','MISSING');end if;
 return result||jsonb_build_object('price_channel',chosen,'price_basis',case when coalesce(signatures,0)>1 then 'CHOOSE_CHANNEL' when chosen='STANDARD' then 'STANDARD' when p_channel='STANDARD' and chosen is not null then 'LEGACY' else 'CHANNEL' end);
end $$;
create function public.save_menu_entry(p_organisation_id uuid,p_request_id uuid,p_value jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare id uuid;old private.setup_requests;digest text:=md5(p_value::text);begin
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Menu editing access denied.' using errcode='42501';end if;
 perform 1 from public.organisations o where o.id=p_organisation_id for update;
 select * into old from private.setup_requests where organisation_id=p_organisation_id and request_id=p_request_id and kind='MENU_ENTRY';
 if found then if old.input_hash<>digest then raise exception 'Refresh before saving changed details.' using errcode='22023';end if;return old.result_id;end if;
 if p_value->>'primary_category' not in('FOOD','DRINK') or nullif(p_value->>'primary_category','') is null or not exists(select 1 from public.restaurant_menu_categories where organisation_id=p_organisation_id and major=p_value->>'primary_category' and name=p_value->>'category' and is_active) then raise exception 'Choose Food or Drink and an active subcategory from Menu categories.' using errcode='22023';end if;
 id:=public.save_menu_setup(p_organisation_id,p_request_id,p_value);
 if nullif(p_value->>'price','') is not null then
  perform public.save_menu_selling_price(p_organisation_id,id,p_request_id,(p_value->>'price_location_id')::uuid,'STANDARD',(p_value->>'price')::numeric,p_value->>'tax_setting',(p_value->>'tax_percent')::numeric,(p_value->>'price_date')::date,null,'Standard price entered with menu');
 end if;
 insert into private.setup_requests values(p_organisation_id,p_request_id,'MENU_ENTRY',digest,id);return id;
end $$;
revoke all on function public.menu_categories(uuid),public.save_menu_categories(uuid,integer,jsonb),public.save_setup_menu_categories(jsonb),public.complete_restaurant_setup_with_categories(),public.menu_margin_for_scope(uuid,uuid,uuid,text,date),public.save_menu_entry(uuid,uuid,jsonb) from public,anon;
grant execute on function public.menu_categories(uuid),public.save_menu_categories(uuid,integer,jsonb),public.save_setup_menu_categories(jsonb),public.complete_restaurant_setup_with_categories(),public.menu_margin_for_scope(uuid,uuid,uuid,text,date),public.save_menu_entry(uuid,uuid,jsonb) to authenticated;

create or replace function public.selling_menu_profitability(p_organisation_id uuid,p_location_id uuid,p_channel text,p_as_of date,p_search text,p_page integer,p_status text default 'ALL',p_major text default 'ALL',p_subcategory text default '')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare outlet public.locations; currency text; business_day date; result jsonb; eligible_count integer;
begin
 if not private.pp_reference_price_read(p_organisation_id) then
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
  select * from matching order by case target_state when 'LOSS' then 0 when 'ABOVE_TARGET' then 1 when 'INCOMPLETE' then 2 when 'TARGET_NOT_SET' then 3 else 4 end,
   target_gap_pp desc nulls last,name,id,channel_code limit 25 offset(p_page-1)*25
 )
 select jsonb_build_object('total',(select count(*) from matching),'currency_code',currency,
  'unassigned_menu_count',(select count(*) from public.menu_items where organisation_id=p_organisation_id and is_active and brand_id is null),
  'summary',(select jsonb_build_object('total',count(*),'at_risk',count(*) filter(where target_state in ('LOSS','ABOVE_TARGET')),
   'within_target',count(*) filter(where target_state='WITHIN_TARGET'),'incomplete',count(*) filter(where target_state='INCOMPLETE'),
   'target_not_set',count(*) filter(where target_state='TARGET_NOT_SET')) from scored),
  'rows',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('target',p.target::text,'target_gap_pp',p.target_gap_pp::text,'recipe_quantity',p.recipe_quantity::text) order by case target_state when 'LOSS' then 0 when 'ABOVE_TARGET' then 1 when 'INCOMPLETE' then 2 when 'TARGET_NOT_SET' then 3 else 4 end,
   target_gap_pp desc nulls last,name,id,channel_code) from paged p),'[]'::jsonb)) into result;
 return result;
end; $$;
revoke all on function public.selling_menu_profitability(uuid,uuid,text,date,text,integer,text,text,text) from public,anon;
grant execute on function public.selling_menu_profitability(uuid,uuid,text,date,text,integer,text,text,text) to authenticated;

-- Shared validation for the review screen and the atomic import. No preview writes.
create function private.pp_menu_import_plan(org uuid,site uuid,rows jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;v jsonb;outlet public.locations;m public.menu_items;rv uuid;n integer:=0;result jsonb:='[]';problem text;unchanged boolean;state jsonb;
begin
 if not private.pp_menu_write(org) then raise exception 'Menu editing access denied.' using errcode='42501';end if;
 select * into outlet from public.locations where organisation_id=org and id=site and is_active;
 if not found then raise exception 'Choose an active outlet.' using errcode='22023';end if;
 if rows is null or jsonb_typeof(rows)<>'array' or jsonb_array_length(rows) not between 1 and 100 or octet_length(rows::text)>262144 then raise exception 'Import 1 to 100 menu rows at a time.' using errcode='22023';end if;
 for r in select value from jsonb_array_elements(rows) loop
  n:=n+1;problem:=null;v:=null;state:=null;unchanged:=false;rv:=null;m:=null;
  begin
   if exists(select 1 from jsonb_each(r) where jsonb_typeof(value)<>'string') then raise exception 'All CSV fields must be text.';end if;
   if coalesce(r->>'action','') not in('CREATE','UPDATE') then raise exception 'Action must be CREATE or UPDATE.';end if;
   if coalesce(r->>'menu_code','')!~'^[A-Z0-9][A-Z0-9_-]{0,39}$' or length(trim(coalesce(r->>'menu_name',''))) not between 1 and 120 then raise exception 'Enter a menu code and name.';end if;
   if (select count(*) from jsonb_array_elements(rows) a where a->>'menu_code'=r->>'menu_code')>1 then raise exception 'Menu code occurs more than once in this file.';end if;
   select * into m from public.menu_items where organisation_id=org and code=r->>'menu_code';
   if r->>'action'='CREATE' and m.id is not null then raise exception 'Code already exists. Use UPDATE deliberately or remove the duplicate.';end if;
   if r->>'action'='UPDATE' and(m.id is null or not m.is_active or m.brand_id<>outlet.brand_id or(m.location_id is not null and m.location_id<>site)) then raise exception 'Active menu code is unavailable in this outlet/brand.';end if;
   if r->>'major_category' not in('FOOD','DRINK') or not exists(select 1 from public.restaurant_menu_categories where organisation_id=org and major=r->>'major_category' and name=r->>'subcategory' and is_active) then raise exception 'Choose Food/Drink and an active matching subcategory from Menu categories.';end if;
   if coalesce(r->>'recipe_code','')<>'' then
    select v.id into rv from public.recipe_versions v join public.recipes a on a.organisation_id=v.organisation_id and a.id=v.recipe_id where a.organisation_id=org and a.code=r->>'recipe_code' and a.recipe_type='FINAL' and(a.location_id is null or a.location_id=site) and v.version::text=r->>'recipe_version';
    if rv is null then raise exception 'Final recipe code/version is unavailable in this outlet.';end if;
    if coalesce(r->>'recipe_quantity','')!~'^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' or(r->>'recipe_quantity')::numeric<=0 then raise exception 'Recipe quantity must be positive, up to six decimals.';end if;
   elsif coalesce(r->>'recipe_version','')<>'' or coalesce(r->>'recipe_quantity','')<>'' then raise exception 'Supply recipe code, version and quantity together, or leave all blank for an incomplete item.';
   end if;
   if coalesce(r->>'effective_from','')!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or to_char((r->>'effective_from')::date,'YYYY-MM-DD')<>r->>'effective_from' then raise exception 'Use a valid effective date (YYYY-MM-DD).';end if;
   if coalesce(r->>'selling_price','')<>'' then
    if r->>'selling_price'!~'^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' or(r->>'selling_price')::numeric<=0 or coalesce(r->>'tax_setting','') not in('NONE','INCLUSIVE','EXCLUSIVE') or coalesce(r->>'tax_percent','')!~'^(0|[1-9][0-9]{0,2})(\.[0-9]{1,6})?$' or(r->>'tax_percent')::numeric>100 or(r->>'tax_setting'='NONE' and(r->>'tax_percent')::numeric<>0) then raise exception 'Check the positive selling price and explicit tax treatment/rate.';end if;
   elsif coalesce(r->>'tax_setting','')<>'' or coalesce(r->>'tax_percent','')<>'' then raise exception 'Leave tax fields blank when no price is supplied.';
   end if;
   if rv is not null and exists(select 1 from public.recipe_versions where id=rv and effective_from>(r->>'effective_from')::date) then raise exception 'Menu date is earlier than its recipe version.';end if;
   if m.id is not null then
    state:=jsonb_build_object('menu',to_jsonb(m),'version',(select to_jsonb(x) from public.menu_item_versions x where organisation_id=org and menu_item_id=m.id order by version desc limit 1),'price',(select to_jsonb(x) from public.menu_price_versions x where organisation_id=org and menu_item_id=m.id and location_id=site and channel_code='STANDARD' order by effective_from desc,version desc limit 1));
    unchanged:=m.name=trim(r->>'menu_name') and m.primary_category=r->>'major_category' and m.subcategory=r->>'subcategory'
     and((rv is null and state->'version'='null'::jsonb) or(state->'version'->>'recipe_version_id'=rv::text and(state->'version'->>'recipe_quantity')::numeric=(r->>'recipe_quantity')::numeric and state->'version'->>'effective_from'=r->>'effective_from'))
     and(coalesce(r->>'selling_price','')='' or((state->'price'->>'price')::numeric=(r->>'selling_price')::numeric and state->'price'->>'tax_setting'=r->>'tax_setting' and(state->'price'->>'tax_percent')::numeric=(r->>'tax_percent')::numeric and state->'price'->>'effective_from'=r->>'effective_from' and state->'price'->>'effective_to' is null));
   end if;
   v:=jsonb_build_object('menu_id',m.id,'code',r->>'menu_code','name',trim(r->>'menu_name'),'brand_id',outlet.brand_id,'location_id',m.location_id,'primary_category',r->>'major_category','category',r->>'subcategory','recipe_version_id',rv,'recipe_quantity',r->>'recipe_quantity','effective_from',r->>'effective_from','price',r->>'selling_price','price_location_id',site,'tax_setting',r->>'tax_setting','tax_percent',r->>'tax_percent','price_date',r->>'effective_from');
  exception when others then problem:=sqlerrm;end;
  result:=result||jsonb_build_array(jsonb_build_object('row',n,'code',r->>'menu_code','name',r->>'menu_name','major',r->>'major_category','subcategory',r->>'subcategory','price',r->>'selling_price','action',case when problem is not null then 'ERROR' when coalesce(unchanged,false) then 'UNCHANGED' else r->>'action' end,'error',problem,'warning',case when problem is null and rv is null then 'Recipe missing: saves as incomplete.' when problem is null and coalesce(r->>'selling_price','')='' then 'No new selling price supplied; existing prices are retained.' end,'value',v,'fingerprint',md5(coalesce(state::text,'NEW'))));
 end loop;
 return jsonb_build_object('rows',result,'valid',not exists(select 1 from jsonb_array_elements(result) a where a->>'error' is not null));
end $$;
revoke all on function private.pp_menu_import_plan(uuid,uuid,jsonb) from public,anon,authenticated;
create function public.preview_menu_catalogue_import(p_organisation_id uuid,p_location_id uuid,p_rows jsonb) returns jsonb language sql stable security definer set search_path='' as $$select private.pp_menu_import_plan(p_organisation_id,p_location_id,p_rows)$$;
create function public.post_menu_catalogue_import(p_organisation_id uuid,p_location_id uuid,p_request_id uuid,p_rows jsonb,p_preview jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare plan jsonb;r jsonb;id uuid;n integer:=0;old private.setup_requests;digest text:=md5(jsonb_build_array(p_location_id,p_rows,p_preview)::text);begin
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Menu editing access denied.' using errcode='42501';end if;
 if p_request_id is null then raise exception 'Import request required.' using errcode='22023';end if;
 perform 1 from public.organisations o where o.id=p_organisation_id for update;
 select * into old from private.setup_requests where organisation_id=p_organisation_id and request_id=p_request_id and kind='MENU_IMPORT';
 if found then if old.input_hash<>digest then raise exception 'Refresh and review the changed file.' using errcode='22023';end if;return 0;end if;
 plan:=private.pp_menu_import_plan(p_organisation_id,p_location_id,p_rows);
 if plan is distinct from p_preview or not(plan->>'valid')::boolean then raise exception 'Menu data changed or has errors. Review the file again.' using errcode='22023';end if;
 for r in select value from jsonb_array_elements(plan->'rows') loop
  if r->>'action'<>'UNCHANGED' then id:=public.save_menu_entry(p_organisation_id,md5(p_request_id::text||':'||(r->>'row'))::uuid,r->'value');n:=n+1;end if;
 end loop;
 insert into private.setup_requests values(p_organisation_id,p_request_id,'MENU_IMPORT',digest,p_request_id);
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'MENU_CATALOGUE_IMPORTED',auth.uid(),p_request_id,jsonb_build_object('outlet',p_location_id,'changed_rows',n));return n;
end $$;
revoke all on function public.preview_menu_catalogue_import(uuid,uuid,jsonb),public.post_menu_catalogue_import(uuid,uuid,uuid,jsonb,jsonb) from public,anon;
grant execute on function public.preview_menu_catalogue_import(uuid,uuid,jsonb),public.post_menu_catalogue_import(uuid,uuid,uuid,jsonb,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;

