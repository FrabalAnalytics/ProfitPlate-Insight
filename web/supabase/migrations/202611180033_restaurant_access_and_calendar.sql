-- Manual platform suspension and an explicit restaurant reporting calendar. Apply after 032.
begin;
alter table public.organisations add column access_state text not null default 'ACTIVE' check(access_state in ('ACTIVE','INACTIVE')),
 add column reporting_week_start smallint check(reporting_week_start between 0 and 6),
 add column count_day smallint check(count_day between 0 and 6),add column count_cutoff time;
alter table public.restaurant_setup_drafts add column reporting_week_start smallint check(reporting_week_start between 0 and 6),add column count_day smallint check(count_day between 0 and 6),add column count_cutoff time;
create table private.suspended_memberships(organisation_id uuid not null references public.organisations(id),membership_id uuid not null references public.organisation_memberships(id),primary key(organisation_id,membership_id));
create table private.restaurant_access_events(id uuid primary key default gen_random_uuid(),organisation_id uuid not null references public.organisations(id),state text not null,reason text not null,actor_id uuid not null references auth.users(id),created_at timestamptz not null default now());
revoke all on private.suspended_memberships,private.restaurant_access_events from public,anon,authenticated;
create function private.pp_require_active_restaurant() returns trigger language plpgsql security definer set search_path='' as $$
declare org uuid;state text;
begin
 org:=case when TG_OP='DELETE' then old.organisation_id else new.organisation_id end;
 select access_state into state from public.organisations where id=org for share;
 if state='INACTIVE' then raise exception 'This restaurant is inactive. Contact the platform administrator.' using errcode='42501';end if;
 if TG_OP='DELETE' then return old;end if;return new;
end $$;
-- Existing access helpers use active memberships. Suspension snapshots exactly
-- those memberships, so previously disabled accounts are never reactivated.
create function public.set_restaurant_access(p_organisation_id uuid,p_expected_state text,p_state text,p_reason text,p_confirmed boolean) returns void language plpgsql security definer set search_path='' as $$
declare current_state text;
begin
 if not public.is_platform_admin() then raise exception 'Founder access required.' using errcode='42501';end if;
 if p_state is null or p_state not in ('ACTIVE','INACTIVE') or p_expected_state is null or p_expected_state not in ('ACTIVE','INACTIVE') or p_confirmed is distinct from true or p_reason is null or length(trim(p_reason)) not between 3 and 500 then raise exception 'Confirm the change and give a reason of 3 to 500 characters.' using errcode='22023';end if;
 select access_state into current_state from public.organisations where id=p_organisation_id for update;
 if not found then raise exception 'Restaurant unavailable.' using errcode='22023';end if;
 if current_state<>p_expected_state then raise exception 'Restaurant access has changed. Refresh before continuing.' using errcode='40001';end if;
 if current_state=p_state then return;end if;
 if p_state='INACTIVE' then
  insert into private.suspended_memberships select organisation_id,id from public.organisation_memberships where organisation_id=p_organisation_id and status='active';
  update public.organisation_memberships set status='inactive' where organisation_id=p_organisation_id and status='active';
  update public.organisations set access_state='INACTIVE' where id=p_organisation_id;
 else
  update public.organisations set access_state='ACTIVE' where id=p_organisation_id;
  update public.organisation_memberships m set status='active' from private.suspended_memberships s where s.organisation_id=p_organisation_id and m.organisation_id=s.organisation_id and m.id=s.membership_id;
  delete from private.suspended_memberships where organisation_id=p_organisation_id;
 end if;
 insert into private.restaurant_access_events(organisation_id,state,reason,actor_id) values(p_organisation_id,p_state,trim(p_reason),auth.uid());
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'RESTAURANT_ACCESS',auth.uid(),p_organisation_id,jsonb_build_object('from',current_state,'to',p_state,'reason',trim(p_reason)));
end $$;
-- Guard operational writes and invitation acceptance, including existing sessions.
do $$declare t record;begin
 for t in select c.table_name from information_schema.columns c join information_schema.tables tab using(table_schema,table_name) where c.table_schema='public' and c.column_name='organisation_id' and tab.table_type='BASE TABLE' and c.table_name not in ('audit_events') loop
  execute format('create trigger restaurant_active_write before insert or update or delete on public.%I for each row execute function private.pp_require_active_restaurant()',t.table_name);
 end loop;
end $$;
create function public.account_restaurant_access() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'name',o.name,'state',o.access_state) order by o.name,o.id),'[]'::jsonb) from public.organisations o where exists(select 1 from public.organisation_memberships m where m.organisation_id=o.id and m.user_id=auth.uid() and(m.status='active' or exists(select 1 from private.suspended_memberships s where s.organisation_id=o.id and s.membership_id=m.id)));
$$;
alter function public.platform_workspace(text,text,integer,uuid) rename to pp_platform_workspace_base;
alter function public.pp_platform_workspace_base(text,text,integer,uuid) set schema private;
create or replace function private.pp_platform_workspace_base(p_search text default '',p_state text default 'ALL',p_page integer default 1,p_organisation_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare packet jsonb;
begin
 if not public.is_platform_admin() then raise exception 'Platform administrator access is required.' using errcode='42501'; end if;
 if p_search is null or length(p_search)>80 or p_state is null or p_state not in ('ALL','ONBOARDING','ACCESS_REVIEW') or p_page is null or p_page not between 1 and 100000 then raise exception 'Choose valid platform filters and page.' using errcode='22023'; end if;
 if p_organisation_id is not null and not exists(select 1 from public.organisations where id=p_organisation_id) then raise exception 'Business unavailable.' using errcode='22023'; end if;
 with businesses as materialized(
  select private.pp_setup_progress(o.id) setup,o.id,o.name,o.access_state,o.created_at,o.currency_code,o.time_zone,u.email owner_email,
   (select count(*) from public.locations l where l.organisation_id=o.id) outlets,
   (select count(*) from public.organisation_memberships m where m.organisation_id=o.id and m.status='active') active_members,
   exists(select 1 from public.organisation_memberships m join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id where m.organisation_id=o.id and m.status='active' and r.role_code='restaurant_admin' and r.location_id is null) has_admin,
   (select count(*) from public.team_invitations i where i.organisation_id=o.id and i.state='PENDING' and i.expires_at<now()) expired_invitations,
   (select max(a.created_at) from public.audit_events a where a.organisation_id=o.id) last_activity
  from public.organisations o left join auth.users u on u.id=o.owner_id
 ), filtered as(select * from businesses where p_state<>'ONBOARDING' and(p_state<>'ACCESS_REVIEW' or(access_state='ACTIVE' and(not has_admin or expired_invitations>0))) and(trim(p_search)='' or position(lower(trim(p_search)) in lower(name||' '||coalesce(owner_email,'')))>0)),
 drafts as(select d.business_name,d.step,d.updated_at,u.email owner_email from public.restaurant_setup_drafts d left join auth.users u on u.id=d.user_id where d.completed_organisation_id is null and(trim(p_search)='' or position(lower(trim(p_search)) in lower(d.business_name||' '||coalesce(u.email,'')))>0))
 select jsonb_build_object('summary',jsonb_build_object('restaurants',(select count(*) from businesses),'outlets',(select coalesce(sum(outlets),0) from businesses),'active_memberships',(select coalesce(sum(active_members),0) from businesses),'onboarding',(select count(*) from public.restaurant_setup_drafts where completed_organisation_id is null),'access_review',(select count(*) from businesses where access_state='ACTIVE' and(not has_admin or expired_invitations>0))),
  'total',case when p_state='ONBOARDING' then(select count(*) from drafts) else(select count(*) from filtered) end,
  'businesses',coalesce((select jsonb_agg(to_jsonb(b) order by b.created_at desc,b.id) from(select * from filtered order by created_at desc,id limit 10 offset(p_page-1)*10)b),'[]'::jsonb),
  'drafts',case when p_state='ONBOARDING' then coalesce((select jsonb_agg(to_jsonb(d) order by updated_at desc) from(select * from drafts order by updated_at desc,owner_email limit 10 offset(p_page-1)*10)d),'[]'::jsonb) else '[]'::jsonb end,
  'selected',case when p_organisation_id is not null then(select to_jsonb(b)||jsonb_build_object('roles',coalesce((select jsonb_agg(to_jsonb(r)) from(select mr.role_code,count(*) assignments from public.membership_roles mr join public.organisation_memberships m on m.organisation_id=mr.organisation_id and m.id=mr.membership_id where mr.organisation_id=b.id and m.status='active' group by mr.role_code order by mr.role_code)r),'[]'::jsonb)) from businesses b where b.id=p_organisation_id) end,
  'refreshed_at',statement_timestamp()) into packet;
 return packet;
end $$;
revoke all on function private.pp_platform_workspace_base(text,text,integer,uuid) from public,anon,authenticated;
create function public.platform_workspace(p_search text default '',p_state text default 'ALL',p_page integer default 1,p_organisation_id uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare packet jsonb;rows jsonb;selected jsonb;
begin
 packet:=private.pp_platform_workspace_base(p_search,p_state,p_page,p_organisation_id);
 select coalesce(jsonb_agg(b.value||jsonb_build_object('access_state',o.access_state) order by n),'[]'::jsonb) into rows from jsonb_array_elements(packet->'businesses') with ordinality b(value,n) join public.organisations o on o.id=(b.value->>'id')::uuid;
 selected:=packet->'selected';
 if selected is not null and selected<>'null'::jsonb then selected:=selected||jsonb_build_object('access_state',(select access_state from public.organisations where id=p_organisation_id),'access_events',coalesce((select jsonb_agg(to_jsonb(e) order by created_at desc,id desc) from(select id,state,reason,created_at from private.restaurant_access_events where organisation_id=p_organisation_id order by created_at desc,id desc limit 10)e),'[]'::jsonb));end if;
 return packet||jsonb_build_object('businesses',rows,'selected',selected,'inactive_restaurants',(select count(*) from public.organisations where access_state='INACTIVE'));
end $$;
create function public.save_setup_calendar(p_week_start integer,p_count_day integer,p_cutoff text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in first.' using errcode='42501';end if;
 if (p_week_start is not null and p_week_start not between 0 and 6) or(p_count_day is not null and p_count_day not between 0 and 6) or(p_cutoff is not null and p_cutoff!~'^([01][0-9]|2[0-3]):[0-5][0-9]$') then raise exception 'Choose a valid reporting calendar.' using errcode='22023';end if;
 update public.restaurant_setup_drafts set reporting_week_start=p_week_start,count_day=p_count_day,count_cutoff=p_cutoff::time where user_id=auth.uid() and completed_organisation_id is null;
 if not found and not exists(select 1 from public.restaurant_setup_drafts where user_id=auth.uid() and completed_organisation_id is not null) then raise exception 'Save business details first.' using errcode='22023';end if;
end $$;
create function public.save_reporting_calendar(p_organisation_id uuid,p_timezone text,p_week_start integer,p_count_day integer,p_cutoff text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Restaurant administrator access required.' using errcode='42501';end if;
 if p_week_start is null or p_week_start not between 0 and 6 or p_count_day is null or p_count_day not between 0 and 6 or p_cutoff is null or p_cutoff!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' or not exists(select 1 from pg_catalog.pg_timezone_names where name=p_timezone) then raise exception 'Choose the timezone, week start and physical count cutoff.' using errcode='22023';end if;
 perform 1 from public.organisations where id=p_organisation_id and access_state='ACTIVE' for update;
 if not found then raise exception 'Restaurant unavailable.' using errcode='42501';end if;
 update public.organisations set time_zone=p_timezone,reporting_week_start=p_week_start,count_day=p_count_day,count_cutoff=p_cutoff::time where id=p_organisation_id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'REPORTING_CALENDAR',auth.uid(),p_organisation_id,jsonb_build_object('timezone',p_timezone,'week_start',p_week_start,'count_day',p_count_day,'cutoff',p_cutoff));
end $$;
create function public.complete_restaurant_setup_with_calendar() returns uuid language plpgsql security definer set search_path='' as $$
declare d public.restaurant_setup_drafts;org uuid;
begin
 select * into d from public.restaurant_setup_drafts where user_id=auth.uid() for update;
 if d.reporting_week_start is null or d.count_day is null or d.count_cutoff is null then raise exception 'Complete the reporting calendar first.' using errcode='22023';end if;
 org:=public.complete_restaurant_setup();
 if not exists(select 1 from public.organisations where id=org and reporting_week_start is not null) then perform public.save_reporting_calendar(org,d.timezone,d.reporting_week_start,d.count_day,to_char(d.count_cutoff,'HH24:MI'));end if;
 return org;
end $$;
create function public.reporting_calendar(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare o public.organisations;day date;start_day date;
begin
 if not private.pp_active_member(p_organisation_id) then raise exception 'Restaurant access required.' using errcode='42501';end if;
 select * into o from public.organisations where id=p_organisation_id;
 day:=(now() at time zone o.time_zone)::date;
 start_day:=day-((extract(dow from day)::integer-o.reporting_week_start+7)%7);
 return jsonb_build_object('timezone',o.time_zone,'week_start',o.reporting_week_start,'count_day',o.count_day,'cutoff',to_char(o.count_cutoff,'HH24:MI'),'week_from',start_day,'week_to',start_day+6);
end $$;
revoke all on function private.pp_require_active_restaurant() from public,anon,authenticated;
revoke all on function public.set_restaurant_access(uuid,text,text,text,boolean),public.account_restaurant_access(),public.platform_workspace(text,text,integer,uuid),public.save_setup_calendar(integer,integer,text),public.save_reporting_calendar(uuid,text,integer,integer,text),public.complete_restaurant_setup_with_calendar(),public.reporting_calendar(uuid) from public,anon;
grant execute on function public.set_restaurant_access(uuid,text,text,text,boolean),public.account_restaurant_access(),public.platform_workspace(text,text,integer,uuid),public.save_setup_calendar(integer,integer,text),public.save_reporting_calendar(uuid,text,integer,integer,text),public.complete_restaurant_setup_with_calendar(),public.reporting_calendar(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
