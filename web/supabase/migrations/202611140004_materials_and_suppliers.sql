-- Apply ONCE after 003. Adds tenant-owned catalogue masters, not financial costs.
begin;

create table public.units_of_measure (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  code text not null,
  name text not null,
  dimension text not null check (dimension in ('MASS','VOLUME','COUNT','PACKAGE')),
  canonical_factor numeric(20,6) check (canonical_factor > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((dimension = 'PACKAGE' and canonical_factor is null) or (dimension <> 'PACKAGE' and canonical_factor is not null)),
  unique (organisation_id,id), unique (organisation_id,code)
);

create function private.pp_seed_catalogue_units(target_org uuid)
returns void language sql security definer set search_path = '' as $$
  insert into public.units_of_measure(organisation_id,code,name,dimension,canonical_factor)
  select target_org,v.code,v.name,v.dimension,v.factor from (values
    ('KG','Kilogram','MASS',1::numeric),('G','Gram','MASS',0.001::numeric),
    ('L','Litre','VOLUME',1::numeric),('ML','Millilitre','VOLUME',0.001::numeric),
    ('PCS','Piece','COUNT',1::numeric),('BAG','Bag','PACKAGE',null::numeric),
    ('CARTON','Carton','PACKAGE',null::numeric),('PACK','Pack','PACKAGE',null::numeric),
    ('BOTTLE','Bottle','PACKAGE',null::numeric)
  ) v(code,name,dimension,factor) on conflict do nothing;
$$;
revoke all on function private.pp_seed_catalogue_units(uuid) from public,anon,authenticated;
do $$ declare o record; begin
  for o in select id from public.organisations loop perform private.pp_seed_catalogue_units(o.id); end loop;
end; $$;
create function private.pp_new_organisation_units()
returns trigger language plpgsql security definer set search_path = '' as $$
begin perform private.pp_seed_catalogue_units(new.id); return new; end; $$;
revoke all on function private.pp_new_organisation_units() from public,anon,authenticated;
create trigger seed_organisation_units after insert on public.organisations
for each row execute function private.pp_new_organisation_units();

create table public.item_categories (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  name text not null check (length(trim(name)) between 1 and 60),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organisation_id,id)
);
create unique index pp_category_name_idx on public.item_categories(organisation_id,lower(name));

create table public.items (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9_-]{0,39}$'),
  name text not null check (length(trim(name)) between 1 and 120),
  item_type text not null check (item_type in ('RAW','PACKAGING','RESALE','CONSUMABLE','SEMI_FINISHED','FINISHED')),
  category_id uuid,
  base_uom_id uuid not null,
  legacy_ingredient_id uuid,
  stock_tracked boolean not null default true,
  is_active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organisation_id,id), unique (organisation_id,code),
  unique (organisation_id,legacy_ingredient_id),
  foreign key (organisation_id,category_id) references public.item_categories(organisation_id,id),
  foreign key (organisation_id,base_uom_id) references public.units_of_measure(organisation_id,id),
  foreign key (organisation_id,legacy_ingredient_id) references public.ingredients(organisation_id,id)
);
-- Preserve old ingredient identity and quantities. Do not infer costs from the
-- legacy current_unit_cost zero default. Cost readiness is computed later.
insert into public.items(id,organisation_id,code,name,item_type,base_uom_id,legacy_ingredient_id,is_active)
select i.id,i.organisation_id,'IT-'||upper(replace(i.id::text,'-','')),i.name,'RAW',u.id,i.id,i.is_active
from public.ingredients i join public.units_of_measure u on u.organisation_id=i.organisation_id
and u.code=case i.base_unit when 'g' then 'G' when 'ml' then 'ML' else 'PCS' end;

alter table public.suppliers
  add column code text not null default ('SUP-'||upper(replace(gen_random_uuid()::text,'-','')))
    check (code ~ '^[A-Z0-9][A-Z0-9_-]{0,39}$'),
  add column created_by uuid references auth.users(id),
  add column updated_at timestamptz not null default now(),
  add constraint suppliers_org_code_unique unique (organisation_id,code);

create table public.item_uom_conversions (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  item_id uuid not null,
  from_uom_id uuid not null,
  to_uom_id uuid not null,
  factor numeric(20,6) not null check (factor > 0),
  effective_from date not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (organisation_id,id), unique (organisation_id,item_id,from_uom_id,effective_from),
  foreign key (organisation_id,item_id) references public.items(organisation_id,id),
  foreign key (organisation_id,from_uom_id) references public.units_of_measure(organisation_id,id),
  foreign key (organisation_id,to_uom_id) references public.units_of_measure(organisation_id,id)
);
create index pp_items_name_idx on public.items(organisation_id,name);
create index pp_suppliers_name_idx on public.suppliers(organisation_id,name);

create function private.pp_catalogue_read(target_org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.organisation_memberships m
    join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id
    where m.organisation_id=target_org and m.user_id=(select auth.uid()) and m.status='active'
      and r.role_code in ('ceo','finance','procurement','operations','restaurant_admin'));
$$;
revoke all on function private.pp_catalogue_read(uuid) from public,anon;
grant execute on function private.pp_catalogue_read(uuid) to authenticated;

create function private.pp_catalogue_write(target_org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.organisation_memberships m
    join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id
    where m.organisation_id=target_org and m.user_id=(select auth.uid()) and m.status='active'
      and r.location_id is null and r.role_code in ('restaurant_admin','procurement'));
$$;
revoke all on function private.pp_catalogue_write(uuid) from public,anon;
grant execute on function private.pp_catalogue_write(uuid) to authenticated;
create function public.can_manage_catalogue(p_organisation_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.pp_catalogue_write(p_organisation_id);
$$;
revoke all on function public.can_manage_catalogue(uuid) from public,anon;
grant execute on function public.can_manage_catalogue(uuid) to authenticated;

do $$ declare t text; begin
  foreach t in array array['units_of_measure','item_categories','items','item_uom_conversions'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from public,anon,authenticated',t);
    execute format('grant select on public.%I to authenticated',t);
    execute format('create policy catalogue_read on public.%I for select to authenticated using(private.pp_catalogue_read(organisation_id))',t);
  end loop;
end; $$;
-- Supplier changes now go through the audited catalogue operation.
revoke insert,update,delete on public.suppliers from authenticated;
drop policy tenant_read on public.suppliers;
create policy catalogue_read on public.suppliers for select to authenticated using(private.pp_catalogue_read(organisation_id));

create function public.save_catalogue_material(
  p_organisation_id uuid,p_id uuid,p_code text,p_name text,p_item_type text,
  p_category text,p_base_uom_id uuid,p_stock_tracked boolean,p_is_active boolean
) returns uuid language plpgsql security definer set search_path = '' as $$
declare result_id uuid; v_category_id uuid; previous public.items%rowtype; u public.units_of_measure%rowtype;
begin
  if not private.pp_catalogue_write(p_organisation_id) then raise exception 'Catalogue access denied.' using errcode='42501'; end if;
  if p_code is null or p_code !~ '^[A-Z0-9][A-Z0-9_-]{0,39}$' or length(trim(p_name)) not between 1 and 120
    or length(p_category)>60 or p_item_type not in ('RAW','PACKAGING','RESALE','CONSUMABLE','SEMI_FINISHED','FINISHED')
    then raise exception 'Check your material details.' using errcode='22023'; end if;
  select * into u from public.units_of_measure where organisation_id=p_organisation_id and id=p_base_uom_id;
  if not found or u.dimension='PACKAGE' then raise exception 'Choose a measurable base unit.' using errcode='22023'; end if;
  if p_id is not null then
    select * into previous from public.items where organisation_id=p_organisation_id and id=p_id for update;
    if not found then raise exception 'Material not available.' using errcode='42501'; end if;
    if previous.code<>p_code or previous.base_uom_id<>p_base_uom_id
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
    update public.items set name=trim(p_name),item_type=p_item_type,category_id=v_category_id,
      stock_tracked=p_stock_tracked,is_active=p_is_active,updated_at=now()
      where organisation_id=p_organisation_id and id=p_id returning id into result_id;
  end if;
  insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details)
    values(p_organisation_id,case when p_id is null then 'material.created' else 'material.updated' end,auth.uid(),result_id,
      jsonb_build_object('code',p_code,'is_active',p_is_active,'previous',case when p_id is null then null else to_jsonb(previous) end));
  return result_id;
end; $$;

create function public.save_catalogue_supplier(
  p_organisation_id uuid,p_id uuid,p_code text,p_name text,p_email text,p_phone text,p_address text,p_is_active boolean
) returns uuid language plpgsql security definer set search_path = '' as $$
declare result_id uuid; previous public.suppliers%rowtype;
begin
  if not private.pp_catalogue_write(p_organisation_id) then raise exception 'Catalogue access denied.' using errcode='42501'; end if;
  if p_code is null or p_code !~ '^[A-Z0-9][A-Z0-9_-]{0,39}$' or length(trim(p_name)) not between 1 and 120
    or length(p_email)>254 or length(p_phone)>40 or length(p_address)>500
    or (coalesce(p_email,'')<>'' and p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$')
    then raise exception 'Check your supplier details.' using errcode='22023'; end if;
  if p_id is not null then
    select * into previous from public.suppliers where organisation_id=p_organisation_id and id=p_id for update;
    if not found then raise exception 'Supplier not available.' using errcode='42501'; end if;
    if previous.code<>p_code then raise exception 'Supplier code cannot be changed.' using errcode='22023'; end if;
  end if;
  if p_id is null then
    insert into public.suppliers(organisation_id,code,name,email,phone,address,is_active,created_by)
      values(p_organisation_id,p_code,trim(p_name),nullif(trim(p_email),''),nullif(trim(p_phone),''),nullif(trim(p_address),''),p_is_active,auth.uid()) returning id into result_id;
  else
    update public.suppliers set name=trim(p_name),email=nullif(trim(p_email),''),phone=nullif(trim(p_phone),''),
      address=nullif(trim(p_address),''),is_active=p_is_active,updated_at=now()
      where organisation_id=p_organisation_id and id=p_id returning id into result_id;
  end if;
  insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details)
    values(p_organisation_id,case when p_id is null then 'supplier.created' else 'supplier.updated' end,auth.uid(),result_id,
      jsonb_build_object('code',p_code,'is_active',p_is_active));
  return result_id;
end; $$;

create function public.save_material_conversion(
  p_organisation_id uuid,p_item_id uuid,p_from_uom_id uuid,p_factor numeric,p_effective_from date
) returns uuid language plpgsql security definer set search_path = '' as $$
declare material public.items%rowtype; source public.units_of_measure%rowtype; target public.units_of_measure%rowtype;
  previous public.item_uom_conversions%rowtype; result_id uuid;
begin
  if not private.pp_catalogue_write(p_organisation_id) then raise exception 'Catalogue access denied.' using errcode='42501'; end if;
  if p_factor is null or p_factor<=0 or p_factor>=100000000000000 or p_factor<>round(p_factor,6) or p_effective_from is null
    then raise exception 'Enter a positive factor with at most six decimal places and an effective date.' using errcode='22023'; end if;
  select * into material from public.items where organisation_id=p_organisation_id and id=p_item_id and is_active for update;
  if not found then raise exception 'Active material not available.' using errcode='42501'; end if;
  select * into source from public.units_of_measure where organisation_id=p_organisation_id and id=p_from_uom_id;
  if not found then raise exception 'Unit not available.' using errcode='42501'; end if;
  select * into target from public.units_of_measure where organisation_id=p_organisation_id and id=material.base_uom_id;
  if source.dimension<>'PACKAGE' and (source.dimension<>target.dimension or p_factor*target.canonical_factor<>source.canonical_factor)
    then raise exception 'The factor does not match the unit dimensions.' using errcode='22023'; end if;
  select * into previous from public.item_uom_conversions where organisation_id=p_organisation_id
    and item_id=p_item_id and from_uom_id=p_from_uom_id and effective_from=p_effective_from;
  if found then
    if previous.factor=p_factor then return previous.id; end if;
    raise exception 'A different conversion already exists for this date. Use a new effective date.' using errcode='23505';
  end if;
  insert into public.item_uom_conversions(organisation_id,item_id,from_uom_id,to_uom_id,factor,effective_from,created_by)
    values(p_organisation_id,p_item_id,p_from_uom_id,material.base_uom_id,p_factor,p_effective_from,auth.uid()) returning id into result_id;
  insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details)
    values(p_organisation_id,'conversion.created',auth.uid(),result_id,jsonb_build_object('item_id',p_item_id,'factor',p_factor::text,'effective_from',p_effective_from));
  return result_id;
end; $$;

revoke all on function public.save_catalogue_material(uuid,uuid,text,text,text,text,uuid,boolean,boolean) from public,anon;
revoke all on function public.save_catalogue_supplier(uuid,uuid,text,text,text,text,text,boolean) from public,anon;
revoke all on function public.save_material_conversion(uuid,uuid,uuid,numeric,date) from public,anon;
grant execute on function public.save_catalogue_material(uuid,uuid,text,text,text,text,uuid,boolean,boolean) to authenticated;
grant execute on function public.save_catalogue_supplier(uuid,uuid,text,text,text,text,text,boolean) to authenticated;
grant execute on function public.save_material_conversion(uuid,uuid,uuid,numeric,date) to authenticated;
notify pgrst,'reload schema';
commit;
