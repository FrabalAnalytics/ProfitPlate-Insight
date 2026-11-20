-- Read-only centre material planning. No requisitions, reservations or ledger writes.
begin;
create function private.pp_material_plan_access(org uuid,site uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.pp_stock_read(org) and exists(select 1 from public.stock_locations s where s.organisation_id=org and s.id=site and s.is_active and (private.pp_stock_manager(org) or private.pp_stock_site(org,site,'request')));
$$;
create function public.material_plan_options(p_organisation_id uuid,p_site_id uuid default null,p_date date default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;day date;begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock planning access required.' using errcode='42501';end if;
 day:=coalesce(p_date,(select (now() at time zone time_zone)::date from public.organisations where id=p_organisation_id));
 if p_site_id is not null and not private.pp_material_plan_access(p_organisation_id,p_site_id) then raise exception 'Planning access is required at this centre.' using errcode='42501';end if;
 select jsonb_build_object('centres',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name) from public.stock_locations s where s.organisation_id=p_organisation_id and private.pp_material_plan_access(p_organisation_id,s.id)),'[]'::jsonb),
 'recipes',coalesce((select jsonb_agg(to_jsonb(q) order by q.name,q.version desc) from (
 select distinct on(v.recipe_id) v.id,v.recipe_id,v.name,r.code,v.version,r.recipe_type,v.effective_from,o.quantity::text batch_yield,u.code unit,
 (select ps.id from public.processing_standards ps join public.processing_standard_sites ss on ss.organisation_id=ps.organisation_id and ss.standard_id=ps.id where ps.organisation_id=v.organisation_id and ps.recipe_version_id=v.id and ps.is_active and ss.site_id=p_site_id order by ps.revision desc limit 1) baseline_id
 from public.recipe_versions v join public.recipes r on r.organisation_id=v.organisation_id and r.id=v.recipe_id join public.recipe_outputs o on o.organisation_id=v.organisation_id and o.recipe_version_id=v.id join public.units_of_measure u on u.organisation_id=o.organisation_id and u.id=o.uom_id
 join public.stock_locations s on s.organisation_id=v.organisation_id and s.id=p_site_id
 where v.organisation_id=p_organisation_id and v.effective_from<=day and(r.location_id is null or r.location_id=s.outlet_id)
 order by v.recipe_id,v.effective_from desc,v.version desc)q),'[]'::jsonb),'date',day) into result;
 return result;
end $$;
create function private.pp_material_plan_expand(org uuid,version uuid,factor numeric,day date,mode text,site uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare queue jsonb:=jsonb_build_array(jsonb_build_object('version',version,'factor',factor::text,'path',jsonb_build_array(version)));node jsonb;component record;child public.recipe_versions;output public.recipe_outputs;material public.items;binding uuid;qty numeric;conversion numeric;result jsonb:='[]';steps integer:=0;baseline public.processing_standards;
begin
 -- A permitted baseline pins its saved material inputs. Expanding sub-recipes uses the pinned recipe composition instead.
 if mode='STOCK' then
 select ps.* into baseline from public.processing_standards ps join public.processing_standard_sites ss on ss.organisation_id=ps.organisation_id and ss.standard_id=ps.id where ps.organisation_id=org and ps.recipe_version_id=version and ps.is_active and ss.site_id=site order by ps.revision desc limit 1;
 if found then return(select jsonb_agg(jsonb_build_object('item_id',value->>'item_id','quantity',((value->>'quantity')::numeric*factor)::text)) from jsonb_array_elements(baseline.inputs));end if;
 end if;
 while jsonb_array_length(queue)>0 loop
  node:=queue->0;queue:=queue-0;
  if jsonb_array_length(node->'path')>20 then raise exception 'Recipe nesting exceeds the planning limit.' using errcode='22023';end if;
  if not exists(select 1 from public.recipe_components where organisation_id=org and recipe_version_id=(node->>'version')::uuid) then raise exception 'A selected recipe has no usable components.' using errcode='22023';end if;
  for component in select * from public.recipe_components where organisation_id=org and recipe_version_id=(node->>'version')::uuid order by line_no loop
   steps:=steps+1;if steps>5000 then raise exception 'Recipe plan is too large. Split it into smaller plans.' using errcode='22023';end if;
   qty:=component.normalised_quantity*(node->>'factor')::numeric;
   if qty<=0 or qty>=1e26 then raise exception 'Material requirements exceed supported quantities.' using errcode='22023';end if;
   if component.item_id is not null then result:=result||jsonb_build_array(jsonb_build_object('item_id',component.item_id,'quantity',qty::text));
   else
    select * into child from public.recipe_versions where organisation_id=org and id=component.child_recipe_version_id and effective_from<=day;
    if not found then raise exception 'A saved sub-recipe is unavailable on the plan date.' using errcode='22023';end if;
    select * into output from public.recipe_outputs where organisation_id=org and recipe_version_id=child.id;
    if not found or output.quantity<=0 then raise exception 'A saved sub-recipe needs a usable yield.' using errcode='22023';end if;
    binding:=null;
    if mode='STOCK' then select item_id into binding from public.stock_recipe_bindings where organisation_id=org and recipe_version_id=child.id;end if;
    if binding is not null then
     select * into material from public.items where organisation_id=org and id=binding;
     select a.canonical_factor/b.canonical_factor into conversion from public.units_of_measure a join public.units_of_measure b on b.organisation_id=a.organisation_id and b.id=material.base_uom_id and b.dimension=a.dimension where a.organisation_id=org and a.id=component.base_uom_id;
     if conversion is null then raise exception 'A stocked sub-recipe has incompatible output units.' using errcode='22023';end if;
     result:=result||jsonb_build_array(jsonb_build_object('item_id',binding,'quantity',(qty*conversion)::text));
    else
     if node->'path' @> jsonb_build_array(child.id) then raise exception 'Circular sub-recipes cannot be planned.' using errcode='22023';end if;
     queue:=queue||jsonb_build_array(jsonb_build_object('version',child.id,'factor',(qty/output.quantity)::text,'path',(node->'path')||jsonb_build_array(child.id)));
    end if;
   end if;
  end loop;
 end loop;return result;
end $$;
create function public.generate_material_plan(p_organisation_id uuid,p_site_id uuid,p_date date,p_rows jsonb,p_basis text default 'STOCK') returns jsonb language plpgsql stable security definer set search_path='' as $$
declare options jsonb;entry jsonb;recipe jsonb;qty numeric;requirements jsonb:='[]';sources jsonb:='[]';materials jsonb;expanded jsonb;today date;begin
 if not private.pp_material_plan_access(p_organisation_id,p_site_id) then raise exception 'Planning access is required at this centre.' using errcode='42501';end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 if p_date is null or p_date<today-366 or p_date>today+366 or p_basis not in ('STOCK','RECIPE') or p_basis is null then raise exception 'Choose a plan date within one year and a valid requirement basis.' using errcode='22023';end if;
 if p_rows is null or octet_length(p_rows::text)>32768 or jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) not between 1 and 30 then raise exception 'Select between 1 and 30 recipes.' using errcode='22023';end if;
 if(select count(*)<>count(distinct value->>'recipe_version_id') from jsonb_array_elements(p_rows)) then raise exception 'Combine each recipe target into one line.' using errcode='22023';end if;
 options:=public.material_plan_options(p_organisation_id,p_site_id,p_date);
 for entry in select value from jsonb_array_elements(p_rows) loop
  select value into recipe from jsonb_array_elements(options->'recipes') where value->>'id'=entry->>'recipe_version_id';
  if recipe is null then raise exception 'A recipe changed or is outside this centre/date. Reload recipes and review your targets.' using errcode='22023';end if;
  qty:=private.pp_stock_number(entry->>'quantity');
  expanded:=private.pp_material_plan_expand(p_organisation_id,(recipe->>'id')::uuid,qty/(recipe->>'batch_yield')::numeric,p_date,p_basis,p_site_id);
  if expanded is null then raise exception 'Recipe inputs are incomplete.' using errcode='22023';end if;
  select jsonb_agg(jsonb_build_object('item_id',item_id,'quantity',quantity::text)) into expanded from(select value->>'item_id' item_id,sum((value->>'quantity')::numeric) quantity from jsonb_array_elements(expanded) group by value->>'item_id')q;
  requirements:=requirements||expanded;
  sources:=sources||jsonb_build_array(recipe||jsonb_build_object('target_quantity',qty::text,'requirements',expanded));
 end loop;
 if exists(select 1 from jsonb_array_elements(requirements) r left join public.items i on i.organisation_id=p_organisation_id and i.id=(r->>'item_id')::uuid left join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id where i.id is null or not i.is_active or u.id is null or (i.location_id is not null and (select outlet_id from public.stock_locations where id=p_site_id) is not null and i.location_id<>(select outlet_id from public.stock_locations where id=p_site_id))) then raise exception 'An ingredient is inactive, missing its base unit or outside the centre scope. Complete its setup first.' using errcode='22023';end if;
 with totals as(select (value->>'item_id')::uuid item_id,sum((value->>'quantity')::numeric) quantity from jsonb_array_elements(requirements) group by value->>'item_id'), balances as(
 select t.*,i.name,i.code,i.stock_tracked,u.code unit,case when i.stock_tracked then private.pp_stock_balance(p_organisation_id,p_site_id,i.id)-private.pp_stock_reserved(p_organisation_id,p_site_id,i.id) end available from totals t join public.items i on i.organisation_id=p_organisation_id and i.id=t.item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id)
 select jsonb_agg(jsonb_build_object('item_id',item_id,'name',name,'code',code,'unit',unit,'required',((ceil(quantity*1e12)/1e12))::text,'available',available::text,'shortage',case when available is not null then (greatest(0,ceil(quantity*1e12)/1e12-available))::text end,'stock_tracked',stock_tracked) order by name,item_id) into materials from balances;
 if materials is null or jsonb_array_length(materials)>1000 then raise exception 'No usable materials or too many consolidated materials.' using errcode='22023';end if;
 return jsonb_build_object('organisation',p_organisation_id,'restaurant',(select name from public.organisations where id=p_organisation_id),'centre_id',p_site_id,'centre',(select name from public.stock_locations where id=p_site_id),'plan_date',p_date,'generated_at',statement_timestamp(),'generated_by',auth.uid(),'basis',p_basis,'recipes',sources,'materials',materials);
end $$;
revoke all on function private.pp_material_plan_access(uuid,uuid),private.pp_material_plan_expand(uuid,uuid,numeric,date,text,uuid) from public,anon,authenticated;
revoke all on function public.material_plan_options(uuid,uuid,date),public.generate_material_plan(uuid,uuid,date,jsonb,text) from public,anon;
grant execute on function public.material_plan_options(uuid,uuid,date),public.generate_material_plan(uuid,uuid,date,jsonb,text) to authenticated;
notify pgrst,'reload schema';
commit;
