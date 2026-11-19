-- Recipient-bound invitation recovery, atomic stock-centre grants and email attempt tracking.
begin;
alter table public.team_invitations add column stock_access jsonb not null default '[]',add column email_status text not null default 'NOT_SENT' check(email_status in ('NOT_SENT','REQUESTED','SENT','FAILED')),add column email_attempt_at timestamptz;
create function private.pp_invitation_stock(org uuid,roles jsonb,grants jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare entry jsonb;site public.stock_locations;codes text[];seen uuid[]:='{}';result jsonb:='[]';
begin
 if grants is null or jsonb_typeof(grants)<>'array' or jsonb_array_length(grants)>100 or octet_length(grants::text)>32768 then raise exception 'Choose up to 100 stock centres.' using errcode='22023';end if;
 for entry in select value from jsonb_array_elements(grants) loop
  if jsonb_typeof(entry)<>'object' or entry-array['location_id','can_request','can_record_waste','can_receive','can_dispatch']<>'{}' then raise exception 'Review stock-centre tasks.' using errcode='22023';end if;
  if (entry->>'location_id') is null or entry->>'location_id'!~'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$' then raise exception 'Choose a valid stock centre.' using errcode='22023';end if;
  select * into site from public.stock_locations where organisation_id=org and id=(entry->>'location_id')::uuid and is_active;
  if not found or site.id=any(seen) then raise exception 'Choose distinct active centres in this restaurant.' using errcode='22023';end if;
  select array_agg(r->>'role_code') into codes from jsonb_array_elements(roles) r where(r->>'role_code') in ('inventory','operations','stock_department','kitchen_manager','bar_lead','stock_receiver','stock_dispatcher') and(nullif(r->>'location_id','') is null or r->>'location_id'=site.outlet_id::text);
  if codes is null then raise exception 'A stock role must cover each selected centre and its outlet.' using errcode='22023';end if;
  if exists(select 1 from unnest(array['can_request','can_record_waste','can_receive','can_dispatch']) k where jsonb_typeof(entry->k) is distinct from 'boolean') then raise exception 'Choose each centre task explicitly.' using errcode='22023';end if;
  if ((entry->>'can_request')::boolean or(entry->>'can_record_waste')::boolean) and not(codes&&array['inventory','operations','stock_department','kitchen_manager','bar_lead']) then raise exception 'This role cannot request materials or record waste.' using errcode='22023';end if;
  if(entry->>'can_receive')::boolean and not(codes&&array['inventory','operations','stock_department','kitchen_manager','bar_lead','stock_receiver']) then raise exception 'This role cannot receive transfers.' using errcode='22023';end if;
  if(entry->>'can_dispatch')::boolean and not(codes&&array['inventory','operations','stock_dispatcher']) then raise exception 'This role cannot dispatch stock.' using errcode='22023';end if;
  seen:=array_append(seen,site.id);result:=result||jsonb_build_array(entry);
 end loop;return result;
end $$;
create function public.invite_team_member_with_centres(p_organisation_id uuid,p_request_id uuid,p_email text,p_name text,p_assignments jsonb,p_stock_access jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare packet jsonb;grants jsonb;prior public.team_invitations;
begin
 if not private.pp_team_manage(p_organisation_id) then raise exception 'Team administration required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 grants:=private.pp_invitation_stock(p_organisation_id,private.pp_team_assignments(p_organisation_id,p_assignments),p_stock_access);
 select * into prior from public.team_invitations where organisation_id=p_organisation_id and request_id=p_request_id;
 if found and prior.stock_access<>grants then raise exception 'This request already saved different centre access. Refresh.' using errcode='22023';end if;
 packet:=public.invite_named_team_member(p_organisation_id,p_request_id,p_email,p_name,p_assignments);
 update public.team_invitations set stock_access=grants where id=(packet->>'id')::uuid;
 return packet;
end $$;
create function private.pp_invitation_recipient(invite uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.team_invitations i join auth.users u on u.id=auth.uid() join public.organisations o on o.id=i.organisation_id where i.id=invite and lower(u.email)=i.email and u.email_confirmed_at is not null and i.state='PENDING' and i.expires_at>now() and o.access_state='ACTIVE' and not exists(select 1 from private.platform_admins p where p.user_id in(auth.uid(),i.created_by)) and exists(select 1 from public.organisation_memberships m join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id where m.organisation_id=i.organisation_id and m.user_id=i.created_by and m.status='active' and r.role_code='restaurant_admin' and r.location_id is null));
$$;
create function public.pending_team_invitations() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'organisation_name',o.name,'email',i.email,'expires_at',i.expires_at,'assignments',(select jsonb_agg(r||jsonb_build_object('location_name',l.name)) from jsonb_array_elements(i.assignments) r left join public.locations l on l.organisation_id=i.organisation_id and l.id::text=r->>'location_id'),'stock_centres',coalesce((select jsonb_agg(s.name order by s.name) from jsonb_array_elements(i.stock_access) g join public.stock_locations s on s.organisation_id=i.organisation_id and s.id=(g->>'location_id')::uuid),'[]')) order by i.created_at,i.id),'[]') from public.team_invitations i join public.organisations o on o.id=i.organisation_id where private.pp_invitation_recipient(i.id);
$$;
create function private.pp_accept_invitation(invite uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare invitation public.team_invitations;member_id uuid;roles jsonb;access jsonb;
begin
 select * into invitation from public.team_invitations where id=invite;
 if not found then raise exception 'Invitation unavailable.' using errcode='22023';end if;
 perform 1 from public.organisations where id=invitation.organisation_id for update;
 select * into invitation from public.team_invitations where id=invite for update;
 if invitation.state='ACCEPTED' and invitation.accepted_by=auth.uid() then return invitation.organisation_id;end if;
 if not private.pp_invitation_recipient(invite) then raise exception 'This invitation is unavailable, expired, or belongs to a different verified email.' using errcode='22023';end if;
 roles:=private.pp_team_assignments(invitation.organisation_id,invitation.assignments);access:=private.pp_invitation_stock(invitation.organisation_id,roles,invitation.stock_access);
 if exists(select 1 from public.organisation_memberships where organisation_id=invitation.organisation_id and user_id=auth.uid()) then raise exception 'Your account already has membership here. Ask the administrator to manage existing access.' using errcode='22023';end if;
 insert into public.organisation_memberships(organisation_id,user_id,created_by,display_name) values(invitation.organisation_id,auth.uid(),invitation.created_by,invitation.display_name) returning id into member_id;
 insert into public.membership_roles(organisation_id,membership_id,role_code,location_id,created_by) select invitation.organisation_id,member_id,r->>'role_code',(r->>'location_id')::uuid,invitation.created_by from jsonb_array_elements(roles) r;
 if jsonb_array_length(access)>0 then
  insert into public.stock_member_access(organisation_id,membership_id,mode,revision,updated_by) values(invitation.organisation_id,member_id,'ASSIGNED',1,invitation.created_by);
  insert into public.stock_member_locations(organisation_id,membership_id,location_id,can_request,can_handle,can_approve,can_dispatch,can_receive,can_review_waste,can_record_waste) select invitation.organisation_id,member_id,(g->>'location_id')::uuid,(g->>'can_request')::boolean,false,false,(g->>'can_dispatch')::boolean,(g->>'can_receive')::boolean,false,(g->>'can_record_waste')::boolean from jsonb_array_elements(access) g;
 end if;
 update public.team_invitations set state='ACCEPTED',accepted_by=auth.uid(),accepted_at=now() where id=invite;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(invitation.organisation_id,'TEAM_INVITATION_ACCEPTED',auth.uid(),member_id,jsonb_build_object('invitation_id',invite,'assignments',roles,'stock_access',access));return invitation.organisation_id;
end $$;
create or replace function public.accept_team_invitation(p_token text) returns uuid language plpgsql security definer set search_path='' as $$
declare id uuid;begin
 if p_token is null or p_token!~'^[a-f0-9]{64}$' then raise exception 'This invitation is unavailable or expired.' using errcode='22023';end if;
 select i.id into id from public.team_invitations i where token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex');return private.pp_accept_invitation(id);
end $$;
create function public.accept_pending_team_invitation(p_invitation_id uuid) returns uuid language sql security definer set search_path='' as $$select private.pp_accept_invitation(p_invitation_id)$$;
create function public.team_invitation_email(p_organisation_id uuid,p_invitation_id uuid,p_status text) returns jsonb language plpgsql security definer set search_path='' as $$
declare invitation public.team_invitations;
begin
 if not private.pp_team_manage(p_organisation_id) then raise exception 'Team administration required.' using errcode='42501';end if;
 select * into invitation from public.team_invitations where organisation_id=p_organisation_id and id=p_invitation_id for update;
 if not found or invitation.state<>'PENDING' or invitation.expires_at<=now() then raise exception 'Choose an active pending invitation.' using errcode='22023';end if;
 if p_status is null or p_status not in('REQUESTED','SENT','FAILED') then raise exception 'Choose a valid delivery state.' using errcode='22023';end if;
 if p_status='REQUESTED' and invitation.email_attempt_at>now()-interval '60 seconds' then raise exception 'Wait a minute before resending this invitation email.' using errcode='22023';end if;
 if p_status<>'REQUESTED' and invitation.email_status<>'REQUESTED' then raise exception 'Start an email attempt first.' using errcode='22023';end if;
 update public.team_invitations set email_status=p_status,email_attempt_at=case when p_status='REQUESTED' then clock_timestamp() else email_attempt_at end where id=invitation.id;
 return jsonb_build_object('email',invitation.email,'status',p_status);
end $$;
alter function public.team_directory(uuid,text,integer,integer) rename to pp_team_directory_before_invite_centres;
alter function public.pp_team_directory_before_invite_centres(uuid,text,integer,integer) set schema private;
create function public.team_directory(p_organisation_id uuid,p_search text default '',p_page integer default 1,p_invite_page integer default 1) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare packet jsonb;begin
 packet:=private.pp_team_directory_before_invite_centres(p_organisation_id,p_search,p_page,p_invite_page);
 return packet||jsonb_build_object('invitations',coalesce((select jsonb_agg(j.value||jsonb_build_object('stock_centres',coalesce((select jsonb_agg(s.name order by s.name) from jsonb_array_elements(i.stock_access) g join public.stock_locations s on s.organisation_id=i.organisation_id and s.id=(g->>'location_id')::uuid),'[]'),'email_status',i.email_status) order by j.n) from jsonb_array_elements(packet->'invitations') with ordinality j(value,n) join public.team_invitations i on i.id=(j.value->>'id')::uuid),'[]'));
end $$;
alter function public.inspect_team_invitation(text) rename to pp_inspect_invitation_before_centres;
alter function public.pp_inspect_invitation_before_centres(text) set schema private;
create function public.inspect_team_invitation(p_token text) returns jsonb language plpgsql stable security definer set search_path='' as $$declare packet jsonb;begin
 packet:=private.pp_inspect_invitation_before_centres(p_token);
 return packet||jsonb_build_object('stock_centres',coalesce((select jsonb_agg(s.name order by s.name) from public.team_invitations i cross join lateral jsonb_array_elements(i.stock_access) g join public.stock_locations s on s.organisation_id=i.organisation_id and s.id=(g->>'location_id')::uuid where i.token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex')),'[]'));
end $$;
revoke all on function private.pp_inspect_invitation_before_centres(text) from public,anon,authenticated;
revoke all on function public.inspect_team_invitation(text) from public,anon;
grant execute on function public.inspect_team_invitation(text) to authenticated;
revoke all on function private.pp_team_directory_before_invite_centres(uuid,text,integer,integer),private.pp_invitation_stock(uuid,jsonb,jsonb),private.pp_invitation_recipient(uuid),private.pp_accept_invitation(uuid) from public,anon,authenticated;
revoke all on function public.invite_team_member_with_centres(uuid,uuid,text,text,jsonb,jsonb),public.pending_team_invitations(),public.accept_pending_team_invitation(uuid),public.team_invitation_email(uuid,uuid,text),public.team_directory(uuid,text,integer,integer) from public,anon;
grant execute on function public.invite_team_member_with_centres(uuid,uuid,text,text,jsonb,jsonb),public.pending_team_invitations(),public.accept_pending_team_invitation(uuid),public.team_invitation_email(uuid,uuid,text),public.team_directory(uuid,text,integer,integer) to authenticated;
notify pgrst,'reload schema';
commit;
