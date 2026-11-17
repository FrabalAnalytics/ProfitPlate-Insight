-- Apply after 023. Explicit stock assignments narrow existing role/outlet access.
-- Existing staff retain outlet-based access until an administrator selects ASSIGNED.
begin;
create table public.stock_member_access (
 organisation_id uuid not null, membership_id uuid not null,
 mode text not null check(mode in ('OUTLET','ASSIGNED')), revision integer not null default 1 check(revision>0),
 updated_by uuid not null references auth.users(id), updated_at timestamptz not null default clock_timestamp(),
 primary key(organisation_id,membership_id),
 foreign key(organisation_id,membership_id) references public.organisation_memberships(organisation_id,id)
);
create table public.stock_member_locations (
 organisation_id uuid not null, membership_id uuid not null, location_id uuid not null,
 can_request boolean not null, can_handle boolean not null, can_approve boolean not null,
 primary key(organisation_id,membership_id,location_id),
 foreign key(organisation_id,membership_id) references public.stock_member_access(organisation_id,membership_id),
 foreign key(organisation_id,location_id) references public.stock_locations(organisation_id,id)
);
alter table public.stock_member_access enable row level security;
alter table public.stock_member_locations enable row level security;
revoke all on public.stock_member_access,public.stock_member_locations from public,anon,authenticated;

create function private.pp_stock_assignment(org uuid, site uuid, capability text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisation_memberships m
  left join public.stock_member_access a on a.organisation_id=m.organisation_id and a.membership_id=m.id
  left join public.stock_member_locations g on g.organisation_id=m.organisation_id and g.membership_id=m.id and g.location_id=site
  where m.organisation_id=org and m.user_id=auth.uid() and m.status='active'
  and (coalesce(a.mode,'OUTLET')='OUTLET' or (g.location_id is not null and
   case capability when 'read' then true when 'request' then g.can_request when 'inventory' then g.can_handle when 'approve' then g.can_approve else false end)));
$$;
create or replace function private.pp_stock_site(org uuid, site uuid, mode text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.stock_locations s where s.organisation_id=org and s.id=site and
 case when mode='read' then
  private.pp_stock_manager(org) or private.pp_stock_role(org,'ceo',null) or private.pp_stock_role(org,'finance',s.outlet_id) or private.pp_stock_role(org,'procurement',s.outlet_id)
  or ((private.pp_stock_role(org,'inventory',s.outlet_id) or private.pp_stock_role(org,'operations',s.outlet_id)) and private.pp_stock_assignment(org,site,'read'))
 when mode in ('request','approve') then
  (private.pp_stock_role(org,'inventory',s.outlet_id) or private.pp_stock_role(org,'operations',s.outlet_id)) and private.pp_stock_assignment(org,site,mode)
 when mode='inventory' then private.pp_stock_role(org,'inventory',s.outlet_id) and private.pp_stock_assignment(org,site,'inventory')
 else false end);
$$;
create function private.pp_stock_route_approver(org uuid, site uuid, role_name text) returns boolean
language sql stable security definer set search_path='' as $$
 select private.pp_stock_manager(org) or exists(select 1 from public.stock_locations s where s.organisation_id=org and s.id=site
  and private.pp_stock_role(org,role_name,s.outlet_id) and private.pp_stock_site(org,site,'approve'));
$$;
revoke all on function private.pp_stock_assignment(uuid,uuid,text),private.pp_stock_route_approver(uuid,uuid,text) from public,anon,authenticated;

create function public.stock_access_directory(p_organisation_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'Only a business-wide Restaurant Administrator can manage department access.' using errcode='42501'; end if;
 select jsonb_build_object('members',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'email',u.email,'mode',coalesce(a.mode,'OUTLET'),'revision',coalesce(a.revision,0),
  'review_access',exists(select 1 from public.membership_roles r where r.organisation_id=m.organisation_id and r.membership_id=m.id and r.role_code in ('restaurant_admin','ceo','finance','procurement')),
  'roles',(select jsonb_agg(jsonb_build_object('role_code',r.role_code,'outlet_id',r.location_id,'outlet_name',l.name) order by r.role_code,r.location_id) from public.membership_roles r left join public.locations l on l.organisation_id=r.organisation_id and l.id=r.location_id where r.organisation_id=m.organisation_id and r.membership_id=m.id),
  'assignments',coalesce((select jsonb_agg(jsonb_build_object('location_id',g.location_id,'can_request',g.can_request,'can_handle',g.can_handle,'can_approve',g.can_approve) order by g.location_id) from public.stock_member_locations g where g.organisation_id=m.organisation_id and g.membership_id=m.id),'[]'::jsonb)) order by u.email,m.id)
 from public.organisation_memberships m join auth.users u on u.id=m.user_id left join public.stock_member_access a on a.organisation_id=m.organisation_id and a.membership_id=m.id
 where m.organisation_id=p_organisation_id and m.status='active' and exists(select 1 from public.membership_roles r where r.organisation_id=m.organisation_id and r.membership_id=m.id and r.role_code in ('inventory','operations'))),'[]'::jsonb)) into result;
 return result;
end $$;

create function public.save_stock_member_access(p_organisation_id uuid,p_membership_id uuid,p_revision integer,p_mode text,p_assignments jsonb) returns integer
language plpgsql security definer set search_path='' as $$
declare current_revision integer; entry jsonb; site public.stock_locations; seen uuid[]:='{}'; prior jsonb;
begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'Only a business-wide Restaurant Administrator can manage department access.' using errcode='42501'; end if;
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
  if src.id is null or dst.id is null or not (private.pp_stock_site(p_organisation_id,dst.id,'request') or (private.pp_stock_site(p_organisation_id,src.id,'inventory') and private.pp_stock_site(p_organisation_id,src.id,'request'))) then raise exception 'Request access is required at the receiving department, or Inventory access at the source.' using errcode='42501'; end if;
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
  if exists(select 1 from public.stock_documents where organisation_id=p_organisation_id and receipt_id=rec.id and state<>'CANCELLED') then raise exception 'This GRN already has a stock request.' using errcode='22023'; end if;
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
  if exists(select 1 from public.stock_documents d where d.organisation_id=p_organisation_id and d.kind='DIRECT_RECEIPT' and d.state<>'CANCELLED' and d.output->>'supplier_id'=p_document->>'supplier_id' and lower(d.output->>'delivery_reference')=lower(trim(p_document->>'delivery_reference'))) then raise exception 'This supplier delivery reference already has a stock request. Review its existing record.' using errcode='22023'; end if;
 end if;
 if kind='OPENING' and exists(select 1 from public.stock_ledger e join jsonb_array_elements(lines) l on l->>'item_id'=e.item_id::text where e.organisation_id=p_organisation_id and e.location_id=dst.id) then raise exception 'Opening balances must be the first posting for each listed material at that stock location. Use a reviewed count for corrections.' using errcode='22023'; end if;
 insert into public.stock_documents(id,organisation_id,request_id,input_hash,reference,kind,source_id,destination_id,route_id,receipt_id,recipe_version_id,document_date,note,lines,output,count_fingerprint,created_by)
 values(result,p_organisation_id,p_request_id,digest,'STK-'||upper(substr(replace(result::text,'-',''),1,12)),kind,src.id,dst.id,route.id,rec.id,case when kind='PRODUCTION' then (p_document->>'recipe_version_id')::uuid end,day,trim(p_document->>'note'),lines,
 case when kind='DIRECT_RECEIPT' then jsonb_build_object('supplier_id',p_document->>'supplier_id','delivery_reference',trim(p_document->>'delivery_reference')) else output end,fingerprint,auth.uid());
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_REQUESTED',auth.uid(),result,jsonb_build_object('kind',kind));
 return result;
end $$;


-- Recheck source-specific approvals at decision time and in the returned action flags.
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
  elsif not (private.pp_stock_manager(p_organisation_id) or private.pp_stock_role(p_organisation_id,'finance',null)) then raise exception 'Finance or Restaurant Administrator must approve stock adjustments, receipts and production.' using errcode='42501'; end if;
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


create or replace function public.stock_workspace(p_organisation_id uuid,p_location_id uuid default null,p_page integer default 1) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock access denied.' using errcode='42501'; end if;
 if p_page is null or p_page not between 1 and 100000 then raise exception 'Choose a valid page.' using errcode='22023'; end if;
 if p_location_id is not null and not private.pp_stock_site(p_organisation_id,p_location_id,'read') then raise exception 'Stock location unavailable.' using errcode='42501'; end if;
 select jsonb_build_object('manage',private.pp_stock_manager(p_organisation_id),
 'locations',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('read',private.pp_stock_site(p_organisation_id,s.id,'read'),'request',private.pp_stock_site(p_organisation_id,s.id,'request'),'inventory',private.pp_stock_site(p_organisation_id,s.id,'inventory'),'outlet_name',l.name) order by s.name) from public.stock_locations s left join public.locations l on l.organisation_id=s.organisation_id and l.id=s.outlet_id
  where s.organisation_id=p_organisation_id and (private.pp_stock_site(p_organisation_id,s.id,'read') or exists(select 1 from public.stock_routes r where r.organisation_id=s.organisation_id and r.is_active and ((r.source_id=s.id and private.pp_stock_site(p_organisation_id,r.destination_id,'read')) or (r.destination_id=s.id and private.pp_stock_site(p_organisation_id,r.source_id,'read')))))),'[]'::jsonb),
 'routes',coalesce((select jsonb_agg(to_jsonb(r) order by r.kind,r.id) from public.stock_routes r where r.organisation_id=p_organisation_id and (private.pp_stock_site(p_organisation_id,r.source_id,'read') or private.pp_stock_site(p_organisation_id,r.destination_id,'read'))),'[]'::jsonb),
 'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',i.name,'code',i.code,'unit',u.code,'item_type',i.item_type) order by i.name) from public.items i join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id where i.organisation_id=p_organisation_id and i.is_active and i.stock_tracked),'[]'::jsonb),
 'outlets',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.locations where organisation_id=p_organisation_id and is_active and private.pp_stock_manager(p_organisation_id)),'[]'::jsonb),
 'suppliers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.suppliers where organisation_id=p_organisation_id and is_active),'[]'::jsonb),
 'recipes',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'name',v.name,'version',v.version,'code',r.code,'yield',o.quantity::text,'unit',u.code,'item_id',b.item_id) order by r.code,v.version desc) from public.recipe_versions v join public.recipes r on r.organisation_id=v.organisation_id and r.id=v.recipe_id join public.recipe_outputs o on o.organisation_id=v.organisation_id and o.recipe_version_id=v.id join public.units_of_measure u on u.organisation_id=o.organisation_id and u.id=o.uom_id left join public.stock_recipe_bindings b on b.organisation_id=v.organisation_id and b.recipe_version_id=v.id where v.organisation_id=p_organisation_id),'[]'::jsonb),
 'grns',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'reference',g.reference,'outlet',l.name,'date',g.received_on) order by g.created_at desc) from public.goods_receipts g join public.purchase_orders po on po.organisation_id=g.organisation_id and po.id=g.order_id join public.locations l on l.organisation_id=po.organisation_id and l.id=po.location_id where g.organisation_id=p_organisation_id and private.pp_inventory_access(p_organisation_id,po.location_id) and exists(select 1 from public.stock_locations x where x.organisation_id=p_organisation_id and x.is_active and (x.outlet_id=po.location_id or x.outlet_id is null) and private.pp_stock_site(p_organisation_id,x.id,'inventory') and private.pp_stock_site(p_organisation_id,x.id,'request')) and not private.pp_receipt_voided(p_organisation_id,g.id) and not exists(select 1 from public.goods_receipt_void_requests where organisation_id=g.organisation_id and receipt_id=g.id and state='PENDING') and not exists(select 1 from public.stock_documents where organisation_id=g.organisation_id and receipt_id=g.id and state<>'CANCELLED')),'[]'::jsonb),
 'balances',coalesce((select jsonb_agg(jsonb_build_object('location_id',s.id,'location',s.name,'item_id',i.id,'name',i.name,'code',i.code,'unit',u.code,'quantity',q.qty::text) order by s.name,i.name) from (select location_id,item_id,sum(quantity) qty from public.stock_ledger where organisation_id=p_organisation_id group by location_id,item_id) q join public.stock_locations s on s.organisation_id=p_organisation_id and s.id=q.location_id join public.items i on i.organisation_id=p_organisation_id and i.id=q.item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id where private.pp_stock_site(p_organisation_id,s.id,'read') and (p_location_id is null or s.id=p_location_id)),'[]'::jsonb),
 'total',(select count(*) from public.stock_documents d where d.organisation_id=p_organisation_id and private.pp_stock_doc_read(p_organisation_id,d.id) and (p_location_id is null or d.source_id=p_location_id or d.destination_id=p_location_id)),
 'documents',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc,q.id) from (select d.*,s.name source_name,t.name destination_name,
   a.email created_label,b.email approved_label,c.email dispatched_label,e.email completed_label,
   jsonb_strip_nulls(jsonb_build_object('approve',case when d.state='REQUESTED' and d.created_by<>auth.uid() and (case when d.kind in ('TRANSFER','ISSUE') then private.pp_stock_route_approver(p_organisation_id,d.source_id,r.approval_role) else private.pp_stock_manager(p_organisation_id) or private.pp_stock_role(p_organisation_id,'finance',null) end) then true end,
    'post',case when d.state='APPROVED' and d.kind not in ('TRANSFER','ISSUE') and private.pp_stock_site(p_organisation_id,coalesce(d.source_id,d.destination_id),'inventory') then true end,
    'dispatch',case when d.state='APPROVED' and d.kind in ('TRANSFER','ISSUE') and private.pp_stock_site(p_organisation_id,d.source_id,'inventory') then true end,
    'receive',case when d.state='DISPATCHED' and d.dispatched_by<>auth.uid() and private.pp_stock_site(p_organisation_id,d.destination_id,'inventory') then true end,
    'cancel',case when d.state in ('REQUESTED','APPROVED') and (d.created_by=auth.uid() or private.pp_stock_manager(p_organisation_id)) then true end)) actions
  from public.stock_documents d left join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id left join public.stock_locations t on t.organisation_id=d.organisation_id and t.id=d.destination_id left join public.stock_routes r on r.organisation_id=d.organisation_id and r.id=d.route_id
  left join auth.users a on a.id=d.created_by left join auth.users b on b.id=d.approved_by left join auth.users c on c.id=d.dispatched_by left join auth.users e on e.id=d.completed_by
  where d.organisation_id=p_organisation_id and private.pp_stock_doc_read(p_organisation_id,d.id) and (p_location_id is null or d.source_id=p_location_id or d.destination_id=p_location_id) order by d.created_at desc,d.id limit 25 offset (p_page-1)*25) q),'[]'::jsonb),
 'ledger',coalesce((select jsonb_agg(to_jsonb(q) order by q.id desc) from (select e.id,e.document_id,d.reference,s.name location,i.name material,u.code unit,e.quantity::text,e.occurred_on,e.created_at from public.stock_ledger e join public.stock_documents d on d.organisation_id=e.organisation_id and d.id=e.document_id join public.stock_locations s on s.organisation_id=e.organisation_id and s.id=e.location_id join public.items i on i.organisation_id=e.organisation_id and i.id=e.item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id where e.organisation_id=p_organisation_id and private.pp_stock_site(p_organisation_id,e.location_id,'read') and (p_location_id is null or e.location_id=p_location_id) order by e.id desc limit 100) q),'[]'::jsonb)) into result;
 return result;
end $$;


notify pgrst,'reload schema';
commit;
