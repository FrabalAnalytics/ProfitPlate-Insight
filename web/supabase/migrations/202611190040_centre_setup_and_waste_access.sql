-- Combine centre setup with owner access, and separate waste logging from requests.
begin;
alter table public.stock_member_locations add column can_record_waste boolean not null default false;
-- Preserve current recording access for existing explicit assignments.
update public.stock_member_locations set can_record_waste=can_request;
create function private.pp_can_record_waste(org uuid,site uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.pp_waste_site(org,site) and exists(select 1 from public.stock_locations s where s.organisation_id=org and s.id=site and s.is_active) and exists(
 select 1 from public.organisation_memberships m join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id
 where m.organisation_id=org and m.user_id=auth.uid() and m.status='active' and r.role_code in ('inventory_manager','inventory','operations','stock_department','kitchen_manager','bar_lead')
 and(r.location_id is null or r.location_id=(select outlet_id from public.stock_locations where organisation_id=org and id=site))
 and(case when coalesce((select mode from public.stock_member_access where organisation_id=org and membership_id=m.id),case when exists(select 1 from public.membership_roles d where d.organisation_id=org and d.membership_id=m.id and d.role_code in ('stock_department','kitchen_manager','bar_lead','stock_receiver','stock_dispatcher')) then 'ASSIGNED' else 'OUTLET' end)='ASSIGNED'
 then exists(select 1 from public.stock_member_locations g where g.organisation_id=org and g.membership_id=m.id and g.location_id=site and g.can_record_waste)
 else private.pp_stock_site(org,site,'request') end));
$$;
revoke all on function private.pp_can_record_waste(uuid,uuid) from public,anon,authenticated;

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
  if jsonb_typeof(entry) is distinct from 'object' or jsonb_typeof(entry->'can_request') is distinct from 'boolean' or jsonb_typeof(entry->'can_handle') is distinct from 'boolean' or jsonb_typeof(entry->'can_approve') is distinct from 'boolean' or (entry?'can_dispatch' and jsonb_typeof(entry->'can_dispatch') is distinct from 'boolean') or (entry?'can_receive' and jsonb_typeof(entry->'can_receive') is distinct from 'boolean') or (entry?'can_record_waste' and jsonb_typeof(entry->'can_record_waste') is distinct from 'boolean') or (entry?'can_review_waste' and jsonb_typeof(entry->'can_review_waste') is distinct from 'boolean') then raise exception 'Choose explicit stock-process permissions.' using errcode='22023'; end if;
  begin select * into site from public.stock_locations where organisation_id=p_organisation_id and id=(entry->>'location_id')::uuid and is_active;exception when invalid_text_representation then raise exception 'Choose a valid stock location.' using errcode='22023';end;
  if site.id is null or site.id=any(seen) then raise exception 'Choose distinct active stock locations in this business.' using errcode='22023'; end if;
  select array_agg(role_code) into roles from public.membership_roles where organisation_id=p_organisation_id and membership_id=p_membership_id and role_code in ('inventory','operations','stock_department','kitchen_manager','bar_lead','stock_receiver','stock_dispatcher') and (location_id is null or (site.outlet_id is not null and location_id=site.outlet_id));
  if roles is null then raise exception 'Stock assignments cannot exceed the current role/outlet scope.' using errcode='22023'; end if;
  if (entry->>'can_request')::boolean and not (roles&&array['inventory','operations','stock_department','kitchen_manager','bar_lead']) then raise exception 'This process role cannot initiate requisitions.' using errcode='22023';end if;
  if (entry->>'can_handle')::boolean and not ('inventory'=any(roles)) then raise exception 'Department/process roles cannot post arbitrary stock adjustments; the Inventory Manager handles posting.' using errcode='22023';end if;
  if (entry->>'can_approve')::boolean and not (roles&&array['inventory','operations']) then raise exception 'Approval authority belongs to the Inventory Manager or the configured source approver.' using errcode='22023';end if;
  if coalesce((entry->>'can_dispatch')::boolean,(entry->>'can_handle')::boolean) and not (roles&&array['inventory','stock_dispatcher']) then raise exception 'Dispatch permission requires a dispatcher process role.' using errcode='22023';end if;
  if coalesce((entry->>'can_receive')::boolean,(entry->>'can_handle')::boolean) and not (roles&&array['inventory','stock_department','kitchen_manager','bar_lead','stock_receiver']) then raise exception 'Receiving permission requires a department or receiver role.' using errcode='22023';end if;
  if coalesce((entry->>'can_review_waste')::boolean,false) and not(roles&&array['inventory','operations','stock_department','kitchen_manager','bar_lead']) then raise exception 'Waste review requires a department or operational stock role at this centre.' using errcode='22023';end if;
  if coalesce((entry->>'can_record_waste')::boolean,(entry->>'can_request')::boolean) and not(roles&&array['inventory','operations','stock_department','kitchen_manager','bar_lead']) then raise exception 'Waste recording requires an operational role at this centre.' using errcode='22023';end if;
  seen:=array_append(seen,site.id);
 end loop;
 insert into public.stock_member_access(organisation_id,membership_id,mode,revision,updated_by) values(p_organisation_id,p_membership_id,p_mode,version+1,auth.uid()) on conflict(organisation_id,membership_id) do update set mode=excluded.mode,revision=excluded.revision,updated_by=excluded.updated_by,updated_at=clock_timestamp();
 delete from public.stock_member_locations where organisation_id=p_organisation_id and membership_id=p_membership_id;
 insert into public.stock_member_locations(organisation_id,membership_id,location_id,can_request,can_handle,can_approve,can_dispatch,can_receive,can_review_waste,can_record_waste)
 select p_organisation_id,p_membership_id,(g->>'location_id')::uuid,(g->>'can_request')::boolean,(g->>'can_handle')::boolean,(g->>'can_approve')::boolean,coalesce((g->>'can_dispatch')::boolean,(g->>'can_handle')::boolean),coalesce((g->>'can_receive')::boolean,(g->>'can_handle')::boolean),coalesce((g->>'can_review_waste')::boolean,false),coalesce((g->>'can_record_waste')::boolean,(g->>'can_request')::boolean) from jsonb_array_elements(p_assignments) g;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_DEPARTMENT_ACCESS_CHANGED',auth.uid(),p_membership_id,jsonb_build_object('previous',prior,'mode',p_mode,'assignments',p_assignments,'revision',version+1));return version+1;
end $$;

create or replace function public.stock_access_directory(p_organisation_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'An Inventory Manager or business-wide Restaurant Administrator must manage department access.' using errcode='42501'; end if;
 select jsonb_build_object('members',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'email',u.email,'display_name',private.pp_member_label(m.organisation_id,m.id),'mode',coalesce(a.mode,case when exists(select 1 from public.membership_roles x where x.organisation_id=m.organisation_id and x.membership_id=m.id and x.role_code in ('stock_department','kitchen_manager','bar_lead','stock_receiver','stock_dispatcher')) then 'ASSIGNED' else 'OUTLET' end),'revision',coalesce(a.revision,0),
  'review_access',exists(select 1 from public.membership_roles r where r.organisation_id=m.organisation_id and r.membership_id=m.id and r.role_code in ('restaurant_admin','inventory_manager','ceo','finance','procurement')),
  'roles',(select jsonb_agg(jsonb_build_object('role_code',r.role_code,'outlet_id',r.location_id,'outlet_name',l.name) order by r.role_code,r.location_id) from public.membership_roles r left join public.locations l on l.organisation_id=r.organisation_id and l.id=r.location_id where r.organisation_id=m.organisation_id and r.membership_id=m.id),
  'assignments',coalesce((select jsonb_agg(jsonb_build_object('location_id',g.location_id,'can_request',g.can_request,'can_handle',g.can_handle,'can_approve',g.can_approve,'can_dispatch',g.can_dispatch,'can_receive',g.can_receive,'can_review_waste',g.can_review_waste,'can_record_waste',g.can_record_waste) order by g.location_id) from public.stock_member_locations g where g.organisation_id=m.organisation_id and g.membership_id=m.id),'[]'::jsonb)) order by u.email,m.id)
 from public.organisation_memberships m join auth.users u on u.id=m.user_id left join public.stock_member_access a on a.organisation_id=m.organisation_id and a.membership_id=m.id
 where m.organisation_id=p_organisation_id and m.status='active' and exists(select 1 from public.membership_roles r where r.organisation_id=m.organisation_id and r.membership_id=m.id and r.role_code in ('inventory','operations','stock_department','kitchen_manager','bar_lead','stock_receiver','stock_dispatcher'))),'[]'::jsonb)) into result;
 return result;
end $$;

create or replace function public.processing_setup(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock setup access required.' using errcode='42501';end if;
 select jsonb_build_object('waste_own_centres',private.pp_waste_own_centres(p_organisation_id),'waste_sites',coalesce((select jsonb_agg(jsonb_build_object('id',ws.id,'name',ws.name,'outlet_id',ws.outlet_id,'is_active',ws.is_active,'can_record',private.pp_can_record_waste(p_organisation_id,ws.id)) order by ws.name,ws.id) from public.stock_locations ws where ws.organisation_id=p_organisation_id and private.pp_waste_site(p_organisation_id,ws.id)),'[]'::jsonb),'processing_centre_id',(select centre_id from public.stock_processing_settings where organisation_id=p_organisation_id),'manage',private.pp_stock_manager(p_organisation_id),'sites',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('responsible_name',private.pp_member_label(m.organisation_id,m.id),'responsible_active',m.status='active','request',private.pp_stock_site(s.organisation_id,s.id,'request')) order by s.name) from public.stock_locations s left join public.organisation_memberships m on m.organisation_id=s.organisation_id and m.id=s.responsible_membership_id left join auth.users u on u.id=m.user_id where s.organisation_id=p_organisation_id and private.pp_stock_site(s.organisation_id,s.id,'read')),'[]'::jsonb),
 'members',case when private.pp_stock_manager(p_organisation_id) then coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'name',private.pp_member_label(m.organisation_id,m.id)) order by u.email) from public.organisation_memberships m join auth.users u on u.id=m.user_id where m.organisation_id=p_organisation_id and m.status='active'),'[]'::jsonb) else '[]'::jsonb end,
 'standards',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('recipe_name',v.name,'output_name',i.name,'output_unit',u.code,'primary_name',p.name,'primary_unit',pu.code,'site_ids',(select jsonb_agg(site_id) from public.processing_standard_sites where organisation_id=s.organisation_id and standard_id=s.id)) order by v.name,s.revision desc)
 from public.processing_standards s join public.recipe_versions v on v.organisation_id=s.organisation_id and v.id=s.recipe_version_id join public.items i on i.organisation_id=s.organisation_id and i.id=s.output_item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id join public.items p on p.organisation_id=s.organisation_id and p.id=s.primary_item_id join public.units_of_measure pu on pu.organisation_id=p.organisation_id and pu.id=p.base_uom_id
 where s.organisation_id=p_organisation_id and s.is_active and(private.pp_stock_manager(p_organisation_id) or exists(select 1 from public.processing_standard_sites ss where ss.organisation_id=s.organisation_id and ss.standard_id=s.id and private.pp_stock_site(p_organisation_id,ss.site_id,'read')))),'[]'::jsonb)) into result;return result;
end $$;

create or replace function private.pp_stock_request_before_named_waste(p_organisation_id uuid,p_request_id uuid,p_document jsonb,p_lines jsonb) returns uuid
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
  if src.id is null or not(case when kind='WASTE' then private.pp_can_record_waste(p_organisation_id,src.id) else private.pp_stock_site(p_organisation_id,src.id,'request') end) then raise exception 'Inventory or Operations access is required at this stock location.' using errcode='42501'; end if;
 end if;
 if kind='WASTE' and not private.pp_waste_site(p_organisation_id,src.id) then raise exception 'Record waste only for your responsible stock centre.' using errcode='42501';end if;
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

create or replace function private.pp_record_named_waste(org uuid,doc uuid,submitter text) returns uuid
language plpgsql security definer set search_path='' as $$
declare d public.stock_documents; line jsonb; name text:=trim(submitter);
begin
 if not private.pp_stock_read(org) then raise exception 'Stock access required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=org for update;
 select * into d from public.stock_documents where organisation_id=org and id=doc and kind='WASTE';
 if not found or not private.pp_stock_doc_read(org,doc) or not private.pp_waste_site(org,d.source_id) or not private.pp_can_record_waste(org,d.source_id) or d.created_by<>auth.uid() then raise exception 'Only the recorder with waste access at this centre can complete this record.' using errcode='42501';end if;
 if name is null or length(name) not between 1 and 120 or name ~ '[[:cntrl:]]' then raise exception 'Enter the submitter name (up to 120 characters).' using errcode='22023';end if;
 if d.state='POSTED' and d.submitter_name=name then return d.id;end if;
 if d.state not in ('REQUESTED','APPROVED') then raise exception 'This waste record is already complete or closed.' using errcode='22023';end if;
 if not exists(select 1 from public.stock_locations where organisation_id=org and id=d.source_id and is_active) then raise exception 'Choose an active stock centre.' using errcode='22023';end if;
 for line in select value from jsonb_array_elements(d.lines) loop
  perform private.pp_stock_entry(org,d.id,d.source_id,(line->>'item_id')::uuid,-(line->>'quantity')::numeric,d.document_date);
 end loop;
 update public.stock_documents set submitter_name=name,state='POSTED',completed_by=auth.uid(),completed_at=clock_timestamp() where id=d.id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(org,'WASTE_RECORDED',auth.uid(),d.id,jsonb_build_object('kind','WASTE','centre',d.source_id,'submitter_name',name,'approval_required',false));
 return d.id;
end $$;

create or replace function private.pp_stock_packet(org uuid, doc uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select to_jsonb(d)||jsonb_build_object('source_name',s.name,'destination_name',t.name,'manager_return',(private.pp_stock_receive_allowed(org,d.id) and d.dispatched_by=auth.uid()),'created_label',a.email,'approved_label',b.email,'dispatched_label',c.email,'completed_label',e.email,
 'finish_waste',d.kind='WASTE' and d.state in ('REQUESTED','APPROVED') and d.created_by=auth.uid() and private.pp_can_record_waste(org,d.source_id),'actions',jsonb_strip_nulls(jsonb_build_object(
 'approve',case when d.kind<>'WASTE' and d.state='REQUESTED' and d.created_by<>auth.uid() and (case when d.kind='WASTE' then private.pp_waste_review(org,d.source_id) when d.kind in ('TRANSFER','ISSUE') then r.is_active and private.pp_stock_route_approver(org,d.source_id,r.approval_role) else private.pp_stock_manager(org) or private.pp_stock_role(org,'finance',null) end) then true end,
 'decline',case when d.kind<>'WASTE' and d.state='REQUESTED' and d.created_by<>auth.uid() and(case when d.kind='WASTE' then private.pp_waste_review(org,d.source_id) else private.pp_stock_manager(org) end) then true end,
 'post',case when d.kind<>'WASTE' and d.state='APPROVED' and d.kind not in ('TRANSFER','ISSUE') and(case when d.kind='WASTE' then d.created_by<>auth.uid() and private.pp_waste_review(org,d.source_id) else private.pp_stock_site(org,coalesce(d.source_id,d.destination_id),'inventory') end) then true end,
 'dispatch',case when d.state='APPROVED' and d.kind in ('TRANSFER','ISSUE') and private.pp_stock_site(org,d.source_id,'dispatch') then true end,
 'receive',case when private.pp_stock_receive_allowed(org,d.id) then true end,'reject',case when private.pp_stock_receive_allowed(org,d.id) then true end,
 'cancel',case when d.state in ('REQUESTED','APPROVED') and (d.created_by=auth.uid() or private.pp_stock_manager(org)) then true end,
 'resolve',case when d.state in ('PARTIAL','REJECTED') and d.resolved_at is null and private.pp_stock_manager(org) then true end)))
 from public.stock_documents d left join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id left join public.stock_locations t on t.organisation_id=d.organisation_id and t.id=d.destination_id
 left join public.stock_routes r on r.organisation_id=d.organisation_id and r.id=d.route_id left join auth.users a on a.id=d.created_by left join auth.users b on b.id=d.approved_by left join auth.users c on c.id=d.dispatched_by left join auth.users e on e.id=d.completed_by
 where d.organisation_id=org and d.id=doc and private.pp_stock_doc_read(org,doc);
$$;

create function public.save_stock_centre_with_access(p_organisation_id uuid,p_value jsonb,p_enable_owner boolean,p_revision integer,p_owner_tasks jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare site uuid; member uuid; rev integer; mode text; grants jsonb; current_grant jsonb; entry jsonb;
begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'Stock setup access required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if p_enable_owner is null then raise exception 'Choose whether to enable owner access.' using errcode='22023';end if;
 site:=public.save_stock_centre(p_organisation_id,p_value);
 if not p_enable_owner then return site;end if;
 member:=(p_value->>'responsible')::uuid;
 if jsonb_typeof(p_owner_tasks) is distinct from 'object' or jsonb_typeof(p_owner_tasks->'can_request') is distinct from 'boolean' or jsonb_typeof(p_owner_tasks->'can_record_waste') is distinct from 'boolean' or jsonb_typeof(p_owner_tasks->'can_receive') is distinct from 'boolean' or p_owner_tasks-array['can_request','can_record_waste','can_receive']<>'{}'::jsonb then raise exception 'Review the owner tasks before saving.' using errcode='22023';end if;
 if not exists(select 1 from public.membership_roles r join public.stock_locations s on s.organisation_id=r.organisation_id and s.id=site where r.organisation_id=p_organisation_id and r.membership_id=member and r.role_code in ('inventory_manager','inventory','operations','stock_department','kitchen_manager','bar_lead') and(r.location_id is null or r.location_id=s.outlet_id)) then raise exception 'Choose an owner with an operational role at this outlet, or save without changing their access.' using errcode='22023';end if;
 select a.revision,a.mode into rev,mode from public.stock_member_access a where a.organisation_id=p_organisation_id and a.membership_id=member;
 rev:=coalesce(rev,0);
 if rev is distinct from p_revision then raise exception 'Team access changed. Refresh and review the owner tasks.' using errcode='22023';end if;
 mode:=coalesce(mode,case when exists(select 1 from public.membership_roles where organisation_id=p_organisation_id and membership_id=member and role_code in ('stock_department','kitchen_manager','bar_lead','stock_receiver','stock_dispatcher')) then 'ASSIGNED' else 'OUTLET' end);
 -- Existing role-wide access stays intact. Owning the centre unlocks its waste scope.
 if mode='OUTLET' then return site;end if;
 select to_jsonb(g)-'organisation_id'-'membership_id' into current_grant from public.stock_member_locations g where g.organisation_id=p_organisation_id and g.membership_id=member and g.location_id=site;
 entry:=coalesce(current_grant,jsonb_build_object('location_id',site,'can_request',false,'can_handle',false,'can_approve',false,'can_dispatch',false,'can_receive',false,'can_record_waste',false,'can_review_waste',false))||p_owner_tasks;
 select coalesce(jsonb_agg(to_jsonb(g)-'organisation_id'-'membership_id'),'[]'::jsonb) into grants from public.stock_member_locations g where g.organisation_id=p_organisation_id and g.membership_id=member and g.location_id<>site;
 perform public.save_stock_member_access(p_organisation_id,member,rev,'ASSIGNED',grants||jsonb_build_array(entry));
 return site;
end $$;
revoke all on function public.save_stock_centre_with_access(uuid,jsonb,boolean,integer,jsonb) from public,anon;
grant execute on function public.save_stock_centre_with_access(uuid,jsonb,boolean,integer,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
