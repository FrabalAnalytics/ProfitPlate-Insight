-- Phase 1: setup scopes, completeness and restaurant-defined targets. Apply after 031.
begin;
alter table public.items alter column base_uom_id drop not null;
alter table public.items drop constraint items_item_type_check;
alter table public.items add constraint items_item_type_check check(item_type in ('RAW','PACKAGING','RESALE','CONSUMABLE','SEMI_FINISHED','FINISHED','GENERAL'));
alter table public.items add column location_id uuid, add column weekly_count_required boolean not null default false, add column supply_class text not null default 'PURCHASED' check(supply_class in ('PURCHASED','PROCESSED','BOTH')),
 add foreign key(organisation_id,location_id) references public.locations(organisation_id,id);
update public.items set supply_class='PROCESSED' where item_type in ('SEMI_FINISHED','FINISHED');
alter table public.recipes add column location_id uuid,add foreign key(organisation_id,location_id) references public.locations(organisation_id,id);
alter table public.menu_items add column location_id uuid,add column primary_category text check(primary_category in ('FOOD','DRINK','PACKAGING')),add column subcategory text not null default '' check(length(subcategory)<=60),add foreign key(organisation_id,location_id) references public.locations(organisation_id,id);
create table public.cost_targets(organisation_id uuid not null references public.organisations(id),location_id uuid,food_percent numeric(9,6) check(food_percent between 0 and 100),beverage_percent numeric(9,6) check(beverage_percent between 0 and 100),updated_at timestamptz not null default now(),updated_by uuid not null references auth.users(id),unique nulls not distinct(organisation_id,location_id),foreign key(organisation_id,location_id) references public.locations(organisation_id,id));
create table public.zero_opening_confirmations(organisation_id uuid not null,item_id uuid not null,stock_location_id uuid not null,opening_date date not null,note text not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),primary key(organisation_id,item_id,stock_location_id),foreign key(organisation_id,item_id) references public.items(organisation_id,id),foreign key(organisation_id,stock_location_id) references public.stock_locations(organisation_id,id));
create table private.setup_requests(organisation_id uuid not null,request_id uuid not null,kind text not null,input_hash text not null,result_id uuid not null,primary key(organisation_id,request_id,kind));
revoke all on private.setup_requests from public,anon,authenticated;
alter table public.cost_targets enable row level security;
alter table public.zero_opening_confirmations enable row level security;
revoke all on public.cost_targets,public.zero_opening_confirmations from public,anon,authenticated;

create function private.pp_setup_location(org uuid,loc uuid) returns void language plpgsql stable security definer set search_path='' as $$begin
 if loc is not null and not exists(select 1 from public.locations where organisation_id=org and id=loc and is_active) then raise exception 'Choose an active location in this business.' using errcode='22023';end if;
end $$;
create function public.save_cost_targets(p_organisation_id uuid,p_location_id uuid,p_food numeric,p_beverage numeric) returns void language plpgsql security definer set search_path='' as $$begin
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Restaurant administrator access required.' using errcode='42501';end if;
 perform private.pp_setup_location(p_organisation_id,p_location_id);
 if p_food not between 0 and 100 or p_beverage not between 0 and 100 or p_food<>round(p_food,6) or p_beverage<>round(p_beverage,6) then raise exception 'Targets must be between 0 and 100, up to six decimals.' using errcode='22023';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 insert into public.cost_targets values(p_organisation_id,p_location_id,p_food,p_beverage,now(),auth.uid()) on conflict(organisation_id,location_id) do update set food_percent=p_food,beverage_percent=p_beverage,updated_at=now(),updated_by=auth.uid();
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'SETUP_TARGETS',auth.uid(),coalesce(p_location_id,p_organisation_id),jsonb_build_object('location',p_location_id,'food',p_food,'beverage',p_beverage));
end $$;
create function private.pp_cost_target(org uuid,loc uuid,category text) returns numeric language sql stable security definer set search_path='' as $$
 select case category when 'FOOD' then coalesce(l.food_percent,b.food_percent) when 'DRINK' then coalesce(l.beverage_percent,b.beverage_percent) end from(select 1)x left join public.cost_targets b on b.organisation_id=org and b.location_id is null left join public.cost_targets l on l.organisation_id=org and l.location_id=loc;
$$;
create function public.setup_profiles(p_organisation_id uuid,p_kind text,p_ids uuid[]) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;day date;
begin
 if not private.pp_catalogue_read(p_organisation_id) then raise exception 'Setup access denied.' using errcode='42501';end if;
 if p_kind not in ('MATERIAL','MENU','RECIPE') or p_kind is null or p_ids is null or cardinality(p_ids)>25 then raise exception 'Choose up to 25 setup records.' using errcode='22023';end if;
 select(now() at time zone time_zone)::date into day from public.organisations where id=p_organisation_id;
 if p_kind='MATERIAL' then
 select coalesce(jsonb_object_agg(i.id::text,jsonb_build_object('location_id',i.location_id,'weekly_count_required',i.weekly_count_required,'supply_class',i.supply_class,
 'last_price',case when private.pp_reference_price_read(p_organisation_id) then price.cost_per_base_unit::text end,'price_date',case when private.pp_reference_price_read(p_organisation_id) then price.price_date end,
 'missing',to_jsonb(array_remove(array[case when i.base_uom_id is null then 'Base unit' end,case when price.id is null then 'Reference price' end,
 case when i.stock_tracked and (not exists(select 1 from public.stock_locations s where s.organisation_id=i.organisation_id and s.is_active and(i.location_id is null or s.outlet_id is null or s.outlet_id=i.location_id)) or exists(select 1 from public.stock_locations s where s.organisation_id=i.organisation_id and s.is_active and(i.location_id is null or s.outlet_id is null or s.outlet_id=i.location_id) and not private.pp_opening_ready(i.organisation_id,i.id,s.id))) then 'Opening stock' end],null)))),'{}'::jsonb) into result
 from public.items i left join lateral(select p.id,p.cost_per_base_unit,p.price_date from public.material_reference_prices p where p.organisation_id=i.organisation_id and p.item_id=i.id and p.price_date<=day order by p.price_date desc,p.version desc limit 1)price on true where i.organisation_id=p_organisation_id and i.id=any(p_ids);
 elsif p_kind='RECIPE' then
 select coalesce(jsonb_object_agg(id::text,jsonb_build_object('location_id',location_id)),'{}') into result from public.recipes where organisation_id=p_organisation_id and id=any(p_ids);
 else
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Menu access denied.' using errcode='42501';end if;
 select coalesce(jsonb_object_agg(m.id::text,jsonb_build_object('location_id',m.location_id,'primary_category',m.primary_category,'subcategory',m.subcategory,
 'missing',to_jsonb(array_remove(array[case when m.primary_category is null then 'Primary category' end,case when m.subcategory='' then 'Subcategory' end,case when v.id is null then 'Final recipe' end,
 case when not exists(select 1 from public.locations l where l.organisation_id=m.organisation_id and l.is_active and l.brand_id=m.brand_id and(m.location_id is null or l.id=m.location_id)) or exists(select 1 from public.locations l where l.organisation_id=m.organisation_id and l.is_active and l.brand_id=m.brand_id and(m.location_id is null or l.id=m.location_id) and not exists(select 1 from(select distinct on(p.channel_code) p.* from public.menu_price_versions p where p.organisation_id=m.organisation_id and p.menu_item_id=m.id and p.location_id=l.id and p.effective_from<=day order by p.channel_code,p.effective_from desc,p.version desc)current_price where current_price.effective_to is null or current_price.effective_to>=day)) then 'Selling price' end,
 case when v.id is not null and(public.recipe_reference_cost_estimate(m.organisation_id,v.recipe_version_id,day,v.recipe_quantity)->>'cost_state')<>'ESTIMATED' then 'Recipe cost' end],null)))),'{}') into result
 from public.menu_items m left join lateral(select id,recipe_version_id,recipe_quantity from public.menu_item_versions where organisation_id=m.organisation_id and menu_item_id=m.id and effective_from<=day order by effective_from desc,version desc limit 1)v on true where m.organisation_id=p_organisation_id and m.id=any(p_ids);
 end if;return result;
end $$;
create function private.pp_opening_ready(org uuid,item uuid,site uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.zero_opening_confirmations where organisation_id=org and item_id=item and stock_location_id=site) or exists(select 1 from public.stock_documents d cross join lateral jsonb_array_elements(d.lines)l where d.organisation_id=org and d.state='POSTED' and((d.kind='OPENING' and d.destination_id=site) or(d.kind='COUNT' and d.source_id=site)) and l->>'item_id'=item::text);
$$;
create function public.confirm_zero_opening(p_organisation_id uuid,p_item_id uuid,p_site_id uuid,p_date date,p_note text) returns void language plpgsql security definer set search_path='' as $$begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'Inventory Manager access required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if p_date is null or p_date>(select(now() at time zone time_zone)::date from public.organisations where id=p_organisation_id) or p_note is null or length(trim(p_note)) not between 1 and 300 then raise exception 'Enter a valid opening date and source note.' using errcode='22023';end if;
 if not exists(select 1 from public.items i join public.stock_locations s on s.organisation_id=i.organisation_id where i.organisation_id=p_organisation_id and i.id=p_item_id and s.id=p_site_id and s.is_active and i.is_active and i.stock_tracked and i.base_uom_id is not null and(i.location_id is null or s.outlet_id is null or s.outlet_id=i.location_id)) then raise exception 'Choose a measurable material and compatible stock location.' using errcode='22023';end if;
 if exists(select 1 from public.stock_ledger where organisation_id=p_organisation_id and item_id=p_item_id and location_id=p_site_id) or exists(select 1 from public.stock_documents d cross join lateral jsonb_array_elements(d.lines)l where d.organisation_id=p_organisation_id and(d.source_id=p_site_id or d.destination_id=p_site_id) and d.state not in ('CANCELLED','POSTED','RECEIVED') and l->>'item_id'=p_item_id::text) then raise exception 'Stock history or pending movements exist. Use the reviewed stock workflow.' using errcode='22023';end if;
 insert into public.zero_opening_confirmations values(p_organisation_id,p_item_id,p_site_id,p_date,trim(p_note),auth.uid(),now()) on conflict do nothing;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'ZERO_OPENING_CONFIRMED',auth.uid(),p_item_id,jsonb_build_object('stock_location',p_site_id,'date',p_date,'note',p_note));
end $$;
create or replace function public.save_catalogue_material(
  p_organisation_id uuid,p_id uuid,p_code text,p_name text,p_item_type text,
  p_category text,p_base_uom_id uuid,p_stock_tracked boolean,p_is_active boolean
) returns uuid language plpgsql security definer set search_path = '' as $$
declare result_id uuid; v_category_id uuid; previous public.items%rowtype; u public.units_of_measure%rowtype;
begin
  if not private.pp_catalogue_write(p_organisation_id) then raise exception 'Catalogue access denied.' using errcode='42501'; end if;
  if p_code is null or p_code !~ '^[A-Z0-9][A-Z0-9_-]{0,39}$' or length(trim(p_name)) not between 1 and 120
    or length(p_category)>60 or p_item_type not in ('RAW','PACKAGING','RESALE','CONSUMABLE','SEMI_FINISHED','FINISHED','GENERAL')
    then raise exception 'Check your material details.' using errcode='22023'; end if;
  select * into u from public.units_of_measure where organisation_id=p_organisation_id and id=p_base_uom_id;
  if p_base_uom_id is not null and (u.id is null or u.dimension='PACKAGE') then raise exception 'Choose a measurable base unit.' using errcode='22023'; end if;
  if p_id is not null then
    select * into previous from public.items where organisation_id=p_organisation_id and id=p_id for update;
    if not found then raise exception 'Material not available.' using errcode='42501'; end if;
    if previous.code<>p_code or (previous.base_uom_id is not null and previous.base_uom_id is distinct from p_base_uom_id)
      then raise exception 'Material code and base unit cannot be changed.' using errcode='22023'; end if;
  end if;
  if nullif(trim(p_category),'') is not null then
    insert into public.item_categories(organisation_id,name,created_by) values(p_organisation_id,trim(p_category),auth.uid())
      on conflict(organisation_id,lower(name)) do update set name=public.item_categories.name
      returning id into v_category_id;
  end if;
  if p_id is null then
    insert into public.items(organisation_id,code,name,item_type,category_id,base_uom_id,stock_tracked,is_active,created_by)
      values(p_organisation_id,p_code,trim(p_name),p_item_type,v_category_id,p_base_uom_id,p_stock_tracked,p_is_active,auth.uid()) returning id into result_id;
  else
    update public.items set base_uom_id=p_base_uom_id,name=trim(p_name),item_type=p_item_type,category_id=v_category_id,
      stock_tracked=p_stock_tracked,is_active=p_is_active,updated_at=now()
      where organisation_id=p_organisation_id and id=p_id returning id into result_id;
  end if;
  insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details)
    values(p_organisation_id,case when p_id is null then 'material.created' else 'material.updated' end,auth.uid(),result_id,
      jsonb_build_object('code',p_code,'is_active',p_is_active,'previous',case when p_id is null then null else to_jsonb(previous) end));
  return result_id;
end; $$;


create function public.save_setup_profile(p_organisation_id uuid,p_kind text,p_id uuid,p_location_id uuid,p_primary text default null,p_subcategory text default '',p_weekly boolean default false,p_supply text default 'PURCHASED') returns void language plpgsql security definer set search_path='' as $$begin
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
 if p_primary is not null and p_primary not in ('FOOD','DRINK','PACKAGING') or p_subcategory is null or length(p_subcategory)>60 then raise exception 'Choose a valid category and subcategory.' using errcode='22023';end if;
 if exists(select 1 from public.menu_items where organisation_id=p_organisation_id and id=p_id and location_id is distinct from p_location_id) and(exists(select 1 from public.menu_price_versions where organisation_id=p_organisation_id and menu_item_id=p_id) or exists(select 1 from public.sales_lines where organisation_id=p_organisation_id and menu_item_id=p_id)) then raise exception 'Menu scope stays fixed after pricing or sales. Create a separate scoped item.' using errcode='22023';end if;
 if p_location_id is not null and not exists(select 1 from public.menu_items m join public.locations l on l.organisation_id=m.organisation_id and l.brand_id=m.brand_id where m.organisation_id=p_organisation_id and m.id=p_id and l.id=p_location_id) then raise exception 'Choose a location belonging to this menu brand.' using errcode='22023';end if;
 update public.menu_items set location_id=p_location_id,primary_category=p_primary,subcategory=trim(p_subcategory) where organisation_id=p_organisation_id and id=p_id;
 end if;
 if not found then raise exception 'Setup record unavailable.' using errcode='42501';end if;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'SETUP_PROFILE',auth.uid(),p_id,jsonb_build_object('kind',p_kind,'location',p_location_id,'category',p_primary,'subcategory',p_subcategory,'weekly',p_weekly,'supply',p_supply));
end $$;
create function public.save_material_setup(p_organisation_id uuid,p_value jsonb) returns uuid language plpgsql security definer set search_path='' as $$declare id uuid;begin
 id:=public.save_catalogue_material(p_organisation_id,nullif(p_value->>'id','')::uuid,p_value->>'code',p_value->>'name',p_value->>'item_type',coalesce(p_value->>'category',''),nullif(p_value->>'base_uom_id','')::uuid,(p_value->>'stock_tracked')::boolean,(p_value->>'is_active')::boolean);
 perform public.save_setup_profile(p_organisation_id,'MATERIAL',id,nullif(p_value->>'location_id','')::uuid,null,'',coalesce((p_value->>'weekly_count_required')::boolean,false),coalesce(p_value->>'supply_class','PURCHASED'));return id;
end $$;
create function public.save_menu_setup(p_organisation_id uuid,p_request_id uuid,p_value jsonb) returns uuid language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare id uuid;v uuid;old private.setup_requests;digest text:=md5(p_value::text);begin
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Menu editing access denied.' using errcode='42501';end if;
 if p_request_id is null then raise exception 'Save request required.' using errcode='22023';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into old from private.setup_requests where organisation_id=p_organisation_id and request_id=p_request_id and kind='MENU';
 if found then if old.input_hash<>digest then raise exception 'Refresh before saving changed details.' using errcode='22023';end if;return old.result_id;end if;
 if p_value->>'code' is null or p_value->>'code' !~ '^[A-Z0-9][A-Z0-9_-]{0,39}$' or p_value->>'name' is null or length(trim(p_value->>'name')) not between 1 and 120 then raise exception 'Enter a menu code and name.' using errcode='22023';end if;
 if not exists(select 1 from public.brands b where b.organisation_id=p_organisation_id and b.id=(p_value->>'brand_id')::uuid) then raise exception 'Choose an available brand.' using errcode='22023';end if;
 id:=nullif(p_value->>'menu_id','')::uuid;
 if id is null then insert into public.menu_items(organisation_id,code,name,brand_id) values(p_organisation_id,p_value->>'code',trim(p_value->>'name'),(p_value->>'brand_id')::uuid) returning public.menu_items.id into id;
 else
 if not exists(select 1 from public.menu_items m where m.organisation_id=p_organisation_id and m.id=id and m.code=p_value->>'code' and m.brand_id=(p_value->>'brand_id')::uuid and m.is_active) then raise exception 'Active menu item unavailable or identity changed.' using errcode='42501';end if;
 update public.menu_items set name=trim(p_value->>'name') where organisation_id=p_organisation_id and public.menu_items.id=id;
 end if;
 perform public.save_setup_profile(p_organisation_id,'MENU',id,nullif(p_value->>'location_id','')::uuid,nullif(p_value->>'primary_category',''),coalesce(p_value->>'category',''));
 if nullif(p_value->>'recipe_version_id','') is not null then
 v:=public.publish_menu_item_version(p_organisation_id,id,p_request_id,p_value->>'code',p_value->>'name',(p_value->>'brand_id')::uuid,coalesce(p_value->>'category',''),(p_value->>'recipe_version_id')::uuid,(p_value->>'recipe_quantity')::numeric,(p_value->>'effective_from')::date,coalesce(p_value->>'notes',''));
 end if;
 insert into private.setup_requests values(p_organisation_id,p_request_id,'MENU',digest,id);return id;
end $$;
create function public.publish_recipe_setup(p_organisation_id uuid,p_request_id uuid,p_value jsonb,p_components jsonb) returns uuid language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare id uuid;v uuid;old private.setup_requests;digest text:=md5(jsonb_build_array(p_value,p_components)::text);begin
 if not private.pp_recipe_write(p_organisation_id) then raise exception 'Recipe editing access denied.' using errcode='42501';end if;
 if p_request_id is null then raise exception 'Save request required.' using errcode='22023';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into old from private.setup_requests where organisation_id=p_organisation_id and request_id=p_request_id and kind='RECIPE';if found then if old.input_hash<>digest then raise exception 'Refresh before saving changed details.' using errcode='22023';end if;return old.result_id;end if;
 id:=nullif(p_value->>'recipe_id','')::uuid;
 if id is null then insert into public.recipes(organisation_id,code,name,recipe_type,created_by) values(p_organisation_id,p_value->>'code',trim(p_value->>'name'),p_value->>'recipe_type',auth.uid()) returning public.recipes.id into id;end if;
 perform public.save_setup_profile(p_organisation_id,'RECIPE',id,nullif(p_value->>'location_id','')::uuid);
 v:=public.publish_recipe_version(p_organisation_id,id,p_request_id,p_value->>'code',p_value->>'name',p_value->>'recipe_type',(p_value->>'effective_from')::date,(p_value->>'yield_quantity')::numeric,(p_value->>'yield_uom_id')::uuid,coalesce(p_value->>'notes',''),p_components);
 insert into private.setup_requests values(p_organisation_id,p_request_id,'RECIPE',digest,v);return v;
end $$;
-- Scope is catalogue availability, not a replacement for role permissions.
create function private.pp_setup_scope_guard() returns trigger language plpgsql security definer set search_path='' as $$declare loc uuid;restricted uuid;item uuid;recipe uuid;x jsonb;destination uuid;begin
 if tg_table_name='recipe_components' then
 select r.location_id into loc from public.recipe_versions v join public.recipes r on r.organisation_id=v.organisation_id and r.id=v.recipe_id where v.organisation_id=new.organisation_id and v.id=new.recipe_version_id;
 if new.item_id is not null then select location_id into restricted from public.items where organisation_id=new.organisation_id and id=new.item_id;else select r.location_id into restricted from public.recipe_versions v join public.recipes r on r.organisation_id=v.organisation_id and r.id=v.recipe_id where v.organisation_id=new.organisation_id and v.id=new.child_recipe_version_id;end if;
 elsif tg_table_name='menu_item_versions' then
 select location_id into loc from public.menu_items where organisation_id=new.organisation_id and id=new.menu_item_id;
 select r.location_id into restricted from public.recipe_versions v join public.recipes r on r.organisation_id=v.organisation_id and r.id=v.recipe_id where v.organisation_id=new.organisation_id and v.id=new.recipe_version_id;
 elsif tg_table_name='menu_price_versions' then
 loc:=new.location_id;select location_id into restricted from public.menu_items where organisation_id=new.organisation_id and id=new.menu_item_id;
 elsif tg_table_name='sales_lines' then
 select location_id into loc from public.sales_headers where organisation_id=new.organisation_id and id=new.sale_id;select location_id into restricted from public.menu_items where organisation_id=new.organisation_id and id=new.menu_item_id;
 elsif tg_table_name='purchase_lines' then
 item:=new.item_id;select location_id into loc from public.purchase_headers where organisation_id=new.organisation_id and id=new.purchase_id;
 elsif tg_table_name='purchase_order_lines' then
 item:=new.item_id;select location_id into loc from public.purchase_orders where organisation_id=new.organisation_id and id=new.order_id;
 elsif tg_table_name='stock_ledger' then
 item:=new.item_id;select outlet_id into loc from public.stock_locations where organisation_id=new.organisation_id and id=new.location_id;
 else
 select outlet_id into loc from public.stock_locations where organisation_id=new.organisation_id and id=new.source_id;
 select outlet_id into destination from public.stock_locations where organisation_id=new.organisation_id and id=new.destination_id;
 for x in select * from jsonb_array_elements(new.lines) loop
  if new.kind='OPENING' and exists(select 1 from public.zero_opening_confirmations where organisation_id=new.organisation_id and item_id=(x->>'item_id')::uuid and stock_location_id=new.destination_id) then raise exception 'Zero opening already confirmed. Use a reviewed count for corrections.' using errcode='22023';end if;
  select location_id into restricted from public.items where organisation_id=new.organisation_id and id=(x->>'item_id')::uuid;
  if restricted is not null and((loc is not null and loc<>restricted) or(destination is not null and destination<>restricted)) then raise exception 'Material is unavailable for this movement location.' using errcode='22023';end if;
 end loop;restricted:=null;
 if new.kind='PRODUCTION' then select r.location_id into restricted from public.recipe_versions v join public.recipes r on r.organisation_id=v.organisation_id and r.id=v.recipe_id where v.organisation_id=new.organisation_id and v.id=new.recipe_version_id;end if;
 end if;
 if item is not null then
 if not exists(select 1 from public.items where organisation_id=new.organisation_id and id=item and base_uom_id is not null) then raise exception 'Complete the material base unit before recording quantities.' using errcode='22023';end if;
 select location_id into restricted from public.items where organisation_id=new.organisation_id and id=item;
 if tg_table_name='stock_ledger' and loc is null then return new;end if;
 end if;
 if restricted is not null and restricted is distinct from loc then raise exception 'This component or item belongs to another location. Choose a compatible scope.' using errcode='22023';end if;
 return new;
end $$;
do $$declare t text;begin foreach t in array array['recipe_components','menu_item_versions','menu_price_versions','sales_lines','purchase_lines','purchase_order_lines','stock_ledger','stock_documents'] loop execute format('create trigger setup_scope_guard before insert on public.%I for each row execute function private.pp_setup_scope_guard()',t);end loop;end $$;
create or replace function public.save_menu_selling_price(p_organisation_id uuid,p_menu_id uuid,p_request_id uuid,p_location_id uuid,p_channel text,
 p_price numeric,p_tax_setting text,p_tax_percent numeric,p_effective_from date,p_effective_to date,p_notes text)
returns uuid language plpgsql security definer set search_path='' as $$
declare root public.menu_items%rowtype; previous public.menu_price_versions%rowtype; digest text;
 result_id uuid; next_version integer; currency text;
begin
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Selling-price editing requires an organisation-wide restaurant administrator.' using errcode='42501'; end if;
 if p_request_id is null or p_price is null or p_price<=0 or p_price>=1e14 or p_price<>round(p_price,6)
  or p_tax_setting is null or p_tax_setting not in ('NONE','EXCLUSIVE','INCLUSIVE') or p_tax_percent is null
  or p_tax_percent<0 or p_tax_percent>100 or p_tax_percent<>round(p_tax_percent,6) or (p_tax_setting='NONE' and p_tax_percent<>0)
  or p_channel is null or p_channel not in ('DINE_IN','TAKEAWAY','DELIVERY') or p_effective_from is null
  or p_effective_to<p_effective_from or p_notes is null or length(trim(p_notes)) not between 1 and 300
  then raise exception 'Check the price, tax setting, dates, channel and source note.' using errcode='22023'; end if;
 select currency_code into currency from public.organisations where id=p_organisation_id for update;
 digest:=md5(jsonb_build_array(p_menu_id,p_location_id,p_channel,p_price,p_tax_setting,p_tax_percent,p_effective_from,p_effective_to,p_notes,currency)::text);
 select * into previous from public.menu_price_versions where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then
  if previous.input_hash<>digest then raise exception 'This save request was already used. Refresh before saving different details.' using errcode='22023'; end if;
  return previous.id;
 end if;
 select * into root from public.menu_items where organisation_id=p_organisation_id and id=p_menu_id and is_active;
 if not found then raise exception 'Active menu item unavailable.' using errcode='42501'; end if;
 perform 1 from public.locations where organisation_id=p_organisation_id and id=p_location_id and is_active and brand_id=root.brand_id;
 if not found then raise exception 'Choose an active location belonging to this menu brand.' using errcode='22023'; end if;
 select coalesce(max(version),0)+1 into next_version from public.menu_price_versions where organisation_id=p_organisation_id and menu_item_id=p_menu_id;
 insert into public.menu_price_versions(organisation_id,menu_item_id,location_id,channel_code,version,currency_code,price,tax_setting,tax_percent,effective_from,effective_to,notes,request_id,input_hash,created_by)
 values(p_organisation_id,p_menu_id,p_location_id,p_channel,next_version,currency,p_price,p_tax_setting,p_tax_percent,p_effective_from,p_effective_to,trim(p_notes),p_request_id,digest,auth.uid()) returning id into result_id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'menu.price_saved',auth.uid(),result_id,jsonb_build_object('menu_item_id',p_menu_id,'version',next_version,'location_id',p_location_id,'channel',p_channel));
 return result_id;
end; $$;


create function private.pp_setup_progress(org uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare stages jsonb;material_count int;missing_materials int;menus int;missing_menus int;day date;begin
 select(now() at time zone time_zone)::date into day from public.organisations where id=org;
 select count(*),count(*) filter(where i.base_uom_id is null or not exists(select 1 from public.material_reference_prices p where p.organisation_id=org and p.item_id=i.id and p.price_date<=day) or(i.stock_tracked and(not exists(select 1 from public.stock_locations s where s.organisation_id=org and s.is_active and(i.location_id is null or s.outlet_id is null or s.outlet_id=i.location_id)) or exists(select 1 from public.stock_locations s where s.organisation_id=org and s.is_active and(i.location_id is null or s.outlet_id is null or s.outlet_id=i.location_id) and not private.pp_opening_ready(org,i.id,s.id))))) into material_count,missing_materials from public.items i where i.organisation_id=org and i.is_active;
 select count(*),count(*) filter(where m.primary_category is null or m.subcategory='' or not exists(select 1 from public.menu_item_versions v where v.organisation_id=org and v.menu_item_id=m.id and v.effective_from<=day) or not exists(select 1 from public.locations l where l.organisation_id=org and l.is_active and l.brand_id=m.brand_id and(m.location_id is null or l.id=m.location_id)) or exists(select 1 from public.locations l where l.organisation_id=org and l.is_active and l.brand_id=m.brand_id and(m.location_id is null or l.id=m.location_id) and not exists(select 1 from(select distinct on(channel_code) * from public.menu_price_versions p where p.organisation_id=org and p.menu_item_id=m.id and p.location_id=l.id and p.effective_from<=day order by channel_code,effective_from desc,version desc)price where price.effective_to is null or price.effective_to>=day))) into menus,missing_menus from public.menu_items m where m.organisation_id=org and m.is_active;
 stages:=jsonb_build_array(
 jsonb_build_object('name','Business & locations','ready',exists(select 1 from public.locations where organisation_id=org and is_active),'path','/workspace/setup','detail','Business profile and active outlets'),
 jsonb_build_object('name','Users & roles','ready',exists(select 1 from public.organisation_memberships m join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id where m.organisation_id=org and m.status='active'),'path','/workspace/team','detail','Active members with assigned roles'),
 jsonb_build_object('name','Suppliers','ready',exists(select 1 from public.suppliers where organisation_id=org and is_active),'path','/workspace/materials','detail','Active supplier catalogue'),
 jsonb_build_object('name','Materials, prices & opening stock','ready',material_count>0 and missing_materials=0,'path','/workspace/materials','detail',missing_materials||' incomplete of '||material_count||' active materials'),
 jsonb_build_object('name','Recipes','ready',exists(select 1 from public.recipes where organisation_id=org) and not exists(select 1 from public.recipes r where r.organisation_id=org and not exists(select 1 from public.recipe_versions v where v.organisation_id=org and v.recipe_id=r.id)),'path','/workspace/recipes','detail','Saved recipe versions'),
 jsonb_build_object('name','Menu mapping & selling prices','ready',menus>0 and missing_menus=0,'path','/workspace/menus','detail',missing_menus||' incomplete of '||menus||' active menu items'),
 jsonb_build_object('name','Food & beverage targets','ready',exists(select 1 from public.locations where organisation_id=org and is_active) and not exists(select 1 from public.locations l where l.organisation_id=org and l.is_active and(private.pp_cost_target(org,l.id,'FOOD') is null or private.pp_cost_target(org,l.id,'DRINK') is null)),'path','/workspace/setup/standards','detail','Business targets or location overrides'));
 return jsonb_build_object('completed',(select count(*) from jsonb_array_elements(stages)s where(s->>'ready')::boolean),'total',7,'stages',stages,'missing_materials',missing_materials,'missing_menus',missing_menus);
end $$;
create function public.setup_workspace(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not(private.pp_reference_price_read(p_organisation_id) or private.pp_stock_manager(p_organisation_id)) then raise exception 'Setup administration access required.' using errcode='42501';end if;
 return jsonb_build_object('progress',private.pp_setup_progress(p_organisation_id),'can_edit',private.pp_menu_write(p_organisation_id),'can_open',private.pp_stock_manager(p_organisation_id),
 'locations',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'name',l.name,'food',private.pp_cost_target(p_organisation_id,l.id,'FOOD')::text,'beverage',private.pp_cost_target(p_organisation_id,l.id,'DRINK')::text) order by l.name) from public.locations l where l.organisation_id=p_organisation_id and l.is_active),'[]'::jsonb),
 'targets',coalesce((select jsonb_agg(jsonb_build_object('location_id',location_id,'food',food_percent::text,'beverage',beverage_percent::text)) from public.cost_targets where organisation_id=p_organisation_id),'[]'::jsonb),
 'sites',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'outlet_id',outlet_id) order by name) from public.stock_locations where organisation_id=p_organisation_id and is_active),'[]'::jsonb),
 'materials',coalesce((select jsonb_agg(to_jsonb(i)) from(select id,name,location_id from public.items where organisation_id=p_organisation_id and is_active and stock_tracked and base_uom_id is not null order by name,id limit 1000)i),'[]'::jsonb));
end $$;
create or replace function public.menu_profitability(p_organisation_id uuid,p_location_id uuid,p_channel text,p_as_of date,p_search text,p_page integer)
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
  select m.id,m.code,m.primary_category,private.pp_cost_target(p_organisation_id,p_location_id,m.primary_category) target,coalesce(v.name,m.name) as name,v.id as version_id,v.version,v.recipe_quantity,v.effective_from
  from public.menu_items m
  left join lateral (
   select id,name,version,recipe_quantity,effective_from from public.menu_item_versions
   where organisation_id=p_organisation_id and menu_item_id=m.id and effective_from<=p_as_of
   order by effective_from desc,version desc limit 1
  ) v on true
  where m.organisation_id=p_organisation_id and m.is_active and m.brand_id=outlet.brand_id and(m.location_id is null or m.location_id=p_location_id)
  and (trim(p_search)='' or position(lower(trim(p_search)) in lower(coalesce(v.name,m.name)||' '||m.code))>0)
 ), paged as (
  select * from eligible order by name,id limit 25 offset (p_page-1)*25
 )
 select jsonb_build_object('total',(select count(*) from eligible),'currency_code',currency,
  'unassigned_menu_count',(select count(*) from public.menu_items where organisation_id=p_organisation_id and is_active and brand_id is null),
  'rows',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.code,'name',p.name,
   'primary_category',p.primary_category,'target',p.target::text,'version_id',p.version_id,'version',p.version,'effective_from',p.effective_from,'recipe_quantity',p.recipe_quantity::text,
   'estimate',case when p.version_id is null then null else public.menu_food_margin_estimate(
    p_organisation_id,p.version_id,p_location_id,p_channel,p_as_of) end) order by p.name,p.id) from paged p),'[]'::jsonb)) into result;
 return result;
end; $$;
create or replace function public.get_menu_item(p_organisation_id uuid,p_menu_id uuid,p_version_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare root public.menu_items%rowtype; selected public.menu_item_versions%rowtype; result jsonb;
begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Menu access denied.' using errcode='42501'; end if;
 select * into root from public.menu_items where organisation_id=p_organisation_id and id=p_menu_id;
 if not found then raise exception 'Menu item unavailable.' using errcode='42501'; end if;
 select * into selected from public.menu_item_versions where organisation_id=p_organisation_id and menu_item_id=p_menu_id
  and (p_version_id is null or id=p_version_id) order by version desc limit 1;
 if not found and p_version_id is not null then raise exception 'Menu version unavailable.' using errcode='42501'; end if;
 select jsonb_build_object('item',jsonb_build_object('id',root.id,'code',root.code,'name',root.name,'brand_id',root.brand_id,'is_active',root.is_active,'location_id',root.location_id,'primary_category',root.primary_category,'subcategory',root.subcategory),
  'version',case when selected.id is null then null else (to_jsonb(selected)-'input_hash'-'request_id')||jsonb_build_object('recipe_quantity',selected.recipe_quantity::text) end,
  'recipe',case when selected.id is null then null else (select jsonb_build_object('id',v.id,'label',v.name||' · v'||v.version,'code',r.code,
   'uom_id',o.uom_id,'uom_code',u.code,'dimension',u.dimension,'effective_from',v.effective_from) from public.recipe_versions v
   join public.recipes r on r.organisation_id=v.organisation_id and r.id=v.recipe_id
   join public.recipe_outputs o on o.organisation_id=v.organisation_id and o.recipe_version_id=v.id
   join public.units_of_measure u on u.organisation_id=o.organisation_id and u.id=o.uom_id where v.id=selected.recipe_version_id) end,
  'versions',coalesce((select jsonb_agg(jsonb_build_object('id',id,'version',version,'name',name,'effective_from',effective_from) order by version desc)
   from public.menu_item_versions where organisation_id=p_organisation_id and menu_item_id=p_menu_id),'[]'::jsonb),
  'prices',coalesce((select jsonb_agg(to_jsonb(p) order by p.version desc) from (
   select id,version,location_id,channel_code,currency_code,price::text,tax_setting,tax_percent::text,effective_from,effective_to,notes
   from public.menu_price_versions where organisation_id=p_organisation_id and menu_item_id=p_menu_id order by version desc limit 25) p),'[]'::jsonb)) into result;
 return result;
end; $$;

create or replace function public.menu_food_margin_estimate(p_organisation_id uuid,p_version_id uuid,p_location_id uuid,p_channel text,p_as_of date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare version_row public.menu_item_versions%rowtype; root public.menu_items%rowtype; price_row public.menu_price_versions%rowtype;
 currency text; recipe_estimate jsonb; price_issue text; net numeric; tax numeric; customer_total numeric; cost numeric; margin numeric;
begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Menu financial access denied.' using errcode='42501'; end if;
 select * into version_row from public.menu_item_versions where organisation_id=p_organisation_id and id=p_version_id;
 if not found then raise exception 'Menu version unavailable.' using errcode='42501'; end if;
 select * into root from public.menu_items where organisation_id=p_organisation_id and id=version_row.menu_item_id;
 if not root.is_active then raise exception 'Reactivate the menu item to preview its current food margin.' using errcode='22023'; end if;
 select currency_code into currency from public.organisations where id=p_organisation_id;
 if p_as_of is null or p_as_of<version_row.effective_from or p_as_of>(select (now() at time zone time_zone)::date from public.organisations where id=p_organisation_id)
  then raise exception 'Choose a business date on or after this menu version starts, and not in the future.' using errcode='22023'; end if;
 if p_channel is null or p_channel not in ('DINE_IN','TAKEAWAY','DELIVERY') then raise exception 'Choose a valid sales channel.' using errcode='22023'; end if;
 perform 1 from public.locations where organisation_id=p_organisation_id and id=p_location_id and is_active and brand_id=root.brand_id and(root.location_id is null or id=root.location_id);
 if not found then raise exception 'Choose an active location belonging to the menu brand.' using errcode='22023'; end if;
 recipe_estimate:=public.recipe_reference_cost_estimate(p_organisation_id,version_row.recipe_version_id,p_as_of,version_row.recipe_quantity);
 select * into price_row from public.menu_price_versions where organisation_id=p_organisation_id and menu_item_id=root.id
  and location_id=p_location_id and channel_code=p_channel and effective_from<=p_as_of order by effective_from desc,version desc limit 1;
 if not found then price_issue:='MISSING_SELLING_PRICE';
 elsif price_row.currency_code<>currency then price_issue:='PRICE_CURRENCY_MISMATCH';
 elsif price_row.effective_to is not null and p_as_of>price_row.effective_to then price_issue:='EXPIRED_SELLING_PRICE';
 else
  net:=round(case when price_row.tax_setting='INCLUSIVE' then price_row.price/(1+price_row.tax_percent/100) else price_row.price end,12);
  customer_total:=round(case when price_row.tax_setting='EXCLUSIVE' then price_row.price*(1+price_row.tax_percent/100) else price_row.price end,12);
  tax:=customer_total-net;
  if net<=0 then raise exception 'The net selling amount exceeds supported precision.' using errcode='22023'; end if;
 end if;
 cost:=(recipe_estimate->>'target_cost')::numeric;
 if price_issue is null and cost is not null then margin:=net-cost; end if;
 return jsonb_build_object('cost_state',case when margin is null then 'MISSING' else 'ESTIMATED' end,
  'method','MENU_REFERENCE_MARGIN_V1','as_of',p_as_of,'currency_code',currency,'recipe_estimate',recipe_estimate,
  'price_issue',price_issue,'price',case when price_row.id is null then null else jsonb_build_object('id',price_row.id,'version',price_row.version,
   'amount',price_row.price::text,'tax_setting',price_row.tax_setting,'tax_percent',price_row.tax_percent::text,'effective_from',price_row.effective_from,'effective_to',price_row.effective_to) end,
  'net_revenue',net::text,'tax_amount',tax::text,'customer_total',customer_total::text,'estimated_food_cost',cost::text,
  'estimated_food_margin',margin::text,'food_cost_percent',case when margin is not null then round(cost/net*100,6)::text else null end,
  'food_margin_percent',case when margin is not null then round(margin/net*100,6)::text else null end);
end; $$;

create or replace function public.platform_workspace(p_search text default '',p_state text default 'ALL',p_page integer default 1,p_organisation_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare packet jsonb;
begin
 if not public.is_platform_admin() then raise exception 'Platform administrator access is required.' using errcode='42501'; end if;
 if p_search is null or length(p_search)>80 or p_state is null or p_state not in ('ALL','ONBOARDING','ACCESS_REVIEW') or p_page is null or p_page not between 1 and 100000 then raise exception 'Choose valid platform filters and page.' using errcode='22023'; end if;
 if p_organisation_id is not null and not exists(select 1 from public.organisations where id=p_organisation_id) then raise exception 'Business unavailable.' using errcode='22023'; end if;
 with businesses as materialized(
  select private.pp_setup_progress(o.id) setup,o.id,o.name,o.created_at,o.currency_code,o.time_zone,u.email owner_email,
   (select count(*) from public.locations l where l.organisation_id=o.id) outlets,
   (select count(*) from public.organisation_memberships m where m.organisation_id=o.id and m.status='active') active_members,
   exists(select 1 from public.organisation_memberships m join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id where m.organisation_id=o.id and m.status='active' and r.role_code='restaurant_admin' and r.location_id is null) has_admin,
   (select count(*) from public.team_invitations i where i.organisation_id=o.id and i.state='PENDING' and i.expires_at<now()) expired_invitations,
   (select max(a.created_at) from public.audit_events a where a.organisation_id=o.id) last_activity
  from public.organisations o left join auth.users u on u.id=o.owner_id
 ), filtered as(select * from businesses where p_state<>'ONBOARDING' and(p_state<>'ACCESS_REVIEW' or not has_admin or expired_invitations>0) and(trim(p_search)='' or position(lower(trim(p_search)) in lower(name||' '||coalesce(owner_email,'')))>0)),
 drafts as(select d.business_name,d.step,d.updated_at,u.email owner_email from public.restaurant_setup_drafts d left join auth.users u on u.id=d.user_id where d.completed_organisation_id is null and(trim(p_search)='' or position(lower(trim(p_search)) in lower(d.business_name||' '||coalesce(u.email,'')))>0))
 select jsonb_build_object('summary',jsonb_build_object('restaurants',(select count(*) from businesses),'outlets',(select coalesce(sum(outlets),0) from businesses),'active_memberships',(select coalesce(sum(active_members),0) from businesses),'onboarding',(select count(*) from public.restaurant_setup_drafts where completed_organisation_id is null),'access_review',(select count(*) from businesses where not has_admin or expired_invitations>0)),
  'total',case when p_state='ONBOARDING' then(select count(*) from drafts) else(select count(*) from filtered) end,
  'businesses',coalesce((select jsonb_agg(to_jsonb(b) order by b.created_at desc,b.id) from(select * from filtered order by created_at desc,id limit 10 offset(p_page-1)*10)b),'[]'::jsonb),
  'drafts',case when p_state='ONBOARDING' then coalesce((select jsonb_agg(to_jsonb(d) order by updated_at desc) from(select * from drafts order by updated_at desc,owner_email limit 10 offset(p_page-1)*10)d),'[]'::jsonb) else '[]'::jsonb end,
  'selected',case when p_organisation_id is not null then(select to_jsonb(b)||jsonb_build_object('roles',coalesce((select jsonb_agg(to_jsonb(r)) from(select mr.role_code,count(*) assignments from public.membership_roles mr join public.organisation_memberships m on m.organisation_id=mr.organisation_id and m.id=mr.membership_id where mr.organisation_id=b.id and m.status='active' group by mr.role_code order by mr.role_code)r),'[]'::jsonb)) from businesses b where b.id=p_organisation_id) end,
  'refreshed_at',statement_timestamp()) into packet;
 return packet;
end $$;

create or replace function public.executive_profitability_briefing(p_organisation_id uuid,p_from date,p_to date,p_location_id uuid)
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

 with risks as materialized(
 select v,(v->>'estimated_food_cost')::numeric cost,(v->>'net_revenue')::numeric revenue,(v->>'estimated_food_margin')::numeric margin,
 l.id location_id,l.name location_name,m.primary_category,private.pp_cost_target(p_organisation_id,l.id,m.primary_category) target
 from public.locations l cross join lateral jsonb_array_elements(public.sales_period_summary(p_organisation_id,p_from,p_to,l.id)->'menus')v
 join public.menu_items m on m.organisation_id=p_organisation_id and m.id=(v->>'menu_item_id')::uuid
 where l.organisation_id=p_organisation_id and(l.id=p_location_id or p_location_id is null)
 ), flagged as(select * from risks where margin<0 or(target is not null and cost/nullif(revenue,0)*100>target))
 select jsonb_build_object('total',(select count(*) from flagged),'target_missing',(select count(*) from risks where target is null),'rows',coalesce((select jsonb_agg(v||jsonb_build_object(
 'food_cost_percent',round(cost/nullif(revenue,0)*100,6)::text,'margin_percent',round(margin/nullif(revenue,0)*100,6)::text,'locations',location_name,'location_id',location_id,'primary_category',primary_category,'target',target::text)
 order by margin,revenue desc) from(select * from flagged order by margin,revenue desc limit 5)f),'[]'::jsonb)) into menus;
 return jsonb_build_object('from',p_from,'to',p_to,'prior_from',prior_from,'prior_to',prior_to,'currency',currency,
  'summary',overview->'summary','comparison',overview->'comparison','previous',previous,
  'food_cost_percent',round((overview->'summary'->>'estimated_food_cost')::numeric/nullif((overview->'summary'->>'net_revenue')::numeric,0)*100,6)::text,
  'food_cost_change_pp',round(((overview->'summary'->>'estimated_food_cost')::numeric/nullif((overview->'summary'->>'net_revenue')::numeric,0)
   -(previous->>'estimated_food_cost')::numeric/nullif((previous->>'net_revenue')::numeric,0))*100,6)::text,
  'food_margin_change_pp',((overview->'summary'->>'food_margin_percent')::numeric-(previous->>'food_margin_percent')::numeric)::text,
  'outlets',overview->'outlets','prices',prices,'waste',waste,'movements',movements,'menus',menus,
  'recorded_days',(select count(*) from jsonb_array_elements(overview->'daily')d where(d->>'lines')::integer>0),'refreshed_at',statement_timestamp());
end; $$;

revoke all on function private.pp_setup_location(uuid,uuid),private.pp_cost_target(uuid,uuid,text),private.pp_opening_ready(uuid,uuid,uuid),private.pp_setup_progress(uuid),private.pp_setup_scope_guard() from public,anon,authenticated;
revoke all on function public.save_cost_targets(uuid,uuid,numeric,numeric),public.setup_profiles(uuid,text,uuid[]),public.confirm_zero_opening(uuid,uuid,uuid,date,text),public.save_setup_profile(uuid,text,uuid,uuid,text,text,boolean,text),public.save_material_setup(uuid,jsonb),public.save_menu_setup(uuid,uuid,jsonb),public.publish_recipe_setup(uuid,uuid,jsonb,jsonb),public.setup_workspace(uuid) from public,anon;
grant execute on function public.save_cost_targets(uuid,uuid,numeric,numeric),public.setup_profiles(uuid,text,uuid[]),public.confirm_zero_opening(uuid,uuid,uuid,date,text),public.save_setup_profile(uuid,text,uuid,uuid,text,text,boolean,text),public.save_material_setup(uuid,jsonb),public.save_menu_setup(uuid,uuid,jsonb),public.publish_recipe_setup(uuid,uuid,jsonb,jsonb),public.setup_workspace(uuid) to authenticated;
create function public.opening_readiness(p_organisation_id uuid,p_page integer default 1) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'Inventory setup access required.' using errcode='42501';end if;
 if p_page is null or p_page not between 1 and 100000 then raise exception 'Choose a valid page.' using errcode='22023';end if;
 with required as materialized(select i.id item_id,i.name material,i.base_uom_id,s.id site_id,s.name site,private.pp_opening_ready(i.organisation_id,i.id,s.id) ready from public.items i join public.stock_locations s on s.organisation_id=i.organisation_id and s.is_active and(i.location_id is null or s.outlet_id is null or s.outlet_id=i.location_id) where i.organisation_id=p_organisation_id and i.is_active and i.stock_tracked),paged as(select * from required order by ready,material,item_id,site,site_id limit 10 offset(p_page-1)*10)
 select jsonb_build_object('total',(select count(*) from required),'missing',(select count(*) from required where not ready),'rows',coalesce((select jsonb_agg(to_jsonb(p) order by ready,material,item_id,site,site_id) from paged p),'[]'::jsonb)) into result;return result;
end $$;
revoke all on function public.opening_readiness(uuid,integer) from public,anon;
grant execute on function public.opening_readiness(uuid,integer) to authenticated;
notify pgrst,'reload schema';
commit;
