-- Guided stock centres, immutable processing standards and measured production.
-- Existing batches remain readable; new measured batches retain their standard and actual evidence.
begin;
alter table public.stock_locations add column processing_enabled boolean not null default false,add column responsible_membership_id uuid,
 add foreign key(organisation_id,responsible_membership_id) references public.organisation_memberships(organisation_id,id);
create table public.processing_standards(
 id uuid primary key default gen_random_uuid(),organisation_id uuid not null references public.organisations(id),recipe_version_id uuid not null,revision integer not null,
 request_id uuid not null,input_hash text not null,output_item_id uuid not null,primary_item_id uuid not null,primary_quantity numeric(38,12) not null check(primary_quantity>0),
 expected_output numeric(38,12) not null check(expected_output>0),inputs jsonb not null,output_spec text not null check(length(output_spec) between 1 and 1000),
 target_piece_weight_kg numeric(20,6) check(target_piece_weight_kg>0),expected_trim_kg numeric(20,6) check(expected_trim_kg>=0),tolerance_percent numeric(9,6) not null check(tolerance_percent between 0 and 100),
 is_active boolean not null default true,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(organisation_id,id),unique(organisation_id,recipe_version_id,revision),unique(organisation_id,request_id),
 foreign key(organisation_id,recipe_version_id) references public.recipe_versions(organisation_id,id),foreign key(organisation_id,output_item_id) references public.items(organisation_id,id),foreign key(organisation_id,primary_item_id) references public.items(organisation_id,id));
create table public.processing_standard_sites(organisation_id uuid not null,standard_id uuid not null,site_id uuid not null,primary key(organisation_id,standard_id,site_id),foreign key(organisation_id,standard_id) references public.processing_standards(organisation_id,id),foreign key(organisation_id,site_id) references public.stock_locations(organisation_id,id));
create table public.processing_batches(organisation_id uuid not null,document_id uuid not null,standard_id uuid not null,expected_output numeric(38,12) not null,actual_output numeric(38,12) not null,
 output_variance numeric(38,12) not null,variance_percent numeric not null,outside_tolerance boolean not null,usable_weight_kg numeric(20,6),variance_reason text not null,primary_actual numeric(38,12) not null,responsible_name text not null,input_weight_kg numeric(38,12),waste_weight_kg numeric(38,12),mass_balance_kg numeric(38,12),
 primary key(organisation_id,document_id),foreign key(organisation_id,document_id) references public.stock_documents(organisation_id,id),foreign key(organisation_id,standard_id) references public.processing_standards(organisation_id,id));
create table public.processing_waste(organisation_id uuid not null,document_id uuid not null,item_id uuid not null,quantity numeric(38,12) not null check(quantity>0),reason text not null check(length(reason) between 1 and 500),primary key(organisation_id,document_id,item_id),foreign key(organisation_id,document_id) references public.processing_batches(organisation_id,document_id),foreign key(organisation_id,item_id) references public.items(organisation_id,id));
create table private.processing_batch_costs(organisation_id uuid not null,document_id uuid not null,value jsonb not null,created_at timestamptz not null default now(),primary key(organisation_id,document_id),foreign key(organisation_id,document_id) references public.processing_batches(organisation_id,document_id));
revoke all on private.processing_batch_costs from public,anon,authenticated;
do $$declare name text;begin foreach name in array array['processing_standards','processing_standard_sites','processing_batches','processing_waste'] loop
 execute format('alter table public.%I enable row level security',name);execute format('revoke all on public.%I from public,anon,authenticated',name);
 execute format('create trigger restaurant_active_write before insert or update or delete on public.%I for each row execute function private.pp_require_active_restaurant()',name);
end loop;end $$;
create function private.pp_processing_inputs(org uuid,version uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if exists(select 1 from public.recipe_components c left join public.stock_recipe_bindings b on b.organisation_id=c.organisation_id and b.recipe_version_id=c.child_recipe_version_id where c.organisation_id=org and c.recipe_version_id=version and c.child_recipe_version_id is not null and b.item_id is null) then raise exception 'Link each stocked sub-recipe output before configuring this processing standard.' using errcode='22023';end if;
 select jsonb_agg(jsonb_build_object('item_id',q.item_id,'quantity',q.quantity::text,'name',i.name,'code',i.code,'unit',u.code) order by i.name,i.id) into result
 from(select coalesce(c.item_id,b.item_id) item_id,sum(c.normalised_quantity*case when c.item_id is not null then 1 else bu.canonical_factor/iu.canonical_factor end) quantity
 from public.recipe_components c left join public.stock_recipe_bindings b on b.organisation_id=c.organisation_id and b.recipe_version_id=c.child_recipe_version_id
 left join public.items ci on ci.organisation_id=b.organisation_id and ci.id=b.item_id left join public.units_of_measure bu on bu.organisation_id=c.organisation_id and bu.id=c.base_uom_id left join public.units_of_measure iu on iu.organisation_id=ci.organisation_id and iu.id=ci.base_uom_id
 where c.organisation_id=org and c.recipe_version_id=version group by coalesce(c.item_id,b.item_id))q
 join public.items i on i.organisation_id=org and i.id=q.item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id;
 if result is null then raise exception 'Recipe inputs are unavailable.' using errcode='22023';end if;return result;
end $$;
create function public.save_stock_centre(p_organisation_id uuid,p_value jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare site uuid:=nullif(p_value->>'id','')::uuid;responsible uuid:=nullif(p_value->>'responsible','')::uuid;enabled boolean:=(p_value->>'processing_enabled')::boolean;old public.stock_locations;
begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'Stock setup access required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if enabled is null or octet_length(p_value::text)>8192 or p_value->>'code'!~'^[A-Z0-9][A-Z0-9_-]{0,39}$' or length(trim(coalesce(p_value->>'name',''))) not between 1 and 120 or p_value->>'kind' not in ('WAREHOUSE','STORE','KITCHEN','BAR','PRODUCTION') then raise exception 'Enter a centre code, name and storage type.' using errcode='22023';end if;
 if responsible is not null and not exists(select 1 from public.organisation_memberships where organisation_id=p_organisation_id and id=responsible and status='active') then raise exception 'Choose an active responsible member from this restaurant.' using errcode='22023';end if;
 if enabled and responsible is null then raise exception 'Assign a responsible member before enabling processing.' using errcode='22023';end if;
 perform private.pp_setup_location(p_organisation_id,nullif(p_value->>'outlet_id','')::uuid);
 if site is null then site:=public.save_stock_configuration(p_organisation_id,'LOCATION',p_value);
 else
  select * into old from public.stock_locations where organisation_id=p_organisation_id and id=site for update;
  if not found or old.code is distinct from p_value->>'code' then raise exception 'Choose an existing centre; its code cannot change.' using errcode='22023';end if;
  if (old.outlet_id is distinct from nullif(p_value->>'outlet_id','')::uuid or old.kind is distinct from p_value->>'kind') and exists(select 1 from public.stock_documents where organisation_id=p_organisation_id and(source_id=site or destination_id=site)) then raise exception 'A centre with movement history must keep its outlet and storage type. Create a new centre instead.' using errcode='22023';end if;
  update public.stock_locations set name=trim(p_value->>'name'),kind=p_value->>'kind',outlet_id=nullif(p_value->>'outlet_id','')::uuid,department=trim(coalesce(p_value->>'department','')) where organisation_id=p_organisation_id and id=site;
 end if;
 update public.stock_locations set processing_enabled=enabled,responsible_membership_id=responsible where organisation_id=p_organisation_id and id=site;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_CENTRE_SETUP',auth.uid(),site,jsonb_build_object('processing_enabled',enabled,'responsible',responsible));return site;
end $$;
create function public.processing_output_choices(p_organisation_id uuid,p_search text default '',p_version_id uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;expected_dimension text;
begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock access required.' using errcode='42501';end if;
 if p_search is null or length(p_search)>80 then raise exception 'Use a search of up to 80 characters.' using errcode='22023';end if;
 if p_version_id is not null then select u.dimension into expected_dimension from public.recipe_outputs o join public.units_of_measure u on u.organisation_id=o.organisation_id and u.id=o.uom_id where o.organisation_id=p_organisation_id and o.recipe_version_id=p_version_id;if not found then raise exception 'Recipe unavailable.' using errcode='22023';end if;end if;
 with choices as(select i.id,i.code,i.name,u.code unit,array_remove(array[case when not i.is_active then 'Activate material' end,case when not i.stock_tracked then 'Enable stock tracking' end,case when i.item_type not in ('SEMI_FINISHED','FINISHED') then 'Set type to Semi-finished or Finished' end,case when i.base_uom_id is null then 'Add base unit' when expected_dimension is not null and u.dimension<>expected_dimension then 'Base unit does not match recipe output' end],null) issues
 from public.items i left join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id where i.organisation_id=p_organisation_id and(trim(p_search)='' or position(lower(trim(p_search)) in lower(i.name||' '||i.code))>0))
 select jsonb_build_object('total',(select count(*) from choices),'rows',coalesce((select jsonb_agg(to_jsonb(c) order by name,id) from(select * from choices order by name,id limit 25)c),'[]'::jsonb)) into result;return result;
end $$;
create function public.processing_setup(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock setup access required.' using errcode='42501';end if;
 select jsonb_build_object('manage',private.pp_stock_manager(p_organisation_id),'sites',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('responsible_name',u.email,'responsible_active',m.status='active','request',private.pp_stock_site(s.organisation_id,s.id,'request')) order by s.name) from public.stock_locations s left join public.organisation_memberships m on m.organisation_id=s.organisation_id and m.id=s.responsible_membership_id left join auth.users u on u.id=m.user_id where s.organisation_id=p_organisation_id and private.pp_stock_site(s.organisation_id,s.id,'read')),'[]'::jsonb),
 'members',case when private.pp_stock_manager(p_organisation_id) then coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'name',u.email) order by u.email) from public.organisation_memberships m join auth.users u on u.id=m.user_id where m.organisation_id=p_organisation_id and m.status='active'),'[]'::jsonb) else '[]'::jsonb end,
 'standards',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('recipe_name',v.name,'output_name',i.name,'output_unit',u.code,'primary_name',p.name,'primary_unit',pu.code,'site_ids',(select jsonb_agg(site_id) from public.processing_standard_sites where organisation_id=s.organisation_id and standard_id=s.id)) order by v.name,s.revision desc)
 from public.processing_standards s join public.recipe_versions v on v.organisation_id=s.organisation_id and v.id=s.recipe_version_id join public.items i on i.organisation_id=s.organisation_id and i.id=s.output_item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id join public.items p on p.organisation_id=s.organisation_id and p.id=s.primary_item_id join public.units_of_measure pu on pu.organisation_id=p.organisation_id and pu.id=p.base_uom_id
 where s.organisation_id=p_organisation_id and s.is_active and(private.pp_stock_manager(p_organisation_id) or exists(select 1 from public.processing_standard_sites ss where ss.organisation_id=s.organisation_id and ss.standard_id=s.id and private.pp_stock_site(p_organisation_id,ss.site_id,'read')))),'[]'::jsonb)) into result;return result;
end $$;
create function public.processing_recipe_inputs(p_organisation_id uuid,p_version_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'Processing setup access required.' using errcode='42501';end if;return private.pp_processing_inputs(p_organisation_id,p_version_id);end $$;
create function public.save_processing_standard(p_organisation_id uuid,p_request_id uuid,p_value jsonb) returns uuid language plpgsql security definer set search_path='' as $$
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
create function private.pp_protect_processing_standard() returns trigger language plpgsql set search_path='' as $$begin
 if TG_OP='DELETE' or(to_jsonb(new)-'is_active') is distinct from(to_jsonb(old)-'is_active') then raise exception 'Processing baselines are immutable. Save a new standard revision.' using errcode='22023';end if;return new;end $$;
create trigger protect_processing_standard before update or delete on public.processing_standards for each row execute function private.pp_protect_processing_standard();
create function private.pp_pin_processing_binding() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from public.processing_standards where organisation_id=old.organisation_id and(recipe_version_id=old.recipe_version_id or exists(select 1 from public.recipe_components c where c.organisation_id=old.organisation_id and c.recipe_version_id=processing_standards.recipe_version_id and c.child_recipe_version_id=old.recipe_version_id))) and new.item_id is distinct from old.item_id then raise exception 'This output is pinned by a processing standard. Publish a new recipe version to change its produced SKU.' using errcode='22023';end if;return new;end $$;
create trigger pin_processing_binding before update on public.stock_recipe_bindings for each row execute function private.pp_pin_processing_binding();
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
  insert into public.processing_batches values(p_organisation_id,result,standard.id,expected_base,(output->>'quantity')::numeric,(output->>'output_variance')::numeric,deviation,outside,usable,reason,primary_actual,coalesce((select u.email from public.organisation_memberships m join auth.users u on u.id=m.user_id where m.organisation_id=p_organisation_id and m.id=src.responsible_membership_id),'Assigned member'),input_mass,waste_mass,mass_balance);
  insert into public.processing_waste select p_organisation_id,result,(value->>'item_id')::uuid,(value->>'quantity')::numeric,trim(value->>'reason') from jsonb_array_elements(waste);
 end if;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_REQUESTED',auth.uid(),result,jsonb_build_object('kind',kind));
 return result;
end $$;

create function private.pp_processing_cost_snapshot(org uuid,doc uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d public.stock_documents;b public.processing_batches;s public.processing_standards;line jsonb;price jsonb;items jsonb:='[]';total numeric:=0;missing integer:=0;amount numeric;baseline jsonb;yield_qty numeric;currency text;
begin
 select * into d from public.stock_documents where organisation_id=org and id=doc;
 select * into b from public.processing_batches where organisation_id=org and document_id=doc;
 select * into s from public.processing_standards where organisation_id=org and id=b.standard_id;
 select currency_code into currency from public.organisations where id=org;
 for line in select value from jsonb_array_elements(d.lines) loop
  price:=private.pp_effective_material_cost(org,(line->>'item_id')::uuid,d.document_date,array[]::uuid[]);
  if (line->>'quantity')::numeric=0 then amount:=0;elsif price->>'unit_cost' is null then amount:=null;missing:=missing+1;else amount:=(line->>'quantity')::numeric*(price->>'unit_cost')::numeric;end if;
  total:=total+coalesce(amount,0);items:=items||jsonb_build_array(jsonb_build_object('item_id',line->>'item_id','quantity',line->>'quantity','amount',amount::text,'source',price));
 end loop;
 select quantity into yield_qty from public.recipe_outputs where organisation_id=org and recipe_version_id=s.recipe_version_id;
 baseline:=private.pp_recipe_cost(org,s.recipe_version_id,d.document_date,yield_qty,array[]::uuid[]);
 return jsonb_build_object('basis','POSTED_BATCH_ESTIMATE_V1','currency',currency,'as_of',d.document_date,'missing',missing,'lines',items,
 'batch_cost',case when missing=0 then round(total,12)::text end,'known_subtotal',round(total,12)::text,
 'actual_unit_cost',case when missing=0 and b.actual_output>0 then round(total/b.actual_output,12)::text end,
 'standard_unit_cost',case when baseline->>'cost_state'='ESTIMATED' then round((baseline->>'batch_cost')::numeric/s.expected_output,12)::text end);
end $$;
alter function public.stock_document_action(uuid,uuid,text,text,jsonb) rename to pp_stock_action_before_processing;
alter function public.pp_stock_action_before_processing(uuid,uuid,text,text,jsonb) set schema private;
revoke all on function private.pp_stock_action_before_processing(uuid,uuid,text,text,jsonb) from public,anon,authenticated;
create function public.stock_document_action(p_organisation_id uuid,p_document_id uuid,p_action text,p_note text,p_received jsonb default null) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock access required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if p_action='POST' and exists(select 1 from public.processing_batches where organisation_id=p_organisation_id and document_id=p_document_id) then
  if not exists(select 1 from public.stock_documents d join public.processing_batches b on b.organisation_id=d.organisation_id and b.document_id=d.id join public.processing_standard_sites ss on ss.organisation_id=b.organisation_id and ss.standard_id=b.standard_id and ss.site_id=d.source_id join public.stock_locations s on s.organisation_id=ss.organisation_id and s.id=ss.site_id join public.organisation_memberships m on m.organisation_id=s.organisation_id and m.id=s.responsible_membership_id and m.status='active' where d.organisation_id=p_organisation_id and d.id=p_document_id and s.is_active and s.processing_enabled) then raise exception 'This processing centre was disabled or its responsible membership is inactive. Resolve setup before posting.' using errcode='22023';end if;
 end if;
 result:=private.pp_stock_action_before_processing(p_organisation_id,p_document_id,p_action,p_note,p_received);
 if p_action='POST' and exists(select 1 from public.processing_batches where organisation_id=p_organisation_id and document_id=result) then insert into private.processing_batch_costs values(p_organisation_id,result,private.pp_processing_cost_snapshot(p_organisation_id,result),now()) on conflict do nothing;end if;
 return result;
end $$;
create function public.processing_activity(p_organisation_id uuid,p_site_id uuid,p_from date,p_to date,p_kind text default 'BATCHES',p_page integer default 1,p_state text default 'ALL') returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock history access required.' using errcode='42501';end if;
 if p_site_id is not null and not private.pp_stock_site(p_organisation_id,p_site_id,'read') then raise exception 'Stock centre unavailable.' using errcode='42501';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>366 or p_kind is null or p_kind not in ('BATCHES','WASTE') or p_page is null or p_page not between 1 and 100000 or p_state is null or p_state not in ('ALL','REQUESTED','APPROVED','POSTED','CANCELLED','REJECTED') then raise exception 'Choose dates within 367 days, a record type and a valid page.' using errcode='22023';end if;
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
 where d.organisation_id=p_organisation_id and d.document_date between p_from and p_to and(p_state='ALL' or d.state=p_state) and(p_site_id is null or d.source_id=p_site_id) and private.pp_stock_doc_read(p_organisation_id,d.id)
 union all
 select d.id,d.reference,d.document_date,d.state,s.id,s.name,i.id,i.name,u.code,l->>'quantity',d.note,false from public.stock_documents d cross join lateral jsonb_array_elements(d.lines) l join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id join public.items i on i.organisation_id=d.organisation_id and i.id=(l->>'item_id')::uuid join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id
 where d.organisation_id=p_organisation_id and d.kind='WASTE' and d.document_date between p_from and p_to and(p_state='ALL' or d.state=p_state) and(p_site_id is null or d.source_id=p_site_id) and private.pp_stock_doc_read(p_organisation_id,d.id)),paged as(select * from rows order by document_date desc,id,item_id limit 10 offset(p_page-1)*10)
 select jsonb_build_object('total',(select count(*) from rows),'rows',coalesce((select jsonb_agg(to_jsonb(p) order by document_date desc,id,item_id) from paged p),'[]'::jsonb)) into result;
 end if;return result;
end $$;
-- Protect standards and measurements from direct edits; operational writes remain through checked RPCs.
revoke all on function private.pp_processing_inputs(uuid,uuid),private.pp_protect_processing_standard(),private.pp_pin_processing_binding(),private.pp_processing_cost_snapshot(uuid,uuid) from public,anon,authenticated;
revoke all on function public.save_stock_centre(uuid,jsonb),public.processing_output_choices(uuid,text,uuid),public.processing_setup(uuid),public.processing_recipe_inputs(uuid,uuid),public.save_processing_standard(uuid,uuid,jsonb),public.processing_activity(uuid,uuid,date,date,text,integer,text),public.stock_document_action(uuid,uuid,text,text,jsonb) from public,anon;
grant execute on function public.save_stock_centre(uuid,jsonb),public.processing_output_choices(uuid,text,uuid),public.processing_setup(uuid),public.processing_recipe_inputs(uuid,uuid),public.save_processing_standard(uuid,uuid,jsonb),public.processing_activity(uuid,uuid,date,date,text,integer,text),public.stock_document_action(uuid,uuid,text,text,jsonb) to authenticated;

alter function private.pp_setup_progress(uuid) rename to pp_setup_before_processing_centres;
revoke all on function private.pp_setup_before_processing_centres(uuid) from public,anon,authenticated;
create function private.pp_setup_progress(org uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;stages jsonb;begin
 result:=private.pp_setup_before_processing_centres(org);stages:=result->'stages';
 stages:=stages||jsonb_build_array(jsonb_build_object('name','Stock centres','ready',exists(select 1 from public.stock_locations where organisation_id=org and is_active) and not exists(select 1 from public.stock_locations s where s.organisation_id=org and s.is_active and not exists(select 1 from public.organisation_memberships m where m.organisation_id=s.organisation_id and m.id=s.responsible_membership_id and m.status='active')),'path','/workspace/setup/centres','detail','Named storage centres and responsible members'));
 if exists(select 1 from public.items where organisation_id=org and is_active and supply_class='PROCESSED') then stages:=stages||jsonb_build_array(jsonb_build_object('name','Processing baselines','ready',not exists(select 1 from public.items i where i.organisation_id=org and i.is_active and i.supply_class='PROCESSED' and not exists(select 1 from public.processing_standards s where s.organisation_id=org and s.output_item_id=i.id and s.is_active)),'path','/workspace/setup/production','detail','Versioned yields and permitted processing centres'));end if;
 return result||jsonb_build_object('stages',stages,'total',jsonb_array_length(stages),'completed',(select count(*) from jsonb_array_elements(stages)s where(s->>'ready')::boolean));
end $$;
revoke all on function private.pp_setup_progress(uuid) from public,anon,authenticated;


create function private.pp_processing_immutable() returns trigger language plpgsql set search_path='' as $$begin raise exception 'Processing evidence is immutable. Record a new revision or a corrective stock document.' using errcode='22023';end $$;
create trigger processing_batch_immutable before update or delete on public.processing_batches for each row execute function private.pp_processing_immutable();
create trigger processing_waste_immutable before update or delete on public.processing_waste for each row execute function private.pp_processing_immutable();
create trigger processing_sites_immutable before update or delete on public.processing_standard_sites for each row execute function private.pp_processing_immutable();
create trigger processing_cost_immutable before update or delete on private.processing_batch_costs for each row execute function private.pp_processing_immutable();
revoke all on function private.pp_processing_immutable() from public,anon,authenticated;


alter function public.executive_profitability_briefing(uuid,date,date,uuid) rename to pp_executive_before_processing_centres;
alter function public.pp_executive_before_processing_centres(uuid,date,date,uuid) set schema private;
revoke all on function private.pp_executive_before_processing_centres(uuid,date,date,uuid) from public,anon,authenticated;
create function public.executive_profitability_briefing(p_organisation_id uuid,p_from date,p_to date,p_location_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;processing jsonb;begin
 result:=private.pp_executive_before_processing_centres(p_organisation_id,p_from,p_to,p_location_id);
 with batches as materialized(select d.id,d.reference,d.source_id,s.name centre,v.name recipe,u.code output_unit,b.expected_output::text expected_output,b.actual_output::text actual_output,b.variance_percent::text variance_percent,b.outside_tolerance,b.mass_balance_kg::text unexplained_weight_kg,b.responsible_name,c.value->>'actual_unit_cost' actual_unit_cost,c.value->>'standard_unit_cost' standard_unit_cost
 from public.processing_batches b join public.stock_documents d on d.organisation_id=b.organisation_id and d.id=b.document_id join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id join public.processing_standards ps on ps.organisation_id=b.organisation_id and ps.id=b.standard_id join public.recipe_versions v on v.organisation_id=ps.organisation_id and v.id=ps.recipe_version_id join public.items i on i.organisation_id=ps.organisation_id and i.id=ps.output_item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id left join private.processing_batch_costs c on c.organisation_id=b.organisation_id and c.document_id=b.document_id
 where d.organisation_id=p_organisation_id and d.state='POSTED' and d.document_date between p_from and p_to and(p_location_id is null or s.outlet_id=p_location_id)),exceptions as(select * from batches where outside_tolerance or coalesce(unexplained_weight_kg::numeric,0)>0.000001)
 select jsonb_build_object('batches',(select count(*) from batches),'exceptions',(select count(*) from exceptions),'rows',coalesce((select jsonb_agg(to_jsonb(e)) from(select * from exceptions order by abs(variance_percent::numeric) desc,id limit 5)e),'[]'::jsonb)) into processing;
 return result||jsonb_build_object('processing',processing);
end $$;
revoke all on function public.executive_profitability_briefing(uuid,date,date,uuid) from public,anon;
grant execute on function public.executive_profitability_briefing(uuid,date,date,uuid) to authenticated;

notify pgrst,'reload schema';
commit;
