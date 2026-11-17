-- Apply after 024. Explicit Inventory Manager role; no automatic membership changes.
begin;
insert into public.roles(code,name) values('inventory_manager','Inventory Manager') on conflict(code) do update set name=excluded.name;
create function private.pp_inventory_manager(org uuid) returns boolean
language sql stable security definer set search_path='' as $$ select private.pp_stock_role(org,'inventory_manager',null); $$;
revoke all on function private.pp_inventory_manager(uuid) from public,anon,authenticated;
create or replace function private.pp_stock_manager(org uuid) returns boolean
language sql stable security definer set search_path='' as $$ select private.pp_stock_role(org,'restaurant_admin',null) or private.pp_inventory_manager(org); $$;
alter table public.stock_routes drop constraint stock_routes_approval_role_check;
alter table public.stock_routes add constraint stock_routes_approval_role_check check(approval_role in ('inventory','inventory_manager','operations','restaurant_admin'));

create or replace function private.pp_stock_read(org uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisation_memberships m join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id
 where m.organisation_id=org and m.user_id=auth.uid() and m.status='active' and r.role_code in ('ceo','restaurant_admin','finance','procurement','inventory','inventory_manager','operations'));
$$;
create or replace function private.pp_stock_site(org uuid, site uuid, mode text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.stock_locations s where s.organisation_id=org and s.id=site and
 case when mode='read' then
  private.pp_stock_manager(org) or private.pp_stock_role(org,'ceo',null) or private.pp_stock_role(org,'finance',s.outlet_id) or private.pp_stock_role(org,'procurement',s.outlet_id)
  or ((private.pp_stock_role(org,'inventory',s.outlet_id) or private.pp_stock_role(org,'operations',s.outlet_id)) and private.pp_stock_assignment(org,site,'read'))
 when mode in ('request','approve') then
  private.pp_inventory_manager(org) or (private.pp_stock_role(org,'inventory',s.outlet_id) or private.pp_stock_role(org,'operations',s.outlet_id)) and private.pp_stock_assignment(org,site,mode)
 when mode='inventory' then private.pp_inventory_manager(org) or private.pp_stock_role(org,'inventory',s.outlet_id) and private.pp_stock_assignment(org,site,'inventory')
 else false end);
$$;
create or replace function private.pp_inventory_access(target_org uuid,target_location uuid default null) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisation_memberships m join public.membership_roles r
 on r.organisation_id=m.organisation_id and r.membership_id=m.id
 where m.organisation_id=target_org and m.user_id=auth.uid() and m.status='active' and r.role_code in ('inventory','inventory_manager')
 and (target_location is null or r.location_id is null or r.location_id=target_location));
$$;
create or replace function private.pp_team_assignments(target_org uuid, input jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if input is null or jsonb_typeof(input)<>'array' or jsonb_array_length(input) not between 1 and 20 then
  raise exception 'Choose between 1 and 20 role assignments.' using errcode='22023'; end if;
 if exists(select 1 from jsonb_array_elements(input) e where jsonb_typeof(e)<>'object'
  or coalesce(e->>'role_code','') not in ('ceo','finance','procurement','inventory','inventory_manager','operations','restaurant_admin')
  or (e->>'role_code'='inventory_manager' and e->>'location_id' is not null)
  or (e->>'location_id' is not null and not exists(select 1 from public.locations l
    where l.organisation_id=target_org and l.id::text=e->>'location_id' and l.is_active))) then
  raise exception 'Choose recognised roles and active locations in this business.' using errcode='22023'; end if;
 select jsonb_agg(v order by v->>'role_code',v->>'location_id') into result from
 (select distinct jsonb_build_object('role_code',e->>'role_code','location_id',e->>'location_id') v
  from jsonb_array_elements(input) e) s;
 return result;
end; $$;

create or replace function public.save_stock_configuration(p_organisation_id uuid,p_kind text,p_value jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid; src public.stock_locations; dst public.stock_locations; u public.units_of_measure; v public.units_of_measure;
begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'Inventory Manager or business-wide Restaurant Administrator access is required.' using errcode='42501'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if p_kind='LOCATION' then
  if coalesce(p_value->>'code','')!~'^[A-Z0-9][A-Z0-9_-]{0,39}$' or length(trim(coalesce(p_value->>'name',''))) not between 1 and 120
   or coalesce(p_value->>'kind','') not in ('WAREHOUSE','STORE','KITCHEN','BAR','PRODUCTION') or length(coalesce(p_value->>'department',''))>80 then raise exception 'Enter a code, name, stock location type and optional department.' using errcode='22023'; end if;
  if nullif(p_value->>'outlet_id','') is not null and not exists(select 1 from public.locations where organisation_id=p_organisation_id and id=(p_value->>'outlet_id')::uuid and is_active) then raise exception 'Choose an active outlet in this business.' using errcode='22023'; end if;
  if exists(select 1 from public.stock_locations where organisation_id=p_organisation_id and code=p_value->>'code') then raise exception 'That stock location code already exists.' using errcode='22023'; end if;
  insert into public.stock_locations(organisation_id,code,name,kind,outlet_id,department) values(p_organisation_id,p_value->>'code',trim(p_value->>'name'),p_value->>'kind',nullif(p_value->>'outlet_id','')::uuid,trim(coalesce(p_value->>'department',''))) returning id into result;
 elsif p_kind='ROUTE' then
  select * into src from public.stock_locations where organisation_id=p_organisation_id and id=(p_value->>'source_id')::uuid and is_active;
  select * into dst from public.stock_locations where organisation_id=p_organisation_id and id=(p_value->>'destination_id')::uuid and is_active;
  if src.id is null or dst.id is null or src.id=dst.id or coalesce(p_value->>'kind','') not in ('TRANSFER','ISSUE') or coalesce(p_value->>'approval_role','') not in ('inventory','inventory_manager','operations','restaurant_admin') then raise exception 'Choose different active stock locations, a movement type and an approval role.' using errcode='22023'; end if;
  insert into public.stock_routes(organisation_id,source_id,destination_id,kind,approval_role) values(p_organisation_id,src.id,dst.id,p_value->>'kind',p_value->>'approval_role')
   on conflict(organisation_id,source_id,destination_id,kind) do update set approval_role=excluded.approval_role,is_active=true returning id into result;
 elsif p_kind='BINDING' then
  select uom.* into u from public.recipe_outputs o join public.units_of_measure uom on uom.organisation_id=o.organisation_id and uom.id=o.uom_id where o.organisation_id=p_organisation_id and o.recipe_version_id=(p_value->>'recipe_version_id')::uuid;
  select uom.* into v from public.items i join public.units_of_measure uom on uom.organisation_id=i.organisation_id and uom.id=i.base_uom_id where i.organisation_id=p_organisation_id and i.id=(p_value->>'item_id')::uuid and i.is_active and i.stock_tracked and i.item_type in ('SEMI_FINISHED','FINISHED');
  if u.id is null or v.id is null or u.dimension<>v.dimension or u.dimension='PACKAGE' then raise exception 'Bind a published recipe to an active tracked semi-finished/finished material with a compatible base unit.' using errcode='22023'; end if;
  if exists(select 1 from public.stock_documents where organisation_id=p_organisation_id and kind='PRODUCTION' and state<>'CANCELLED' and (recipe_version_id=(p_value->>'recipe_version_id')::uuid or lines::text like '%'||(p_value->>'recipe_version_id')||'%')) then raise exception 'This recipe binding is already used. Publish a new recipe version to change its stock output.' using errcode='22023'; end if;
  insert into public.stock_recipe_bindings values(p_organisation_id,(p_value->>'recipe_version_id')::uuid,(p_value->>'item_id')::uuid) on conflict(organisation_id,recipe_version_id) do update set item_id=excluded.item_id;
  result:=(p_value->>'recipe_version_id')::uuid;
 elsif p_kind in ('LOCATION_STATE','ROUTE_STATE') then
  result:=(p_value->>'id')::uuid;
  if p_kind='LOCATION_STATE' then
   if exists(select 1 from public.stock_documents where organisation_id=p_organisation_id and state in ('REQUESTED','APPROVED','DISPATCHED') and (source_id=result or destination_id=result))
    or exists(select 1 from public.stock_ledger where organisation_id=p_organisation_id and location_id=result group by item_id having sum(quantity)<>0) then raise exception 'Clear stock and finish pending movements before deactivating a stock location.' using errcode='22023'; end if;
   update public.stock_locations set is_active=(p_value->>'active')::boolean where organisation_id=p_organisation_id and id=result;
  else
   update public.stock_routes set is_active=(p_value->>'active')::boolean where organisation_id=p_organisation_id and id=result;
  end if;
  if not found then raise exception 'Configuration unavailable.' using errcode='42501'; end if;
 else raise exception 'Unknown stock configuration.' using errcode='22023'; end if;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_CONFIGURATION',auth.uid(),result,jsonb_build_object('kind',p_kind,'value',p_value));
 return result;
end $$;

create or replace function public.stock_access_directory(p_organisation_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'An Inventory Manager or business-wide Restaurant Administrator must manage department access.' using errcode='42501'; end if;
 select jsonb_build_object('members',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'email',u.email,'mode',coalesce(a.mode,'OUTLET'),'revision',coalesce(a.revision,0),
  'review_access',exists(select 1 from public.membership_roles r where r.organisation_id=m.organisation_id and r.membership_id=m.id and r.role_code in ('restaurant_admin','inventory_manager','ceo','finance','procurement')),
  'roles',(select jsonb_agg(jsonb_build_object('role_code',r.role_code,'outlet_id',r.location_id,'outlet_name',l.name) order by r.role_code,r.location_id) from public.membership_roles r left join public.locations l on l.organisation_id=r.organisation_id and l.id=r.location_id where r.organisation_id=m.organisation_id and r.membership_id=m.id),
  'assignments',coalesce((select jsonb_agg(jsonb_build_object('location_id',g.location_id,'can_request',g.can_request,'can_handle',g.can_handle,'can_approve',g.can_approve) order by g.location_id) from public.stock_member_locations g where g.organisation_id=m.organisation_id and g.membership_id=m.id),'[]'::jsonb)) order by u.email,m.id)
 from public.organisation_memberships m join auth.users u on u.id=m.user_id left join public.stock_member_access a on a.organisation_id=m.organisation_id and a.membership_id=m.id
 where m.organisation_id=p_organisation_id and m.status='active' and exists(select 1 from public.membership_roles r where r.organisation_id=m.organisation_id and r.membership_id=m.id and r.role_code in ('inventory','operations'))),'[]'::jsonb)) into result;
 return result;
end $$;

create or replace function public.save_stock_member_access(p_organisation_id uuid,p_membership_id uuid,p_revision integer,p_mode text,p_assignments jsonb) returns integer
language plpgsql security definer set search_path='' as $$
declare current_revision integer; entry jsonb; site public.stock_locations; seen uuid[]:='{}'; prior jsonb;
begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'An Inventory Manager or business-wide Restaurant Administrator must manage department access.' using errcode='42501'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if not exists(select 1 from public.organisation_memberships m where m.organisation_id=p_organisation_id and m.id=p_membership_id and m.status='active'
  and exists(select 1 from public.membership_roles r where r.organisation_id=m.organisation_id and r.membership_id=m.id and r.role_code in ('inventory','operations'))) then raise exception 'Choose an active Inventory or Operations member in this business.' using errcode='42501'; end if;
 if p_mode is null or p_mode not in ('OUTLET','ASSIGNED') or jsonb_typeof(p_assignments) is distinct from 'array' or jsonb_array_length(p_assignments)>100
  or octet_length(p_assignments::text)>32768 or (p_mode='OUTLET' and jsonb_array_length(p_assignments)>0) then raise exception 'Choose outlet access or up to 100 explicit stock locations.' using errcode='22023'; end if;
 select a.revision,to_jsonb(a) into current_revision,prior from public.stock_member_access a where a.organisation_id=p_organisation_id and a.membership_id=p_membership_id;
 current_revision:=coalesce(current_revision,0);
 if p_revision is distinct from current_revision then raise exception 'Department access changed. Refresh and review the latest assignments before saving.' using errcode='22023'; end if;
 prior:=coalesce(prior,'{}'::jsonb)||jsonb_build_object('assignments',coalesce((select jsonb_agg(to_jsonb(g) order by g.location_id) from public.stock_member_locations g where g.organisation_id=p_organisation_id and g.membership_id=p_membership_id),'[]'::jsonb));
 for entry in select value from jsonb_array_elements(p_assignments) loop
  if jsonb_typeof(entry)<>'object' or jsonb_typeof(entry->'can_request') is distinct from 'boolean' or jsonb_typeof(entry->'can_handle') is distinct from 'boolean' or jsonb_typeof(entry->'can_approve') is distinct from 'boolean' then raise exception 'Each stock location needs explicit request, handle and approval permissions.' using errcode='22023'; end if;
  begin select * into site from public.stock_locations where organisation_id=p_organisation_id and id=(entry->>'location_id')::uuid and is_active;
  exception when invalid_text_representation then raise exception 'Choose a valid stock location.' using errcode='22023'; end;
  if site.id is null or site.id=any(seen) then raise exception 'Choose distinct active stock locations in this business.' using errcode='22023'; end if;
  if not exists(select 1 from public.membership_roles r where r.organisation_id=p_organisation_id and r.membership_id=p_membership_id and r.role_code in ('inventory','operations') and (r.location_id is null or (site.outlet_id is not null and r.location_id=site.outlet_id))) then raise exception 'A stock assignment cannot exceed the member Inventory/Operations outlet scope. Update Users & roles first.' using errcode='22023'; end if;
  if (entry->>'can_handle')::boolean and not exists(select 1 from public.membership_roles r where r.organisation_id=p_organisation_id and r.membership_id=p_membership_id and r.role_code='inventory' and (r.location_id is null or (site.outlet_id is not null and r.location_id=site.outlet_id))) then raise exception 'Handling stock requires an Inventory role for that outlet. Operations alone can request stock but cannot post, dispatch or receive it.' using errcode='22023'; end if;
  seen:=array_append(seen,site.id);
 end loop;
 insert into public.stock_member_access(organisation_id,membership_id,mode,revision,updated_by) values(p_organisation_id,p_membership_id,p_mode,current_revision+1,auth.uid())
 on conflict(organisation_id,membership_id) do update set mode=excluded.mode,revision=excluded.revision,updated_by=excluded.updated_by,updated_at=clock_timestamp();
 delete from public.stock_member_locations where organisation_id=p_organisation_id and membership_id=p_membership_id;
 insert into public.stock_member_locations(organisation_id,membership_id,location_id,can_request,can_handle,can_approve)
 select p_organisation_id,p_membership_id,(g->>'location_id')::uuid,(g->>'can_request')::boolean,(g->>'can_handle')::boolean,(g->>'can_approve')::boolean from jsonb_array_elements(p_assignments) g;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_DEPARTMENT_ACCESS_CHANGED',auth.uid(),p_membership_id,jsonb_build_object('previous',prior,'mode',p_mode,'assignments',p_assignments,'revision',current_revision+1));
 return current_revision+1;
end $$;
revoke all on function public.stock_access_directory(uuid),public.save_stock_member_access(uuid,uuid,integer,text,jsonb) from public,anon;
grant execute on function public.stock_access_directory(uuid),public.save_stock_member_access(uuid,uuid,integer,text,jsonb) to authenticated;

create or replace function public.stock_document_action(p_organisation_id uuid,p_document_id uuid,p_action text,p_note text,p_received jsonb default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare d public.stock_documents; route public.stock_routes; site public.stock_locations; line jsonb; rec jsonb; item uuid; qty numeric; accepted numeric; actor uuid:=auth.uid();
begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock access is required.' using errcode='42501'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into d from public.stock_documents where organisation_id=p_organisation_id and id=p_document_id;
 if d.id is null or not private.pp_stock_doc_read(p_organisation_id,d.id) then raise exception 'Stock document unavailable.' using errcode='42501'; end if;
 if length(trim(coalesce(p_note,''))) not between 1 and 1000 then raise exception 'Enter a decision/source note.' using errcode='22023'; end if;
 if p_action='CANCEL' then
  if d.created_by<>actor and not private.pp_stock_manager(p_organisation_id) then raise exception 'Only the requester or administrator may cancel.' using errcode='42501'; end if;
  if d.state not in ('REQUESTED','APPROVED') then raise exception 'Only unposted, undispatched requests may be cancelled.' using errcode='22023'; end if;
  update public.stock_documents set state='CANCELLED',decision_note=p_note,completed_by=actor,completed_at=clock_timestamp() where id=d.id;
 elsif p_action='APPROVE' then
  if d.created_by=actor then raise exception 'A different authorised colleague must approve this request.' using errcode='42501'; end if;
  if d.kind in ('TRANSFER','ISSUE') then
   select * into route from public.stock_routes where organisation_id=p_organisation_id and id=d.route_id and is_active;
   select * into site from public.stock_locations where organisation_id=p_organisation_id and id=d.source_id;
   if route.id is null or not (private.pp_stock_route_approver(p_organisation_id,d.source_id,route.approval_role)) then raise exception 'The configured source approval role is required.' using errcode='42501'; end if;
  elsif not (private.pp_stock_manager(p_organisation_id) or private.pp_stock_role(p_organisation_id,'finance',null)) then raise exception 'Inventory Manager, Finance or Restaurant Administrator must approve stock adjustments, receipts and production.' using errcode='42501'; end if;
  if d.state<>'REQUESTED' then raise exception 'This request is no longer awaiting approval.' using errcode='22023'; end if;
  update public.stock_documents set state='APPROVED',approved_by=actor,approved_at=clock_timestamp(),decision_note=p_note where id=d.id;
 elsif p_action in ('POST','DISPATCH') then
  if d.state<>'APPROVED' then raise exception 'Refresh: this request must be approved and not already posted.' using errcode='22023'; end if;
  if not private.pp_stock_site(p_organisation_id,coalesce(d.source_id,d.destination_id),'inventory') then raise exception 'Inventory access is required at the source stock location.' using errcode='42501'; end if;
  if p_action='DISPATCH' and d.kind not in ('TRANSFER','ISSUE') or p_action='POST' and d.kind in ('TRANSFER','ISSUE') then raise exception 'Use dispatch for transfers/issues, or post for other stock records.' using errcode='22023'; end if;
  if exists(select 1 from public.stock_locations where organisation_id=p_organisation_id and id in(d.source_id,d.destination_id) and not is_active) then raise exception 'A stock location was deactivated.' using errcode='22023'; end if;
  if d.kind in ('TRANSFER','ISSUE') and not exists(select 1 from public.stock_routes where organisation_id=p_organisation_id and id=d.route_id and is_active) then raise exception 'This route is no longer active.' using errcode='22023'; end if;
  if d.kind='COUNT' and d.count_fingerprint<>private.pp_stock_fingerprint(p_organisation_id,d.source_id) then raise exception 'Stock changed after this count. Cancel and recount before posting.' using errcode='22023'; end if;
  if d.kind='OPENING' and exists(select 1 from public.stock_ledger e join jsonb_array_elements(d.lines) l on l->>'item_id'=e.item_id::text where e.organisation_id=p_organisation_id and e.location_id=d.destination_id) then raise exception 'Opening balances must be the first posting for each listed material at that stock location.' using errcode='22023'; end if;
  if d.kind='GRN' and (private.pp_receipt_voided(p_organisation_id,d.receipt_id) or exists(select 1 from public.goods_receipt_void_requests where organisation_id=p_organisation_id and receipt_id=d.receipt_id and state='PENDING')) then raise exception 'This GRN was voided or awaits a void decision. Cancel the stock request.' using errcode='22023'; end if;
  for line in select value from jsonb_array_elements(d.lines) loop
   item:=(line->>'item_id')::uuid;qty:=(line->>'quantity')::numeric;
   if d.kind='COUNT' then qty:=qty-private.pp_stock_balance(p_organisation_id,d.source_id,item);
   elsif d.source_id is not null then qty:=-qty; end if;
   perform private.pp_stock_entry(p_organisation_id,d.id,coalesce(d.source_id,d.destination_id),item,qty,d.document_date);
  end loop;
  if d.kind='PRODUCTION' then
   perform private.pp_stock_entry(p_organisation_id,d.id,d.source_id,(d.output->>'item_id')::uuid,(d.output->>'quantity')::numeric,d.document_date);
  end if;
  update public.stock_documents set state=case when p_action='DISPATCH' then 'DISPATCHED' else 'POSTED' end,
   dispatched_by=case when p_action='DISPATCH' then actor end,dispatched_at=case when p_action='DISPATCH' then clock_timestamp() end,
   completed_by=case when p_action='POST' then actor end,completed_at=case when p_action='POST' then clock_timestamp() end,decision_note=p_note where id=d.id;
 elsif p_action='RECEIVE' then
  if not private.pp_stock_site(p_organisation_id,d.destination_id,'inventory') or d.dispatched_by=actor then raise exception 'A different Inventory colleague with destination access must confirm receipt.' using errcode='42501'; end if;
  if d.state<>'DISPATCHED' then raise exception 'Only dispatched movements can be received.' using errcode='22023'; end if;
  if jsonb_typeof(p_received) is distinct from 'array' or jsonb_array_length(p_received)<>jsonb_array_length(d.lines) or octet_length(p_received::text)>65536 then raise exception 'Confirm every dispatched material exactly once.' using errcode='22023'; end if;
  for line in select value from jsonb_array_elements(d.lines) loop
   item:=(line->>'item_id')::uuid;qty:=(line->>'quantity')::numeric;
   if (select count(*) from jsonb_array_elements(p_received) r where r->>'item_id'=item::text)<>1 then raise exception 'Confirm every dispatched material exactly once.' using errcode='22023'; end if;
   select value into rec from jsonb_array_elements(p_received) where value->>'item_id'=item::text;
   accepted:=private.pp_stock_number(rec->>'quantity',true);
   if accepted>qty or (accepted<qty and length(trim(coalesce(rec->>'reason',''))) not between 1 and 500) then raise exception 'Received stock cannot exceed dispatched quantity; explain every shortage or damaged quantity.' using errcode='22023'; end if;
   perform private.pp_stock_entry(p_organisation_id,d.id,d.destination_id,item,accepted,greatest(d.document_date,(select(now() at time zone time_zone)::date from public.organisations where id=p_organisation_id)));
  end loop;
  update public.stock_documents set state='RECEIVED',received_lines=p_received,completed_by=actor,completed_at=clock_timestamp(),decision_note=p_note where id=d.id;
 else raise exception 'Choose an available stock action.' using errcode='22023'; end if;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_'||p_action,actor,d.id,jsonb_build_object('note',p_note,'received',p_received));
 return d.id;
end $$;



notify pgrst,'reload schema';
commit;
