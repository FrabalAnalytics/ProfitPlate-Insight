-- Apply ONCE after 008. Fixed recipe-backed menus, price events and live estimates.
begin;
-- Preserve legacy identities, recipes and prices without treating old prices as
-- dated, tax-declared price records. Canonical new rows leave selling_price NULL.
alter table public.menu_items alter column selling_price drop not null;
alter table public.menu_items drop constraint menu_items_organisation_id_name_key;
alter table public.menu_items add column code text, add column brand_id uuid,
 add constraint menu_brand_tenant_fk foreign key(organisation_id,brand_id) references public.brands(organisation_id,id);
update public.menu_items set code='MENU-'||upper(replace(id::text,'-',''));
alter table public.menu_items alter column code set not null;
alter table public.menu_items add constraint menu_code_format check(code ~ '^[A-Z0-9][A-Z0-9_-]{0,39}$'),
 add constraint menu_code_tenant_unique unique(organisation_id,code);

create function private.pp_menu_write(target_org uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisation_memberships m join public.membership_roles r
 on r.organisation_id=m.organisation_id and r.membership_id=m.id
 where m.organisation_id=target_org and m.user_id=(select auth.uid()) and m.status='active'
 and r.location_id is null and r.role_code='restaurant_admin');
$$;
revoke all on function private.pp_menu_write(uuid) from public,anon,authenticated;
create function public.menu_access(p_organisation_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('read',private.pp_reference_price_read(p_organisation_id),'write',private.pp_menu_write(p_organisation_id));
$$;

create table public.menu_item_versions (
 id uuid primary key default gen_random_uuid(), organisation_id uuid not null references public.organisations(id),
 menu_item_id uuid not null, version integer not null check(version>0), name text not null check(length(trim(name)) between 1 and 120),
 category text not null check(length(category)<=60), recipe_version_id uuid not null,
 recipe_quantity numeric(20,6) not null check(recipe_quantity>0), effective_from date not null,
 notes text not null check(length(notes)<=1000), request_id uuid not null, input_hash text not null,
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 unique(organisation_id,id), unique(organisation_id,menu_item_id,version), unique(organisation_id,request_id),
 foreign key(organisation_id,menu_item_id) references public.menu_items(organisation_id,id),
 foreign key(organisation_id,recipe_version_id) references public.recipe_versions(organisation_id,id)
);
create table public.menu_price_versions (
 id uuid primary key default gen_random_uuid(), organisation_id uuid not null references public.organisations(id),
 menu_item_id uuid not null, location_id uuid not null, channel_code text not null check(channel_code in ('DINE_IN','TAKEAWAY','DELIVERY')),
 version integer not null check(version>0), currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 price numeric(20,6) not null check(price>0), tax_setting text not null check(tax_setting in ('NONE','EXCLUSIVE','INCLUSIVE')),
 tax_percent numeric(9,6) not null check(tax_percent>=0 and tax_percent<=100),
 effective_from date not null, effective_to date check(effective_to>=effective_from),
 notes text not null check(length(trim(notes)) between 1 and 300), request_id uuid not null, input_hash text not null,
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 check(tax_setting<>'NONE' or tax_percent=0),
 unique(organisation_id,id), unique(organisation_id,menu_item_id,version), unique(organisation_id,request_id),
 foreign key(organisation_id,menu_item_id) references public.menu_items(organisation_id,id),
 foreign key(organisation_id,location_id) references public.locations(organisation_id,id)
);
create index pp_menu_prices_scope on public.menu_price_versions(organisation_id,menu_item_id,location_id,channel_code,effective_from desc,version desc);
create index pp_menu_name_search on public.menu_items(organisation_id,name,id);
revoke insert,update,delete on public.menu_items,public.menu_categories from authenticated;
drop policy tenant_read on public.menu_items;
create policy menu_financial_read on public.menu_items for select to authenticated using(private.pp_reference_price_read(organisation_id));
do $$ declare t text; begin
 foreach t in array array['menu_item_versions','menu_price_versions'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('create policy menu_financial_read on public.%I for select to authenticated using(private.pp_reference_price_read(organisation_id))',t);
 end loop;
end; $$;

create function public.search_menu_recipes(p_organisation_id uuid,p_search text,p_page integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Menu access denied.' using errcode='42501'; end if;
 if p_search is null or length(p_search)>80 or p_page is null or p_page not between 0 and 100000 then raise exception 'Invalid recipe search.' using errcode='22023'; end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into result from (
  select v.id,v.name||' · v'||v.version as label,r.code,o.uom_id,u.code as uom_code,u.dimension,v.effective_from
  from public.recipe_versions v join public.recipes r on r.organisation_id=v.organisation_id and r.id=v.recipe_id
  join public.recipe_outputs o on o.organisation_id=v.organisation_id and o.recipe_version_id=v.id
  join public.units_of_measure u on u.organisation_id=o.organisation_id and u.id=o.uom_id
  where v.organisation_id=p_organisation_id and r.recipe_type='FINAL'
  and (strpos(lower(v.name),lower(p_search))>0 or strpos(lower(r.code),lower(p_search))>0)
  order by v.name,v.version desc,v.id limit 26 offset p_page*25
 ) x;
 return result;
end; $$;

create function public.publish_menu_item_version(p_organisation_id uuid,p_menu_id uuid,p_request_id uuid,p_code text,p_name text,
 p_brand_id uuid,p_category text,p_recipe_version_id uuid,p_recipe_quantity numeric,p_effective_from date,p_notes text)
returns uuid language plpgsql security definer set search_path='' as $$
declare root public.menu_items%rowtype; source public.recipe_versions%rowtype; previous public.menu_item_versions%rowtype;
 item_id uuid; version_id uuid; next_version integer; digest text;
begin
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Menu editing requires an organisation-wide restaurant administrator.' using errcode='42501'; end if;
 if p_request_id is null or p_code is null or p_code !~ '^[A-Z0-9][A-Z0-9_-]{0,39}$'
  or p_name is null or length(trim(p_name)) not between 1 and 120 or p_category is null or length(p_category)>60
  or p_notes is null or length(p_notes)>1000 or p_recipe_quantity is null or p_recipe_quantity<=0 or p_recipe_quantity>=1e14
  or p_recipe_quantity<>round(p_recipe_quantity,6) or p_effective_from is null then raise exception 'Check the menu code, name, recipe quantity and effective date.' using errcode='22023'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 digest:=md5(jsonb_build_array(p_menu_id,p_code,p_name,p_brand_id,p_category,p_recipe_version_id,p_recipe_quantity,p_effective_from,p_notes)::text);
 select * into previous from public.menu_item_versions where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then
  if previous.input_hash<>digest then raise exception 'This save request was already used. Refresh before publishing different details.' using errcode='22023'; end if;
  return previous.id;
 end if;
 perform 1 from public.brands where organisation_id=p_organisation_id and id=p_brand_id;
 if not found then raise exception 'Brand is unavailable in this business.' using errcode='42501'; end if;
 select v.* into source from public.recipe_versions v join public.recipes r on r.organisation_id=v.organisation_id and r.id=v.recipe_id
  where v.organisation_id=p_organisation_id and v.id=p_recipe_version_id and r.recipe_type='FINAL';
 if not found then raise exception 'Choose a saved final recipe version in this business.' using errcode='22023'; end if;
 if p_effective_from<source.effective_from then raise exception 'A menu version cannot start before its recipe version.' using errcode='22023'; end if;
 if p_menu_id is null then
  insert into public.menu_items(organisation_id,code,name,brand_id,is_active) values(p_organisation_id,p_code,trim(p_name),p_brand_id,true) returning id into item_id;
 else
  select * into root from public.menu_items where organisation_id=p_organisation_id and id=p_menu_id for update;
  if not found then raise exception 'Menu item is unavailable.' using errcode='42501'; end if;
  if not root.is_active then raise exception 'Reactivate the menu item before publishing another version.' using errcode='22023'; end if;
  if root.code<>p_code or (root.brand_id is not null and root.brand_id<>p_brand_id) then raise exception 'The menu code and assigned brand stay fixed.' using errcode='22023'; end if;
  item_id:=root.id;
  update public.menu_items set name=trim(p_name),brand_id=p_brand_id where id=item_id;
 end if;
 select coalesce(max(version),0)+1 into next_version from public.menu_item_versions where organisation_id=p_organisation_id and menu_item_id=item_id;
 insert into public.menu_item_versions(organisation_id,menu_item_id,version,name,category,recipe_version_id,recipe_quantity,effective_from,notes,request_id,input_hash,created_by)
 values(p_organisation_id,item_id,next_version,trim(p_name),trim(p_category),p_recipe_version_id,p_recipe_quantity,p_effective_from,p_notes,p_request_id,digest,auth.uid()) returning id into version_id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'menu.version_published',auth.uid(),version_id,jsonb_build_object('menu_item_id',item_id,'version',next_version));
 return version_id;
end; $$;

create function public.set_menu_item_active(p_organisation_id uuid,p_menu_id uuid,p_active boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Menu access denied.' using errcode='42501'; end if;
 if p_active is null then raise exception 'Choose a valid status.' using errcode='22023'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 update public.menu_items set is_active=p_active where organisation_id=p_organisation_id and id=p_menu_id;
 if not found then raise exception 'Menu item unavailable.' using errcode='42501'; end if;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'menu.status_changed',auth.uid(),p_menu_id,jsonb_build_object('active',p_active));
end; $$;

create function public.save_menu_selling_price(p_organisation_id uuid,p_menu_id uuid,p_request_id uuid,p_location_id uuid,p_channel text,
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
 if not exists(select 1 from public.menu_item_versions where organisation_id=p_organisation_id and menu_item_id=p_menu_id) then raise exception 'Publish a recipe-linked menu version before adding prices.' using errcode='22023'; end if;
 perform 1 from public.locations where organisation_id=p_organisation_id and id=p_location_id and is_active and brand_id=root.brand_id;
 if not found then raise exception 'Choose an active location belonging to this menu brand.' using errcode='22023'; end if;
 select coalesce(max(version),0)+1 into next_version from public.menu_price_versions where organisation_id=p_organisation_id and menu_item_id=p_menu_id;
 insert into public.menu_price_versions(organisation_id,menu_item_id,location_id,channel_code,version,currency_code,price,tax_setting,tax_percent,effective_from,effective_to,notes,request_id,input_hash,created_by)
 values(p_organisation_id,p_menu_id,p_location_id,p_channel,next_version,currency,p_price,p_tax_setting,p_tax_percent,p_effective_from,p_effective_to,trim(p_notes),p_request_id,digest,auth.uid()) returning id into result_id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'menu.price_saved',auth.uid(),result_id,jsonb_build_object('menu_item_id',p_menu_id,'version',next_version,'location_id',p_location_id,'channel',p_channel));
 return result_id;
end; $$;

create function public.get_menu_item(p_organisation_id uuid,p_menu_id uuid,p_version_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare root public.menu_items%rowtype; selected public.menu_item_versions%rowtype; result jsonb;
begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Menu access denied.' using errcode='42501'; end if;
 select * into root from public.menu_items where organisation_id=p_organisation_id and id=p_menu_id;
 if not found then raise exception 'Menu item unavailable.' using errcode='42501'; end if;
 select * into selected from public.menu_item_versions where organisation_id=p_organisation_id and menu_item_id=p_menu_id
  and (p_version_id is null or id=p_version_id) order by version desc limit 1;
 if not found and p_version_id is not null then raise exception 'Menu version unavailable.' using errcode='42501'; end if;
 select jsonb_build_object('item',jsonb_build_object('id',root.id,'code',root.code,'name',root.name,'brand_id',root.brand_id,'is_active',root.is_active),
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

create function public.menu_food_margin_estimate(p_organisation_id uuid,p_version_id uuid,p_location_id uuid,p_channel text,p_as_of date)
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
 perform 1 from public.locations where organisation_id=p_organisation_id and id=p_location_id and is_active and brand_id=root.brand_id;
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

revoke all on function public.menu_access(uuid) from public,anon;
revoke all on function public.search_menu_recipes(uuid,text,integer) from public,anon;
revoke all on function public.publish_menu_item_version(uuid,uuid,uuid,text,text,uuid,text,uuid,numeric,date,text) from public,anon;
revoke all on function public.set_menu_item_active(uuid,uuid,boolean) from public,anon;
revoke all on function public.save_menu_selling_price(uuid,uuid,uuid,uuid,text,numeric,text,numeric,date,date,text) from public,anon;
revoke all on function public.get_menu_item(uuid,uuid,uuid) from public,anon;
revoke all on function public.menu_food_margin_estimate(uuid,uuid,uuid,text,date) from public,anon;
grant execute on function public.menu_access(uuid) to authenticated;
grant execute on function public.search_menu_recipes(uuid,text,integer) to authenticated;
grant execute on function public.publish_menu_item_version(uuid,uuid,uuid,text,text,uuid,text,uuid,numeric,date,text) to authenticated;
grant execute on function public.set_menu_item_active(uuid,uuid,boolean) to authenticated;
grant execute on function public.save_menu_selling_price(uuid,uuid,uuid,uuid,text,numeric,text,numeric,date,date,text) to authenticated;
grant execute on function public.get_menu_item(uuid,uuid,uuid) to authenticated;
grant execute on function public.menu_food_margin_estimate(uuid,uuid,uuid,text,date) to authenticated;
notify pgrst,'reload schema';
commit;
