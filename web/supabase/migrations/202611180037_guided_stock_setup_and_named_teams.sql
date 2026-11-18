-- Named restaurant teams, one designated processing unit and guided operational logs.
-- Historical centres, immutable baselines and posted stock evidence are retained.
begin;
alter table public.organisation_memberships add column display_name text not null default '' check(length(display_name)<=120);
alter table public.team_invitations add column display_name text not null default '' check(length(display_name)<=120);
alter table public.items add column requires_processing boolean not null default false;
-- Existing approved transformations identify their input materials without guessing other material flags.
update public.items i set requires_processing=true where exists(select 1 from public.processing_standards s where s.organisation_id=i.organisation_id and s.primary_item_id=i.id);
insert into public.roles(code,name) values('kitchen_manager','Kitchen Manager'),('bar_lead','Bar Lead') on conflict(code) do update set name=excluded.name;
create table public.stock_processing_settings(organisation_id uuid primary key references public.organisations(id),centre_id uuid not null,updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now(),foreign key(organisation_id,centre_id) references public.stock_locations(organisation_id,id));
alter table public.stock_processing_settings enable row level security;
revoke all on public.stock_processing_settings from public,anon,authenticated;
create trigger active_processing_settings before insert or update or delete on public.stock_processing_settings for each row execute function private.pp_require_active_restaurant();


create function private.pp_member_label(org uuid,member uuid) returns text language sql stable security definer set search_path='' as $$
 select coalesce(nullif(m.display_name,''),u.email)||coalesce(' / '||(select string_agg(distinct r.name,', ' order by r.name) from public.membership_roles mr join public.roles r on r.code=mr.role_code where mr.organisation_id=m.organisation_id and mr.membership_id=m.id),'') from public.organisation_memberships m join auth.users u on u.id=m.user_id where m.organisation_id=org and m.id=member;
$$;

create or replace function private.pp_team_assignments(target_org uuid, input jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if input is null or jsonb_typeof(input)<>'array' or jsonb_array_length(input) not between 1 and 20 then
  raise exception 'Choose between 1 and 20 role assignments.' using errcode='22023'; end if;
 if exists(select 1 from jsonb_array_elements(input) e where jsonb_typeof(e)<>'object'
  or coalesce(e->>'role_code','') not in ('ceo','finance','procurement','inventory','inventory_manager','stock_department','kitchen_manager','bar_lead','stock_receiver','stock_dispatcher','operations','restaurant_admin')
  or (e->>'role_code'='inventory_manager' and e->>'location_id' is not null)
  or (e->>'location_id' is not null and not exists(select 1 from public.locations l
    where l.organisation_id=target_org and l.id::text=e->>'location_id' and l.is_active))) then
  raise exception 'Choose recognised roles and active locations in this business.' using errcode='22023'; end if;
 select jsonb_agg(v order by v->>'role_code',v->>'location_id') into result from
 (select distinct jsonb_build_object('role_code',e->>'role_code','location_id',e->>'location_id') v
  from jsonb_array_elements(input) e) s;
 return result;
end; $$;

create or replace function private.pp_stock_read(org uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisation_memberships m join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id where m.organisation_id=org and m.user_id=auth.uid() and m.status='active' and r.role_code in ('ceo','restaurant_admin','finance','inventory','inventory_manager','operations','stock_department','kitchen_manager','bar_lead','stock_receiver','stock_dispatcher'));
$$;

create or replace function public.stock_access_directory(p_organisation_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'An Inventory Manager or business-wide Restaurant Administrator must manage department access.' using errcode='42501'; end if;
 select jsonb_build_object('members',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'email',u.email,'display_name',private.pp_member_label(m.organisation_id,m.id),'mode',coalesce(a.mode,case when exists(select 1 from public.membership_roles x where x.organisation_id=m.organisation_id and x.membership_id=m.id and x.role_code in ('stock_department','kitchen_manager','bar_lead','stock_receiver','stock_dispatcher')) then 'ASSIGNED' else 'OUTLET' end),'revision',coalesce(a.revision,0),
  'review_access',exists(select 1 from public.membership_roles r where r.organisation_id=m.organisation_id and r.membership_id=m.id and r.role_code in ('restaurant_admin','inventory_manager','ceo','finance','procurement')),
  'roles',(select jsonb_agg(jsonb_build_object('role_code',r.role_code,'outlet_id',r.location_id,'outlet_name',l.name) order by r.role_code,r.location_id) from public.membership_roles r left join public.locations l on l.organisation_id=r.organisation_id and l.id=r.location_id where r.organisation_id=m.organisation_id and r.membership_id=m.id),
  'assignments',coalesce((select jsonb_agg(jsonb_build_object('location_id',g.location_id,'can_request',g.can_request,'can_handle',g.can_handle,'can_approve',g.can_approve,'can_dispatch',g.can_dispatch,'can_receive',g.can_receive) order by g.location_id) from public.stock_member_locations g where g.organisation_id=m.organisation_id and g.membership_id=m.id),'[]'::jsonb)) order by u.email,m.id)
 from public.organisation_memberships m join auth.users u on u.id=m.user_id left join public.stock_member_access a on a.organisation_id=m.organisation_id and a.membership_id=m.id
 where m.organisation_id=p_organisation_id and m.status='active' and exists(select 1 from public.membership_roles r where r.organisation_id=m.organisation_id and r.membership_id=m.id and r.role_code in ('inventory','operations','stock_department','kitchen_manager','bar_lead','stock_receiver','stock_dispatcher'))),'[]'::jsonb)) into result;
 return result;
end $$;

create or replace function public.save_stock_member_access(p_organisation_id uuid,p_membership_id uuid,p_revision integer,p_mode text,p_assignments jsonb) returns integer
language plpgsql security definer set search_path='' as $$
declare version integer; entry jsonb; site public.stock_locations; seen uuid[]:='{}'; prior jsonb; roles text[];
begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'Inventory Manager or business-wide Restaurant Administrator access is required.' using errcode='42501'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if not exists(select 1 from public.organisation_memberships where organisation_id=p_organisation_id and id=p_membership_id and status='active') then raise exception 'Choose an active member in this business.' using errcode='42501'; end if;
 select array_agg(role_code) into roles from public.membership_roles where organisation_id=p_organisation_id and membership_id=p_membership_id and role_code in ('inventory','operations','stock_department','kitchen_manager','bar_lead','stock_receiver','stock_dispatcher');
 if roles is null then raise exception 'Choose a department or stock-process member.' using errcode='42501'; end if;
 if p_mode is null or p_mode not in ('OUTLET','ASSIGNED') or jsonb_typeof(p_assignments) is distinct from 'array' or jsonb_array_length(p_assignments)>100 or octet_length(p_assignments::text)>32768 or (p_mode='OUTLET' and jsonb_array_length(p_assignments)>0) then raise exception 'Choose up to 100 explicit stock locations.' using errcode='22023'; end if;
 if p_mode='OUTLET' and not (roles&&array['inventory','operations']) then raise exception 'Department and delegated process roles require selected stock locations.' using errcode='22023'; end if;
 select a.revision,to_jsonb(a) into version,prior from public.stock_member_access a where a.organisation_id=p_organisation_id and a.membership_id=p_membership_id;
 version:=coalesce(version,0);if version is distinct from p_revision then raise exception 'Department access changed. Refresh and review the latest assignments before saving.' using errcode='22023'; end if;
 prior:=coalesce(prior,'{}')||jsonb_build_object('assignments',coalesce((select jsonb_agg(to_jsonb(g)) from public.stock_member_locations g where g.organisation_id=p_organisation_id and g.membership_id=p_membership_id),'[]'));
 for entry in select value from jsonb_array_elements(p_assignments) loop
  if jsonb_typeof(entry) is distinct from 'object' or jsonb_typeof(entry->'can_request') is distinct from 'boolean' or jsonb_typeof(entry->'can_handle') is distinct from 'boolean' or jsonb_typeof(entry->'can_approve') is distinct from 'boolean' or (entry?'can_dispatch' and jsonb_typeof(entry->'can_dispatch') is distinct from 'boolean') or (entry?'can_receive' and jsonb_typeof(entry->'can_receive') is distinct from 'boolean') then raise exception 'Choose explicit stock-process permissions.' using errcode='22023'; end if;
  begin select * into site from public.stock_locations where organisation_id=p_organisation_id and id=(entry->>'location_id')::uuid and is_active;exception when invalid_text_representation then raise exception 'Choose a valid stock location.' using errcode='22023';end;
  if site.id is null or site.id=any(seen) then raise exception 'Choose distinct active stock locations in this business.' using errcode='22023'; end if;
  select array_agg(role_code) into roles from public.membership_roles where organisation_id=p_organisation_id and membership_id=p_membership_id and role_code in ('inventory','operations','stock_department','kitchen_manager','bar_lead','stock_receiver','stock_dispatcher') and (location_id is null or (site.outlet_id is not null and location_id=site.outlet_id));
  if roles is null then raise exception 'Stock assignments cannot exceed the current role/outlet scope.' using errcode='22023'; end if;
  if (entry->>'can_request')::boolean and not (roles&&array['inventory','operations','stock_department','kitchen_manager','bar_lead']) then raise exception 'This process role cannot initiate requisitions.' using errcode='22023';end if;
  if (entry->>'can_handle')::boolean and not ('inventory'=any(roles)) then raise exception 'Department/process roles cannot post arbitrary stock adjustments; the Inventory Manager handles posting.' using errcode='22023';end if;
  if (entry->>'can_approve')::boolean and not (roles&&array['inventory','operations']) then raise exception 'Approval authority belongs to the Inventory Manager or the configured source approver.' using errcode='22023';end if;
  if coalesce((entry->>'can_dispatch')::boolean,(entry->>'can_handle')::boolean) and not (roles&&array['inventory','stock_dispatcher']) then raise exception 'Dispatch permission requires a dispatcher process role.' using errcode='22023';end if;
  if coalesce((entry->>'can_receive')::boolean,(entry->>'can_handle')::boolean) and not (roles&&array['inventory','stock_department','kitchen_manager','bar_lead','stock_receiver']) then raise exception 'Receiving permission requires a department or receiver role.' using errcode='22023';end if;
  seen:=array_append(seen,site.id);
 end loop;
 insert into public.stock_member_access(organisation_id,membership_id,mode,revision,updated_by) values(p_organisation_id,p_membership_id,p_mode,version+1,auth.uid()) on conflict(organisation_id,membership_id) do update set mode=excluded.mode,revision=excluded.revision,updated_by=excluded.updated_by,updated_at=clock_timestamp();
 delete from public.stock_member_locations where organisation_id=p_organisation_id and membership_id=p_membership_id;
 insert into public.stock_member_locations(organisation_id,membership_id,location_id,can_request,can_handle,can_approve,can_dispatch,can_receive)
 select p_organisation_id,p_membership_id,(g->>'location_id')::uuid,(g->>'can_request')::boolean,(g->>'can_handle')::boolean,(g->>'can_approve')::boolean,coalesce((g->>'can_dispatch')::boolean,(g->>'can_handle')::boolean),coalesce((g->>'can_receive')::boolean,(g->>'can_handle')::boolean) from jsonb_array_elements(p_assignments) g;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_DEPARTMENT_ACCESS_CHANGED',auth.uid(),p_membership_id,jsonb_build_object('previous',prior,'mode',p_mode,'assignments',p_assignments,'revision',version+1));return version+1;
end $$;

create or replace function private.pp_operational_types(org uuid) returns text[]
language plpgsql stable security definer set search_path='' as $$
declare result text[]:='{}'; stock boolean;
begin
 if private.pp_reference_price_read(org) or private.pp_inventory_access(org) then result:=result||array['PO','GRN']; end if;
 if private.pp_reference_price_read(org) then result:=result||array['INVOICE']; end if;
 if private.pp_sales_read(org) then result:=result||array['SALES']; end if;
 select exists(select 1 from public.organisation_memberships m join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id
  where m.organisation_id=org and m.user_id=auth.uid() and m.status='active' and r.role_code in
  ('ceo','restaurant_admin','finance','inventory_manager','inventory','operations','stock_department','kitchen_manager','bar_lead','stock_receiver','stock_dispatcher')) into stock;
 if stock then result:=result||array['REQUISITIONS','WASTE','COUNTS','CONSUMPTION','PRODUCTION','STOCK_RECEIPTS','MOVEMENTS']; end if;
 return result;
end $$;

create or replace function private.pp_stock_process(org uuid, site uuid, role_name text, capability text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.stock_locations s join public.stock_member_locations g on g.organisation_id=s.organisation_id and g.location_id=s.id
 join public.stock_member_access a on a.organisation_id=g.organisation_id and a.membership_id=g.membership_id and a.mode='ASSIGNED'
 join public.organisation_memberships m on m.organisation_id=g.organisation_id and m.id=g.membership_id and m.user_id=auth.uid() and m.status='active'
 join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id and (r.role_code=role_name or (role_name='stock_department' and r.role_code in ('kitchen_manager','bar_lead'))) and (r.location_id is null or (s.outlet_id is not null and r.location_id=s.outlet_id))
 where s.organisation_id=org and s.id=site and case capability when 'read' then true when 'request' then g.can_request when 'receive' then g.can_receive when 'dispatch' then g.can_dispatch else false end);
$$;

create or replace function public.team_directory(p_organisation_id uuid,p_search text default '',p_page integer default 1,p_invite_page integer default 1)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare members jsonb; invites jsonb; total bigint; invite_total bigint;
begin
 if not private.pp_team_manage(p_organisation_id) then raise exception 'Team administration is restricted.' using errcode='42501'; end if;
 if p_search is null or length(p_search)>120 or p_page is null or p_page not between 1 and 100000 or p_invite_page is null or p_invite_page not between 1 and 100000 then
 raise exception 'Check the team search and page.' using errcode='22023'; end if;
 select count(*) into total from public.organisation_memberships m join auth.users u on u.id=m.user_id
 where m.organisation_id=p_organisation_id and strpos(lower(coalesce(u.email,'')||' '||m.display_name),lower(trim(p_search)))>0;
 select coalesce(jsonb_agg(v order by v->>'email'),'[]') into members from (
 select jsonb_build_object('id',m.id,'user_id',m.user_id,'email',u.email,'display_name',m.display_name,'status',m.status,'updated_at',m.updated_at,
 'is_owner',o.owner_id=m.user_id,'is_self',m.user_id=auth.uid(),
 'assignments',coalesce((select jsonb_agg(jsonb_build_object('role_code',r.role_code,'location_id',r.location_id,'location_name',l.name) order by r.role_code,l.name)
 from public.membership_roles r left join public.locations l on l.id=r.location_id and l.organisation_id=r.organisation_id
 where r.membership_id=m.id and r.organisation_id=m.organisation_id),'[]')) v
 from public.organisation_memberships m join auth.users u on u.id=m.user_id join public.organisations o on o.id=m.organisation_id
 where m.organisation_id=p_organisation_id and strpos(lower(coalesce(u.email,'')||' '||m.display_name),lower(trim(p_search)))>0
 order by u.email,m.id limit 25 offset(p_page-1)*25) s;
 select count(*) into invite_total from public.team_invitations where organisation_id=p_organisation_id;
 select coalesce(jsonb_agg(v order by created_at desc),'[]') into invites from (
 select created_at,jsonb_build_object('id',id,'email',email,'display_name',display_name,'state',case when state='PENDING' and expires_at<=now() then 'EXPIRED' else state end,
 'created_at',created_at,'expires_at',expires_at,'assignments',assignments) v
 from public.team_invitations where organisation_id=p_organisation_id order by created_at desc,id limit 25 offset(p_invite_page-1)*25) s;
 return jsonb_build_object('members',members,'member_total',total,'invitations',invites,'invitation_total',invite_total);
end; $$;

create or replace function public.accept_team_invitation(p_token text)
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
 insert into public.organisation_memberships(organisation_id,user_id,created_by,display_name) values(invitation.organisation_id,auth.uid(),invitation.created_by,invitation.display_name) returning id into member_id;
 insert into public.membership_roles(organisation_id,membership_id,role_code,location_id,created_by)
 select invitation.organisation_id,member_id,e->>'role_code',(e->>'location_id')::uuid,invitation.created_by from jsonb_array_elements(grants) e;
 update public.team_invitations set state='ACCEPTED',accepted_by=auth.uid(),accepted_at=now() where id=invitation.id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details)
 values(invitation.organisation_id,'TEAM_INVITATION_ACCEPTED',auth.uid(),member_id,jsonb_build_object('invitation_id',invitation.id,'assignments',grants));
 return invitation.organisation_id;
end; $$;

create or replace function public.save_material_setup(p_organisation_id uuid,p_value jsonb) returns uuid language plpgsql security definer set search_path='' as $$declare saved_id uuid;begin
 saved_id:=public.save_catalogue_material(p_organisation_id,nullif(p_value->>'id','')::uuid,p_value->>'code',p_value->>'name',p_value->>'item_type',coalesce(p_value->>'category',''),nullif(p_value->>'base_uom_id','')::uuid,(p_value->>'stock_tracked')::boolean,(p_value->>'is_active')::boolean);
 perform public.save_setup_profile(p_organisation_id,'MATERIAL',saved_id,nullif(p_value->>'location_id','')::uuid,null,'',coalesce((p_value->>'weekly_count_required')::boolean,false),coalesce(p_value->>'supply_class','PURCHASED'));update public.items set requires_processing=coalesce((p_value->>'requires_processing')::boolean,requires_processing) where organisation_id=p_organisation_id and public.items.id=saved_id;return saved_id;
end $$;

create or replace function public.save_stock_centre(p_organisation_id uuid,p_value jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare site uuid:=nullif(p_value->>'id','')::uuid;responsible uuid:=nullif(p_value->>'responsible','')::uuid;enabled boolean:=coalesce((p_value->>'processing_enabled')::boolean,false);old public.stock_locations;
begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'Stock setup access required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if enabled is null or octet_length(p_value::text)>8192 or p_value->>'code'!~'^[A-Z0-9][A-Z0-9_-]{0,39}$' or length(trim(coalesce(p_value->>'name',''))) not between 1 and 120 or p_value->>'kind' not in ('WAREHOUSE','STORE','KITCHEN','BAR','PRODUCTION') then raise exception 'Enter a centre code, name and storage type.' using errcode='22023';end if;
 if responsible is not null and not exists(select 1 from public.organisation_memberships where organisation_id=p_organisation_id and id=responsible and status='active') then raise exception 'Choose an active responsible member from this restaurant.' using errcode='22023';end if;
 if responsible is null then raise exception 'Assign a responsible member to every stock centre.' using errcode='22023';end if;
 perform private.pp_setup_location(p_organisation_id,nullif(p_value->>'outlet_id','')::uuid);
 if site is null then
 if exists(select 1 from public.stock_locations where organisation_id=p_organisation_id and code=p_value->>'code') then raise exception 'That stock centre code already exists.' using errcode='22023';end if;
 insert into public.stock_locations(organisation_id,code,name,kind,outlet_id,department,responsible_membership_id) values(p_organisation_id,p_value->>'code',trim(p_value->>'name'),p_value->>'kind',nullif(p_value->>'outlet_id','')::uuid,trim(coalesce(p_value->>'department','')),responsible) returning id into site;
 else
  select * into old from public.stock_locations where organisation_id=p_organisation_id and id=site for update;
  if not found or old.code is distinct from p_value->>'code' then raise exception 'Choose an existing centre; its code cannot change.' using errcode='22023';end if;
  if (old.outlet_id is distinct from nullif(p_value->>'outlet_id','')::uuid or old.kind is distinct from p_value->>'kind') and exists(select 1 from public.stock_documents where organisation_id=p_organisation_id and(source_id=site or destination_id=site)) then raise exception 'A centre with movement history must keep its outlet and storage type. Create a new centre instead.' using errcode='22023';end if;
  update public.stock_locations set name=trim(p_value->>'name'),kind=p_value->>'kind',outlet_id=nullif(p_value->>'outlet_id','')::uuid,department=trim(coalesce(p_value->>'department','')) where organisation_id=p_organisation_id and id=site;
 end if;
 if exists(select 1 from public.stock_processing_settings where organisation_id=p_organisation_id) then enabled:=exists(select 1 from public.stock_processing_settings where organisation_id=p_organisation_id and centre_id=site);end if;
 update public.stock_locations set processing_enabled=enabled,responsible_membership_id=responsible where organisation_id=p_organisation_id and id=site;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_CENTRE_SETUP',auth.uid(),site,jsonb_build_object('processing_enabled',enabled,'responsible',responsible));return site;
end $$;

create or replace function public.processing_setup(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock setup access required.' using errcode='42501';end if;
 select jsonb_build_object('processing_centre_id',(select centre_id from public.stock_processing_settings where organisation_id=p_organisation_id),'manage',private.pp_stock_manager(p_organisation_id),'sites',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('responsible_name',private.pp_member_label(m.organisation_id,m.id),'responsible_active',m.status='active','request',private.pp_stock_site(s.organisation_id,s.id,'request')) order by s.name) from public.stock_locations s left join public.organisation_memberships m on m.organisation_id=s.organisation_id and m.id=s.responsible_membership_id left join auth.users u on u.id=m.user_id where s.organisation_id=p_organisation_id and private.pp_stock_site(s.organisation_id,s.id,'read')),'[]'::jsonb),
 'members',case when private.pp_stock_manager(p_organisation_id) then coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'name',private.pp_member_label(m.organisation_id,m.id)) order by u.email) from public.organisation_memberships m join auth.users u on u.id=m.user_id where m.organisation_id=p_organisation_id and m.status='active'),'[]'::jsonb) else '[]'::jsonb end,
 'standards',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('recipe_name',v.name,'output_name',i.name,'output_unit',u.code,'primary_name',p.name,'primary_unit',pu.code,'site_ids',(select jsonb_agg(site_id) from public.processing_standard_sites where organisation_id=s.organisation_id and standard_id=s.id)) order by v.name,s.revision desc)
 from public.processing_standards s join public.recipe_versions v on v.organisation_id=s.organisation_id and v.id=s.recipe_version_id join public.items i on i.organisation_id=s.organisation_id and i.id=s.output_item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id join public.items p on p.organisation_id=s.organisation_id and p.id=s.primary_item_id join public.units_of_measure pu on pu.organisation_id=p.organisation_id and pu.id=p.base_uom_id
 where s.organisation_id=p_organisation_id and s.is_active and(private.pp_stock_manager(p_organisation_id) or exists(select 1 from public.processing_standard_sites ss where ss.organisation_id=s.organisation_id and ss.standard_id=s.id and private.pp_stock_site(p_organisation_id,ss.site_id,'read')))),'[]'::jsonb)) into result;return result;
end $$;

create or replace function public.save_processing_standard(p_organisation_id uuid,p_request_id uuid,p_value jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare prior public.processing_standards;selected_version uuid:=(p_value->>'recipe_version_id')::uuid;primary_item uuid:=(p_value->>'primary_item_id')::uuid;inputs jsonb;primary_qty numeric;output_item uuid;output_qty numeric;site uuid;sites uuid[];result uuid;rev integer;hash text:=md5(p_value::text);tolerance numeric;piece_weight numeric;trim_weight numeric;primary_weight numeric;
begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'Processing setup access required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if p_request_id is null or octet_length(p_value::text)>32768 then raise exception 'Refresh processing setup.' using errcode='22023';end if;
 select * into prior from public.processing_standards where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then if prior.input_hash<>hash or prior.created_by<>auth.uid() then raise exception 'This setup request was already used.' using errcode='22023';end if;return prior.id;end if;
 inputs:=private.pp_processing_inputs(p_organisation_id,selected_version);
 select (value->>'quantity')::numeric into primary_qty from jsonb_array_elements(inputs) where value->>'item_id'=primary_item::text;
 select b.item_id,o.quantity*ou.canonical_factor/iu.canonical_factor into output_item,output_qty from public.stock_recipe_bindings b join public.recipe_outputs o on o.organisation_id=b.organisation_id and o.recipe_version_id=b.recipe_version_id join public.units_of_measure ou on ou.organisation_id=o.organisation_id and ou.id=o.uom_id join public.items i on i.organisation_id=b.organisation_id and i.id=b.item_id join public.units_of_measure iu on iu.organisation_id=i.organisation_id and iu.id=i.base_uom_id where b.organisation_id=p_organisation_id and b.recipe_version_id=selected_version;
 if primary_qty is null or output_item is null or primary_qty<=0 or output_qty<=0 or output_item=primary_item or output_qty<>round(output_qty,12) then raise exception 'Link the produced SKU and choose a main input from this recipe.' using errcode='22023';end if;
 tolerance:=private.pp_stock_number(p_value->>'tolerance_percent',true);
 if tolerance>100 or tolerance<>round(tolerance,6) or length(trim(coalesce(p_value->>'output_spec',''))) not between 1 and 1000 then raise exception 'Describe the output size/specification and enter a tolerance from 0 to 100 percent.' using errcode='22023';end if;
 if jsonb_typeof(p_value->'site_ids') is distinct from 'array' or jsonb_array_length(p_value->'site_ids') not between 1 and 50 then raise exception 'Choose at least one processing centre.' using errcode='22023';end if;
 select array_agg(distinct value::uuid) into sites from jsonb_array_elements_text(p_value->'site_ids');
 if exists(select 1 from public.stock_processing_settings where organisation_id=p_organisation_id) and (cardinality(sites)<>1 or not exists(select 1 from public.stock_processing_settings where organisation_id=p_organisation_id and centre_id=sites[1])) then raise exception 'Use the designated processing unit from Stock centres setup.' using errcode='22023';end if;
 foreach site in array sites loop
  if not exists(select 1 from public.stock_locations s join public.organisation_memberships m on m.organisation_id=s.organisation_id and m.id=s.responsible_membership_id and m.status='active' where s.organisation_id=p_organisation_id and s.id=site and s.is_active and s.processing_enabled) then raise exception 'Every permitted centre must be active, allow processing and have an active responsible member.' using errcode='22023';end if;
  if exists(select 1 from public.stock_locations c join public.items i on i.organisation_id=c.organisation_id and(i.id=output_item or exists(select 1 from jsonb_array_elements(inputs) l where l->>'item_id'=i.id::text)) where c.organisation_id=p_organisation_id and c.id=site and c.outlet_id is not null and i.location_id is not null and c.outlet_id<>i.location_id) then raise exception 'A permitted centre is outside the scope of a recipe input or output SKU.' using errcode='22023';end if;
 end loop;
 piece_weight:=case when nullif(p_value->>'target_piece_weight_kg','') is not null then private.pp_stock_number(p_value->>'target_piece_weight_kg') end;
 trim_weight:=case when nullif(p_value->>'expected_trim_kg','') is not null then private.pp_stock_number(p_value->>'expected_trim_kg',true) end;
 if piece_weight<>round(piece_weight,6) or trim_weight<>round(trim_weight,6) then raise exception 'Use up to six decimal places for baseline weights in KG.' using errcode='22023';end if;
 if piece_weight is not null and not exists(select 1 from public.items i join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id where i.organisation_id=p_organisation_id and i.id=output_item and u.dimension='COUNT') then raise exception 'A target piece weight applies only to count-based output SKUs.' using errcode='22023';end if;
 if trim_weight is not null then
  select primary_qty*u.canonical_factor/kg.canonical_factor into primary_weight from public.items i join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id and u.dimension='MASS' join public.units_of_measure kg on kg.organisation_id=i.organisation_id and kg.code='KG' where i.organisation_id=p_organisation_id and i.id=primary_item;
  if primary_weight is null or trim_weight>primary_weight then raise exception 'Expected trim in KG requires a weight-based main input and cannot exceed that input.' using errcode='22023';end if;
 end if;
 update public.processing_standards set is_active=false where organisation_id=p_organisation_id and is_active and recipe_version_id in(select rv.id from public.recipe_versions rv where rv.organisation_id=p_organisation_id and rv.recipe_id=(select recipe_id from public.recipe_versions where organisation_id=p_organisation_id and id=selected_version));
 select coalesce(max(revision),0)+1 into rev from public.processing_standards where organisation_id=p_organisation_id and recipe_version_id=selected_version;
 insert into public.processing_standards(organisation_id,recipe_version_id,revision,request_id,input_hash,output_item_id,primary_item_id,primary_quantity,expected_output,inputs,output_spec,target_piece_weight_kg,expected_trim_kg,tolerance_percent,created_by)
 values(p_organisation_id,selected_version,rev,p_request_id,hash,output_item,primary_item,primary_qty,output_qty,inputs,trim(p_value->>'output_spec'),piece_weight,trim_weight,tolerance,auth.uid()) returning id into result;
 insert into public.processing_standard_sites select p_organisation_id,result,unnest(sites);
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'PROCESSING_STANDARD',auth.uid(),result,jsonb_build_object('recipe_version_id',selected_version,'revision',rev));return result;
end $$;

create function public.save_member_name(p_organisation_id uuid,p_membership_id uuid,p_name text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.organisations where id=p_organisation_id for update;
 if not exists(select 1 from public.organisation_memberships where organisation_id=p_organisation_id and id=p_membership_id and status='active' and (user_id=auth.uid() or private.pp_team_manage(p_organisation_id))) then raise exception 'An active member or restaurant administrator is required.' using errcode='42501';end if;
 if p_name is null or length(trim(p_name)) not between 1 and 120 or p_name ~ '[[:cntrl:]]' then raise exception 'Enter a name of up to 120 characters.' using errcode='22023';end if;
 update public.organisation_memberships set display_name=trim(p_name) where organisation_id=p_organisation_id and id=p_membership_id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id) values(p_organisation_id,'MEMBER_NAME_UPDATED',auth.uid(),p_membership_id);
end $$;
create function public.invite_named_team_member(p_organisation_id uuid,p_request_id uuid,p_email text,p_name text,p_assignments jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;prior_name text;begin
 if not private.pp_team_manage(p_organisation_id) then raise exception 'Team administration is restricted.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if p_name is null or length(trim(p_name)) not between 1 and 120 or p_name ~ '[[:cntrl:]]' then raise exception 'Enter the colleague name (up to 120 characters).' using errcode='22023';end if;
 select display_name into prior_name from public.team_invitations where organisation_id=p_organisation_id and request_id=p_request_id;
 if found and prior_name is distinct from trim(p_name) then raise exception 'This invitation request was already used. Refresh before changing it.' using errcode='22023';end if;
 result:=public.create_team_invitation(p_organisation_id,p_request_id,p_email,p_assignments);
 update public.team_invitations set display_name=trim(p_name) where organisation_id=p_organisation_id and id=(result->>'id')::uuid;
 return result;
end $$;
create function public.set_processing_unit(p_organisation_id uuid,p_centre_id uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare old_site uuid;begin
 if not private.pp_team_manage(p_organisation_id) then raise exception 'Restaurant administrator access is required to designate the processing unit.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if not exists(select 1 from public.stock_locations s join public.organisation_memberships m on m.organisation_id=s.organisation_id and m.id=s.responsible_membership_id and m.status='active' where s.organisation_id=p_organisation_id and s.id=p_centre_id and s.is_active) then raise exception 'Choose an active stock centre with a responsible member.' using errcode='22023';end if;
 if exists(select 1 from public.stock_locations s where s.organisation_id=p_organisation_id and s.is_active and not exists(select 1 from public.organisation_memberships m where m.organisation_id=s.organisation_id and m.id=s.responsible_membership_id and m.status='active')) then raise exception 'Assign an active responsible member to every active stock centre first.' using errcode='22023';end if;
 select centre_id into old_site from public.stock_processing_settings where organisation_id=p_organisation_id;
 if old_site is not distinct from p_centre_id then return p_centre_id;end if;
 if exists(select 1 from public.stock_documents where organisation_id=p_organisation_id and kind='PRODUCTION' and state in ('REQUESTED','APPROVED')) then raise exception 'Finish or cancel pending processing batches before changing the processing unit.' using errcode='22023';end if;
 insert into public.stock_processing_settings values(p_organisation_id,p_centre_id,auth.uid(),now()) on conflict(organisation_id) do update set centre_id=excluded.centre_id,updated_by=excluded.updated_by,updated_at=clock_timestamp();
 update public.stock_locations set processing_enabled=(id=p_centre_id) where organisation_id=p_organisation_id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'PROCESSING_UNIT_SELECTED',auth.uid(),p_centre_id,jsonb_build_object('previous',old_site));return p_centre_id;
end $$;
-- Once a restaurant adopts designated-unit setup, all active centres keep accountable owners.
-- Existing unconfigured restaurants remain visible and are prompted to complete setup.
create function private.pp_stock_centre_accountability() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from public.stock_processing_settings where organisation_id=new.organisation_id) then
 if new.is_active and not exists(select 1 from public.organisation_memberships where organisation_id=new.organisation_id and id=new.responsible_membership_id and status='active') then raise exception 'Every active stock centre requires an active responsible member.' using errcode='22023';end if;
 if new.processing_enabled and not exists(select 1 from public.stock_processing_settings where organisation_id=new.organisation_id and centre_id=new.id) then raise exception 'Only the designated processing unit may process materials.' using errcode='22023';end if;
 end if;return new;
end $$;
create trigger stock_centre_accountability before insert or update on public.stock_locations for each row execute function private.pp_stock_centre_accountability();
-- One guided baseline save publishes a versioned processing recipe, binds its SKU and saves the approved yield atomically.
create function public.save_material_processing_baseline(p_organisation_id uuid,p_request_id uuid,p_value jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare source public.items;produced public.items;site uuid;version_id uuid;result_id uuid;prior private.setup_requests;digest text:=md5(p_value::text);recipe_id uuid;begin
 if not private.pp_team_manage(p_organisation_id) or not private.pp_recipe_write(p_organisation_id) then raise exception 'Restaurant administrator access is required for processing master data.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if p_request_id is null or p_value is null or octet_length(p_value::text)>8192 then raise exception 'Refresh and complete the processing baseline.' using errcode='22023';end if;
 select * into prior from private.setup_requests where organisation_id=p_organisation_id and request_id=p_request_id and kind='PROCESSING';
 if found then if prior.input_hash<>digest then raise exception 'Refresh before saving changed baseline details.' using errcode='22023';end if;return prior.result_id;end if;
 select centre_id into site from public.stock_processing_settings where organisation_id=p_organisation_id;
 if site is null then raise exception 'Choose the business processing unit in Stock centres first.' using errcode='22023';end if;
 select * into source from public.items where organisation_id=p_organisation_id and id=(p_value->>'input_item_id')::uuid and is_active and stock_tracked and requires_processing and base_uom_id is not null;
 select * into produced from public.items where organisation_id=p_organisation_id and id=(p_value->>'output_item_id')::uuid and is_active and stock_tracked and item_type in ('SEMI_FINISHED','FINISHED') and supply_class in ('PROCESSED','BOTH') and base_uom_id is not null;
 if source.id is null or produced.id is null or source.id=produced.id then raise exception 'Choose an input marked Requires processing and a different tracked processed output SKU with a base unit.' using errcode='22023';end if;
 -- Revisions use the existing output recipe family; never create competing output cost sources.
 select distinct rv.recipe_id into recipe_id from public.stock_recipe_bindings b join public.recipe_versions rv on rv.organisation_id=b.organisation_id and rv.id=b.recipe_version_id where b.organisation_id=p_organisation_id and b.item_id=produced.id;
 version_id:=public.publish_recipe_setup(p_organisation_id,p_request_id,jsonb_build_object('recipe_id',recipe_id,'code',p_value->>'code','name',p_value->>'name','recipe_type','SUB_RECIPE','effective_from',p_value->>'effective_from','yield_quantity',p_value->>'output_quantity','yield_uom_id',produced.base_uom_id,'location_id',source.location_id,'notes','Material processing baseline'),jsonb_build_array(jsonb_build_object('kind','ITEM','target_id',source.id,'quantity',p_value->>'input_quantity','uom_id',source.base_uom_id)));
 perform public.save_stock_configuration(p_organisation_id,'BINDING',jsonb_build_object('recipe_version_id',version_id,'item_id',produced.id));
 result_id:=public.save_processing_standard(p_organisation_id,p_request_id,jsonb_build_object('recipe_version_id',version_id,'primary_item_id',source.id,'output_spec',p_value->>'output_spec','tolerance_percent',p_value->>'tolerance_percent','site_ids',jsonb_build_array(site),'target_piece_weight_kg',p_value->>'target_piece_weight_kg','expected_trim_kg',p_value->>'expected_trim_kg'));
 insert into private.setup_requests values(p_organisation_id,p_request_id,'PROCESSING',digest,result_id);return result_id;
end $$;
revoke all on function private.pp_member_label(uuid,uuid),private.pp_stock_centre_accountability() from public,anon,authenticated;
revoke all on function public.save_member_name(uuid,uuid,text),public.invite_named_team_member(uuid,uuid,text,text,jsonb),public.set_processing_unit(uuid,uuid),public.save_material_processing_baseline(uuid,uuid,jsonb) from public,anon;
grant execute on function public.save_member_name(uuid,uuid,text),public.invite_named_team_member(uuid,uuid,text,text,jsonb),public.set_processing_unit(uuid,uuid),public.save_material_processing_baseline(uuid,uuid,jsonb) to authenticated;
create or replace function public.processing_activity(p_organisation_id uuid,p_site_id uuid,p_from date,p_to date,p_kind text default 'BATCHES',p_page integer default 1,p_state text default 'ALL') returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock history access required.' using errcode='42501';end if;
 if p_site_id is not null and not private.pp_stock_site(p_organisation_id,p_site_id,'read') then raise exception 'Stock centre unavailable.' using errcode='42501';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>366 or p_kind is null or p_kind not in ('BATCHES','WASTE','LOSSES') or p_page is null or p_page not between 1 and 100000 or p_state is null or p_state not in ('ALL','REQUESTED','APPROVED','POSTED','CANCELLED','REJECTED') then raise exception 'Choose dates within 367 days, a record type and a valid page.' using errcode='22023';end if;
 if p_kind='BATCHES' then
 with rows as materialized(select d.id,d.reference,d.document_date,d.state,d.source_id,s.name site,v.name recipe_name,i.name output_name,u.code output_unit,b.*,st.inputs standard_inputs,st.primary_quantity,st.expected_output baseline_output,st.output_spec,st.target_piece_weight_kg,st.expected_trim_kg,st.tolerance_percent,d.lines actual_inputs,
 (select jsonb_agg(jsonb_build_object('item_id',w.item_id,'name',wi.name,'unit',wu.code,'quantity',w.quantity::text,'reason',w.reason)) from public.processing_waste w join public.items wi on wi.organisation_id=w.organisation_id and wi.id=w.item_id join public.units_of_measure wu on wu.organisation_id=wi.organisation_id and wu.id=wi.base_uom_id where w.organisation_id=d.organisation_id and w.document_id=d.id) waste,
 creator.email recorded_by,reviewer.email reviewed_by,poster.email posted_by,
 case when private.pp_reference_price_read(p_organisation_id) then cost.value end costs
 from public.stock_documents d join public.processing_batches b on b.organisation_id=d.organisation_id and b.document_id=d.id join public.processing_standards st on st.organisation_id=b.organisation_id and st.id=b.standard_id join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id join public.recipe_versions v on v.organisation_id=st.organisation_id and v.id=st.recipe_version_id join public.items i on i.organisation_id=st.organisation_id and i.id=st.output_item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id
 left join private.processing_batch_costs cost on cost.organisation_id=d.organisation_id and cost.document_id=d.id left join auth.users creator on creator.id=d.created_by left join auth.users reviewer on reviewer.id=d.approved_by left join auth.users poster on poster.id=d.completed_by
 where d.organisation_id=p_organisation_id and d.document_date between p_from and p_to and(p_state='ALL' or d.state=p_state) and(p_site_id is null or d.source_id=p_site_id) and private.pp_stock_doc_read(p_organisation_id,d.id)),paged as(select * from rows order by document_date desc,id limit 10 offset(p_page-1)*10)
 select jsonb_build_object('total',(select count(*) from rows),'outside_tolerance',(select count(*) from rows where state='POSTED' and outside_tolerance),'rows',coalesce((select jsonb_agg(to_jsonb(p) order by document_date desc,id) from paged p),'[]'::jsonb)) into result;
 else
 with rows as materialized(
 select d.id,d.reference,d.document_date,d.state,s.id site_id,s.name site,i.id item_id,i.name material,u.code unit,w.quantity::text quantity,w.reason,true included_in_production from public.processing_waste w join public.stock_documents d on d.organisation_id=w.organisation_id and d.id=w.document_id join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id join public.items i on i.organisation_id=w.organisation_id and i.id=w.item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id
 where p_kind='WASTE' and d.organisation_id=p_organisation_id and d.document_date between p_from and p_to and(p_state='ALL' or d.state=p_state) and(p_site_id is null or d.source_id=p_site_id) and private.pp_stock_doc_read(p_organisation_id,d.id)
 union all
 select d.id,d.reference,d.document_date,d.state,s.id,s.name,i.id,i.name,u.code,l->>'quantity',d.note,false from public.stock_documents d cross join lateral jsonb_array_elements(d.lines) l join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id join public.items i on i.organisation_id=d.organisation_id and i.id=(l->>'item_id')::uuid join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id
 where d.organisation_id=p_organisation_id and d.kind='WASTE' and d.document_date between p_from and p_to and(p_state='ALL' or d.state=p_state) and(p_site_id is null or d.source_id=p_site_id) and private.pp_stock_doc_read(p_organisation_id,d.id)),paged as(select * from rows order by document_date desc,id,item_id limit 10 offset(p_page-1)*10)
 select jsonb_build_object('total',(select count(*) from rows),'rows',coalesce((select jsonb_agg(to_jsonb(p) order by document_date desc,id,item_id) from paged p),'[]'::jsonb)) into result;
 end if;return result;
end $$;

alter function private.pp_setup_progress(uuid) rename to pp_setup_before_guided_stock;
revoke all on function private.pp_setup_before_guided_stock(uuid) from public,anon,authenticated;
create function private.pp_setup_progress(org uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;stages jsonb;begin
 result:=private.pp_setup_before_guided_stock(org);
 select coalesce(jsonb_agg(value),'[]'::jsonb) into stages from jsonb_array_elements(result->'stages') where value->>'name'<>'Processing baselines';
 if exists(select 1 from public.items where organisation_id=org and is_active and(requires_processing or supply_class='PROCESSED')) then
 stages:=stages||jsonb_build_array(jsonb_build_object('name','Processing baselines','ready',exists(select 1 from public.stock_processing_settings where organisation_id=org) and not exists(select 1 from public.items i where i.organisation_id=org and i.is_active and i.requires_processing and not exists(select 1 from public.processing_standards ps join public.processing_standard_sites ss on ss.organisation_id=ps.organisation_id and ss.standard_id=ps.id join public.stock_processing_settings cfg on cfg.organisation_id=ss.organisation_id and cfg.centre_id=ss.site_id where ps.organisation_id=org and ps.primary_item_id=i.id and ps.is_active)),'path','/workspace/setup/production','detail','Designated processing unit and expected input-to-output yields'));
 end if;
 return result||jsonb_build_object('stages',stages,'total',jsonb_array_length(stages),'completed',(select count(*) from jsonb_array_elements(stages)s where(s->>'ready')::boolean));
end $$;
revoke all on function private.pp_setup_progress(uuid) from public,anon,authenticated;
create function private.pp_keep_centre_owner_active() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.status<>'active' and exists(select 1 from public.stock_processing_settings where organisation_id=new.organisation_id) and exists(select 1 from public.stock_locations where organisation_id=new.organisation_id and responsible_membership_id=new.id and is_active) then raise exception 'Reassign this member stock centres before deactivating their account.' using errcode='22023';end if;return new;
end $$;
create trigger keep_centre_owner_active before update of status on public.organisation_memberships for each row execute function private.pp_keep_centre_owner_active();
revoke all on function private.pp_keep_centre_owner_active() from public,anon,authenticated;

create or replace function public.request_stock_document(p_organisation_id uuid,p_request_id uuid,p_document jsonb,p_lines jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid:=gen_random_uuid(); prior public.stock_documents; src public.stock_locations; dst public.stock_locations; route public.stock_routes;
 kind text:=p_document->>'kind'; day date; digest text; lines jsonb; output jsonb; rec public.goods_receipts; po public.purchase_orders;
 r record; qty numeric; planned numeric; actual numeric; base_factor numeric; bound uuid; out_qty numeric; expected numeric; fingerprint text; standard public.processing_standards; actual_lines jsonb; waste jsonb; entry jsonb; primary_actual numeric; expected_base numeric; deviation numeric; outside boolean; reason text; usable numeric; input_mass numeric; waste_mass numeric; mass_balance numeric; measurable boolean;
begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock access is required.' using errcode='42501'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if p_request_id is null or octet_length(coalesce(p_document::text,''))>65536 then raise exception 'Refresh and enter a valid stock request.' using errcode='22023'; end if;
 digest:=md5(jsonb_build_array(p_document,p_lines)::text);
 select * into prior from public.stock_documents where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then
  if prior.input_hash<>digest or prior.created_by<>auth.uid() then raise exception 'This request was already used. Refresh before creating another.' using errcode='22023'; end if;
  return prior.id;
 end if;
 if kind not in ('OPENING','GRN','DIRECT_RECEIPT','TRANSFER','ISSUE','COUNT','WASTE','CONSUMPTION','PRODUCTION') or kind is null then raise exception 'Choose a stock movement type.' using errcode='22023'; end if;
 begin day:=(p_document->>'date')::date; exception when others then raise exception 'Choose a valid movement date.' using errcode='22023'; end;
 if day is null or day>(select(now() at time zone time_zone)::date from public.organisations where id=p_organisation_id) or length(trim(coalesce(p_document->>'note',''))) not between 1 and 1000 then raise exception 'Choose a date that is not in the future and enter the source/reason.' using errcode='22023'; end if;
 select * into src from public.stock_locations where organisation_id=p_organisation_id and id=nullif(p_document->>'source_id','')::uuid and is_active;
 select * into dst from public.stock_locations where organisation_id=p_organisation_id and id=nullif(p_document->>'destination_id','')::uuid and is_active;
 if kind in ('TRANSFER','ISSUE') then
  select * into route from public.stock_routes where organisation_id=p_organisation_id and id=nullif(p_document->>'route_id','')::uuid and is_active;
  if route.id is null or route.kind<>kind then raise exception 'Choose a configured active route for this movement type.' using errcode='22023'; end if;
  select * into src from public.stock_locations where organisation_id=p_organisation_id and id=route.source_id and is_active;
  select * into dst from public.stock_locations where organisation_id=p_organisation_id and id=route.destination_id and is_active;
  if src.id is null or dst.id is null or not (private.pp_stock_site(p_organisation_id,dst.id,'request') or private.pp_stock_site(p_organisation_id,src.id,'request')) then raise exception 'Request access is required at the receiving department, or Inventory access at the source.' using errcode='42501'; end if;
 elsif kind in ('OPENING','GRN','DIRECT_RECEIPT') then
  src.id:=null;
  if dst.id is null or not (private.pp_stock_site(p_organisation_id,dst.id,'inventory') and private.pp_stock_site(p_organisation_id,dst.id,'request')) then raise exception 'Inventory access is required at the receiving stock location.' using errcode='42501'; end if;
 else
  dst.id:=null;
  if src.id is null or not private.pp_stock_site(p_organisation_id,src.id,'request') then raise exception 'Inventory or Operations access is required at this stock location.' using errcode='42501'; end if;
 end if;
 if kind='GRN' then
  select * into rec from public.goods_receipts where organisation_id=p_organisation_id and id=nullif(p_document->>'receipt_id','')::uuid;
  select * into po from public.purchase_orders where organisation_id=p_organisation_id and id=rec.order_id;
  if rec.id is null or private.pp_receipt_voided(p_organisation_id,rec.id) or exists(select 1 from public.goods_receipt_void_requests where organisation_id=p_organisation_id and receipt_id=rec.id and state='PENDING')
   or not private.pp_inventory_access(p_organisation_id,po.location_id) or (dst.outlet_id is not null and dst.outlet_id<>po.location_id) or day<rec.received_on then raise exception 'Choose an active GRN for this outlet (or a central store), with no pending void, on or before the stock date.' using errcode='22023'; end if;
  if exists(select 1 from public.stock_documents where organisation_id=p_organisation_id and receipt_id=rec.id and state not in ('CANCELLED','REJECTED')) then raise exception 'This GRN already has a stock request.' using errcode='22023'; end if;
  select jsonb_agg(jsonb_build_object('item_id',q.item_id,'quantity',q.qty::text)) into lines from (
   select l.item_id,sum(g.accepted*(l.payload->>'conversion_factor')::numeric) qty from public.goods_receipt_lines g join public.purchase_order_lines l on l.organisation_id=g.organisation_id and l.order_id=g.order_id and l.id=g.order_line_id
   where g.organisation_id=p_organisation_id and g.receipt_id=rec.id and g.accepted>0 group by l.item_id
  ) q;
  lines:=private.pp_stock_lines(p_organisation_id,lines);
 elsif kind='PRODUCTION' then
  if nullif(p_document->>'processing_standard_id','') is not null then
   select * into standard from public.processing_standards where organisation_id=p_organisation_id and id=(p_document->>'processing_standard_id')::uuid and is_active;
   if not found or standard.recipe_version_id is distinct from nullif(p_document->>'recipe_version_id','')::uuid or not exists(select 1 from public.recipe_versions where organisation_id=p_organisation_id and id=standard.recipe_version_id and effective_from<=day) then raise exception 'Choose an active processing standard for this recipe version.' using errcode='22023';end if;
   if not exists(select 1 from public.processing_standard_sites ss join public.stock_locations s on s.organisation_id=ss.organisation_id and s.id=ss.site_id join public.organisation_memberships m on m.organisation_id=s.organisation_id and m.id=s.responsible_membership_id and m.status='active' where ss.organisation_id=p_organisation_id and ss.standard_id=standard.id and ss.site_id=src.id and s.processing_enabled and s.is_active) then raise exception 'This centre is not enabled for the selected processing standard.' using errcode='22023';end if;
   actual_lines:=private.pp_stock_lines(p_organisation_id,p_lines);
   if exists(select 1 from jsonb_array_elements(actual_lines) l where not exists(select 1 from jsonb_array_elements(standard.inputs) s where s->>'item_id'=l->>'item_id')) or exists(select 1 from jsonb_array_elements(standard.inputs) s where not exists(select 1 from jsonb_array_elements(actual_lines) l where l->>'item_id'=s->>'item_id')) then raise exception 'Record actual consumption for every input in the standard, including explicit zero where unused.' using errcode='22023';end if;
   select (value->>'quantity')::numeric into primary_actual from jsonb_array_elements(actual_lines) where value->>'item_id'=standard.primary_item_id::text;
   if primary_actual is null or primary_actual<=0 then raise exception 'Enter a positive measured main input quantity.' using errcode='22023';end if;
   actual:=private.pp_stock_number(p_document->>'actual_output',true);
   select ou.canonical_factor/iu.canonical_factor into base_factor from public.recipe_outputs ro join public.units_of_measure ou on ou.organisation_id=ro.organisation_id and ou.id=ro.uom_id join public.items i on i.organisation_id=ro.organisation_id and i.id=standard.output_item_id join public.units_of_measure iu on iu.organisation_id=i.organisation_id and iu.id=i.base_uom_id where ro.organisation_id=p_organisation_id and ro.recipe_version_id=standard.recipe_version_id;
   expected_base:=round(standard.expected_output*primary_actual/standard.primary_quantity,12);qty:=actual;
   if expected_base<=0 or expected_base>=1e26 or qty>=1e26 then raise exception 'Batch quantities exceed supported precision.' using errcode='22023';end if;
   deviation:=100*(qty-expected_base)/expected_base;outside:=abs(deviation)>standard.tolerance_percent;
   reason:=trim(coalesce(p_document->>'variance_reason',''));
   if length(reason)>1000 or(outside and length(reason)=0) then raise exception 'Explain the output variance outside the approved tolerance.' using errcode='22023';end if;
   usable:=case when nullif(p_document->>'usable_weight_kg','') is not null then private.pp_stock_number(p_document->>'usable_weight_kg',true) end;
   if usable is not null and usable<>round(usable,6) then raise exception 'Record weight in KG with up to six decimal places.' using errcode='22023';end if;
   waste:=coalesce(p_document->'processing_waste','[]'::jsonb);
   if jsonb_typeof(waste) is distinct from 'array' or jsonb_array_length(waste)>100 then raise exception 'Use up to 100 measured waste lines.' using errcode='22023';end if;
   if (p_document->>'waste_confirmed') is distinct from 'true' then raise exception 'Confirm measured waste, or explicitly confirm no measured waste to record.' using errcode='22023';end if;
   if(select count(*)<>count(distinct value->>'item_id') from jsonb_array_elements(waste)) then raise exception 'Combine waste for each input into one line.' using errcode='22023';end if;
   for entry in select value from jsonb_array_elements(waste) loop
    select (value->>'quantity')::numeric into expected from jsonb_array_elements(actual_lines) where value->>'item_id'=entry->>'item_id';
    if expected is null or private.pp_stock_number(entry->>'quantity')>expected or length(trim(coalesce(entry->>'reason',''))) not between 1 and 500 then raise exception 'Measured waste must refer to a consumed input, not exceed its consumption, and have a reason.' using errcode='22023';end if;
   end loop;
   select coalesce(bool_and(u.dimension='MASS' or(l->>'quantity')::numeric=0),false),sum((l->>'quantity')::numeric*u.canonical_factor/kg.canonical_factor) into measurable,input_mass
   from jsonb_array_elements(actual_lines) l join public.items i on i.organisation_id=p_organisation_id and i.id=(l->>'item_id')::uuid join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id join public.units_of_measure kg on kg.organisation_id=i.organisation_id and kg.code='KG';
   if not measurable then input_mass:=null;end if;
   if input_mass is not null then
    select coalesce(sum((l->>'quantity')::numeric*u.canonical_factor/kg.canonical_factor),0) into waste_mass from jsonb_array_elements(waste) l join public.items i on i.organisation_id=p_organisation_id and i.id=(l->>'item_id')::uuid join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id join public.units_of_measure kg on kg.organisation_id=i.organisation_id and kg.code='KG';
    if usable is not null then
     mass_balance:=input_mass-usable-waste_mass;
     if mass_balance < -0.000001 then raise exception 'Measured usable output and waste exceed the total weight consumed. Check the measurements.' using errcode='22023';end if;
     if mass_balance>0.000001 and length(reason)=0 then raise exception 'Explain the weight not accounted for by measured usable output and recorded waste.' using errcode='22023';end if;
    end if;
   end if;
   if qty=0 and coalesce(usable,0)>0 then raise exception 'Usable output weight requires usable output quantity.' using errcode='22023';end if;
   lines:=actual_lines;
   output:=jsonb_build_object('item_id',standard.output_item_id,'quantity',qty::text,'planned_output',expected_base::text,'actual_output',actual::text,'recipe_version_id',standard.recipe_version_id,'processing_standard_id',standard.id,'expected_output',expected_base::text,'output_variance',(qty-expected_base)::text,'variance_percent',round(deviation,6)::text,'outside_tolerance',outside,'variance_reason',reason,'usable_weight_kg',usable::text,'waste_included_in_inputs',true,'output_unit_basis','STOCK_BASE');
  else raise exception 'Save a processing standard, choose its centre and record actual inputs before requesting production.' using errcode='22023';end if;
  -- Pin child bindings as evidence; future changes cannot rewrite these inputs.
 else lines:=private.pp_stock_lines(p_organisation_id,p_lines); end if;
 if kind<>'COUNT' and not(kind='PRODUCTION' and standard.id is not null) and exists(select 1 from jsonb_array_elements(lines) l where (l->>'quantity')::numeric<=0) then raise exception 'Movement quantities must be positive.' using errcode='22023'; end if;
 if kind='COUNT' then fingerprint:=private.pp_stock_fingerprint(p_organisation_id,src.id); end if;
 if kind='DIRECT_RECEIPT' then
  if nullif(p_document->>'supplier_id','') is null or not exists(select 1 from public.suppliers where organisation_id=p_organisation_id and id=(p_document->>'supplier_id')::uuid and is_active)
   or length(trim(coalesce(p_document->>'delivery_reference',''))) not between 1 and 100 then raise exception 'Choose the supplier and enter its delivery reference.' using errcode='22023'; end if;
  if exists(select 1 from public.stock_documents d where d.organisation_id=p_organisation_id and d.kind='DIRECT_RECEIPT' and d.state not in ('CANCELLED','REJECTED') and d.output->>'supplier_id'=p_document->>'supplier_id' and lower(d.output->>'delivery_reference')=lower(trim(p_document->>'delivery_reference'))) then raise exception 'This supplier delivery reference already has a stock request. Review its existing record.' using errcode='22023'; end if;
 end if;
 if kind='OPENING' and exists(select 1 from public.stock_ledger e join jsonb_array_elements(lines) l on l->>'item_id'=e.item_id::text where e.organisation_id=p_organisation_id and e.location_id=dst.id) then raise exception 'Opening balances must be the first posting for each listed material at that stock location. Use a reviewed count for corrections.' using errcode='22023'; end if;
 insert into public.stock_documents(id,organisation_id,request_id,input_hash,reference,kind,source_id,destination_id,route_id,receipt_id,recipe_version_id,document_date,note,lines,output,count_fingerprint,created_by)
 values(result,p_organisation_id,p_request_id,digest,'STK-'||upper(substr(replace(result::text,'-',''),1,12)),kind,src.id,dst.id,route.id,rec.id,case when kind='PRODUCTION' then (p_document->>'recipe_version_id')::uuid end,day,trim(p_document->>'note'),lines,
 case when kind='DIRECT_RECEIPT' then jsonb_build_object('supplier_id',p_document->>'supplier_id','delivery_reference',trim(p_document->>'delivery_reference')) else output end,fingerprint,auth.uid());
 if standard.id is not null then
  insert into public.processing_batches values(p_organisation_id,result,standard.id,expected_base,(output->>'quantity')::numeric,(output->>'output_variance')::numeric,deviation,outside,usable,reason,primary_actual,coalesce(private.pp_member_label(p_organisation_id,src.responsible_membership_id),'Assigned member'),input_mass,waste_mass,mass_balance);
  insert into public.processing_waste select p_organisation_id,result,(value->>'item_id')::uuid,(value->>'quantity')::numeric,trim(value->>'reason') from jsonb_array_elements(waste);
 end if;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_REQUESTED',auth.uid(),result,jsonb_build_object('kind',kind));
 return result;
end $$;
notify pgrst,'reload schema';
commit;
