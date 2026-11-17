-- Apply ONCE after migrations 001 and 002. Preserves auth, founder and legacy IDs.
begin;

alter table public.organisations
  add column country_code text not null default 'NG' check (country_code ~ '^[A-Z]{2}$'),
  add column concept text check (concept in ('QSR','CASUAL_DINING','FINE_DINING','BAKERY','CAFE','BAR','CLOUD_KITCHEN','BUFFET','CATERING','OTHER')),
  add column setup_completed_at timestamptz;

create table public.brands (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  code text not null check (length(code) between 1 and 40),
  name text not null check (length(trim(name)) between 1 and 120),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organisation_id, id), unique (organisation_id, code)
);

create table public.locations (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  brand_id uuid not null,
  legacy_branch_id uuid,
  code text not null check (length(code) between 1 and 40),
  name text not null check (length(trim(name)) between 1 and 120),
  location_type text not null default 'OUTLET' check (location_type = 'OUTLET'),
  timezone text not null,
  address text check (length(address) <= 500),
  is_active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organisation_id, id), unique (organisation_id, code),
  unique (organisation_id, legacy_branch_id),
  foreign key (organisation_id, brand_id) references public.brands(organisation_id, id),
  foreign key (organisation_id, legacy_branch_id) references public.branches(organisation_id, id)
);

-- Shared role dictionary, read-only to clients. Membership assignments are tenant-owned.
create table public.roles (
  code text primary key,
  name text not null
);
insert into public.roles values
  ('ceo','CEO / Managing Director'), ('finance','Finance / Auditor'),
  ('procurement','Inventory / Procurement Manager'), ('operations','Operations Manager'),
  ('restaurant_admin','Restaurant Administrator');

create table public.organisation_memberships (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  user_id uuid not null references auth.users(id),
  status text not null default 'active' check (status in ('active','inactive')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organisation_id, id), unique (organisation_id, user_id)
);
create index pp_memberships_user_idx on public.organisation_memberships(user_id, status);

create table public.membership_roles (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  membership_id uuid not null,
  role_code text not null references public.roles(code),
  location_id uuid,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organisation_id, membership_id) references public.organisation_memberships(organisation_id, id),
  foreign key (organisation_id, location_id) references public.locations(organisation_id, id),
  unique nulls not distinct (organisation_id, membership_id, role_code, location_id)
);

-- Personal setup drafts are user-owned, not restaurant records. No tenant exists yet.
-- Only these explicitly personal rows omit organisation_id.
create table public.restaurant_setup_drafts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id),
  business_name text not null default '' check (length(business_name) <= 120),
  concept text not null default '',
  country_code text not null default 'NG',
  currency_code text not null default 'NGN',
  brand_name text not null default '' check (length(brand_name) <= 120),
  location_name text not null default '' check (length(location_name) <= 120),
  timezone text not null default 'Africa/Lagos',
  address text not null default '' check (length(address) <= 500),
  step integer not null default 1 check (step between 1 and 3),
  completed_organisation_id uuid references public.organisations(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  event_type text not null,
  actor_id uuid references auth.users(id),
  entity_id uuid not null,
  details jsonb not null default '{}',
  created_at timestamptz not null default now()
);

-- Compatibility backfill: existing branches keep their IDs and original references.
insert into public.brands (organisation_id, code, name, created_by)
select id, 'PRIMARY', name, owner_id from public.organisations;
insert into public.locations (id, organisation_id, brand_id, legacy_branch_id, code, name, timezone, address, is_active, created_by)
select b.id, b.organisation_id, br.id, b.id, 'LOC-' || upper(replace(b.id::text,'-','')),
  b.name, o.time_zone, b.address, b.is_active, o.owner_id
from public.branches b join public.organisations o on o.id = b.organisation_id
join public.brands br on br.organisation_id = b.organisation_id and br.code = 'PRIMARY';

insert into public.organisation_memberships (organisation_id, user_id, created_by)
select id, owner_id, owner_id from public.organisations;
insert into public.organisation_memberships (organisation_id, user_id, created_by)
select m.organisation_id, m.user_id, o.owner_id from public.organisation_members m
join public.organisations o on o.id = m.organisation_id on conflict do nothing;
insert into public.membership_roles (organisation_id, membership_id, role_code, created_by)
select m.organisation_id, m.id, r.code, o.owner_id
from public.organisation_memberships m join public.organisations o on o.id = m.organisation_id
cross join public.roles r where m.user_id = o.owner_id and r.code in ('ceo','restaurant_admin');
insert into public.membership_roles (organisation_id, membership_id, role_code, created_by)
select m.organisation_id, m.id, case when old.role = 'manager' then 'restaurant_admin' else 'finance' end, o.owner_id
from public.organisation_members old join public.organisation_memberships m
on m.organisation_id = old.organisation_id and m.user_id = old.user_id
join public.organisations o on o.id = m.organisation_id
where old.user_id <> o.owner_id on conflict do nothing;

create function private.pp_active_member(target_org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.organisation_memberships m
    where m.organisation_id = target_org and m.user_id = (select auth.uid()) and m.status = 'active');
$$;

create or replace function private.pp_is_owner(target_organisation uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.organisations o
    join public.organisation_memberships m on m.organisation_id = o.id and m.user_id = o.owner_id
    where o.id = target_organisation and o.owner_id = (select auth.uid()) and m.status = 'active');
$$;

-- Conservative bridge for legacy organisation-wide operational tables: scoped
-- staff cannot use an organisation-level grant to see other locations' records.
create or replace function private.pp_has_access(target_organisation uuid, needs_write boolean)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.organisation_memberships m
    join public.membership_roles r on r.organisation_id = m.organisation_id and r.membership_id = m.id
    where m.organisation_id = target_organisation and m.user_id = (select auth.uid())
      and m.status = 'active' and r.location_id is null
      and (not needs_write or r.role_code = 'restaurant_admin'));
$$;

create function private.pp_location_access(target_org uuid, target_location uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.organisation_memberships m
    join public.membership_roles r on r.organisation_id = m.organisation_id and r.membership_id = m.id
    where m.organisation_id = target_org and m.user_id = (select auth.uid()) and m.status = 'active'
      and (r.location_id is null or r.location_id = target_location));
$$;

create function private.pp_brand_access(target_org uuid, target_brand uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.organisation_memberships m
    join public.membership_roles r on r.organisation_id = m.organisation_id and r.membership_id = m.id
    where m.organisation_id = target_org and m.user_id = (select auth.uid()) and m.status = 'active'
      and (r.location_id is null or exists (select 1 from public.locations l
        where l.organisation_id = target_org and l.id = r.location_id and l.brand_id = target_brand)));
$$;

revoke all on function private.pp_active_member(uuid) from public;
revoke all on function private.pp_location_access(uuid,uuid) from public;
revoke all on function private.pp_brand_access(uuid,uuid) from public;
grant execute on function private.pp_active_member(uuid) to authenticated;
grant execute on function private.pp_location_access(uuid,uuid) to authenticated;
grant execute on function private.pp_brand_access(uuid,uuid) to authenticated;

drop policy organisations_read on public.organisations;
create policy organisations_read on public.organisations for select to authenticated
  using (private.pp_active_member(id));
-- All new organisation creation is atomic through complete_restaurant_setup().
revoke insert on public.organisations from authenticated;
revoke insert, update, delete on public.organisation_members from authenticated;

do $$ declare t text; begin
  foreach t in array array['brands','locations','roles','organisation_memberships','membership_roles','restaurant_setup_drafts','audit_events'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end; $$;
create policy roles_read on public.roles for select to authenticated using (true);
create policy brands_read on public.brands for select to authenticated using (private.pp_brand_access(organisation_id,id));
create policy locations_read on public.locations for select to authenticated using (private.pp_location_access(organisation_id,id));
create policy memberships_read on public.organisation_memberships for select to authenticated
  using ((user_id = (select auth.uid()) and status = 'active') or private.pp_is_owner(organisation_id));
create policy membership_roles_read on public.membership_roles for select to authenticated
  using (private.pp_is_owner(organisation_id) or exists (select 1 from public.organisation_memberships m
    where m.organisation_id = membership_roles.organisation_id and m.id = membership_roles.membership_id
      and m.user_id = (select auth.uid()) and m.status = 'active'));
create policy drafts_read on public.restaurant_setup_drafts for select to authenticated using (user_id = (select auth.uid()));
create policy audit_read on public.audit_events for select to authenticated using (private.pp_is_owner(organisation_id));

create function public.save_restaurant_setup(
  p_business_name text, p_concept text, p_country_code text, p_currency_code text,
  p_brand_name text, p_location_name text, p_timezone text, p_address text, p_step integer
) returns uuid language plpgsql security definer set search_path = '' as $$
declare draft_id uuid; caller uuid := auth.uid();
begin
  if caller is null or not exists (select 1 from auth.users where id = caller and email_confirmed_at is not null)
    then raise exception 'Verify your email before setting up a restaurant.' using errcode = '42501'; end if;
  if public.is_platform_admin() then raise exception 'Use a restaurant owner account for restaurant setup.' using errcode = '42501'; end if;
  if p_step is null or p_step not between 1 and 3
    or p_country_code !~ '^[A-Z]{2}$' or p_currency_code !~ '^[A-Z]{3}$'
    or p_concept not in ('','QSR','CASUAL_DINING','FINE_DINING','BAKERY','CAFE','BAR','CLOUD_KITCHEN','BUFFET','CATERING','OTHER')
    or not exists (select 1 from pg_catalog.pg_timezone_names where name = p_timezone)
    then raise exception 'Invalid setup details.' using errcode = '22023'; end if;
  insert into public.restaurant_setup_drafts (user_id,business_name,concept,country_code,currency_code,brand_name,location_name,timezone,address,step)
  values (caller,trim(p_business_name),p_concept,p_country_code,p_currency_code,trim(p_brand_name),trim(p_location_name),p_timezone,trim(p_address),p_step)
  on conflict (user_id) do update set business_name=excluded.business_name,concept=excluded.concept,
    country_code=excluded.country_code,currency_code=excluded.currency_code,brand_name=excluded.brand_name,
    location_name=excluded.location_name,timezone=excluded.timezone,address=excluded.address,step=excluded.step,updated_at=now()
  where restaurant_setup_drafts.completed_organisation_id is null
  returning id into draft_id;
  if draft_id is null then
    select id into draft_id from public.restaurant_setup_drafts where user_id = caller;
  end if;
  return draft_id;
end; $$;

create function public.complete_restaurant_setup()
returns uuid language plpgsql security definer set search_path = '' as $$
declare d public.restaurant_setup_drafts%rowtype; org_id uuid; brand_id uuid; loc_id uuid; member_id uuid; caller uuid := auth.uid();
begin
  if caller is null or not exists (select 1 from auth.users where id = caller and email_confirmed_at is not null)
    then raise exception 'Verify your email before setting up a restaurant.' using errcode = '42501'; end if;
  if public.is_platform_admin() then raise exception 'Use a restaurant owner account for restaurant setup.' using errcode = '42501'; end if;
  select * into d from public.restaurant_setup_drafts where user_id = caller for update;
  if not found then raise exception 'Save your restaurant details first.' using errcode = '22023'; end if;
  if d.completed_organisation_id is not null then return d.completed_organisation_id; end if;
  if length(trim(d.business_name)) = 0 or length(trim(d.brand_name)) = 0 or length(trim(d.location_name)) = 0 or d.concept = ''
    then raise exception 'Complete the business and location details first.' using errcode = '22023'; end if;
  insert into public.organisations (name,owner_id,currency_code,time_zone,country_code,concept,setup_completed_at)
    values (d.business_name,caller,d.currency_code,d.timezone,d.country_code,d.concept,now()) returning id into org_id;
  insert into public.brands (organisation_id,code,name,created_by)
    values (org_id,'PRIMARY',d.brand_name,caller) returning id into brand_id;
  insert into public.branches (organisation_id,name,address) values (org_id,d.location_name,d.address) returning id into loc_id;
  insert into public.locations (id,organisation_id,brand_id,legacy_branch_id,code,name,timezone,address,created_by)
    values (loc_id,org_id,brand_id,loc_id,'PRIMARY',d.location_name,d.timezone,d.address,caller);
  insert into public.organisation_memberships (organisation_id,user_id,created_by)
    values (org_id,caller,caller) returning id into member_id;
  insert into public.membership_roles (organisation_id,membership_id,role_code,created_by)
    values (org_id,member_id,'ceo',caller),(org_id,member_id,'restaurant_admin',caller);
  insert into public.audit_events (organisation_id,event_type,actor_id,entity_id,details)
    values (org_id,'restaurant.onboarded',caller,org_id,jsonb_build_object('brand_id',brand_id,'location_id',loc_id,'draft_id',d.id));
  update public.restaurant_setup_drafts set completed_organisation_id=org_id,updated_at=now() where id=d.id;
  return org_id;
end; $$;

revoke all on function public.save_restaurant_setup(text,text,text,text,text,text,text,text,integer) from public, anon;
revoke all on function public.complete_restaurant_setup() from public, anon;
grant execute on function public.save_restaurant_setup(text,text,text,text,text,text,text,text,integer) to authenticated;
grant execute on function public.complete_restaurant_setup() to authenticated;
notify pgrst, 'reload schema';
commit;
