-- Multiple authorised processing centres; multiple inputs, exactly one output per batch.
-- Existing centre flags, baselines, stock balances and historical batch evidence are preserved.
begin;
create table private.processing_centre_revisions(organisation_id uuid primary key references public.organisations(id),revision bigint not null default 0);
revoke all on private.processing_centre_revisions from public,anon,authenticated;
insert into private.processing_centre_revisions(organisation_id) select id from public.organisations;
create function private.pp_processing_centre_revision() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_op='INSERT' or (old.processing_enabled,old.is_active,old.responsible_membership_id) is distinct from (new.processing_enabled,new.is_active,new.responsible_membership_id) then
 insert into private.processing_centre_revisions values(new.organisation_id,1) on conflict(organisation_id) do update set revision=private.processing_centre_revisions.revision+1;end if;return new;end $$;
create trigger processing_centre_revision after insert or update on public.stock_locations for each row execute function private.pp_processing_centre_revision();
create or replace function private.pp_stock_centre_accountability() returns trigger language plpgsql security definer set search_path='' as $$begin
 if (new.processing_enabled or exists(select 1 from public.stock_processing_settings where organisation_id=new.organisation_id)) and new.is_active and not exists(select 1 from public.organisation_memberships where organisation_id=new.organisation_id and id=new.responsible_membership_id and status='active') then raise exception 'Every active processing centre requires an active responsible member.' using errcode='22023';end if;
 if tg_op='UPDATE' and old.processing_enabled and (not new.processing_enabled or not new.is_active) and exists(select 1 from public.stock_documents where organisation_id=new.organisation_id and source_id=new.id and kind='PRODUCTION' and state in ('REQUESTED','APPROVED')) then raise exception 'Finish or cancel pending batches at this centre before disabling production.' using errcode='22023';end if;
 return new;end $$;
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
  if not(p_value?'processing_enabled') then enabled:=old.processing_enabled;end if;
  update public.stock_locations set name=trim(p_value->>'name'),kind=p_value->>'kind',outlet_id=nullif(p_value->>'outlet_id','')::uuid,department=trim(coalesce(p_value->>'department','')) where organisation_id=p_organisation_id and id=site;
 end if;
 update public.stock_locations set processing_enabled=enabled,responsible_membership_id=responsible where organisation_id=p_organisation_id and id=site;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_CENTRE_SETUP',auth.uid(),site,jsonb_build_object('processing_enabled',enabled,'responsible',responsible));return site;
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

-- Retain the old single-unit RPC for compatibility. New setup uses the scoped list below.
create function public.save_processing_centres(p_organisation_id uuid,p_centre_ids uuid[],p_revision bigint) returns bigint language plpgsql security definer set search_path='' as $$
declare current_revision bigint;previous uuid[];chosen uuid[];begin
 if not private.pp_team_manage(p_organisation_id) then raise exception 'Restaurant administrator access is required to enable production centres.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if p_centre_ids is null or cardinality(p_centre_ids)>50 or array_position(p_centre_ids,null) is not null then raise exception 'Choose up to 50 production centres.' using errcode='22023';end if;
 select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) into chosen from unnest(p_centre_ids) x;
 select coalesce((select revision from private.processing_centre_revisions where organisation_id=p_organisation_id),0) into current_revision;
 if p_revision is distinct from current_revision then raise exception 'Centre setup changed. Refresh before saving production permissions.' using errcode='22023';end if;
 if exists(select 1 from unnest(chosen) as u(centre_id) where not exists(select 1 from public.stock_locations s join public.organisation_memberships m on m.organisation_id=s.organisation_id and m.id=s.responsible_membership_id and m.status='active' where s.organisation_id=p_organisation_id and s.id=u.centre_id and s.is_active)) then raise exception 'Choose active centres in this restaurant with active responsible members.' using errcode='22023';end if;
 select coalesce(array_agg(id order by id),'{}'::uuid[]) into previous from public.stock_locations where organisation_id=p_organisation_id and processing_enabled;
 if previous=chosen then return current_revision;end if;
 update public.stock_locations set processing_enabled=(id=any(chosen)) where organisation_id=p_organisation_id and processing_enabled is distinct from (id=any(chosen));
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'PROCESSING_CENTRES_UPDATED',auth.uid(),p_organisation_id,jsonb_build_object('before',previous,'after',chosen));
 return coalesce((select revision from private.processing_centre_revisions where organisation_id=p_organisation_id),0);
end $$;
alter function public.processing_setup(uuid) rename to pp_processing_setup_before_multiple_centres;
alter function public.pp_processing_setup_before_multiple_centres(uuid) set schema private;
revoke all on function private.pp_processing_setup_before_multiple_centres(uuid) from public,anon,authenticated;
create function public.processing_setup(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;centres jsonb;begin
 result:=private.pp_processing_setup_before_multiple_centres(p_organisation_id);
 select coalesce(jsonb_agg(s->'id' order by s->>'name'),'[]'::jsonb) into centres from jsonb_array_elements(result->'sites') s where (s->>'processing_enabled')::boolean and (s->>'is_active')::boolean;
 return result||jsonb_build_object('processing_centre_ids',centres,'processing_centre_id',case when centres @> jsonb_build_array(result->'processing_centre_id') then result->'processing_centre_id' else centres->0 end,'processing_centres_revision',coalesce((select revision from private.processing_centre_revisions where organisation_id=p_organisation_id),0));
end $$;

create or replace function public.save_material_processing_baseline(p_organisation_id uuid,p_request_id uuid,p_value jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare source public.items;produced public.items;site uuid;version_id uuid;result_id uuid;prior private.setup_requests;digest text:=md5(p_value::text);recipe_id uuid;inputs jsonb;components jsonb:='[]';entry jsonb;material public.items;sites jsonb;
begin
 if not private.pp_team_manage(p_organisation_id) or not private.pp_recipe_write(p_organisation_id) then raise exception 'Restaurant administrator access is required for processing master data.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if p_request_id is null or p_value is null or octet_length(p_value::text)>32768 then raise exception 'Refresh and complete the processing baseline.' using errcode='22023';end if;
 select * into prior from private.setup_requests where organisation_id=p_organisation_id and request_id=p_request_id and kind='PROCESSING';
 if found then if prior.input_hash<>digest then raise exception 'Refresh before saving changed baseline details.' using errcode='22023';end if;return prior.result_id;end if;
 sites:=p_value->'site_ids';
 if sites is null then select centre_id into site from public.stock_processing_settings where organisation_id=p_organisation_id;sites:=case when site is null then '[]'::jsonb else jsonb_build_array(site) end;end if;
 if jsonb_typeof(sites) is distinct from 'array' or jsonb_array_length(sites) not between 1 and 50 then raise exception 'Choose at least one permitted production centre.' using errcode='22023';end if;
 inputs:=coalesce(p_value->'inputs',jsonb_build_array(jsonb_build_object('item_id',p_value->>'input_item_id','quantity',p_value->>'input_quantity')));
 if jsonb_typeof(inputs) is distinct from 'array' or jsonb_array_length(inputs) not between 1 and 30 then raise exception 'Enter between 1 and 30 input materials.' using errcode='22023';end if;
 if (select count(*)<>count(distinct value->>'item_id') from jsonb_array_elements(inputs)) then raise exception 'Combine each input material into one baseline line.' using errcode='22023';end if;
 select * into source from public.items where organisation_id=p_organisation_id and id=(p_value->>'input_item_id')::uuid and is_active and stock_tracked and requires_processing and base_uom_id is not null;
 select * into produced from public.items where organisation_id=p_organisation_id and id=(p_value->>'output_item_id')::uuid and is_active and stock_tracked and item_type in ('SEMI_FINISHED','FINISHED') and supply_class in ('PROCESSED','BOTH') and base_uom_id is not null;
 if source.id is null or produced.id is null or source.id=produced.id or not exists(select 1 from jsonb_array_elements(inputs) where value->>'item_id'=source.id::text) then raise exception 'Choose a main input marked Requires processing and a different tracked processed output SKU.' using errcode='22023';end if;
 for entry in select value from jsonb_array_elements(inputs) loop
  select * into material from public.items where organisation_id=p_organisation_id and id=(entry->>'item_id')::uuid and is_active and stock_tracked and base_uom_id is not null;
  if material.id is null or material.id=produced.id then raise exception 'Choose active tracked input materials in this restaurant, distinct from the output.' using errcode='22023';end if;
  perform private.pp_stock_number(entry->>'quantity');
  components:=components||jsonb_build_array(jsonb_build_object('kind','ITEM','target_id',material.id,'quantity',entry->>'quantity','uom_id',material.base_uom_id));
 end loop;
 select distinct rv.recipe_id into recipe_id from public.stock_recipe_bindings b join public.recipe_versions rv on rv.organisation_id=b.organisation_id and rv.id=b.recipe_version_id where b.organisation_id=p_organisation_id and b.item_id=produced.id;
 version_id:=public.publish_recipe_setup(p_organisation_id,p_request_id,jsonb_build_object('recipe_id',recipe_id,'code',p_value->>'code','name',p_value->>'name','recipe_type','SUB_RECIPE','effective_from',p_value->>'effective_from','yield_quantity',p_value->>'output_quantity','yield_uom_id',produced.base_uom_id,'location_id',source.location_id,'notes','Single-output material production baseline'),components);
 perform public.save_stock_configuration(p_organisation_id,'BINDING',jsonb_build_object('recipe_version_id',version_id,'item_id',produced.id));
 result_id:=public.save_processing_standard(p_organisation_id,p_request_id,jsonb_build_object('recipe_version_id',version_id,'primary_item_id',source.id,'output_spec',p_value->>'output_spec','tolerance_percent',p_value->>'tolerance_percent','site_ids',sites,'target_piece_weight_kg',p_value->>'target_piece_weight_kg','expected_trim_kg',p_value->>'expected_trim_kg'));
 insert into private.setup_requests values(p_organisation_id,p_request_id,'PROCESSING',digest,result_id);return result_id;
end $$;
-- Recompute readiness against all enabled, owned centres, not the legacy default pointer.
alter function public.setup_workspace(uuid) rename to pp_setup_before_multiple_centres;
alter function public.pp_setup_before_multiple_centres(uuid) set schema private;
revoke all on function private.pp_setup_before_multiple_centres(uuid) from public,anon,authenticated;
create function public.setup_workspace(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;stages jsonb;begin
 result:=private.pp_setup_before_multiple_centres(p_organisation_id);
 select jsonb_agg(case when value->>'name'='Processing baselines' then value||jsonb_build_object('detail','Enabled production centres and versioned single-output baselines','ready',not exists(select 1 from public.items i where i.organisation_id=p_organisation_id and i.is_active and i.requires_processing and not exists(select 1 from public.processing_standards ps join public.processing_standard_sites ss on ss.organisation_id=ps.organisation_id and ss.standard_id=ps.id join public.stock_locations s on s.organisation_id=ss.organisation_id and s.id=ss.site_id join public.organisation_memberships m on m.organisation_id=s.organisation_id and m.id=s.responsible_membership_id and m.status='active' where ps.organisation_id=i.organisation_id and ps.primary_item_id=i.id and ps.is_active and s.is_active and s.processing_enabled))) else value end order by n) into stages from jsonb_array_elements(result->'progress'->'stages') with ordinality as t(value,n);
 if stages is not null then result:=jsonb_set(result,'{progress,stages}',stages);result:=jsonb_set(result,'{progress,completed}',to_jsonb((select count(*) from jsonb_array_elements(stages) where (value->>'ready')::boolean)));end if;return result;
end $$;
revoke all on function private.pp_processing_centre_revision(),private.pp_stock_centre_accountability() from public,anon,authenticated;
revoke all on function public.save_processing_centres(uuid,uuid[],bigint),public.processing_setup(uuid),public.setup_workspace(uuid) from public,anon;
grant execute on function public.save_processing_centres(uuid,uuid[],bigint),public.processing_setup(uuid),public.setup_workspace(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
