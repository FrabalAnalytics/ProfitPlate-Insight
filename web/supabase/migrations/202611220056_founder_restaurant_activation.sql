-- New applications require Founder activation. Existing states and records are retained.
begin;
alter table public.organisations drop constraint organisations_access_state_check;
alter table public.organisations add constraint organisations_access_state_check check(access_state in('PENDING','ACTIVE','INACTIVE'));
alter table public.organisations alter column access_state set default 'PENDING';
create index if not exists restaurant_activation_directory on public.organisations(access_state,created_at desc,id);

-- Transaction-bound provisioning is private. Nested legacy completion APIs cannot bypass approval.
create table private.restaurant_registration_runs(actor_id uuid primary key references auth.users(id),transaction_id bigint not null,depth integer not null);
create table private.restaurant_access_transitions(organisation_id uuid primary key references public.organisations(id),actor_id uuid not null,transaction_id bigint not null);
revoke all on private.restaurant_registration_runs,private.restaurant_access_transitions from public,anon,authenticated;

create function private.pp_restaurant_transition(org uuid) returns boolean language sql stable security definer set search_path='' as $$
 select public.is_platform_admin() and exists(select 1 from private.restaurant_access_transitions where organisation_id=org and actor_id=auth.uid() and transaction_id=txid_current());
$$;
create or replace function private.pp_require_active_restaurant() returns trigger language plpgsql security definer set search_path='' as $$
declare org uuid;state text;begin
 org:=case when TG_OP='DELETE' then old.organisation_id else new.organisation_id end;
 select access_state into state from public.organisations where id=org for share;
 if state is distinct from 'ACTIVE' and not(TG_TABLE_SCHEMA='public' and TG_TABLE_NAME='organisation_memberships' and private.pp_restaurant_transition(org)) then
  raise exception 'Restaurant activation is required. Pending or inactive restaurants cannot change workspace data.' using errcode='42501';
 end if;
 if TG_OP='DELETE' then return old;end if;return new;
end $$;

create function private.pp_registration_begin() returns boolean language plpgsql security definer set search_path='' as $$
declare draft public.restaurant_setup_drafts;begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) or public.is_platform_admin() then raise exception 'A verified restaurant applicant account is required.' using errcode='42501';end if;
 select * into draft from public.restaurant_setup_drafts where user_id=auth.uid() for update;
 if not found then raise exception 'Save restaurant details first.' using errcode='22023';end if;
 if exists(select 1 from private.restaurant_registration_runs where actor_id=auth.uid() and transaction_id=txid_current()) then
  update private.restaurant_registration_runs set depth=depth+1 where actor_id=auth.uid();return true;
 end if;
 if draft.completed_organisation_id is not null then return false;end if;
 insert into private.restaurant_registration_runs values(auth.uid(),txid_current(),1);return true;
end $$;
create function private.pp_registration_finish(org uuid) returns void language plpgsql security definer set search_path='' as $$
declare remaining integer;begin
 update private.restaurant_registration_runs set depth=depth-1 where actor_id=auth.uid() and transaction_id=txid_current() returning depth into remaining;
 if remaining is null then raise exception 'Registration context unavailable.' using errcode='42501';end if;
 if remaining>0 then return;end if;
 if not exists(select 1 from public.organisations o join public.restaurant_setup_drafts d on d.completed_organisation_id=o.id and d.user_id=auth.uid() where o.id=org and o.owner_id=auth.uid() and o.access_state='ACTIVE') then raise exception 'Registration result unavailable.' using errcode='42501';end if;
 insert into private.suspended_memberships select organisation_id,id from public.organisation_memberships where organisation_id=org and status='active' on conflict do nothing;
 update public.organisation_memberships set status='inactive' where organisation_id=org and status='active';
 update public.organisations set access_state='PENDING' where id=org;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(org,'RESTAURANT_ACTIVATION_REQUESTED',auth.uid(),org,jsonb_build_object('state','PENDING'));
 delete from private.restaurant_registration_runs where actor_id=auth.uid();
end $$;

-- Initial seed rows are built inside the atomic registration call, then access is suspended
-- before it returns. No committed applicant workspace is temporarily active.
do $$declare definition text;updated text;name text;legacy text;begin
 definition:=pg_get_functiondef('public.complete_restaurant_setup()'::regprocedure);
 updated:=replace(definition,'name,owner_id,currency_code,time_zone,country_code,concept,setup_completed_at','name,owner_id,currency_code,time_zone,country_code,concept,setup_completed_at,access_state');
 updated:=replace(updated,'d.concept,now()) returning id into org_id;','d.concept,now(),''ACTIVE'') returning id into org_id;');
 if updated=definition or position('now(),''ACTIVE'') returning id' in updated)=0 then raise exception 'Expected initial registration insert missing.';end if;
 execute updated;
 foreach name in array array['complete_restaurant_setup','complete_restaurant_setup_with_calendar','complete_restaurant_setup_with_channels','complete_restaurant_setup_with_categories','complete_restaurant_setup_with_expenses'] loop
  legacy:='pp_056_'||name;
  execute format('alter function public.%I() rename to %I',name,legacy);
  execute format('alter function public.%I() set schema private',legacy);
  execute format('revoke all on function private.%I() from public,anon,authenticated',legacy);
  execute format($function$create function public.%I() returns uuid language plpgsql security definer set search_path='' as $body$
   declare org uuid;begin
    if not private.pp_registration_begin() then select completed_organisation_id into org from public.restaurant_setup_drafts where user_id=auth.uid();return org;end if;
    org:=private.%I();perform private.pp_registration_finish(org);return org;
   end $body$;$function$,name,legacy);
  execute format('revoke all on function public.%I() from public,anon',name);
  execute format('grant execute on function public.%I() to authenticated',name);
 end loop;
end $$;

create function private.pp_guard_restaurant_state() returns trigger language plpgsql security definer set search_path='' as $$begin
 if TG_OP='INSERT' then
  if new.access_state='PENDING' or auth.uid() is null or exists(select 1 from private.restaurant_registration_runs where actor_id=auth.uid() and transaction_id=txid_current() and depth>0) then return new;end if;
 elsif new.access_state=old.access_state or auth.uid() is null or private.pp_restaurant_transition(new.id) or(new.access_state='PENDING' and old.access_state='ACTIVE' and new.owner_id=auth.uid() and exists(select 1 from private.restaurant_registration_runs where actor_id=auth.uid() and transaction_id=txid_current() and depth=0)) then return new;
 end if;
 raise exception 'Restaurant status is controlled by the Founder.' using errcode='42501';
end $$;
create trigger restaurant_state_control before insert or update of access_state on public.organisations for each row execute function private.pp_guard_restaurant_state();

create or replace function private.pp_keep_centre_owner_active() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.status<>'active' and not private.pp_restaurant_transition(new.organisation_id) and exists(select 1 from public.stock_processing_settings where organisation_id=new.organisation_id) and exists(select 1 from public.stock_locations where organisation_id=new.organisation_id and responsible_membership_id=new.id and is_active) then raise exception 'Reassign this member stock centres before deactivating their account.' using errcode='22023';end if;return new;
end $$;
create or replace function public.set_restaurant_access(p_organisation_id uuid,p_expected_state text,p_state text,p_reason text,p_confirmed boolean) returns void language plpgsql security definer set search_path='' as $$
declare current_state text;begin
 if not public.is_platform_admin() then raise exception 'Founder access required.' using errcode='42501';end if;
 if p_state is null or p_state not in('ACTIVE','INACTIVE') or p_expected_state is null or p_expected_state not in('PENDING','ACTIVE','INACTIVE') or p_confirmed is distinct from true or p_reason is null or length(trim(p_reason)) not between 3 and 500 then raise exception 'Confirm the change and give a reason of 3 to 500 characters.' using errcode='22023';end if;
 select access_state into current_state from public.organisations where id=p_organisation_id for update;
 if not found then raise exception 'Restaurant unavailable.' using errcode='22023';end if;
 if current_state<>p_expected_state then raise exception 'Restaurant access has changed. Refresh before continuing.' using errcode='40001';end if;
 if current_state=p_state then return;end if;
 insert into private.restaurant_access_transitions values(p_organisation_id,auth.uid(),txid_current());
 if p_state='INACTIVE' then
  insert into private.suspended_memberships select organisation_id,id from public.organisation_memberships where organisation_id=p_organisation_id and status='active' on conflict do nothing;
  update public.organisations set access_state='INACTIVE' where id=p_organisation_id;
  update public.organisation_memberships set status='inactive' where organisation_id=p_organisation_id and status='active';
 else
  update public.organisations set access_state='ACTIVE' where id=p_organisation_id;
  update public.organisation_memberships m set status='active' from private.suspended_memberships s where s.organisation_id=p_organisation_id and m.organisation_id=s.organisation_id and m.id=s.membership_id;
  delete from private.suspended_memberships where organisation_id=p_organisation_id;
 end if;
 insert into private.restaurant_access_events(organisation_id,state,reason,actor_id) values(p_organisation_id,p_state,trim(p_reason),auth.uid());
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'RESTAURANT_ACCESS',auth.uid(),p_organisation_id,jsonb_build_object('from',current_state,'to',p_state,'reason',trim(p_reason)));
 delete from private.restaurant_access_transitions where organisation_id=p_organisation_id;
end $$;

-- Cover every current public/private tenant table, including later stock and import modules.
-- Only lifecycle bookkeeping and audit trails can be written while access is blocked.
do $$declare t record;begin
 for t in select c.table_schema,c.table_name from information_schema.columns c join information_schema.tables tab using(table_schema,table_name) where c.table_schema in('public','private') and c.column_name='organisation_id' and tab.table_type='BASE TABLE' and not(c.table_schema='public' and c.table_name='audit_events') and not(c.table_schema='private' and c.table_name in('suspended_memberships','restaurant_access_events','restaurant_access_transitions')) loop
  execute format('drop trigger if exists restaurant_active_write on %I.%I',t.table_schema,t.table_name);
  execute format('create trigger restaurant_active_write before insert or update or delete on %I.%I for each row execute function private.pp_require_active_restaurant()',t.table_schema,t.table_name);
 end loop;
end $$;

-- Directory work is bounded to the requested page; setup progress is not calculated
-- for every registered restaurant or for applications that have not been activated.
create function private.pp_activation_business(org uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',o.id,'name',o.name,'access_state',o.access_state,'created_at',o.created_at,'currency_code',o.currency_code,'time_zone',o.time_zone,'country_code',o.country_code,'concept',o.concept,'owner_email',u.email,
 'outlets',(select count(*) from public.locations where organisation_id=o.id),'active_members',(select count(*) from public.organisation_memberships where organisation_id=o.id and status='active'),
 'has_admin',exists(select 1 from public.organisation_memberships m join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id where m.organisation_id=o.id and m.status='active' and r.role_code='restaurant_admin' and r.location_id is null),
 'expired_invitations',(select count(*) from public.team_invitations where organisation_id=o.id and state='PENDING' and expires_at<now()),'last_activity',(select max(created_at) from public.audit_events where organisation_id=o.id),
 'setup',case when o.access_state='PENDING' then null else private.pp_setup_progress(o.id) end)
 from public.organisations o left join auth.users u on u.id=o.owner_id where o.id=org;
$$;
create or replace function public.platform_workspace(p_search text default '',p_state text default 'ALL',p_page integer default 1,p_organisation_id uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;chosen jsonb;begin
 if not public.is_platform_admin() then raise exception 'Founder access required.' using errcode='42501';end if;
 if p_search is null or length(p_search)>80 or p_state is null or p_state not in('ALL','PENDING','ACTIVE','INACTIVE','ONBOARDING','ACCESS_REVIEW') or p_page is null or p_page not between 1 and 100000 then raise exception 'Choose valid platform filters and page.' using errcode='22023';end if;
 if p_organisation_id is not null and not exists(select 1 from public.organisations where id=p_organisation_id) then raise exception 'Restaurant unavailable.' using errcode='22023';end if;
 with base as materialized(select o.id,o.name,o.created_at,o.access_state,u.email owner_email,
 o.access_state='ACTIVE' and(not exists(select 1 from public.organisation_memberships m join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id where m.organisation_id=o.id and m.status='active' and r.role_code='restaurant_admin' and r.location_id is null) or exists(select 1 from public.team_invitations where organisation_id=o.id and state='PENDING' and expires_at<now())) review
 from public.organisations o left join auth.users u on u.id=o.owner_id),
 matching as materialized(select * from base where p_state<>'ONBOARDING' and(p_state='ALL' or access_state=p_state or(p_state='ACCESS_REVIEW' and review)) and(trim(p_search)='' or position(lower(trim(p_search)) in lower(name||' '||coalesce(owner_email,'')))>0)),
 paged as(select * from matching order by created_at desc,id limit 10 offset(p_page-1)*10),
 drafts as materialized(select d.business_name,d.step,d.updated_at,u.email owner_email from public.restaurant_setup_drafts d left join auth.users u on u.id=d.user_id where d.completed_organisation_id is null and(trim(p_search)='' or position(lower(trim(p_search)) in lower(d.business_name||' '||coalesce(u.email,'')))>0))
 select jsonb_build_object('summary',jsonb_build_object('restaurants',(select count(*) from base),'outlets',(select count(*) from public.locations),'active_memberships',(select count(*) from public.organisation_memberships where status='active'),'onboarding',(select count(*) from public.restaurant_setup_drafts where completed_organisation_id is null),'access_review',(select count(*) from base where review),'pending',(select count(*) from base where access_state='PENDING')),
 'inactive_restaurants',(select count(*) from base where access_state='INACTIVE'),'pending_restaurants',(select count(*) from base where access_state='PENDING'),
 'total',case when p_state='ONBOARDING' then(select count(*) from drafts) else(select count(*) from matching) end,
 'businesses',coalesce((select jsonb_agg(private.pp_activation_business(p.id) order by p.created_at desc,p.id) from paged p),'[]'::jsonb),
 'drafts',case when p_state='ONBOARDING' then coalesce((select jsonb_agg(to_jsonb(d) order by updated_at desc,owner_email) from(select * from drafts order by updated_at desc,owner_email limit 10 offset(p_page-1)*10)d),'[]'::jsonb) else '[]'::jsonb end,
 'refreshed_at',statement_timestamp()) into result;
 if p_organisation_id is not null then
  chosen:=private.pp_activation_business(p_organisation_id)||jsonb_build_object('roles',coalesce((select jsonb_agg(jsonb_build_object('role_code',role_code,'assignments',assignments) order by role_code) from(select r.role_code,count(*) assignments from public.membership_roles r join public.organisation_memberships m on m.organisation_id=r.organisation_id and m.id=r.membership_id where r.organisation_id=p_organisation_id and m.status='active' group by r.role_code)r),'[]'::jsonb),
  'access_events',coalesce((select jsonb_agg(to_jsonb(e) order by created_at desc,id desc) from(select id,state,reason,created_at from private.restaurant_access_events where organisation_id=p_organisation_id order by created_at desc,id desc limit 10)e),'[]'::jsonb));
 end if;
 return result||jsonb_build_object('selected',chosen);
end $$;
revoke all on function private.pp_restaurant_transition(uuid),private.pp_registration_begin(),private.pp_registration_finish(uuid),private.pp_guard_restaurant_state(),private.pp_activation_business(uuid) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
