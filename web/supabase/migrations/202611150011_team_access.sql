-- Apply ONCE after 010. Controlled invitations; no auth-user creation or email sending.
begin;

create function private.pp_team_manage(target_org uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisation_memberships m join public.membership_roles r
 on r.organisation_id=m.organisation_id and r.membership_id=m.id
 where m.organisation_id=target_org and m.user_id=auth.uid() and m.status='active'
 and r.role_code='restaurant_admin' and r.location_id is null)
 and not exists(select 1 from private.platform_admins where user_id=auth.uid());
$$;
revoke all on function private.pp_team_manage(uuid) from public,anon,authenticated;

create table public.team_invitations(
 id uuid primary key default gen_random_uuid(),
 organisation_id uuid not null references public.organisations(id),
 request_id uuid not null,
 email text not null check(length(email) between 3 and 254 and email=lower(trim(email))),
 assignments jsonb not null check(jsonb_typeof(assignments)='array'),
 token_hash text not null unique,
 state text not null default 'PENDING' check(state in ('PENDING','ACCEPTED','REVOKED')),
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default(now()+interval '7 days'),
 accepted_by uuid references auth.users(id), accepted_at timestamptz,
 unique(organisation_id,request_id)
);
create index pp_team_invites_org_idx on public.team_invitations(organisation_id,created_at desc);
alter table public.team_invitations enable row level security;
revoke all on public.team_invitations from public,anon,authenticated;

create function private.pp_team_assignments(target_org uuid, input jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if input is null or jsonb_typeof(input)<>'array' or jsonb_array_length(input) not between 1 and 20 then
  raise exception 'Choose between 1 and 20 role assignments.' using errcode='22023'; end if;
 if exists(select 1 from jsonb_array_elements(input) e where jsonb_typeof(e)<>'object'
  or coalesce(e->>'role_code','') not in ('ceo','finance','procurement','operations','restaurant_admin')
  or (e->>'location_id' is not null and not exists(select 1 from public.locations l
    where l.organisation_id=target_org and l.id::text=e->>'location_id' and l.is_active))) then
  raise exception 'Choose recognised roles and active locations in this business.' using errcode='22023'; end if;
 select jsonb_agg(v order by v->>'role_code',v->>'location_id') into result from
 (select distinct jsonb_build_object('role_code',e->>'role_code','location_id',e->>'location_id') v
  from jsonb_array_elements(input) e) s;
 return result;
end; $$;
revoke all on function private.pp_team_assignments(uuid,jsonb) from public,anon,authenticated;

create function public.team_access(p_organisation_id uuid)
returns boolean language sql stable security definer set search_path='' as $$ select private.pp_team_manage(p_organisation_id); $$;

create function public.team_directory(p_organisation_id uuid,p_search text default '',p_page integer default 1,p_invite_page integer default 1)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare members jsonb; invites jsonb; total bigint; invite_total bigint;
begin
 if not private.pp_team_manage(p_organisation_id) then raise exception 'Team administration is restricted.' using errcode='42501'; end if;
 if p_search is null or length(p_search)>120 or p_page is null or p_page not between 1 and 100000 or p_invite_page is null or p_invite_page not between 1 and 100000 then
 raise exception 'Check the team search and page.' using errcode='22023'; end if;
 select count(*) into total from public.organisation_memberships m join auth.users u on u.id=m.user_id
 where m.organisation_id=p_organisation_id and strpos(lower(coalesce(u.email,'')),lower(trim(p_search)))>0;
 select coalesce(jsonb_agg(v order by v->>'email'),'[]') into members from (
 select jsonb_build_object('id',m.id,'user_id',m.user_id,'email',u.email,'status',m.status,'updated_at',m.updated_at,
 'is_owner',o.owner_id=m.user_id,'is_self',m.user_id=auth.uid(),
 'assignments',coalesce((select jsonb_agg(jsonb_build_object('role_code',r.role_code,'location_id',r.location_id,'location_name',l.name) order by r.role_code,l.name)
 from public.membership_roles r left join public.locations l on l.id=r.location_id and l.organisation_id=r.organisation_id
 where r.membership_id=m.id and r.organisation_id=m.organisation_id),'[]')) v
 from public.organisation_memberships m join auth.users u on u.id=m.user_id join public.organisations o on o.id=m.organisation_id
 where m.organisation_id=p_organisation_id and strpos(lower(coalesce(u.email,'')),lower(trim(p_search)))>0
 order by u.email,m.id limit 25 offset(p_page-1)*25) s;
 select count(*) into invite_total from public.team_invitations where organisation_id=p_organisation_id;
 select coalesce(jsonb_agg(v order by created_at desc),'[]') into invites from (
 select created_at,jsonb_build_object('id',id,'email',email,'state',case when state='PENDING' and expires_at<=now() then 'EXPIRED' else state end,
 'created_at',created_at,'expires_at',expires_at,'assignments',assignments) v
 from public.team_invitations where organisation_id=p_organisation_id order by created_at desc,id limit 25 offset(p_invite_page-1)*25) s;
 return jsonb_build_object('members',members,'member_total',total,'invitations',invites,'invitation_total',invite_total);
end; $$;

create function public.create_team_invitation(p_organisation_id uuid,p_request_id uuid,p_email text,p_assignments jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare target_email text:=lower(trim(p_email)); grants jsonb; invitation public.team_invitations; secret text;
begin
 perform 1 from public.organisations where id=p_organisation_id for update;
 if not private.pp_team_manage(p_organisation_id) then raise exception 'Team administration is restricted.' using errcode='42501'; end if;
 if p_request_id is null or target_email is null or length(target_email)>254 or target_email!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
 raise exception 'Enter a valid email address.' using errcode='22023'; end if;
 grants:=private.pp_team_assignments(p_organisation_id,p_assignments);
 select * into invitation from public.team_invitations where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then
  if invitation.email<>target_email or invitation.assignments<>grants then raise exception 'This request was already used. Refresh and try again.' using errcode='22023'; end if;
  return jsonb_build_object('id',invitation.id,'token',null,'expires_at',invitation.expires_at);
 end if;
 if exists(select 1 from public.organisation_memberships m join auth.users u on u.id=m.user_id where m.organisation_id=p_organisation_id and lower(u.email)=target_email) then
  raise exception 'This account is already in your team. Manage its existing access instead.' using errcode='22023'; end if;
 if exists(select 1 from public.team_invitations where organisation_id=p_organisation_id and email=target_email and state='PENDING' and expires_at>now()) then
  raise exception 'An active invitation already exists for this email. Revoke it before creating another.' using errcode='22023'; end if;
 if (select count(*) from public.team_invitations where organisation_id=p_organisation_id and state='PENDING' and expires_at>now())>=100 then
  raise exception 'This business has 100 pending invitations. Revoke unused invitations first.' using errcode='22023'; end if;
 secret:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
 insert into public.team_invitations(organisation_id,request_id,email,assignments,token_hash,created_by)
 values(p_organisation_id,p_request_id,target_email,grants,encode(sha256(convert_to(secret,'UTF8')),'hex'),auth.uid()) returning * into invitation;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details)
 values(p_organisation_id,'TEAM_INVITATION_CREATED',auth.uid(),invitation.id,jsonb_build_object('email',target_email,'assignments',grants));
 return jsonb_build_object('id',invitation.id,'token',secret,'expires_at',invitation.expires_at);
end; $$;

create function public.revoke_team_invitation(p_organisation_id uuid,p_invitation_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare invitation public.team_invitations;
begin
 perform 1 from public.organisations where id=p_organisation_id for update;
 if not private.pp_team_manage(p_organisation_id) then raise exception 'Team administration is restricted.' using errcode='42501'; end if;
 select * into invitation from public.team_invitations where id=p_invitation_id and organisation_id=p_organisation_id for update;
 if not found or invitation.state='ACCEPTED' then raise exception 'This invitation cannot be revoked. Manage accepted members in the team list.' using errcode='22023'; end if;
 if invitation.state='REVOKED' then return; end if;
 update public.team_invitations set state='REVOKED' where id=invitation.id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id) values(p_organisation_id,'TEAM_INVITATION_REVOKED',auth.uid(),invitation.id);
end; $$;

create function public.update_team_member(p_organisation_id uuid,p_membership_id uuid,p_expected_updated_at timestamptz,p_active boolean,p_assignments jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare member public.organisation_memberships; grants jsonb;
begin
 perform 1 from public.organisations where id=p_organisation_id for update;
 if not private.pp_team_manage(p_organisation_id) then raise exception 'Team administration is restricted.' using errcode='42501'; end if;
 select * into member from public.organisation_memberships where organisation_id=p_organisation_id and id=p_membership_id for update;
 if not found then raise exception 'This team member is unavailable.' using errcode='22023'; end if;
 if member.user_id=auth.uid() or exists(select 1 from public.organisations where id=p_organisation_id and owner_id=member.user_id) then
  raise exception 'Owner access and your own access cannot be changed here.' using errcode='42501'; end if;
 if p_expected_updated_at is null or p_expected_updated_at<>member.updated_at then raise exception 'Team access changed. Refresh before saving again.' using errcode='22023'; end if;
 if p_active is null then raise exception 'Choose the member status.' using errcode='22023'; end if;
 -- Deactivation preserves all assignments, including historical inactive locations.
 if p_active then grants:=private.pp_team_assignments(p_organisation_id,p_assignments);
 else select coalesce(jsonb_agg(jsonb_build_object('role_code',role_code,'location_id',location_id)),'[]') into grants
 from public.membership_roles where membership_id=member.id and organisation_id=p_organisation_id; end if;
 if p_active then
  delete from public.membership_roles where membership_id=member.id and organisation_id=p_organisation_id;
  insert into public.membership_roles(organisation_id,membership_id,role_code,location_id,created_by)
  select p_organisation_id,member.id,e->>'role_code',(e->>'location_id')::uuid,auth.uid() from jsonb_array_elements(grants) e;
 end if;
 update public.organisation_memberships set status=case when p_active then 'active' else 'inactive' end,updated_at=clock_timestamp() where id=member.id;
 -- Permissions changed by this workflow invalidate that member's outstanding grants.
 update public.team_invitations set state='REVOKED' where organisation_id=p_organisation_id and created_by=member.user_id and state='PENDING';
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details)
 values(p_organisation_id,'TEAM_MEMBER_UPDATED',auth.uid(),member.id,jsonb_build_object('active',p_active,'assignments',grants));
end; $$;

create function public.inspect_team_invitation(p_token text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare invitation public.team_invitations; caller_email text; verified timestamptz;
begin
 if p_token is null or p_token!~'^[a-f0-9]{64}$' then raise exception 'This invitation is unavailable or expired.' using errcode='22023'; end if;
 select email,email_confirmed_at into caller_email,verified from auth.users where id=auth.uid();
 select * into invitation from public.team_invitations where token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex');
 if not found or verified is null or lower(caller_email) is distinct from invitation.email or exists(select 1 from private.platform_admins where user_id=auth.uid())
 or invitation.state<>'PENDING' or invitation.expires_at<=now()
 or exists(select 1 from private.platform_admins where user_id=invitation.created_by) or not exists(
 select 1 from public.organisation_memberships m join public.membership_roles r on r.membership_id=m.id and r.organisation_id=m.organisation_id
 where m.organisation_id=invitation.organisation_id and m.user_id=invitation.created_by and m.status='active' and r.role_code='restaurant_admin' and r.location_id is null)
 then raise exception 'This invitation is unavailable, expired, or belongs to a different verified email.' using errcode='22023'; end if;
 return jsonb_build_object('organisation_name',(select name from public.organisations where id=invitation.organisation_id),
 'email',invitation.email,'expires_at',invitation.expires_at,'assignments',(select jsonb_agg(jsonb_build_object('role_code',e->>'role_code','location_id',e->>'location_id','location_name',l.name))
 from jsonb_array_elements(invitation.assignments) e left join public.locations l on l.organisation_id=invitation.organisation_id and l.id::text=e->>'location_id'));
end; $$;

create function public.accept_team_invitation(p_token text)
returns uuid language plpgsql security definer set search_path='' as $$
declare invitation public.team_invitations; member_id uuid; grants jsonb;
begin
 if p_token is null or p_token!~'^[a-f0-9]{64}$' then raise exception 'This invitation is unavailable or expired.' using errcode='22023'; end if;
 select * into invitation from public.team_invitations where token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex');
 if not found then raise exception 'This invitation is unavailable or expired.' using errcode='22023'; end if;
 perform 1 from public.organisations where id=invitation.organisation_id for update;
 select * into invitation from public.team_invitations where id=invitation.id for update;
 if invitation.state='ACCEPTED' and invitation.accepted_by=auth.uid() then return invitation.organisation_id; end if;
 perform public.inspect_team_invitation(p_token);
 grants:=private.pp_team_assignments(invitation.organisation_id,invitation.assignments);
 if exists(select 1 from public.organisation_memberships where organisation_id=invitation.organisation_id and user_id=auth.uid()) then
 raise exception 'Your account already has membership here. Ask the administrator to manage existing access.' using errcode='22023'; end if;
 insert into public.organisation_memberships(organisation_id,user_id,created_by) values(invitation.organisation_id,auth.uid(),invitation.created_by) returning id into member_id;
 insert into public.membership_roles(organisation_id,membership_id,role_code,location_id,created_by)
 select invitation.organisation_id,member_id,e->>'role_code',(e->>'location_id')::uuid,invitation.created_by from jsonb_array_elements(grants) e;
 update public.team_invitations set state='ACCEPTED',accepted_by=auth.uid(),accepted_at=now() where id=invitation.id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details)
 values(invitation.organisation_id,'TEAM_INVITATION_ACCEPTED',auth.uid(),member_id,jsonb_build_object('invitation_id',invitation.id,'assignments',grants));
 return invitation.organisation_id;
end; $$;

revoke all on function public.team_access(uuid),public.team_directory(uuid,text,integer,integer),
 public.create_team_invitation(uuid,uuid,text,jsonb),public.revoke_team_invitation(uuid,uuid),
 public.update_team_member(uuid,uuid,timestamptz,boolean,jsonb),public.inspect_team_invitation(text),public.accept_team_invitation(text) from public,anon;
grant execute on function public.team_access(uuid),public.team_directory(uuid,text,integer,integer),
 public.create_team_invitation(uuid,uuid,text,jsonb),public.revoke_team_invitation(uuid,uuid),
 public.update_team_member(uuid,uuid,timestamptz,boolean,jsonb),public.inspect_team_invitation(text),public.accept_team_invitation(text) to authenticated;
commit;
