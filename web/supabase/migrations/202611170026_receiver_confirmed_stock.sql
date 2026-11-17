-- Apply after 025. Acceptance posts both sides; preserve previously dispatched history.
begin;
insert into public.roles(code,name) values ('stock_department','Department stock user'),('stock_receiver','Stock receiver (optional)'),('stock_dispatcher','Stock dispatcher (optional)') on conflict(code) do update set name=excluded.name;
alter table public.stock_documents add column posting_policy text not null default 'ON_DISPATCH' check(posting_policy in ('ON_DISPATCH','ON_ACCEPT')),
 add column resolved_at timestamptz, add column resolved_by uuid references auth.users(id), add column resolution_note text;
drop index public.stock_grn_once;
create unique index stock_grn_once on public.stock_documents(organisation_id,receipt_id) where receipt_id is not null and state not in ('CANCELLED','REJECTED');
drop index public.stock_direct_receipt_once;
create unique index stock_direct_receipt_once on public.stock_documents(organisation_id,(output->>'supplier_id'),lower(output->>'delivery_reference')) where kind='DIRECT_RECEIPT' and state not in ('CANCELLED','REJECTED');
alter table public.stock_documents alter column posting_policy set default 'ON_ACCEPT';
alter table public.stock_documents drop constraint stock_documents_state_check;
alter table public.stock_documents add constraint stock_documents_state_check check(state in ('REQUESTED','APPROVED','DISPATCHED','RECEIVED','PARTIAL','REJECTED','POSTED','CANCELLED'));
alter table public.stock_member_locations add column can_dispatch boolean not null default false, add column can_receive boolean not null default false;
update public.stock_member_locations set can_dispatch=can_handle,can_receive=can_handle;

create or replace function private.pp_stock_assignment(org uuid, site uuid, capability text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisation_memberships m
 left join public.stock_member_access a on a.organisation_id=m.organisation_id and a.membership_id=m.id
 left join public.stock_member_locations g on g.organisation_id=m.organisation_id and g.membership_id=m.id and g.location_id=site
 where m.organisation_id=org and m.user_id=auth.uid() and m.status='active' and
 (coalesce(a.mode,'OUTLET')='OUTLET' or (g.location_id is not null and case capability when 'read' then true when 'request' then g.can_request when 'inventory' then g.can_handle when 'approve' then g.can_approve when 'dispatch' then g.can_dispatch when 'receive' then g.can_receive else false end)));
$$;
create function private.pp_stock_process(org uuid, site uuid, role_name text, capability text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.stock_locations s join public.stock_member_locations g on g.organisation_id=s.organisation_id and g.location_id=s.id
 join public.stock_member_access a on a.organisation_id=g.organisation_id and a.membership_id=g.membership_id and a.mode='ASSIGNED'
 join public.organisation_memberships m on m.organisation_id=g.organisation_id and m.id=g.membership_id and m.user_id=auth.uid() and m.status='active'
 join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id and r.role_code=role_name and (r.location_id is null or (s.outlet_id is not null and r.location_id=s.outlet_id))
 where s.organisation_id=org and s.id=site and case capability when 'read' then true when 'request' then g.can_request when 'receive' then g.can_receive when 'dispatch' then g.can_dispatch else false end);
$$;
revoke all on function private.pp_stock_process(uuid,uuid,text,text) from public,anon,authenticated;
create or replace function private.pp_stock_site(org uuid, site uuid, mode text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.stock_locations s where s.organisation_id=org and s.id=site and case
 when mode='read' then private.pp_stock_manager(org) or private.pp_stock_role(org,'ceo',null) or private.pp_stock_role(org,'finance',s.outlet_id) or private.pp_stock_role(org,'procurement',s.outlet_id)
  or ((private.pp_stock_role(org,'inventory',s.outlet_id) or private.pp_stock_role(org,'operations',s.outlet_id)) and private.pp_stock_assignment(org,site,'read'))
  or private.pp_stock_process(org,site,'stock_department','read') or private.pp_stock_process(org,site,'stock_receiver','read') or private.pp_stock_process(org,site,'stock_dispatcher','read')
 when mode='request' then private.pp_inventory_manager(org) or ((private.pp_stock_role(org,'inventory',s.outlet_id) or private.pp_stock_role(org,'operations',s.outlet_id)) and private.pp_stock_assignment(org,site,'request')) or private.pp_stock_process(org,site,'stock_department','request')
 when mode='approve' then private.pp_inventory_manager(org) or ((private.pp_stock_role(org,'inventory',s.outlet_id) or private.pp_stock_role(org,'operations',s.outlet_id)) and private.pp_stock_assignment(org,site,'approve'))
 when mode='inventory' then private.pp_inventory_manager(org) or (private.pp_stock_role(org,'inventory',s.outlet_id) and private.pp_stock_assignment(org,site,'inventory'))
 when mode='dispatch' then private.pp_inventory_manager(org) or (private.pp_stock_role(org,'inventory',s.outlet_id) and private.pp_stock_assignment(org,site,'dispatch')) or private.pp_stock_process(org,site,'stock_dispatcher','dispatch')
 when mode='receive' then (private.pp_inventory_manager(org) and s.kind in ('STORE','WAREHOUSE')) or (private.pp_stock_role(org,'inventory',s.outlet_id) and private.pp_stock_assignment(org,site,'receive')) or private.pp_stock_process(org,site,'stock_department','receive') or private.pp_stock_process(org,site,'stock_receiver','receive')
 else false end);
$$;
create or replace function private.pp_stock_read(org uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisation_memberships m join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id where m.organisation_id=org and m.user_id=auth.uid() and m.status='active' and r.role_code in ('ceo','restaurant_admin','finance','procurement','inventory','inventory_manager','operations','stock_department','stock_receiver','stock_dispatcher'));
$$;
create function private.pp_stock_reserved(org uuid, site uuid, material uuid, excluded uuid default null) returns numeric
language sql stable security definer set search_path='' as $$
 select coalesce(sum((l->>'quantity')::numeric-case when d.state='DISPATCHED' then 0 else coalesce((select (r->>'quantity')::numeric from jsonb_array_elements(d.received_lines) r where r->>'item_id'=material::text),0) end),0) from public.stock_documents d cross join lateral jsonb_array_elements(d.lines) l
 where d.organisation_id=org and d.source_id=site and d.kind in ('ISSUE','TRANSFER') and ((d.state='DISPATCHED' and d.posting_policy='ON_ACCEPT') or (d.state in ('PARTIAL','REJECTED') and d.resolved_at is null and d.dispatched_at is not null)) and (excluded is null or d.id<>excluded) and l->>'item_id'=material::text;
$$;
revoke all on function private.pp_stock_reserved(uuid,uuid,uuid,uuid) from public,anon,authenticated;
create or replace function private.pp_stock_entry(org uuid, doc uuid, site uuid, material uuid, qty numeric, day date) returns void
language plpgsql security definer set search_path='' as $$
begin
 if qty=0 then return; end if;
 if qty<>round(qty,12) or abs(qty)>=1e26 then raise exception 'Stock quantity exceeds supported precision.' using errcode='22023'; end if;
 if exists(select 1 from public.stock_ledger where organisation_id=org and location_id=site and item_id=material and occurred_on>day) then raise exception 'A later stock movement exists. Use the current movement date and explain any correction.' using errcode='22023'; end if;
 if private.pp_stock_balance(org,site,material)+qty<0 then raise exception 'Insufficient stock. Refresh balances before posting.' using errcode='22023'; end if;
 if qty<0 and private.pp_stock_balance(org,site,material)-private.pp_stock_reserved(org,site,material,doc)+qty<0 then raise exception 'Stock is reserved for pending receiver confirmation. Complete or reject the transfer before using it elsewhere.' using errcode='22023'; end if;
 insert into public.stock_ledger(organisation_id,document_id,location_id,item_id,quantity,occurred_on) values(org,doc,site,material,qty,day);
end $$;

create or replace function public.stock_document_action(p_organisation_id uuid,p_document_id uuid,p_action text,p_note text,p_received jsonb default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare d public.stock_documents; route public.stock_routes; line jsonb; rec jsonb; item uuid; qty numeric; accepted numeric; actor uuid:=auth.uid();
 received jsonb:='[]'; complete boolean:=true; any_accepted boolean:=false; day date; manager_return boolean:=false;
begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock access is required.' using errcode='42501'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into d from public.stock_documents where organisation_id=p_organisation_id and id=p_document_id;
 if d.id is null or not private.pp_stock_doc_read(p_organisation_id,d.id) then raise exception 'Stock document unavailable.' using errcode='42501'; end if;
 if length(trim(coalesce(p_note,''))) not between 1 and 1000 then raise exception 'Enter a decision/source note.' using errcode='22023'; end if;
 select (now() at time zone time_zone)::date into day from public.organisations where id=p_organisation_id;
 if p_action='RESOLVE' then
  if not private.pp_stock_manager(p_organisation_id) then raise exception 'Inventory Manager review is required.' using errcode='42501'; end if;
  if d.state not in ('PARTIAL','REJECTED') or d.resolved_at is not null then raise exception 'Only unresolved incomplete/rejected requests need follow-up.' using errcode='22023'; end if;
  update public.stock_documents set resolved_at=clock_timestamp(),resolved_by=actor,resolution_note=p_note where id=d.id;
 elsif p_action='CANCEL' then
  if d.created_by<>actor and not private.pp_stock_manager(p_organisation_id) then raise exception 'Only the requester or Inventory Manager/administrator may cancel.' using errcode='42501'; end if;
  if d.state not in ('REQUESTED','APPROVED') then raise exception 'Only unposted, undispatched requests may be cancelled.' using errcode='22023'; end if;
  update public.stock_documents set state='CANCELLED',decision_note=p_note,completed_by=actor,completed_at=clock_timestamp() where id=d.id;
 elsif p_action in ('APPROVE','DECLINE') then
  if d.created_by=actor then raise exception 'A different authorised colleague must approve or decline this request.' using errcode='42501'; end if;
  if d.kind in ('TRANSFER','ISSUE') then
   select * into route from public.stock_routes where organisation_id=p_organisation_id and id=d.route_id and is_active;
   if route.id is null or not private.pp_stock_route_approver(p_organisation_id,d.source_id,route.approval_role) then raise exception 'The configured source approval role is required.' using errcode='42501'; end if;
  elsif not (private.pp_stock_manager(p_organisation_id) or private.pp_stock_role(p_organisation_id,'finance',null)) then raise exception 'Inventory Manager, Finance or Restaurant Administrator approval is required.' using errcode='42501'; end if;
  if d.state<>'REQUESTED' then raise exception 'This request is no longer awaiting approval.' using errcode='22023'; end if;
  update public.stock_documents set state=case when p_action='DECLINE' then 'REJECTED' else 'APPROVED' end,approved_by=actor,approved_at=clock_timestamp(),decision_note=p_note,completed_at=case when p_action='DECLINE' then clock_timestamp() end,completed_by=case when p_action='DECLINE' then actor end where id=d.id;
 elsif p_action in ('POST','DISPATCH') then
  if d.state<>'APPROVED' then raise exception 'This request must be approved and not already posted or dispatched.' using errcode='22023'; end if;
  if not private.pp_stock_site(p_organisation_id,coalesce(d.source_id,d.destination_id),case when p_action='DISPATCH' then 'dispatch' else 'inventory' end) then raise exception 'The stock posting or dispatch permission is required at the source.' using errcode='42501'; end if;
  if p_action='DISPATCH' and d.kind not in ('TRANSFER','ISSUE') or p_action='POST' and d.kind in ('TRANSFER','ISSUE') then raise exception 'Dispatch transfers/issues; post other stock records.' using errcode='22023'; end if;
  if exists(select 1 from public.stock_locations where organisation_id=p_organisation_id and id in(d.source_id,d.destination_id) and not is_active) then raise exception 'A stock location was deactivated.' using errcode='22023'; end if;
  if d.kind in ('TRANSFER','ISSUE') and not exists(select 1 from public.stock_routes where organisation_id=p_organisation_id and id=d.route_id and is_active) then raise exception 'This route is no longer active.' using errcode='22023'; end if;
  if d.kind='COUNT' and exists(select 1 from public.stock_documents pending where pending.organisation_id=p_organisation_id and pending.source_id=d.source_id and pending.dispatched_at is not null and pending.state in ('DISPATCHED','PARTIAL','REJECTED') and pending.resolved_at is null) then raise exception 'Complete pending receiver confirmations before counting this stock.' using errcode='22023'; end if;
  if d.kind='COUNT' and d.count_fingerprint<>private.pp_stock_fingerprint(p_organisation_id,d.source_id) then raise exception 'Stock changed after this count. Cancel and recount before posting.' using errcode='22023'; end if;
  if d.kind='OPENING' and exists(select 1 from public.stock_ledger e join jsonb_array_elements(d.lines) l on l->>'item_id'=e.item_id::text where e.organisation_id=p_organisation_id and e.location_id=d.destination_id) then raise exception 'Opening balances must be the first posting for each material at that stock location.' using errcode='22023'; end if;
  if d.kind='GRN' and (private.pp_receipt_voided(p_organisation_id,d.receipt_id) or exists(select 1 from public.goods_receipt_void_requests where organisation_id=p_organisation_id and receipt_id=d.receipt_id and state='PENDING')) then raise exception 'This GRN was voided or awaits a void decision.' using errcode='22023'; end if;
  for line in select value from jsonb_array_elements(d.lines) loop
   item:=(line->>'item_id')::uuid;qty:=(line->>'quantity')::numeric;
   if p_action='DISPATCH' then
    if private.pp_stock_balance(p_organisation_id,d.source_id,item)-private.pp_stock_reserved(p_organisation_id,d.source_id,item)<qty then raise exception 'Insufficient available stock after pending transfer reservations.' using errcode='22023'; end if;
   else
    if d.kind='COUNT' then qty:=qty-private.pp_stock_balance(p_organisation_id,d.source_id,item); elsif d.source_id is not null then qty:=-qty; end if;
    perform private.pp_stock_entry(p_organisation_id,d.id,coalesce(d.source_id,d.destination_id),item,qty,d.document_date);
   end if;
  end loop;
  if d.kind='PRODUCTION' then perform private.pp_stock_entry(p_organisation_id,d.id,d.source_id,(d.output->>'item_id')::uuid,(d.output->>'quantity')::numeric,d.document_date);end if;
  update public.stock_documents set state=case when p_action='DISPATCH' then 'DISPATCHED' else 'POSTED' end,
   posting_policy=case when p_action='DISPATCH' then 'ON_ACCEPT' else posting_policy end,
   dispatched_by=case when p_action='DISPATCH' then actor end,dispatched_at=case when p_action='DISPATCH' then clock_timestamp() end,
   completed_by=case when p_action='POST' then actor end,completed_at=case when p_action='POST' then clock_timestamp() end,decision_note=p_note where id=d.id;
 elsif p_action in ('RECEIVE','REJECT') then
  if not private.pp_stock_site(p_organisation_id,d.destination_id,'receive') then raise exception 'The receiving department must accept or reject this transfer.' using errcode='42501'; end if;
  manager_return:=private.pp_inventory_manager(p_organisation_id) and d.created_by<>actor and exists(select 1 from public.stock_locations s join public.stock_locations t on t.organisation_id=s.organisation_id where s.organisation_id=p_organisation_id and s.id=d.source_id and t.id=d.destination_id and s.kind in ('KITCHEN','BAR','PRODUCTION') and t.kind in ('STORE','WAREHOUSE'));
  if d.dispatched_by=actor and not manager_return then raise exception 'A different receiving colleague must confirm this dispatch.' using errcode='42501'; end if;
  if d.state<>'DISPATCHED' then raise exception 'Only dispatched transfers can be accepted or rejected.' using errcode='22023'; end if;
  if p_action='RECEIVE' and (jsonb_typeof(p_received) is distinct from 'array' or jsonb_array_length(p_received)<>jsonb_array_length(d.lines) or octet_length(p_received::text)>65536) then raise exception 'Confirm every dispatched material exactly once.' using errcode='22023'; end if;
  for line in select value from jsonb_array_elements(d.lines) loop
   item:=(line->>'item_id')::uuid;qty:=(line->>'quantity')::numeric;
   if p_action='REJECT' then accepted:=0;rec:=jsonb_build_object('reason',p_note);
   else
    if (select count(*) from jsonb_array_elements(p_received) r where r->>'item_id'=item::text)<>1 then raise exception 'Confirm every dispatched material exactly once.' using errcode='22023'; end if;
    select value into rec from jsonb_array_elements(p_received) where value->>'item_id'=item::text;accepted:=private.pp_stock_number(rec->>'quantity',true);
   end if;
   if accepted>qty or (accepted<qty and length(trim(coalesce(rec->>'reason',''))) not between 1 and 500) then raise exception 'Accepted stock cannot exceed dispatched quantity; explain all rejected quantities.' using errcode='22023'; end if;
   complete:=complete and accepted=qty;any_accepted:=any_accepted or accepted>0;
   if d.posting_policy='ON_ACCEPT' then
    perform private.pp_stock_entry(p_organisation_id,d.id,d.source_id,item,-accepted,day);
   elsif accepted<qty then
    -- Historical transfers already deducted their source. Return only the rejected share.
    perform private.pp_stock_entry(p_organisation_id,d.id,d.source_id,item,qty-accepted,day);
   end if;
   perform private.pp_stock_entry(p_organisation_id,d.id,d.destination_id,item,accepted,day);
   received:=received||jsonb_build_array(jsonb_build_object('item_id',item,'quantity',accepted::text,'rejected',(qty-accepted)::text,'reason',coalesce(rec->>'reason','')));
  end loop;
  update public.stock_documents set state=case when complete then 'RECEIVED' when any_accepted then 'PARTIAL' else 'REJECTED' end,received_lines=received,completed_by=actor,completed_at=clock_timestamp(),decision_note=p_note where id=d.id;
 else raise exception 'Choose an available stock action.' using errcode='22023'; end if;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_'||p_action,actor,d.id,jsonb_build_object('note',p_note,'received',received,'policy',d.posting_policy,'manager_return',manager_return));return d.id;
end $$;

create or replace function private.pp_team_assignments(target_org uuid, input jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if input is null or jsonb_typeof(input)<>'array' or jsonb_array_length(input) not between 1 and 20 then
  raise exception 'Choose between 1 and 20 role assignments.' using errcode='22023'; end if;
 if exists(select 1 from jsonb_array_elements(input) e where jsonb_typeof(e)<>'object'
  or coalesce(e->>'role_code','') not in ('ceo','finance','procurement','inventory','inventory_manager','stock_department','stock_receiver','stock_dispatcher','operations','restaurant_admin')
  or (e->>'role_code'='inventory_manager' and e->>'location_id' is not null)
  or (e->>'location_id' is not null and not exists(select 1 from public.locations l
    where l.organisation_id=target_org and l.id::text=e->>'location_id' and l.is_active))) then
  raise exception 'Choose recognised roles and active locations in this business.' using errcode='22023'; end if;
 select jsonb_agg(v order by v->>'role_code',v->>'location_id') into result from
 (select distinct jsonb_build_object('role_code',e->>'role_code','location_id',e->>'location_id') v
  from jsonb_array_elements(input) e) s;
 return result;
end; $$;


create or replace function public.stock_access_directory(p_organisation_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'An Inventory Manager or business-wide Restaurant Administrator must manage department access.' using errcode='42501'; end if;
 select jsonb_build_object('members',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'email',u.email,'mode',coalesce(a.mode,case when exists(select 1 from public.membership_roles x where x.organisation_id=m.organisation_id and x.membership_id=m.id and x.role_code in ('stock_department','stock_receiver','stock_dispatcher')) then 'ASSIGNED' else 'OUTLET' end),'revision',coalesce(a.revision,0),
  'review_access',exists(select 1 from public.membership_roles r where r.organisation_id=m.organisation_id and r.membership_id=m.id and r.role_code in ('restaurant_admin','inventory_manager','ceo','finance','procurement')),
  'roles',(select jsonb_agg(jsonb_build_object('role_code',r.role_code,'outlet_id',r.location_id,'outlet_name',l.name) order by r.role_code,r.location_id) from public.membership_roles r left join public.locations l on l.organisation_id=r.organisation_id and l.id=r.location_id where r.organisation_id=m.organisation_id and r.membership_id=m.id),
  'assignments',coalesce((select jsonb_agg(jsonb_build_object('location_id',g.location_id,'can_request',g.can_request,'can_handle',g.can_handle,'can_approve',g.can_approve,'can_dispatch',g.can_dispatch,'can_receive',g.can_receive) order by g.location_id) from public.stock_member_locations g where g.organisation_id=m.organisation_id and g.membership_id=m.id),'[]'::jsonb)) order by u.email,m.id)
 from public.organisation_memberships m join auth.users u on u.id=m.user_id left join public.stock_member_access a on a.organisation_id=m.organisation_id and a.membership_id=m.id
 where m.organisation_id=p_organisation_id and m.status='active' and exists(select 1 from public.membership_roles r where r.organisation_id=m.organisation_id and r.membership_id=m.id and r.role_code in ('inventory','operations','stock_department','stock_receiver','stock_dispatcher'))),'[]'::jsonb)) into result;
 return result;
end $$;


create or replace function private.pp_inventory_access(target_org uuid,target_location uuid default null) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisation_memberships m join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id where m.organisation_id=target_org and m.user_id=auth.uid() and m.status='active' and r.role_code in ('inventory','inventory_manager','stock_receiver') and (target_location is null or r.location_id is null or r.location_id=target_location));
$$;

create or replace function public.save_stock_member_access(p_organisation_id uuid,p_membership_id uuid,p_revision integer,p_mode text,p_assignments jsonb) returns integer
language plpgsql security definer set search_path='' as $$
declare version integer; entry jsonb; site public.stock_locations; seen uuid[]:='{}'; prior jsonb; roles text[];
begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'Inventory Manager or business-wide Restaurant Administrator access is required.' using errcode='42501'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if not exists(select 1 from public.organisation_memberships where organisation_id=p_organisation_id and id=p_membership_id and status='active') then raise exception 'Choose an active member in this business.' using errcode='42501'; end if;
 select array_agg(role_code) into roles from public.membership_roles where organisation_id=p_organisation_id and membership_id=p_membership_id and role_code in ('inventory','operations','stock_department','stock_receiver','stock_dispatcher');
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
  select array_agg(role_code) into roles from public.membership_roles where organisation_id=p_organisation_id and membership_id=p_membership_id and role_code in ('inventory','operations','stock_department','stock_receiver','stock_dispatcher') and (location_id is null or (site.outlet_id is not null and location_id=site.outlet_id));
  if roles is null then raise exception 'Stock assignments cannot exceed the current role/outlet scope.' using errcode='22023'; end if;
  if (entry->>'can_request')::boolean and not (roles&&array['inventory','operations','stock_department']) then raise exception 'This process role cannot initiate requisitions.' using errcode='22023';end if;
  if (entry->>'can_handle')::boolean and not ('inventory'=any(roles)) then raise exception 'Department/process roles cannot post arbitrary stock adjustments; the Inventory Manager handles posting.' using errcode='22023';end if;
  if (entry->>'can_approve')::boolean and not (roles&&array['inventory','operations']) then raise exception 'Approval authority belongs to the Inventory Manager or the configured source approver.' using errcode='22023';end if;
  if coalesce((entry->>'can_dispatch')::boolean,(entry->>'can_handle')::boolean) and not (roles&&array['inventory','stock_dispatcher']) then raise exception 'Dispatch permission requires a dispatcher process role.' using errcode='22023';end if;
  if coalesce((entry->>'can_receive')::boolean,(entry->>'can_handle')::boolean) and not (roles&&array['inventory','stock_department','stock_receiver']) then raise exception 'Receiving permission requires a department or receiver role.' using errcode='22023';end if;
  seen:=array_append(seen,site.id);
 end loop;
 insert into public.stock_member_access(organisation_id,membership_id,mode,revision,updated_by) values(p_organisation_id,p_membership_id,p_mode,version+1,auth.uid()) on conflict(organisation_id,membership_id) do update set mode=excluded.mode,revision=excluded.revision,updated_by=excluded.updated_by,updated_at=clock_timestamp();
 delete from public.stock_member_locations where organisation_id=p_organisation_id and membership_id=p_membership_id;
 insert into public.stock_member_locations(organisation_id,membership_id,location_id,can_request,can_handle,can_approve,can_dispatch,can_receive)
 select p_organisation_id,p_membership_id,(g->>'location_id')::uuid,(g->>'can_request')::boolean,(g->>'can_handle')::boolean,(g->>'can_approve')::boolean,coalesce((g->>'can_dispatch')::boolean,(g->>'can_handle')::boolean),coalesce((g->>'can_receive')::boolean,(g->>'can_handle')::boolean) from jsonb_array_elements(p_assignments) g;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_DEPARTMENT_ACCESS_CHANGED',auth.uid(),p_membership_id,jsonb_build_object('previous',prior,'mode',p_mode,'assignments',p_assignments,'revision',version+1));return version+1;
end $$;

create function private.pp_stock_status(state text, filter text) returns boolean language sql immutable set search_path='' as $$
 select case filter when 'ALL' then true when 'PENDING' then state in ('REQUESTED','APPROVED') when 'AWAITING_RECEIPT' then state='DISPATCHED' when 'COMPLETED' then state in ('RECEIVED','POSTED') when 'INCOMPLETE' then state='PARTIAL' when 'FOLLOW_UP' then state in ('PARTIAL','REJECTED') else state=filter end;
$$;
revoke all on function private.pp_stock_status(text,text) from public,anon,authenticated;

create function public.stock_workspace_alerts(p_organisation_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock access denied.' using errcode='42501';end if;
 with relevant as (
  select d.id,d.reference,d.state,d.created_at,d.dispatched_at,
   case when d.state='REQUESTED' and private.pp_stock_manager(p_organisation_id) and d.created_by<>auth.uid() then 'Approval needed'
    when d.state='APPROVED' and ((d.kind in ('ISSUE','TRANSFER') and private.pp_stock_site(p_organisation_id,d.source_id,'dispatch')) or (d.kind not in ('ISSUE','TRANSFER') and private.pp_stock_site(p_organisation_id,coalesce(d.source_id,d.destination_id),'inventory'))) then 'Ready to dispatch / post'
    when d.state='DISPATCHED' and private.pp_stock_site(p_organisation_id,d.destination_id,'receive') then 'Accept or reject incoming stock'
    when d.state='DISPATCHED' and private.pp_stock_manager(p_organisation_id) then 'Awaiting department acceptance'
    when d.state in ('PARTIAL','REJECTED') and d.resolved_at is null and private.pp_stock_manager(p_organisation_id) then 'Incomplete / rejected: follow-up needed'
    when d.created_by=auth.uid() and d.state in ('PARTIAL','REJECTED') and d.resolved_at is null then 'Your requisition needs follow-up'
    when d.created_by=auth.uid() and d.state in ('REQUESTED','APPROVED') then 'Your requisition is pending'
    else null end label
  from public.stock_documents d where d.organisation_id=p_organisation_id and private.pp_stock_doc_read(p_organisation_id,d.id)
 ) select jsonb_build_object('total',count(*) filter(where label is not null),'approval',count(*) filter(where label='Approval needed'),'incoming',count(*) filter(where label='Accept or reject incoming stock'),'follow_up',count(*) filter(where label in ('Incomplete / rejected: follow-up needed','Your requisition needs follow-up')),
 'overdue',count(*) filter(where label is not null and coalesce(dispatched_at,created_at)<statement_timestamp()-interval '24 hours'),
 'items',coalesce((select jsonb_agg(to_jsonb(q)) from (select id,reference,state,label,coalesce(dispatched_at,created_at) since,coalesce(dispatched_at,created_at)<statement_timestamp()-interval '24 hours' overdue from relevant where label is not null order by coalesce(dispatched_at,created_at),id limit 6) q),'[]')) into result from relevant;
 return result;
end $$;
revoke all on function public.stock_workspace_alerts(uuid) from public,anon;
grant execute on function public.stock_workspace_alerts(uuid) to authenticated;

create function private.pp_stock_receive_allowed(org uuid, doc uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.stock_documents d where d.organisation_id=org and d.id=doc and d.state='DISPATCHED' and private.pp_stock_site(org,d.destination_id,'receive') and
 (d.dispatched_by<>auth.uid() or (private.pp_inventory_manager(org) and d.created_by<>auth.uid() and exists(select 1 from public.stock_locations s join public.stock_locations t on t.organisation_id=s.organisation_id where s.organisation_id=org and s.id=d.source_id and t.id=d.destination_id and s.kind in ('KITCHEN','BAR','PRODUCTION') and t.kind in ('STORE','WAREHOUSE')))));
$$;
create function private.pp_stock_packet(org uuid, doc uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select to_jsonb(d)||jsonb_build_object('source_name',s.name,'destination_name',t.name,'manager_return',(private.pp_stock_receive_allowed(org,d.id) and d.dispatched_by=auth.uid()),'created_label',a.email,'approved_label',b.email,'dispatched_label',c.email,'completed_label',e.email,
 'actions',jsonb_strip_nulls(jsonb_build_object(
 'approve',case when d.state='REQUESTED' and d.created_by<>auth.uid() and (case when d.kind in ('TRANSFER','ISSUE') then r.is_active and private.pp_stock_route_approver(org,d.source_id,r.approval_role) else private.pp_stock_manager(org) or private.pp_stock_role(org,'finance',null) end) then true end,
 'decline',case when d.state='REQUESTED' and d.created_by<>auth.uid() and private.pp_stock_manager(org) then true end,
 'post',case when d.state='APPROVED' and d.kind not in ('TRANSFER','ISSUE') and private.pp_stock_site(org,coalesce(d.source_id,d.destination_id),'inventory') then true end,
 'dispatch',case when d.state='APPROVED' and d.kind in ('TRANSFER','ISSUE') and private.pp_stock_site(org,d.source_id,'dispatch') then true end,
 'receive',case when private.pp_stock_receive_allowed(org,d.id) then true end,'reject',case when private.pp_stock_receive_allowed(org,d.id) then true end,
 'cancel',case when d.state in ('REQUESTED','APPROVED') and (d.created_by=auth.uid() or private.pp_stock_manager(org)) then true end,
 'resolve',case when d.state in ('PARTIAL','REJECTED') and d.resolved_at is null and private.pp_stock_manager(org) then true end)))
 from public.stock_documents d left join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id left join public.stock_locations t on t.organisation_id=d.organisation_id and t.id=d.destination_id
 left join public.stock_routes r on r.organisation_id=d.organisation_id and r.id=d.route_id left join auth.users a on a.id=d.created_by left join auth.users b on b.id=d.approved_by left join auth.users c on c.id=d.dispatched_by left join auth.users e on e.id=d.completed_by
 where d.organisation_id=org and d.id=doc and private.pp_stock_doc_read(org,doc);
$$;
revoke all on function private.pp_stock_packet(uuid,uuid),private.pp_stock_receive_allowed(uuid,uuid) from public,anon,authenticated;

create or replace function public.request_stock_document(p_organisation_id uuid,p_request_id uuid,p_document jsonb,p_lines jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid:=gen_random_uuid(); prior public.stock_documents; src public.stock_locations; dst public.stock_locations; route public.stock_routes;
 kind text:=p_document->>'kind'; day date; digest text; lines jsonb; output jsonb; rec public.goods_receipts; po public.purchase_orders;
 r record; qty numeric; planned numeric; actual numeric; base_factor numeric; bound uuid; out_qty numeric; expected numeric; fingerprint text;
begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock access is required.' using errcode='42501'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if p_request_id is null or octet_length(coalesce(p_document::text,''))>10000 then raise exception 'Refresh and enter a valid stock request.' using errcode='22023'; end if;
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
  planned:=private.pp_stock_number(p_document->>'planned_output'); actual:=private.pp_stock_number(p_document->>'actual_output',true);
  select b.item_id,o.quantity,u.canonical_factor/v.canonical_factor into bound,out_qty,base_factor
   from public.stock_recipe_bindings b join public.recipe_outputs o on o.organisation_id=b.organisation_id and o.recipe_version_id=b.recipe_version_id
   join public.recipe_versions rv on rv.organisation_id=b.organisation_id and rv.id=b.recipe_version_id
   join public.items i on i.organisation_id=b.organisation_id and i.id=b.item_id and i.is_active and i.stock_tracked
   join public.units_of_measure u on u.organisation_id=o.organisation_id and u.id=o.uom_id
   join public.units_of_measure v on v.organisation_id=i.organisation_id and v.id=i.base_uom_id
   where b.organisation_id=p_organisation_id and b.recipe_version_id=nullif(p_document->>'recipe_version_id','')::uuid and rv.effective_from<=day;
  if bound is null then raise exception 'Bind a recipe version to a stock output material before recording production. Its effective date must not be after the movement date.' using errcode='22023'; end if;
  lines:='[]';
  for r in select c.*,b.item_id child_item,bu.canonical_factor/bv.canonical_factor factor
   from public.recipe_components c left join public.stock_recipe_bindings b on b.organisation_id=c.organisation_id and b.recipe_version_id=c.child_recipe_version_id
   left join public.items i on i.organisation_id=b.organisation_id and i.id=b.item_id
   left join public.units_of_measure bu on bu.organisation_id=c.organisation_id and bu.id=c.base_uom_id
   left join public.units_of_measure bv on bv.organisation_id=i.organisation_id and bv.id=i.base_uom_id
   where c.organisation_id=p_organisation_id and c.recipe_version_id=(p_document->>'recipe_version_id')::uuid order by c.line_no loop
   if r.child_recipe_version_id is not null and r.child_item is null then raise exception 'Bind and produce each child sub-recipe before the parent batch. Ingredients are not deducted twice.' using errcode='22023'; end if;
   qty:=round(r.normalised_quantity*planned/out_qty*case when r.item_id is not null then 1 else r.factor end,12);
   if qty<=0 then raise exception 'A production input falls below supported precision.' using errcode='22023'; end if;
   lines:=lines||jsonb_build_array(jsonb_build_object('item_id',coalesce(r.item_id,r.child_item),'quantity',qty::text));
  end loop;
  select jsonb_agg(jsonb_build_object('item_id',q.item_id,'quantity',q.qty::text)) into lines from (select value->>'item_id' item_id,sum((value->>'quantity')::numeric) qty from jsonb_array_elements(lines) group by value->>'item_id') q;
  lines:=private.pp_stock_lines(p_organisation_id,lines);
  if exists(select 1 from jsonb_array_elements(lines) l where l->>'item_id'=bound::text) then raise exception 'Production output must differ from its stock inputs.' using errcode='22023'; end if;
  output:=jsonb_build_object('item_id',bound,'quantity',round(actual*base_factor,12)::text,'planned_output',planned::text,'actual_output',actual::text,'recipe_version_id',p_document->>'recipe_version_id');
  -- Pin child bindings as evidence; future changes cannot rewrite these inputs.
 else lines:=private.pp_stock_lines(p_organisation_id,p_lines); end if;
 if kind<>'COUNT' and exists(select 1 from jsonb_array_elements(lines) l where (l->>'quantity')::numeric<=0) then raise exception 'Movement quantities must be positive.' using errcode='22023'; end if;
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
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_REQUESTED',auth.uid(),result,jsonb_build_object('kind',kind));
 return result;
end $$;



create function public.stock_workspace_v2(p_organisation_id uuid,p_location_id uuid default null,p_page integer default 1,p_status text default 'ALL',p_search text default '',p_document_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock access denied.' using errcode='42501'; end if;
 if p_status is null or p_status not in ('ALL','PENDING','AWAITING_RECEIPT','COMPLETED','INCOMPLETE','FOLLOW_UP','REJECTED','CANCELLED','APPROVED') or p_search is null or length(p_search)>80 then raise exception 'Choose an available requisition filter and search up to 80 characters.' using errcode='22023'; end if;
 if p_page is null or p_page not between 1 and 100000 then raise exception 'Choose a valid page.' using errcode='22023'; end if;
 if p_location_id is not null and not private.pp_stock_site(p_organisation_id,p_location_id,'read') then raise exception 'Stock location unavailable.' using errcode='42501'; end if;
 select jsonb_build_object('manage',private.pp_stock_manager(p_organisation_id),
 'locations',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('read',private.pp_stock_site(p_organisation_id,s.id,'read'),'request',private.pp_stock_site(p_organisation_id,s.id,'request'),'inventory',private.pp_stock_site(p_organisation_id,s.id,'inventory'),'dispatch',private.pp_stock_site(p_organisation_id,s.id,'dispatch'),'receive',private.pp_stock_site(p_organisation_id,s.id,'receive'),'outlet_name',l.name) order by s.name) from public.stock_locations s left join public.locations l on l.organisation_id=s.organisation_id and l.id=s.outlet_id
  where s.organisation_id=p_organisation_id and (private.pp_stock_site(p_organisation_id,s.id,'read') or exists(select 1 from public.stock_routes r where r.organisation_id=s.organisation_id and r.is_active and ((r.source_id=s.id and private.pp_stock_site(p_organisation_id,r.destination_id,'read')) or (r.destination_id=s.id and private.pp_stock_site(p_organisation_id,r.source_id,'read')))))),'[]'::jsonb),
 'routes',coalesce((select jsonb_agg(to_jsonb(r) order by r.kind,r.id) from public.stock_routes r where r.organisation_id=p_organisation_id and (private.pp_stock_site(p_organisation_id,r.source_id,'read') or private.pp_stock_site(p_organisation_id,r.destination_id,'read'))),'[]'::jsonb),
 'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',i.name,'code',i.code,'unit',u.code,'item_type',i.item_type) order by i.name) from public.items i join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id where i.organisation_id=p_organisation_id and i.is_active and i.stock_tracked),'[]'::jsonb),
 'outlets',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.locations where organisation_id=p_organisation_id and is_active and private.pp_stock_manager(p_organisation_id)),'[]'::jsonb),
 'suppliers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.suppliers where organisation_id=p_organisation_id and is_active),'[]'::jsonb),
 'recipes',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'name',v.name,'version',v.version,'code',r.code,'yield',o.quantity::text,'unit',u.code,'item_id',b.item_id) order by r.code,v.version desc) from public.recipe_versions v join public.recipes r on r.organisation_id=v.organisation_id and r.id=v.recipe_id join public.recipe_outputs o on o.organisation_id=v.organisation_id and o.recipe_version_id=v.id join public.units_of_measure u on u.organisation_id=o.organisation_id and u.id=o.uom_id left join public.stock_recipe_bindings b on b.organisation_id=v.organisation_id and b.recipe_version_id=v.id where v.organisation_id=p_organisation_id),'[]'::jsonb),
 'grns',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'reference',g.reference,'outlet',l.name,'date',g.received_on) order by g.created_at desc) from public.goods_receipts g join public.purchase_orders po on po.organisation_id=g.organisation_id and po.id=g.order_id join public.locations l on l.organisation_id=po.organisation_id and l.id=po.location_id where g.organisation_id=p_organisation_id and private.pp_inventory_access(p_organisation_id,po.location_id) and exists(select 1 from public.stock_locations x where x.organisation_id=p_organisation_id and x.is_active and (x.outlet_id=po.location_id or x.outlet_id is null) and private.pp_stock_site(p_organisation_id,x.id,'inventory') and private.pp_stock_site(p_organisation_id,x.id,'request')) and not private.pp_receipt_voided(p_organisation_id,g.id) and not exists(select 1 from public.goods_receipt_void_requests where organisation_id=g.organisation_id and receipt_id=g.id and state='PENDING') and not exists(select 1 from public.stock_documents where organisation_id=g.organisation_id and receipt_id=g.id and state not in ('CANCELLED','REJECTED'))),'[]'::jsonb),
 'balances',coalesce((select jsonb_agg(jsonb_build_object('location_id',s.id,'location',s.name,'item_id',i.id,'name',i.name,'code',i.code,'unit',u.code,'quantity',q.qty::text,'reserved',private.pp_stock_reserved(p_organisation_id,s.id,i.id)::text,'available',(q.qty-private.pp_stock_reserved(p_organisation_id,s.id,i.id))::text) order by s.name,i.name) from (select location_id,item_id,sum(quantity) qty from public.stock_ledger where organisation_id=p_organisation_id group by location_id,item_id) q join public.stock_locations s on s.organisation_id=p_organisation_id and s.id=q.location_id join public.items i on i.organisation_id=p_organisation_id and i.id=q.item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id where private.pp_stock_site(p_organisation_id,s.id,'read') and (p_location_id is null or s.id=p_location_id)),'[]'::jsonb),
 'total',(select count(*) from public.stock_documents d where d.organisation_id=p_organisation_id and private.pp_stock_doc_read(p_organisation_id,d.id) and (p_location_id is null or d.source_id=p_location_id or d.destination_id=p_location_id) and private.pp_stock_status(d.state,p_status) and (p_status<>'FOLLOW_UP' or d.resolved_at is null) and (trim(p_search)='' or position(lower(trim(p_search)) in lower(d.reference||' '||d.note))>0)),
 'selected_document',case when p_document_id is not null then private.pp_stock_packet(p_organisation_id,p_document_id) end,
 'alerts',public.stock_workspace_alerts(p_organisation_id),
 'documents',coalesce((select jsonb_agg(private.pp_stock_packet(p_organisation_id,q.id) order by q.created_at desc,q.id) from (select d.id,d.created_at from public.stock_documents d where d.organisation_id=p_organisation_id and private.pp_stock_doc_read(p_organisation_id,d.id) and (p_location_id is null or d.source_id=p_location_id or d.destination_id=p_location_id) and private.pp_stock_status(d.state,p_status) and (p_status<>'FOLLOW_UP' or d.resolved_at is null) and (trim(p_search)='' or position(lower(trim(p_search)) in lower(d.reference||' '||d.note))>0) order by d.created_at desc,d.id limit 10 offset (p_page-1)*10) q),'[]'::jsonb),
 'ledger',coalesce((select jsonb_agg(to_jsonb(q) order by q.id desc) from (select e.id,e.document_id,d.reference,s.name location,i.name material,u.code unit,e.quantity::text,e.occurred_on,e.created_at from public.stock_ledger e join public.stock_documents d on d.organisation_id=e.organisation_id and d.id=e.document_id join public.stock_locations s on s.organisation_id=e.organisation_id and s.id=e.location_id join public.items i on i.organisation_id=e.organisation_id and i.id=e.item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id where e.organisation_id=p_organisation_id and private.pp_stock_site(p_organisation_id,e.location_id,'read') and (p_location_id is null or e.location_id=p_location_id) order by e.id desc limit 100) q),'[]'::jsonb)) into result;
 return result;
end $$;



revoke all on function public.stock_workspace_v2(uuid,uuid,integer,text,text,uuid) from public,anon;
grant execute on function public.stock_workspace_v2(uuid,uuid,integer,text,text,uuid) to authenticated;
create or replace function public.stock_workspace(p_organisation_id uuid,p_location_id uuid default null,p_page integer default 1) returns jsonb
language sql stable security definer set search_path='' as $$ select public.stock_workspace_v2(p_organisation_id,p_location_id,p_page,'ALL','',null); $$;
notify pgrst,'reload schema';
commit;
