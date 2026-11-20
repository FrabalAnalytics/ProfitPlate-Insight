-- Restaurant-owned sales channels, preserved history and per-channel profitability comparisons.
begin;
create table public.restaurant_sales_channels (
 organisation_id uuid not null references public.organisations(id),code text not null check(code~'^[A-Z0-9][A-Z0-9_-]{0,39}$' and code<>'ALL'),
 name text not null check(length(trim(name)) between 1 and 80 and name!~'[[:cntrl:]]'),is_active boolean not null default true,
 primary key(organisation_id,code)
);
create unique index channel_active_name on public.restaurant_sales_channels(organisation_id,lower(name)) where is_active;
create table private.sales_channel_settings(organisation_id uuid primary key references public.organisations(id),revision integer not null default 0);
revoke all on private.sales_channel_settings from public,anon,authenticated;
alter table public.restaurant_sales_channels enable row level security;
revoke all on public.restaurant_sales_channels from public,anon,authenticated;
grant select on public.restaurant_sales_channels to authenticated;
create policy channel_member_read on public.restaurant_sales_channels for select to authenticated using(private.pp_active_member(organisation_id));
create trigger channel_active_restaurant before insert or update or delete on public.restaurant_sales_channels for each row execute function private.pp_require_active_restaurant();
-- Keep existing channels and legacy API clients usable. Current onboarding replaces these atomically with the owner's explicit choices.
create function private.pp_legacy_sales_channels() returns trigger language plpgsql security definer set search_path='' as $$begin
 insert into public.restaurant_sales_channels values(new.id,'DINE_IN','Dine in',true),(new.id,'TAKEAWAY','Takeaway',true),(new.id,'DELIVERY','Delivery',true);
 insert into private.sales_channel_settings values(new.id,0);return new;
end $$;
revoke all on function private.pp_legacy_sales_channels() from public,anon,authenticated;
-- Backfill before the write trigger is used on future organisations; existing inactive tenants retain their history too.
alter table public.restaurant_sales_channels disable trigger channel_active_restaurant;
insert into public.restaurant_sales_channels select o.id,v.code,v.name,true from public.organisations o cross join(values('DINE_IN','Dine in'),('TAKEAWAY','Takeaway'),('DELIVERY','Delivery')) v(code,name);
insert into private.sales_channel_settings select id,0 from public.organisations;
alter table public.restaurant_sales_channels enable trigger channel_active_restaurant;
create trigger legacy_sales_channels after insert on public.organisations for each row execute function private.pp_legacy_sales_channels();
alter table public.menu_price_versions drop constraint menu_price_versions_channel_code_check;
alter table public.sales_headers drop constraint sales_headers_channel_code_check;
alter table public.menu_price_versions add foreign key(organisation_id,channel_code) references public.restaurant_sales_channels(organisation_id,code);
alter table public.sales_headers add foreign key(organisation_id,channel_code) references public.restaurant_sales_channels(organisation_id,code);
create function private.pp_sales_channel_exists(org uuid,channel text,retired boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.restaurant_sales_channels where organisation_id=org and code=channel and(is_active or retired));
$$;
revoke all on function private.pp_sales_channel_exists(uuid,text,boolean) from public,anon,authenticated;
create function private.pp_check_sales_channels(rows jsonb,allow_empty boolean default false) returns void language plpgsql set search_path='' as $$
begin
 if rows is null or jsonb_typeof(rows)<>'array' or jsonb_array_length(rows)>30 or octet_length(rows::text)>16384 then raise exception 'Use up to 30 sales channels.' using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(rows) r where jsonb_typeof(r->'code') is distinct from 'string' or jsonb_typeof(r->'name') is distinct from 'string' or coalesce(r->>'code','')!~'^[A-Z0-9][A-Z0-9_-]{0,39}$' or r->>'code'='ALL' or length(trim(coalesce(r->>'name',''))) not between 1 and 80 or r->>'name'~'[[:cntrl:]]' or(r?'is_active' and jsonb_typeof(r->'is_active')<>'boolean')) then raise exception 'Enter a unique channel name and code (letters, numbers, underscores or hyphens). ALL is reserved.' using errcode='22023';end if;
 if (select count(*)<>count(distinct value->>'code') or count(*)<>count(distinct lower(trim(value->>'name'))) from jsonb_array_elements(rows)) then raise exception 'Channel names and codes must be unique.' using errcode='22023';end if;
 if not allow_empty and not exists(select 1 from jsonb_array_elements(rows) r where coalesce((r->>'is_active')::boolean,true)) then raise exception 'Choose at least one active sales channel.' using errcode='22023';end if;
end $$;
revoke all on function private.pp_check_sales_channels(jsonb,boolean) from public,anon,authenticated;
create function public.sales_channels(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.pp_active_member(p_organisation_id) then raise exception 'Restaurant access required.' using errcode='42501';end if;
 return jsonb_build_object('manage',private.pp_menu_write(p_organisation_id),'revision',(select revision from private.sales_channel_settings where organisation_id=p_organisation_id),
 'channels',coalesce((select jsonb_agg(jsonb_build_object('code',code,'name',name,'is_active',is_active) order by is_active desc,name,code) from public.restaurant_sales_channels where organisation_id=p_organisation_id),'[]'::jsonb));
end $$;
create function public.save_sales_channels(p_organisation_id uuid,p_revision integer,p_channels jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare version integer;r jsonb;
begin
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Restaurant administrator access required.' using errcode='42501';end if;
 perform private.pp_check_sales_channels(p_channels);
 perform 1 from public.organisations where id=p_organisation_id for update;
 select s.revision into version from private.sales_channel_settings s where s.organisation_id=p_organisation_id;
 if p_revision is distinct from version then raise exception 'Channels changed. Refresh before saving.' using errcode='22023';end if;
 update public.restaurant_sales_channels set is_active=false where organisation_id=p_organisation_id;
 for r in select value from jsonb_array_elements(p_channels) loop
  insert into public.restaurant_sales_channels values(p_organisation_id,r->>'code',trim(r->>'name'),coalesce((r->>'is_active')::boolean,true))
  on conflict(organisation_id,code) do update set name=excluded.name,is_active=excluded.is_active;
 end loop;
 update private.sales_channel_settings s set revision=version+1 where organisation_id=p_organisation_id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'SALES_CHANNELS_UPDATED',auth.uid(),p_organisation_id,jsonb_build_object('channels',p_channels,'revision',version+1));
 return public.sales_channels(p_organisation_id);
end $$;
alter table public.restaurant_setup_drafts add column sales_channels jsonb not null default '[]';
create function public.save_setup_sales_channels(p_channels jsonb) returns void language plpgsql security definer set search_path='' as $$begin
 if auth.uid() is null then raise exception 'Sign in first.' using errcode='42501';end if;
 perform private.pp_check_sales_channels(p_channels,true);
 update public.restaurant_setup_drafts set sales_channels=p_channels where user_id=auth.uid() and completed_organisation_id is null;
 if not found and not exists(select 1 from public.restaurant_setup_drafts where user_id=auth.uid() and completed_organisation_id is not null) then raise exception 'Save business details first.' using errcode='22023';end if;
end $$;
create function public.complete_restaurant_setup_with_channels() returns uuid language plpgsql security definer set search_path='' as $$
declare draft public.restaurant_setup_drafts;org uuid;
begin
 select * into draft from public.restaurant_setup_drafts where user_id=auth.uid() for update;
 if not found then raise exception 'Save setup first.' using errcode='22023';end if;
 if draft.completed_organisation_id is not null then return draft.completed_organisation_id;end if;
 perform private.pp_check_sales_channels(draft.sales_channels);
 org:=public.complete_restaurant_setup_with_calendar();
 delete from public.restaurant_sales_channels where organisation_id=org;
 perform public.save_sales_channels(org,0,draft.sales_channels);
 return org;
end $$;
revoke all on function public.sales_channels(uuid),public.save_sales_channels(uuid,integer,jsonb),public.save_setup_sales_channels(jsonb),public.complete_restaurant_setup_with_channels() from public,anon;
grant execute on function public.sales_channels(uuid),public.save_sales_channels(uuid,integer,jsonb),public.save_setup_sales_channels(jsonb),public.complete_restaurant_setup_with_channels() to authenticated;
-- Replace only the fixed channel guards in existing, otherwise unchanged financial validators.
do $$declare sig text;definition text;updated text;begin
 foreach sig in array array['public.save_menu_selling_price(uuid,uuid,uuid,uuid,text,numeric,text,numeric,date,date,text)','public.menu_food_margin_estimate(uuid,uuid,uuid,text,date)','public.menu_profitability(uuid,uuid,text,date,text,integer)'] loop
  definition:=pg_get_functiondef(sig::regprocedure);
  updated:=replace(definition,$find$p_channel not in ('DINE_IN','TAKEAWAY','DELIVERY')$find$,
   case when sig like 'public.save_menu_selling_price%' then 'not private.pp_sales_channel_exists(p_organisation_id,p_channel,false)' else 'not private.pp_sales_channel_exists(p_organisation_id,p_channel,true)' end);
  if updated=definition then raise exception 'Expected channel guard missing: %',sig;end if;execute updated;
 end loop;
 definition:=pg_get_functiondef('private.pp_validate_sales_csv(uuid,text,text,text,text,jsonb)'::regprocedure);
 updated:=replace(definition,$find$if channel not in ('DINE_IN','TAKEAWAY','DELIVERY') then raise exception 'Unknown sales channel. Map it to DINE_IN, TAKEAWAY or DELIVERY.' using errcode='22023'; end if;$find$,
 $replace$if not private.pp_sales_channel_exists(p_org,channel,false) and not(private.pp_sales_channel_exists(p_org,channel,true) and exists(select 1 from public.sales_headers h join public.locations x on x.organisation_id=h.organisation_id and x.id=h.location_id where h.organisation_id=p_org and h.channel_code=channel and h.source_system=r->>'Source_System' and h.transaction_ref=r->>'Transaction_Ref' and x.code=location_code)) then raise exception 'Unknown or retired sales channel. Configure it in Data & Setup or map to an active channel.' using errcode='22023';end if;$replace$);
 if updated=definition then raise exception 'Expected sales channel guard missing';end if;execute updated;
end $$;
create or replace function public.menu_profitability_dashboard(p_organisation_id uuid,p_location_id uuid,p_channel text,p_as_of date,p_search text,p_page integer,p_status text default 'ALL')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare outlet public.locations; currency text; business_day date; result jsonb; eligible_count integer;
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
 if p_status is null or p_status not in ('ALL','AT_RISK','WITHIN_TARGET','INCOMPLETE','TARGET_NOT_SET') then raise exception 'Choose a valid menu status.' using errcode='22023';end if;
 select count(*) into eligible_count from public.menu_items m left join lateral(select v.name from public.menu_item_versions v where v.organisation_id=m.organisation_id and v.menu_item_id=m.id and v.effective_from<=p_as_of order by v.effective_from desc,v.version desc limit 1)v on true
 where m.organisation_id=p_organisation_id and m.is_active and m.brand_id=outlet.brand_id and(m.location_id is null or m.location_id=p_location_id)
 and(trim(p_search)='' or position(lower(trim(p_search)) in lower(coalesce(v.name,m.name)||' '||m.code))>0);
 if eligible_count*(case when p_channel='ALL' then(select count(*) from public.restaurant_sales_channels where organisation_id=p_organisation_id and is_active) else 1 end)>5000 then
  raise exception 'Narrow the menu search or choose one channel to compare up to 5,000 menu/channel combinations.' using errcode='22023';end if;
 with eligible as materialized (
  select m.id,m.code,c.code channel_code,c.name channel_name,m.primary_category,private.pp_cost_target(p_organisation_id,p_location_id,m.primary_category) target,coalesce(v.name,m.name) as name,v.id as version_id,v.version,v.recipe_quantity,v.effective_from
  from public.menu_items m cross join public.restaurant_sales_channels c
  left join lateral (
   select id,name,version,recipe_quantity,effective_from from public.menu_item_versions
   where organisation_id=p_organisation_id and menu_item_id=m.id and effective_from<=p_as_of
   order by effective_from desc,version desc limit 1
  ) v on true
  where m.organisation_id=p_organisation_id and c.organisation_id=p_organisation_id and((p_channel='ALL' and c.is_active) or c.code=p_channel) and m.is_active and m.brand_id=outlet.brand_id and(m.location_id is null or m.location_id=p_location_id)
  and (trim(p_search)='' or position(lower(trim(p_search)) in lower(coalesce(v.name,m.name)||' '||m.code))>0)
 ), estimates as materialized (
  select e.*,case when version_id is null then null else public.menu_food_margin_estimate(p_organisation_id,version_id,p_location_id,e.channel_code,p_as_of) end estimate from eligible e
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
revoke all on function public.menu_profitability_dashboard(uuid,uuid,text,date,text,integer,text) from public,anon;
grant execute on function public.menu_profitability_dashboard(uuid,uuid,text,date,text,integer,text) to authenticated;

create or replace function public.menu_profitability_scope(p_organisation_id uuid,p_location_id uuid default null,p_channel text default null,p_as_of date default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare day date;site uuid;channel text;
begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Menu financial access denied.' using errcode='42501';end if;
 select coalesce(p_as_of,(now() at time zone time_zone)::date) into day from public.organisations where id=p_organisation_id;
 if day>(select(now() at time zone time_zone)::date from public.organisations where id=p_organisation_id) or(p_channel is not null and (p_channel<>'ALL' and not private.pp_sales_channel_exists(p_organisation_id,p_channel,true))) then raise exception 'Choose a valid date and channel.' using errcode='22023';end if;
 select l.id into site from public.locations l where l.organisation_id=p_organisation_id and l.is_active and(p_location_id is null or l.id=p_location_id)
 order by exists(select 1 from(select distinct on(p.menu_item_id,p.channel_code) p.* from public.menu_price_versions p join public.menu_items m on m.organisation_id=p.organisation_id and m.id=p.menu_item_id and m.is_active and m.brand_id=l.brand_id and(m.location_id is null or m.location_id=l.id) where p.organisation_id=p_organisation_id and p.location_id=l.id and p.effective_from<=day and(p_channel is null or p_channel='ALL' or p.channel_code=p_channel) order by p.menu_item_id,p.channel_code,p.effective_from desc,p.version desc) prices where prices.effective_to is null or prices.effective_to>=day) desc,l.name,l.id limit 1;
 if site is null then return jsonb_build_object('location_id',null,'channel',coalesce(p_channel,'ALL'));end if;
 with latest as (
  select distinct on(p.menu_item_id,p.channel_code) p.* from public.menu_price_versions p
  join public.menu_items m on m.organisation_id=p.organisation_id and m.id=p.menu_item_id and m.is_active
  where p.organisation_id=p_organisation_id and p.location_id=site and p.effective_from<=day order by p.menu_item_id,p.channel_code,p.effective_from desc,p.version desc
 ) select channel_code into channel from latest where effective_to is null or effective_to>=day group by channel_code
 order by count(*) desc,channel_code limit 1;
 return jsonb_build_object('location_id',site,'channel',coalesce(p_channel,channel,(select code from public.restaurant_sales_channels where organisation_id=p_organisation_id and is_active order by name,code limit 1)));
end $$;
revoke all on function public.menu_profitability_scope(uuid,uuid,text,date) from public,anon;
grant execute on function public.menu_profitability_scope(uuid,uuid,text,date) to authenticated;

notify pgrst,'reload schema';
commit;
