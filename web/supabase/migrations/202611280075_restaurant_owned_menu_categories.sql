-- Restaurant-owned menu headings, independent cost families and dated sales classification.
begin;
create table public.restaurant_menu_major_categories(
 organisation_id uuid not null references public.organisations(id),
 code text not null check(code ~ '^[A-Z0-9][A-Z0-9_-]{0,39}$' and code not in('ALL','UNCLASSIFIED')),
 name text not null check(length(trim(name)) between 1 and 60 and name !~ '[[:cntrl:]]'),
 cost_basis text not null check(cost_basis in('FOOD','DRINK','NON_FOOD')),
 target_percent numeric check(target_percent between 0 and 100),
 is_active boolean not null default true,primary key(organisation_id,code)
);
create unique index menu_major_unique_name on public.restaurant_menu_major_categories(organisation_id,lower(name));
insert into public.restaurant_menu_major_categories(organisation_id,code,name,cost_basis)
 select id,'FOOD','Food','FOOD' from public.organisations union all
 select id,'DRINK','Drink','DRINK' from public.organisations union all
 select distinct organisation_id,'PACKAGING','Packaging','NON_FOOD' from public.menu_items where primary_category='PACKAGING';
alter table public.restaurant_menu_major_categories enable row level security;
revoke all on public.restaurant_menu_major_categories from public,anon,authenticated;
grant select on public.restaurant_menu_major_categories to authenticated;
create policy menu_major_read on public.restaurant_menu_major_categories for select to authenticated using(private.pp_active_member(organisation_id));
create trigger menu_major_active before insert or update or delete on public.restaurant_menu_major_categories for each row execute function private.pp_require_active_restaurant();
create function private.pp_seed_menu_majors() returns trigger language plpgsql security definer set search_path='' as $$begin
 insert into public.restaurant_menu_major_categories values(new.id,'FOOD','Food','FOOD',null,true),(new.id,'DRINK','Drink','DRINK',null,true),(new.id,'PACKAGING','Packaging','NON_FOOD',null,true);return new;
end $$;
revoke all on function private.pp_seed_menu_majors() from public,anon,authenticated;
create trigger menu_major_defaults after insert on public.organisations for each row execute function private.pp_seed_menu_majors();
alter table public.restaurant_menu_categories drop constraint restaurant_menu_categories_major_check;
alter table public.restaurant_menu_categories add foreign key(organisation_id,major) references public.restaurant_menu_major_categories(organisation_id,code);
alter table public.menu_items drop constraint menu_items_primary_category_check;
alter table public.menu_items add foreign key(organisation_id,primary_category) references public.restaurant_menu_major_categories(organisation_id,code);

create function private.pp_menu_major_code(org uuid,value text) returns text language sql stable security definer set search_path='' as $$
 select code from public.restaurant_menu_major_categories where organisation_id=org and(lower(code)=lower(trim(value)) or lower(name)=lower(trim(value))) order by (lower(code)=lower(trim(value))) desc limit 1;
$$;
revoke all on function private.pp_menu_major_code(uuid,text) from public,anon,authenticated;

create or replace function private.pp_check_menu_categories(rows jsonb,allow_empty boolean default false) returns void language plpgsql set search_path='' as $$
begin
 if rows is null or jsonb_typeof(rows)<>'array' or jsonb_array_length(rows)>100 or octet_length(rows::text)>65536 then raise exception 'Use up to 100 subcategories.' using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(rows) r where jsonb_typeof(r->'major') is distinct from 'string' or r->>'major' !~ '^[A-Z0-9][A-Z0-9_-]{0,39}$' or r->>'major' in('ALL','UNCLASSIFIED') or jsonb_typeof(r->'name') is distinct from 'string' or length(trim(r->>'name')) not between 1 and 60 or r->>'name'~'[[:cntrl:]]' or(r?'is_active' and jsonb_typeof(r->'is_active')<>'boolean')
 or length(trim(coalesce(r->>'major_name',case r->>'major' when 'FOOD' then 'Food' when 'DRINK' then 'Drink' when 'PACKAGING' then 'Packaging' end,''))) not between 1 and 60
 or(r?'major_name' and jsonb_typeof(r->'major_name')<>'string') or(r?'cost_basis' and jsonb_typeof(r->'cost_basis')<>'string') or coalesce(r->>'major_name','')~'[[:cntrl:]]'
 or coalesce(r->>'cost_basis',case r->>'major' when 'FOOD' then 'FOOD' when 'DRINK' then 'DRINK' when 'PACKAGING' then 'NON_FOOD' end,'') not in('FOOD','DRINK','NON_FOOD')
 or(nullif(r->>'target_percent','') is not null and (case when r->>'target_percent' ~ '^[0-9]{1,3}(\.[0-9]{1,6})?$' then (r->>'target_percent')::numeric not between 0 and 100 else true end))) then raise exception 'Enter a main category, reporting treatment, optional target and subcategory.' using errcode='22023';end if;
 if(select count(distinct value->>'major') from jsonb_array_elements(rows))>30 then raise exception 'Use up to 30 main categories.' using errcode='22023';end if;
 if(select count(*)<>count(distinct(value->>'major',lower(trim(value->>'name')))) from jsonb_array_elements(rows)) then raise exception 'Subcategories must be unique within a main category.' using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(rows) r group by r->>'major' having count(distinct(coalesce(r->>'major_name',r->>'major'),coalesce(r->>'cost_basis',r->>'major'),coalesce(nullif(r->>'target_percent',''),'')))>1) then raise exception 'Use consistent main-category details across its subcategories.' using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(rows) r group by lower(trim(coalesce(r->>'major_name',r->>'major'))) having count(distinct r->>'major')>1) then raise exception 'Main category names must be unique.' using errcode='22023';end if;
 if not allow_empty and not exists(select 1 from jsonb_array_elements(rows) r where coalesce((r->>'is_active')::boolean,true)) then raise exception 'Add at least one active menu subcategory.' using errcode='22023';end if;
end $$;

create or replace function public.menu_categories(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.pp_active_member(p_organisation_id) then raise exception 'Restaurant access required.' using errcode='42501';end if;
 return jsonb_build_object('manage',private.pp_menu_write(p_organisation_id),'revision',coalesce((select revision from private.menu_category_settings where organisation_id=p_organisation_id),0),
 'majors',coalesce((select jsonb_agg(to_jsonb(c)-'organisation_id' order by name,code) from public.restaurant_menu_major_categories c where organisation_id=p_organisation_id),'[]'),
'categories',coalesce((select jsonb_agg(jsonb_build_object('major',c.major,'major_name',m.name,'cost_basis',m.cost_basis,'target_percent',m.target_percent::text,'name',c.name,'is_active',c.is_active) order by m.name,c.name) from public.restaurant_menu_categories c join public.restaurant_menu_major_categories m on m.organisation_id=c.organisation_id and m.code=c.major where c.organisation_id=p_organisation_id),'[]'));
end $$;

-- Snapshot classification belongs to the menu version and recorded sale, not the mutable menu heading.
create table private.menu_version_classifications(
 organisation_id uuid not null,version_id uuid not null,major text,major_name text,cost_basis text,subcategory text,origin text not null,
 primary key(organisation_id,version_id),foreign key(organisation_id,version_id) references public.menu_item_versions(organisation_id,id)
);
create table private.sales_category_classifications(
 organisation_id uuid not null,line_id uuid not null,major text,major_name text,cost_basis text,subcategory text,origin text not null,
 primary key(organisation_id,line_id),foreign key(organisation_id,line_id) references public.sales_lines(organisation_id,id)
);
insert into private.menu_version_classifications
 select v.organisation_id,v.id,m.primary_category,c.name,c.cost_basis,m.subcategory,'LEGACY_BACKFILL'
 from public.menu_item_versions v join public.menu_items m on m.organisation_id=v.organisation_id and m.id=v.menu_item_id left join public.restaurant_menu_major_categories c on c.organisation_id=m.organisation_id and c.code=m.primary_category;
insert into private.sales_category_classifications
 select l.organisation_id,l.id,c.major,c.major_name,c.cost_basis,c.subcategory,'LEGACY_BACKFILL' from public.sales_lines l join private.menu_version_classifications c on c.organisation_id=l.organisation_id and c.version_id=l.menu_version_id;
revoke all on private.menu_version_classifications,private.sales_category_classifications from public,anon,authenticated;
create function private.pp_snapshot_menu_category() returns trigger language plpgsql security definer set search_path='' as $$begin
 insert into private.menu_version_classifications select new.organisation_id,new.id,m.primary_category,c.name,c.cost_basis,m.subcategory,'MENU_VERSION' from public.menu_items m left join public.restaurant_menu_major_categories c on c.organisation_id=m.organisation_id and c.code=m.primary_category where m.organisation_id=new.organisation_id and m.id=new.menu_item_id;
 return new;
end $$;
create trigger menu_category_snapshot after insert on public.menu_item_versions for each row execute function private.pp_snapshot_menu_category();
create function private.pp_snapshot_sales_category() returns trigger language plpgsql security definer set search_path='' as $$begin
 insert into private.sales_category_classifications
 select new.organisation_id,new.id,coalesce(v.major,m.primary_category),coalesce(v.major_name,c.name),coalesce(v.cost_basis,c.cost_basis),coalesce(nullif(v.subcategory,''),m.subcategory),case when v.major is not null then v.origin else 'FIRST_SALE_CLASSIFICATION' end
 from public.menu_items m left join private.menu_version_classifications v on v.organisation_id=m.organisation_id and v.version_id=new.menu_version_id left join public.restaurant_menu_major_categories c on c.organisation_id=m.organisation_id and c.code=m.primary_category where m.organisation_id=new.organisation_id and m.id=new.menu_item_id;
 return new;
end $$;
create trigger sales_category_snapshot after insert on public.sales_lines for each row execute function private.pp_snapshot_sales_category();
revoke all on function private.pp_snapshot_menu_category(),private.pp_snapshot_sales_category() from public,anon,authenticated;

create or replace function public.save_menu_categories(p_organisation_id uuid,p_revision integer,p_categories jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;rev integer;label text;basis text;begin
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Restaurant administrator access required.' using errcode='42501';end if;
 perform private.pp_check_menu_categories(p_categories);
 perform 1 from public.organisations where id=p_organisation_id for update;
 insert into private.menu_category_settings values(p_organisation_id,0) on conflict do nothing;
 select revision into rev from private.menu_category_settings where organisation_id=p_organisation_id;
 if p_revision is distinct from rev then raise exception 'Categories changed. Refresh before saving.' using errcode='22023';end if;
 update public.restaurant_menu_major_categories set is_active=false where organisation_id=p_organisation_id;
 for r in select distinct on(value->>'major') value from jsonb_array_elements(p_categories) order by value->>'major' loop
  label:=trim(coalesce(r->>'major_name',case r->>'major' when 'FOOD' then 'Food' when 'DRINK' then 'Drink' when 'PACKAGING' then 'Packaging' end));
  basis:=coalesce(r->>'cost_basis',case r->>'major' when 'FOOD' then 'FOOD' when 'DRINK' then 'DRINK' when 'PACKAGING' then 'NON_FOOD' end);
  if exists(select 1 from public.restaurant_menu_major_categories c where c.organisation_id=p_organisation_id and c.code=r->>'major' and c.cost_basis<>basis) and exists(select 1 from private.sales_category_classifications s where s.organisation_id=p_organisation_id and s.major=r->>'major') then raise exception 'This category already has sales. Keep its reporting treatment; create a separate category for a different treatment.' using errcode='22023';end if;
  insert into public.restaurant_menu_major_categories values(p_organisation_id,r->>'major',label,basis,nullif(r->>'target_percent','')::numeric,exists(select 1 from jsonb_array_elements(p_categories) x where x->>'major'=r->>'major' and coalesce((x->>'is_active')::boolean,true)))
  on conflict(organisation_id,code) do update set name=excluded.name,cost_basis=excluded.cost_basis,target_percent=excluded.target_percent,is_active=excluded.is_active;
 end loop;
 update public.restaurant_menu_categories set is_active=false where organisation_id=p_organisation_id;
 for r in select value from jsonb_array_elements(p_categories) loop
  insert into public.restaurant_menu_categories values(p_organisation_id,r->>'major',trim(r->>'name'),coalesce((r->>'is_active')::boolean,true)) on conflict(organisation_id,major,name) do update set is_active=excluded.is_active;
 end loop;
 update private.menu_category_settings set revision=rev+1 where organisation_id=p_organisation_id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'MENU_CATEGORIES_UPDATED',auth.uid(),p_organisation_id,jsonb_build_object('categories',p_categories));
 return public.menu_categories(p_organisation_id);
end $$;

create or replace function private.pp_cost_target(org uuid,loc uuid,category text) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce(c.target_percent,case coalesce(c.cost_basis,category) when 'FOOD' then coalesce(l.food_percent,b.food_percent) when 'DRINK' then coalesce(l.beverage_percent,b.beverage_percent) end)
 from(select 1)x left join public.restaurant_menu_major_categories c on c.organisation_id=org and c.code=category left join public.cost_targets b on b.organisation_id=org and b.location_id is null left join public.cost_targets l on l.organisation_id=org and l.location_id=loc;
$$;

-- Existing setup, imports and profitability functions are replaced below with the same signatures.
create or replace function public.save_setup_profile(p_organisation_id uuid,p_kind text,p_id uuid,p_location_id uuid,p_primary text default null,p_subcategory text default '',p_weekly boolean default false,p_supply text default 'PURCHASED') returns void language plpgsql security definer set search_path='' as $$begin
 if not(case p_kind when 'MATERIAL' then private.pp_catalogue_write(p_organisation_id) when 'RECIPE' then private.pp_recipe_write(p_organisation_id) when 'MENU' then private.pp_menu_write(p_organisation_id) else false end) then raise exception 'Setup editing access denied.' using errcode='42501';end if;
 perform private.pp_setup_location(p_organisation_id,p_location_id);
 perform 1 from public.organisations where id=p_organisation_id for update;
 if p_kind='MATERIAL' then
 if p_supply is null or p_supply not in ('PURCHASED','PROCESSED','BOTH') or p_weekly is null then raise exception 'Choose valid material settings.' using errcode='22023';end if;
 if exists(select 1 from public.items where organisation_id=p_organisation_id and id=p_id and location_id is distinct from p_location_id) and(exists(select 1 from public.stock_documents where organisation_id=p_organisation_id and lines::text like '%'||p_id::text||'%') or exists(select 1 from public.purchase_order_lines where organisation_id=p_organisation_id and item_id=p_id) or exists(select 1 from public.purchase_lines where organisation_id=p_organisation_id and item_id=p_id) or exists(select 1 from public.recipe_components where organisation_id=p_organisation_id and item_id=p_id)) then raise exception 'Material scope is fixed once used. Keep the shared material or create a new scoped SKU.' using errcode='22023';end if;
 update public.items set location_id=p_location_id,weekly_count_required=p_weekly,supply_class=p_supply where organisation_id=p_organisation_id and id=p_id;
 elsif p_kind='RECIPE' then
 if exists(select 1 from public.recipes where organisation_id=p_organisation_id and id=p_id and location_id is distinct from p_location_id) and exists(select 1 from public.recipe_versions where organisation_id=p_organisation_id and recipe_id=p_id) then raise exception 'Recipe scope stays fixed after publication. Create a separate scoped recipe.' using errcode='22023';end if;
 update public.recipes set location_id=p_location_id where organisation_id=p_organisation_id and id=p_id;
 else
 if p_primary is not null and not exists(select 1 from public.restaurant_menu_major_categories where organisation_id=p_organisation_id and code=p_primary and is_active) or p_subcategory is null or length(p_subcategory)>60 then raise exception 'Choose a valid category and subcategory.' using errcode='22023';end if;
 if exists(select 1 from public.menu_items where organisation_id=p_organisation_id and id=p_id and location_id is distinct from p_location_id) and(exists(select 1 from public.menu_price_versions where organisation_id=p_organisation_id and menu_item_id=p_id) or exists(select 1 from public.sales_lines where organisation_id=p_organisation_id and menu_item_id=p_id)) then raise exception 'Menu scope stays fixed after pricing or sales. Create a separate scoped item.' using errcode='22023';end if;
 if p_location_id is not null and not exists(select 1 from public.menu_items m join public.locations l on l.organisation_id=m.organisation_id and l.brand_id=m.brand_id where m.organisation_id=p_organisation_id and m.id=p_id and l.id=p_location_id) then raise exception 'Choose a location belonging to this menu brand.' using errcode='22023';end if;
 update public.menu_items set location_id=p_location_id,primary_category=p_primary,subcategory=trim(p_subcategory) where organisation_id=p_organisation_id and id=p_id;
 end if;
 if not found then raise exception 'Setup record unavailable.' using errcode='42501';end if;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'SETUP_PROFILE',auth.uid(),p_id,jsonb_build_object('kind',p_kind,'location',p_location_id,'category',p_primary,'subcategory',p_subcategory,'weekly',p_weekly,'supply',p_supply));
end $$;

create or replace function public.save_menu_entry_before_stock(p_organisation_id uuid,p_request_id uuid,p_value jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare id uuid;old private.setup_requests;digest text:=md5(p_value::text);begin
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Menu editing access denied.' using errcode='42501';end if;
 perform 1 from public.organisations o where o.id=p_organisation_id for update;
 select * into old from private.setup_requests where organisation_id=p_organisation_id and request_id=p_request_id and kind='MENU_ENTRY';
 if found then if old.input_hash<>digest then raise exception 'Refresh before saving changed details.' using errcode='22023';end if;return old.result_id;end if;
 if not exists(select 1 from public.restaurant_menu_major_categories where organisation_id=p_organisation_id and code=p_value->>'primary_category' and is_active) or nullif(p_value->>'primary_category','') is null or not exists(select 1 from public.restaurant_menu_categories where organisation_id=p_organisation_id and major=p_value->>'primary_category' and name=p_value->>'category' and is_active) then raise exception 'Choose an active main category and its subcategory from Menu categories.' using errcode='22023';end if;
 id:=public.save_menu_setup(p_organisation_id,p_request_id,p_value);
 if nullif(p_value->>'price','') is not null then
  perform public.save_menu_selling_price(p_organisation_id,id,p_request_id,(p_value->>'price_location_id')::uuid,'STANDARD',(p_value->>'price')::numeric,p_value->>'tax_setting',(p_value->>'tax_percent')::numeric,(p_value->>'price_date')::date,null,'Standard price entered with menu');
 end if;
 insert into private.setup_requests values(p_organisation_id,p_request_id,'MENU_ENTRY',digest,id);return id;
end $$;

create or replace function private.pp_menu_import_plan(org uuid,site uuid,rows jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;v jsonb;outlet public.locations;m public.menu_items;rv uuid;n integer:=0;result jsonb:='[]';problem text;unchanged boolean;state jsonb;stock_site uuid;
begin
 if not private.pp_menu_write(org) then raise exception 'Menu editing access denied.' using errcode='42501';end if;
 select * into outlet from public.locations where organisation_id=org and id=site and is_active;
 if not found then raise exception 'Choose an active outlet.' using errcode='22023';end if;
 if rows is null or jsonb_typeof(rows)<>'array' or jsonb_array_length(rows) not between 1 and 100 or octet_length(rows::text)>262144 then raise exception 'Import 1 to 100 menu rows at a time.' using errcode='22023';end if;
 for r in select value from jsonb_array_elements(rows) loop
  n:=n+1;r:=jsonb_set(r,'{major_category}',to_jsonb(coalesce(private.pp_menu_major_code(org,r->>'major_category'),r->>'major_category','')));problem:=null;v:=null;state:=null;unchanged:=false;rv:=null;m:=null;stock_site:=null;
  begin
   if exists(select 1 from jsonb_each(r) where jsonb_typeof(value)<>'string') then raise exception 'All CSV fields must be text.';end if;
   if coalesce(r->>'action','') not in('CREATE','UPDATE') then raise exception 'Action must be CREATE or UPDATE.';end if;
   if coalesce(r->>'menu_code','')!~'^[A-Z0-9][A-Z0-9_-]{0,39}$' or length(trim(coalesce(r->>'menu_name',''))) not between 1 and 120 then raise exception 'Enter a menu code and name.';end if;
   if (select count(*) from jsonb_array_elements(rows) a where a->>'menu_code'=r->>'menu_code')>1 then raise exception 'Menu code occurs more than once in this file.';end if;
   select * into m from public.menu_items where organisation_id=org and code=r->>'menu_code';
   if r->>'action'='CREATE' and m.id is not null then raise exception 'Code already exists. Use UPDATE deliberately or remove the duplicate.';end if;
   if r->>'action'='UPDATE' and(m.id is null or not m.is_active or m.brand_id<>outlet.brand_id or(m.location_id is not null and m.location_id<>site)) then raise exception 'Active menu code is unavailable in this outlet/brand.';end if;
   if not exists(select 1 from public.restaurant_menu_major_categories where organisation_id=org and code=r->>'major_category' and is_active) or not exists(select 1 from public.restaurant_menu_categories where organisation_id=org and major=r->>'major_category' and name=r->>'subcategory' and is_active) then raise exception 'Choose an active main category and matching subcategory from Menu categories.';end if;
   if coalesce(r->>'recipe_code','')<>'' then
    select v.id into rv from public.recipe_versions v join public.recipes a on a.organisation_id=v.organisation_id and a.id=v.recipe_id where a.organisation_id=org and a.code=r->>'recipe_code' and a.recipe_type='FINAL' and(a.location_id is null or a.location_id=site) and (coalesce(r->>'recipe_version','')='' or v.version::text=r->>'recipe_version') and v.effective_from<=(r->>'effective_from')::date order by v.effective_from desc,v.version desc limit 1;
    if rv is null then raise exception 'Final recipe code/version is unavailable in this outlet on the selected date.';end if;
    if coalesce(r->>'recipe_quantity','')!~'^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' or(r->>'recipe_quantity')::numeric<=0 then raise exception 'Recipe quantity must be positive, up to six decimals.';end if;
   elsif coalesce(r->>'recipe_version','')<>'' or coalesce(r->>'recipe_quantity','')<>'' then raise exception 'Supply recipe code and quantity together; version is optional. Leave all blank for an incomplete item.';
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
   if coalesce(r->>'stock_centre_code','')<>'' then
    select id into stock_site from public.stock_locations where organisation_id=org and code=r->>'stock_centre_code' and is_active and(outlet_id is null or outlet_id=site);
    if stock_site is null or coalesce(r->>'consumption_mode','') not in('RECIPE','FINISHED') then raise exception 'Choose a compatible stock centre code and RECIPE or FINISHED consumption mode.';end if;
    state:=coalesce(state,'{}'::jsonb)||jsonb_build_object('stock_routes',(select jsonb_agg(to_jsonb(x)) from private.menu_stock_mappings x where organisation_id=org and menu_id=m.id and outlet_id=site));
    unchanged:=coalesce(unchanged,false) and exists(select 1 from private.menu_stock_mappings x where x.organisation_id=org and x.menu_id=m.id and x.outlet_id=site and x.site_id=stock_site and x.mode=r->>'consumption_mode' and x.effective_from=(r->>'effective_from')::date and x.version=(select max(z.version) from private.menu_stock_mappings z where z.organisation_id=org and z.menu_id=m.id and z.outlet_id=site));
   elsif coalesce(r->>'consumption_mode','')<>'' then raise exception 'Supply the stock centre code with the consumption mode.';end if;
   v:=jsonb_build_object('menu_id',m.id,'code',r->>'menu_code','name',trim(r->>'menu_name'),'brand_id',outlet.brand_id,'location_id',m.location_id,'primary_category',r->>'major_category','category',r->>'subcategory','recipe_version_id',rv,'recipe_quantity',r->>'recipe_quantity','effective_from',r->>'effective_from','price',r->>'selling_price','price_location_id',site,'tax_setting',r->>'tax_setting','tax_percent',r->>'tax_percent','price_date',r->>'effective_from','stock_site_id',stock_site,'stock_outlet_id',site,'consumption_mode',r->>'consumption_mode','stock_from',r->>'effective_from');
  exception when others then problem:=sqlerrm;end;
  result:=result||jsonb_build_array(jsonb_build_object('row',n,'code',r->>'menu_code','name',r->>'menu_name','major',r->>'major_category','subcategory',r->>'subcategory','price',r->>'selling_price','action',case when problem is not null then 'ERROR' when coalesce(unchanged,false) then 'UNCHANGED' else r->>'action' end,'error',problem,'warning',case when problem is null and rv is null then 'Recipe missing: saves as incomplete.' when problem is null and coalesce(r->>'selling_price','')='' then 'No new selling price supplied; existing prices are retained.' end,'value',v,'fingerprint',md5(coalesce(state::text,'NEW'))));
 end loop;
 return jsonb_build_object('rows',result,'valid',not exists(select 1 from jsonb_array_elements(result) a where a->>'error' is not null));
end $$;

create or replace function public.selling_menu_profitability(p_organisation_id uuid,p_location_id uuid,p_channel text,p_as_of date,p_search text,p_page integer,p_status text default 'ALL',p_major text default 'ALL',p_subcategory text default '')
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
 if p_major is null or (p_major not in('ALL','UNCLASSIFIED') and not exists(select 1 from public.restaurant_menu_major_categories where organisation_id=p_organisation_id and code=p_major)) or p_subcategory is null or length(p_subcategory)>60 then raise exception 'Choose a valid category.' using errcode='22023';end if;
 select count(*) into eligible_count from public.menu_items m left join lateral(select v.name from public.menu_item_versions v where v.organisation_id=m.organisation_id and v.menu_item_id=m.id and v.effective_from<=p_as_of order by v.effective_from desc,v.version desc limit 1)v on true
 where m.organisation_id=p_organisation_id and m.is_active and m.brand_id=outlet.brand_id and(m.location_id is null or m.location_id=p_location_id)
 and(p_major='ALL' or m.primary_category=p_major or(p_major='UNCLASSIFIED' and not exists(select 1 from public.restaurant_menu_major_categories mc where mc.organisation_id=m.organisation_id and mc.code=m.primary_category))) and(p_subcategory='' or lower(m.subcategory)=lower(p_subcategory)) and(trim(p_search)='' or position(lower(trim(p_search)) in lower(coalesce(v.name,m.name)||' '||m.code))>0);
 if eligible_count>5000 then
  raise exception 'Narrow the menu search or category to compare up to 5,000 selling items.' using errcode='22023';end if;
 with eligible as materialized (
  select m.id,m.code,p_channel channel_code,m.primary_category,(select name from public.restaurant_menu_major_categories where organisation_id=m.organisation_id and code=m.primary_category) major_name,m.subcategory,private.pp_cost_target(p_organisation_id,p_location_id,m.primary_category) target,coalesce(v.name,m.name) as name,v.id as version_id,v.version,v.recipe_quantity,v.effective_from
  from public.menu_items m
  left join lateral (
   select id,name,version,recipe_quantity,effective_from from public.menu_item_versions
   where organisation_id=p_organisation_id and menu_item_id=m.id and effective_from<=p_as_of
   order by effective_from desc,version desc limit 1
  ) v on true
  where m.organisation_id=p_organisation_id and m.is_active and m.brand_id=outlet.brand_id and(m.location_id is null or m.location_id=p_location_id)
  and(p_major='ALL' or m.primary_category=p_major or(p_major='UNCLASSIFIED' and not exists(select 1 from public.restaurant_menu_major_categories mc where mc.organisation_id=m.organisation_id and mc.code=m.primary_category))) and(p_subcategory='' or lower(m.subcategory)=lower(p_subcategory)) and (trim(p_search)='' or position(lower(trim(p_search)) in lower(coalesce(v.name,m.name)||' '||m.code))>0)
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

create or replace function public.selling_menu_profitability_sorted(p_organisation_id uuid,p_location_id uuid,p_channel text,p_as_of date,p_search text,p_page integer,p_status text default 'ALL',p_major text default 'ALL',p_subcategory text default '',p_sort text default 'PRIORITY')
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
 if p_major is null or (p_major not in('ALL','UNCLASSIFIED') and not exists(select 1 from public.restaurant_menu_major_categories where organisation_id=p_organisation_id and code=p_major)) or p_subcategory is null or length(p_subcategory)>60 then raise exception 'Choose a valid category.' using errcode='22023';end if;
 if p_sort is null or p_sort not in('PRIORITY','GROSS_DESC','GROSS_ASC') then raise exception 'Choose a valid profitability sort order.' using errcode='22023';end if;
 select count(*) into eligible_count from public.menu_items m left join lateral(select v.name from public.menu_item_versions v where v.organisation_id=m.organisation_id and v.menu_item_id=m.id and v.effective_from<=p_as_of order by v.effective_from desc,v.version desc limit 1)v on true
 where m.organisation_id=p_organisation_id and m.is_active and m.brand_id=outlet.brand_id and(m.location_id is null or m.location_id=p_location_id)
 and(p_major='ALL' or m.primary_category=p_major or(p_major='UNCLASSIFIED' and not exists(select 1 from public.restaurant_menu_major_categories mc where mc.organisation_id=m.organisation_id and mc.code=m.primary_category))) and(p_subcategory='' or lower(m.subcategory)=lower(p_subcategory)) and(trim(p_search)='' or position(lower(trim(p_search)) in lower(coalesce(v.name,m.name)||' '||m.code))>0);
 if eligible_count>5000 then
  raise exception 'Narrow the menu search or category to compare up to 5,000 selling items.' using errcode='22023';end if;
 with eligible as materialized (
  select m.id,m.code,p_channel channel_code,m.primary_category,(select name from public.restaurant_menu_major_categories where organisation_id=m.organisation_id and code=m.primary_category) major_name,m.subcategory,private.pp_cost_target(p_organisation_id,p_location_id,m.primary_category) target,coalesce(v.name,m.name) as name,v.id as version_id,v.version,v.recipe_quantity,v.effective_from
  from public.menu_items m
  left join lateral (
   select id,name,version,recipe_quantity,effective_from from public.menu_item_versions
   where organisation_id=p_organisation_id and menu_item_id=m.id and effective_from<=p_as_of
   order by effective_from desc,version desc limit 1
  ) v on true
  where m.organisation_id=p_organisation_id and m.is_active and m.brand_id=outlet.brand_id and(m.location_id is null or m.location_id=p_location_id)
  and(p_major='ALL' or m.primary_category=p_major or(p_major='UNCLASSIFIED' and not exists(select 1 from public.restaurant_menu_major_categories mc where mc.organisation_id=m.organisation_id and mc.code=m.primary_category))) and(p_subcategory='' or lower(m.subcategory)=lower(p_subcategory)) and (trim(p_search)='' or position(lower(trim(p_search)) in lower(coalesce(v.name,m.name)||' '||m.code))>0)
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

create or replace function public.sales_period_summary(p_organisation_id uuid,p_from date,p_to date,p_location_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; count_lines integer; currency text;
begin
 if not private.pp_sales_read(p_organisation_id) then raise exception 'Sales access denied.' using errcode='42501'; end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>92 or p_to>(select (now() at time zone time_zone)::date from public.organisations where id=p_organisation_id)
  then raise exception 'Choose up to 93 days, ending no later than the current business date.' using errcode='22023'; end if;
 if p_location_id is not null and not exists(select 1 from public.locations where organisation_id=p_organisation_id and id=p_location_id) then raise exception 'Location unavailable.' using errcode='42501'; end if;
 select currency_code into currency from public.organisations where id=p_organisation_id;
 select count(*) into count_lines from public.sales_lines l join public.sales_headers h on h.organisation_id=l.organisation_id and h.id=l.sale_id
  where l.organisation_id=p_organisation_id and h.sale_date between p_from and p_to and (p_location_id is null or h.location_id=p_location_id);
 if count_lines>1000 then raise exception 'This live preview supports up to 1,000 lines. Narrow the date range or select one location.' using errcode='22023'; end if;
 if exists(select 1 from public.sales_headers where organisation_id=p_organisation_id and sale_date between p_from and p_to
  and (p_location_id is null or location_id=p_location_id) and currency_code<>currency) then raise exception 'The selected period contains a different recorded currency. Currency conversion is not inferred.' using errcode='22023'; end if;
 with priced as materialized (
  select l.*,h.location_id,h.sale_date,i.name as menu_name,i.code,coalesce(c.major,'UNCLASSIFIED') major,coalesce(c.major_name,'Unclassified') major_name,coalesce(c.cost_basis,'UNCLASSIFIED') cost_basis,coalesce(c.subcategory,'') subcategory,c.origin,
   private.pp_sales_cost(p_organisation_id,l.menu_version_id,h.sale_date,l.quantity) as estimate
  from public.sales_lines l join public.sales_headers h on h.organisation_id=l.organisation_id and h.id=l.sale_id
  join public.menu_item_versions v on v.organisation_id=l.organisation_id and v.id=l.menu_version_id
  join public.menu_items i on i.organisation_id=l.organisation_id and i.id=l.menu_item_id left join private.sales_category_classifications c on c.organisation_id=l.organisation_id and c.line_id=l.id
  where l.organisation_id=p_organisation_id and h.sale_date between p_from and p_to and (p_location_id is null or h.location_id=p_location_id)
 ), costs as (
  select *, (estimate->>'cost')::numeric as cost from priced
 ), totals as (
  select count(*)::integer as lines,count(distinct sale_id)::integer as receipts,count(cost)::integer as priced_lines,
   coalesce(sum(quantity),0) as quantity,coalesce(sum(net_revenue),0) as revenue,coalesce(sum(tax),0) as tax,
   coalesce(sum(discount),0) as discounts,coalesce(sum(customer_total),0) as customer_total,sum(cost) as known_subtotal,
   case when count(*)>0 and count(cost)=count(*) then sum(cost) else null end as full_cost from costs
 ), category_grouped as (
  select major,cost_basis,max(major_name) name,count(*)::integer lines,count(cost)::integer priced_lines,sum(net_revenue) revenue,case when count(cost)=count(*) then sum(cost) end full_cost from costs group by major,cost_basis
 ), subcategory_grouped as (
  select major,cost_basis,subcategory,max(major_name) name,count(*)::integer lines,count(cost)::integer priced_lines,sum(net_revenue) revenue,case when count(cost)=count(*) then sum(cost) end full_cost from costs group by major,cost_basis,subcategory
 ), family_grouped as (
  select cost_basis,count(*)::integer lines,count(cost)::integer priced_lines,sum(net_revenue) revenue,case when count(cost)=count(*) then sum(cost) end full_cost from costs group by cost_basis
 ), grouped as (
  select menu_item_id,code,min(menu_name) as name,count(*)::integer as lines,count(cost)::integer as priced_lines,
   sum(quantity) as quantity,sum(net_revenue) as revenue,
   case when count(cost)=count(*) then sum(cost) else null end as full_cost from costs group by menu_item_id,code
 ) select jsonb_build_object('currency_code',currency,'from',p_from,'to',p_to,'lines',t.lines,'receipts',t.receipts,
  'priced_lines',t.priced_lines,'missing_lines',t.lines-t.priced_lines,'quantity',t.quantity::text,'net_revenue',t.revenue::text,
  'tax',t.tax::text,'discounts',t.discounts::text,'customer_total',t.customer_total::text,'known_subtotal',t.known_subtotal::text,
  'estimated_food_cost',t.full_cost::text,'estimated_food_margin',(t.revenue-t.full_cost)::text,
  'food_margin_percent',round((t.revenue-t.full_cost)/nullif(t.revenue,0)*100,6)::text,
  'food_cost_basis',case when exists(select 1 from costs where cost_basis='UNCLASSIFIED') then case when exists(select 1 from costs where cost_basis='NON_FOOD') then 'UNCLASSIFIED' else 'LEGACY_ALL_MENUS' end else 'FOOD_BEVERAGE' end,
  'food_beverage_sales',case when not exists(select 1 from costs where cost_basis='UNCLASSIFIED') then coalesce((select sum(net_revenue) from costs where cost_basis in('FOOD','DRINK')),0)::text when not exists(select 1 from costs where cost_basis='NON_FOOD') then t.revenue::text end,
  'food_beverage_cost',case when not exists(select 1 from costs where cost_basis='UNCLASSIFIED' or(cost_basis in('FOOD','DRINK') and cost is null)) then coalesce((select sum(cost) from costs where cost_basis in('FOOD','DRINK')),0)::text when not exists(select 1 from costs where cost_basis='NON_FOOD') and exists(select 1 from costs where cost_basis='UNCLASSIFIED') then t.full_cost::text end,
  'categories',coalesce((select jsonb_agg(jsonb_build_object('code',major,'name',name,'cost_basis',cost_basis,'lines',lines,'priced_lines',priced_lines,'net_revenue',revenue::text,'share_percent',case when t.revenue>0 then round(revenue/t.revenue*100,6)::text end,'estimated_cost',full_cost::text,'estimated_contribution',(revenue-full_cost)::text,'cost_percent',case when revenue>0 then round(full_cost/revenue*100,6)::text end) order by revenue desc,name,major) from category_grouped),'[]'::jsonb),
  'subcategories',coalesce((select jsonb_agg(jsonb_build_object('code',major,'name',name,'subcategory',subcategory,'cost_basis',cost_basis,'lines',lines,'priced_lines',priced_lines,'net_revenue',revenue::text,'share_percent',case when t.revenue>0 then round(revenue/t.revenue*100,6)::text end,'estimated_cost',full_cost::text,'estimated_contribution',(revenue-full_cost)::text,'cost_percent',case when revenue>0 then round(full_cost/revenue*100,6)::text end) order by major,subcategory) from subcategory_grouped),'[]'::jsonb),
  'cost_families',coalesce((select jsonb_agg(jsonb_build_object('basis',cost_basis,'lines',lines,'priced_lines',priced_lines,'net_revenue',revenue::text,'estimated_cost',full_cost::text,'cost_percent',case when revenue>0 then round(full_cost/revenue*100,6)::text end) order by cost_basis) from family_grouped),'[]'::jsonb),
  'category_trend',coalesce((select jsonb_agg(to_jsonb(x) order by x.date,x.code) from(select sale_date date,major code,max(major_name) name,sum(net_revenue)::text net_revenue from costs group by sale_date,major)x),'[]'::jsonb),
  'legacy_category_lines',(select count(*) from costs where origin='LEGACY_BACKFILL'),
  'menus',coalesce((select jsonb_agg(jsonb_build_object('menu_item_id',menu_item_id,'code',code,'name',name,'lines',lines,'priced_lines',priced_lines,
   'quantity',quantity::text,'net_revenue',revenue::text,'estimated_food_cost',full_cost::text,'estimated_food_margin',(revenue-full_cost)::text) order by name,code) from grouped),'[]'::jsonb),
  'missing',coalesce((select jsonb_agg(jsonb_build_object('menu_version_id',menu_version_id,'menu_item_id',menu_item_id,'menu_name',menu_name,'sale_date',sale_date,'reason',estimate->>'reason'))
   from costs where cost is null),'[]'::jsonb)) into result from totals t;
 return result;
end; $$;

-- Keep later expense-report extensions while switching prime cost to the food/beverage basis.
do $$declare definition text;begin
 definition:=pg_get_functiondef('public.expense_period_report(uuid,date,date,uuid,integer)'::regprocedure);
 definition:=replace(definition,$old$sales->>'estimated_food_cost' is not null$old$,$new$(case when sales?'food_beverage_cost' then sales->>'food_beverage_cost' else sales->>'estimated_food_cost' end) is not null$new$);
 definition:=replace(definition,$old$(sales->>'estimated_food_cost')::numeric+labour$old$,$new$(case when sales?'food_beverage_cost' then sales->>'food_beverage_cost' else sales->>'estimated_food_cost' end)::numeric+labour$new$);
 execute definition;
end $$;

-- Keep every existing briefing extension; replace only the ratio basis, retaining saved packs unchanged.
alter function public.executive_profitability_briefing(uuid,date,date,uuid) rename to pp_briefing_before_categories;
alter function public.pp_briefing_before_categories(uuid,date,date,uuid) set schema private;
revoke all on function private.pp_briefing_before_categories(uuid,date,date,uuid) from public,anon,authenticated;
create function private.pp_summary_food_ratio(summary jsonb) returns numeric language sql immutable set search_path='' as $$
 select case when summary?'food_beverage_cost' then (summary->>'food_beverage_cost')::numeric/nullif((summary->>'food_beverage_sales')::numeric,0)*100 else (summary->>'estimated_food_cost')::numeric/nullif((summary->>'net_revenue')::numeric,0)*100 end;
$$;
revoke all on function private.pp_summary_food_ratio(jsonb) from public,anon,authenticated;
create function public.executive_profitability_briefing(p_organisation_id uuid,p_from date,p_to date,p_location_id uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;begin
 result:=private.pp_briefing_before_categories(p_organisation_id,p_from,p_to,p_location_id);
 return result||jsonb_build_object('food_cost_percent',round(private.pp_summary_food_ratio(result->'summary'),6)::text,'food_cost_change_pp',round(private.pp_summary_food_ratio(result->'summary')-private.pp_summary_food_ratio(result->'previous'),6)::text);
end $$;
revoke all on function public.executive_profitability_briefing(uuid,date,date,uuid) from public,anon;
grant execute on function public.executive_profitability_briefing(uuid,date,date,uuid) to authenticated;

-- Require only targets relevant to the restaurant's configured food/beverage headings.
create function private.pp_menu_targets_ready(org uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.locations where organisation_id=org and is_active) and not exists(
 select 1 from public.locations l where l.organisation_id=org and l.is_active and case when exists(select 1 from public.restaurant_menu_categories c where c.organisation_id=org and c.is_active)
 then exists(select 1 from public.restaurant_menu_categories c join public.restaurant_menu_major_categories m on m.organisation_id=c.organisation_id and m.code=c.major where c.organisation_id=org and c.is_active and m.is_active and m.cost_basis in('FOOD','DRINK') and private.pp_cost_target(org,l.id,c.major) is null)
 else private.pp_cost_target(org,l.id,'FOOD') is null or private.pp_cost_target(org,l.id,'DRINK') is null end);
$$;
revoke all on function private.pp_menu_targets_ready(uuid) from public,anon,authenticated;
do $$declare definition text;begin
 definition:=pg_get_functiondef('private.pp_setup_before_processing_centres(uuid)'::regprocedure);
 definition:=replace(definition,$old$exists(select 1 from public.locations where organisation_id=org and is_active) and not exists(select 1 from public.locations l where l.organisation_id=org and l.is_active and(private.pp_cost_target(org,l.id,'FOOD') is null or private.pp_cost_target(org,l.id,'DRINK') is null))$old$,$new$private.pp_menu_targets_ready(org)$new$);
 if position('private.pp_menu_targets_ready(org)' in definition)=0 then raise exception 'Setup target foundation differs. Apply all preceding migrations before update 075.';end if;
 execute definition;
end $$;
commit;
