-- Recipe-derived estimates for stocked processed SKUs; source and ledger precision remain unchanged.
begin;
create function private.pp_effective_material_cost(org uuid,item uuid,as_of_date date,material_path uuid[] default array[]::uuid[]) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare i public.items;currency text;price record;recipe record;estimate jsonb;result jsonb;roots integer;output_qty numeric;unit_cost numeric;has_binding boolean;
begin
 select * into i from public.items where organisation_id=org and id=item;
 select currency_code into currency from public.organisations where id=org;
 result:=jsonb_build_object('item_id',item,'base_uom_id',i.base_uom_id,'currency_code',currency,'unit_cost',null,'basis',null,'missing_reason','NO_REFERENCE_PRICE');
 if i.id is null or as_of_date is null then return result;end if;
 if item=any(material_path) or cardinality(material_path)>=20 then return result||jsonb_build_object('basis','RECIPE_DERIVED','missing_reason','PROCESSING_CYCLE');end if;
 select exists(select 1 from public.stock_recipe_bindings where organisation_id=org and item_id=item) into has_binding;
 if i.supply_class<>'PROCESSED' and(not has_binding or i.supply_class='BOTH') then
  select * into price from private.pp_material_months(org,as_of_date,item) order by cost_month desc,price_date desc,id limit 1;
  if found then
   return result||jsonb_build_object('unit_cost',case when price.currency_code=currency and price.base_uom_id=i.base_uom_id then price.cost_per_base_unit::text end,
    'price_id',price.id,'price_version',price.version,'price_date',price.price_date,'cost_month',price.cost_month,'basis',price.basis,'source_count',price.source_count,
    'source_note',price.source_note,'base_quantity',price.base_quantity::text,'total_price',price.total_price::text,
    'missing_reason',case when price.currency_code<>currency then 'CURRENCY_MISMATCH' when price.base_uom_id is distinct from i.base_uom_id then 'UNIT_MISMATCH' end);
  end if;
  if not has_binding and i.supply_class<>'PROCESSED' then return result;end if;
 end if;
 result:=result||jsonb_build_object('basis','RECIPE_DERIVED','cost_month',date_trunc('month',as_of_date)::date,'price_date',as_of_date,'source_note','Calculated from the linked processing recipe and its input costs','missing_reason','NO_PRODUCTION_RECIPE');
 select count(distinct v.recipe_id) into roots from public.stock_recipe_bindings b join public.recipe_versions v on v.organisation_id=b.organisation_id and v.id=b.recipe_version_id where b.organisation_id=org and b.item_id=item and v.effective_from<=as_of_date;
 if roots=0 then return result;end if;
 if roots>1 then return result||jsonb_build_object('missing_reason','AMBIGUOUS_PRODUCTION_RECIPE');end if;
 select v.id,v.name,v.version,o.quantity,ou.dimension output_dimension,bu.dimension base_dimension,ou.canonical_factor/bu.canonical_factor factor
 into recipe from public.stock_recipe_bindings b join public.recipe_versions v on v.organisation_id=b.organisation_id and v.id=b.recipe_version_id
 join public.recipe_outputs o on o.organisation_id=v.organisation_id and o.recipe_version_id=v.id
 join public.units_of_measure ou on ou.organisation_id=o.organisation_id and ou.id=o.uom_id
 left join public.units_of_measure bu on bu.organisation_id=i.organisation_id and bu.id=i.base_uom_id
 where b.organisation_id=org and b.item_id=item and v.effective_from<=as_of_date order by v.effective_from desc,v.version desc,v.id limit 1;
 result:=result||jsonb_build_object('recipe_version_id',recipe.id,'recipe_name',recipe.name,'recipe_version',recipe.version);
 if recipe.factor is null or recipe.output_dimension<>recipe.base_dimension or recipe.output_dimension='PACKAGE' then return result||jsonb_build_object('missing_reason','OUTPUT_UNIT_MISMATCH');end if;
 estimate:=private.pp_recipe_cost(org,recipe.id,as_of_date,recipe.quantity,material_path||item);
 if estimate->>'cost_state'<>'ESTIMATED' then return result||jsonb_build_object('missing_reason','PROCESSING_COST_INCOMPLETE','recipe_estimate',estimate);end if;
 output_qty:=recipe.quantity*recipe.factor;unit_cost:=(estimate->>'batch_cost')::numeric/output_qty;
 if unit_cost<=0 or round(unit_cost,12)=0 or unit_cost>=1e26 then return result||jsonb_build_object('missing_reason','COST_PRECISION');end if;
 return result||jsonb_build_object('unit_cost',round(unit_cost,12)::text,'recipe_batch_cost',estimate->>'batch_cost','recipe_output_quantity',output_qty::text,'recipe_estimate',estimate,'missing_reason',null);
end $$;
create or replace function private.pp_recipe_cost(
 p_organisation_id uuid,p_version_id uuid,p_as_of date,p_output_quantity numeric,p_material_path uuid[]
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare output_row public.recipe_outputs%rowtype; version_row public.recipe_versions%rowtype;
 org public.organisations%rowtype; lines jsonb; missing integer; known integer;
 batch_cost numeric; unit_cost numeric; target_cost numeric; partial_cost numeric;
 invalid_precision boolean;
begin
 select * into org from public.organisations where id=p_organisation_id;
 select * into version_row from public.recipe_versions where organisation_id=p_organisation_id and id=p_version_id;
 if not found then raise exception 'Recipe version not available.' using errcode='42501'; end if;
 select * into output_row from public.recipe_outputs where organisation_id=p_organisation_id and recipe_version_id=p_version_id;
 if not found then raise exception 'Recipe output not available.' using errcode='42501'; end if;
 if p_as_of is null or p_as_of<version_row.effective_from or p_as_of>(now() at time zone org.time_zone)::date
  then raise exception 'Choose a cost date on or after this recipe version starts, and not in the future.' using errcode='22023'; end if;
 if p_output_quantity is null or p_output_quantity<=0 or p_output_quantity>=1e14 or p_output_quantity<>round(p_output_quantity,6)
  then raise exception 'Choose a positive output quantity with up to six decimal places.' using errcode='22023'; end if;

 -- Expand immutable composition using pinned child versions and normalised source
 -- quantities. Do not round the recursive multipliers or quantity before costing.
 with recursive expanded as (
  select c.*,1::numeric as multiplier,1 as depth from public.recipe_components c
   where c.organisation_id=p_organisation_id and c.recipe_version_id=p_version_id
  union all
  select c.*,e.multiplier*e.normalised_quantity/o.quantity,e.depth+1 from expanded e
   join public.recipe_outputs o on o.organisation_id=p_organisation_id and o.recipe_version_id=e.child_recipe_version_id
   join public.recipe_components c on c.organisation_id=p_organisation_id and c.recipe_version_id=e.child_recipe_version_id
   where e.depth<20
 ), totals as (
  select item_id,base_uom_id,sum(normalised_quantity*multiplier) as quantity,
   min(target_name) as name,min(target_code) as code,min(target_type) as item_type
   from expanded where item_id is not null group by item_id,base_uom_id
 ), priced as (
  select t.*,u.code as unit_code,(p.value->>'price_id')::uuid price_id,(p.value->>'price_version')::integer price_version,
   (p.value->>'price_date')::date price_date,p.value->>'source_note' source_note,p.value->>'basis' basis,(p.value->>'cost_month')::date cost_month,
   (p.value->>'source_count')::bigint source_count,p.value->>'recipe_version_id' cost_recipe_version_id,p.value->>'recipe_name' cost_recipe_name,
   (p.value->>'unit_cost')::numeric reference_unit_cost,p.value->>'missing_reason' missing_reason
   from totals t join public.units_of_measure u on u.organisation_id=p_organisation_id and u.id=t.base_uom_id
   cross join lateral(select private.pp_effective_material_cost(p_organisation_id,t.item_id,p_as_of,p_material_path) value)p

 ), costs as (
  select *,case when missing_reason is null then quantity*reference_unit_cost end as cost from priced
 ) select coalesce(jsonb_agg(jsonb_build_object('item_id',item_id,'name',name,'code',code,'item_type',item_type,
  'quantity',round(quantity,12)::text,'quantity_below_precision',round(quantity,12)=0,'unit_code',unit_code,
  'price_id',price_id,'price_version',price_version,'price_date',price_date,'source_note',source_note,'price_basis',basis,'price_month',cost_month,'price_source_count',source_count,'cost_recipe_version_id',cost_recipe_version_id,'cost_recipe_name',cost_recipe_name,
  'unit_cost',case when missing_reason is null then reference_unit_cost::text else null end,
  'batch_cost',round(cost,12)::text,'missing_reason',missing_reason) order by name,code,item_id),'[]'::jsonb),
  count(*) filter(where missing_reason is not null)::integer,count(*) filter(where missing_reason is null)::integer,
  sum(cost),coalesce(bool_or(cost is not null and (cost<=0 or round(cost,12)=0 or cost>=1e26)),false)
 into lines,missing,known,partial_cost,invalid_precision from costs;
 if jsonb_array_length(lines)=0 then raise exception 'No material quantities are available for this version.' using errcode='22023'; end if;
 if invalid_precision or partial_cost>=1e26 then raise exception 'The estimate exceeds supported precision. No zero cost has been substituted.' using errcode='22023'; end if;
 if missing=0 then
  batch_cost:=round(partial_cost,12); unit_cost:=round(partial_cost/output_row.quantity,12);
  target_cost:=round(partial_cost*p_output_quantity/output_row.quantity,12);
  if batch_cost<=0 or unit_cost<=0 or target_cost<=0 or greatest(batch_cost,unit_cost,target_cost)>=1e26
   then raise exception 'The estimate exceeds supported precision. No zero cost has been substituted.' using errcode='22023'; end if;
 end if;
 return jsonb_build_object('cost_state',case when missing>0 then 'MISSING' else 'ESTIMATED' end,
  'method','MONTHLY_WEIGHTED_ESTIMATE_V3','as_of',p_as_of,'currency_code',org.currency_code,
  'recipe_version_id',p_version_id,'batch_yield',output_row.quantity::text,
  'yield_unit_code',(select code from public.units_of_measure where organisation_id=p_organisation_id and id=output_row.uom_id),
  'output_quantity',p_output_quantity::text,'missing_count',missing,'priced_count',known,'lines',lines,
  'batch_cost',batch_cost::text,'cost_per_output_unit',unit_cost::text,'target_cost',target_cost::text,
  'known_subtotal',round(partial_cost,12)::text);
end; $$;
create or replace function public.recipe_reference_cost_estimate(p_organisation_id uuid,p_version_id uuid,p_as_of date,p_output_quantity numeric) returns jsonb
language plpgsql stable security definer set search_path='' as $$begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Financial estimate access denied.' using errcode='42501';end if;
 return private.pp_recipe_cost(p_organisation_id,p_version_id,p_as_of,p_output_quantity,array[]::uuid[]);
end $$;
create function public.material_cost_estimates(p_organisation_id uuid,p_ids uuid[],p_as_of date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;today date;
begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Financial estimate access denied.' using errcode='42501';end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 if p_ids is null or cardinality(p_ids)>25 or p_as_of is null or p_as_of>today then raise exception 'Choose up to 25 materials and a valid cost date.' using errcode='22023';end if;
 select coalesce(jsonb_object_agg(i.id::text,private.pp_effective_material_cost(p_organisation_id,i.id,p_as_of,array[]::uuid[])),'{}'::jsonb) into result from public.items i where i.organisation_id=p_organisation_id and i.id=any(p_ids);
 return result;
end $$;
create function private.pp_validate_processing_binding() returns trigger language plpgsql security definer set search_path='' as $$
declare root_id uuid;cycle boolean;
begin
 select recipe_id into root_id from public.recipe_versions where organisation_id=new.organisation_id and id=new.recipe_version_id;
 if exists(select 1 from public.stock_recipe_bindings b join public.recipe_versions v on v.organisation_id=b.organisation_id and v.id=b.recipe_version_id where b.organisation_id=new.organisation_id and b.item_id=new.item_id and b.recipe_version_id<>new.recipe_version_id and v.recipe_id<>root_id) then raise exception 'This produced SKU already has a different processing recipe. Publish a new version of the same recipe or use a separate output SKU.' using errcode='22023';end if;
 with recursive edges as(
  select 'V' kind,c.recipe_version_id id,case when c.item_id is not null then 'I' else 'V' end next_kind,coalesce(c.item_id,c.child_recipe_version_id) next_id from public.recipe_components c where c.organisation_id=new.organisation_id
  union all select 'I',b.item_id,'V',b.recipe_version_id from public.stock_recipe_bindings b where b.organisation_id=new.organisation_id and b.recipe_version_id<>new.recipe_version_id
  union all select 'I',new.item_id,'V',new.recipe_version_id
 ),walk(kind,id) as(
  select 'V'::text,new.recipe_version_id union select e.next_kind,e.next_id from walk w join edges e on e.kind=w.kind and e.id=w.id
 ) select exists(select 1 from walk where kind='I' and id=new.item_id) into cycle;
 if cycle then raise exception 'This link creates a processing cycle: the produced SKU depends on itself. Choose a recipe made from other input materials.' using errcode='22023';end if;
 return new;
end $$;
create trigger processing_cost_binding before insert or update on public.stock_recipe_bindings for each row execute function private.pp_validate_processing_binding();
revoke all on function private.pp_effective_material_cost(uuid,uuid,date,uuid[]),private.pp_recipe_cost(uuid,uuid,date,numeric,uuid[]),private.pp_validate_processing_binding() from public,anon,authenticated;
revoke all on function public.material_cost_estimates(uuid,uuid[],date) from public,anon;
grant execute on function public.material_cost_estimates(uuid,uuid[],date) to authenticated;
create or replace function public.material_monthly_prices(p_organisation_id uuid,p_month date,p_search text default '',p_page integer default 1) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;today date;cutoff date;
begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Business-wide financial access required.' using errcode='42501';end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 if p_month is null or p_month<>date_trunc('month',p_month)::date or p_month>today or p_page is null or p_page not between 1 and 100000 or p_search is null or length(p_search)>80 then raise exception 'Choose a valid month, search and page.' using errcode='22023';end if;
 cutoff:=least(today,(p_month+interval '1 month - 1 day')::date);
 with items as materialized(
 select i.id,i.name,i.code,u.code unit from public.items i left join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id where i.organisation_id=p_organisation_id and(trim(p_search)='' or position(lower(trim(p_search)) in lower(i.code||' '||i.name))>0)
 ),paged as(
 select i.*,(c.value->>'cost_month')::date cost_month,c.value->>'unit_cost' average,c.value->>'base_quantity' quantity,c.value->>'total_price' net_amount,c.value->>'basis' basis,(c.value->>'source_count')::bigint source_count,c.value->>'currency_code' currency_code,c.value->>'price_date' price_date,c.value->>'missing_reason' missing_reason,c.value->>'recipe_version_id' recipe_version_id,c.value->>'recipe_name' recipe_name
 from(select * from items order by name,id limit 10 offset(p_page-1)*10)i cross join lateral(select private.pp_effective_material_cost(p_organisation_id,i.id,cutoff,array[]::uuid[]) value)c

 )select jsonb_build_object('total',(select count(*) from items),'as_of',cutoff,'month',p_month,'rows',coalesce((select jsonb_agg(to_jsonb(p) order by name,id) from paged p),'[]'::jsonb)) into result;
 return result;
end $$;
create or replace function public.setup_profiles(p_organisation_id uuid,p_kind text,p_ids uuid[]) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;day date;
begin
 if not private.pp_catalogue_read(p_organisation_id) then raise exception 'Setup access denied.' using errcode='42501';end if;
 if p_kind not in ('MATERIAL','MENU','RECIPE') or p_kind is null or p_ids is null or cardinality(p_ids)>25 then raise exception 'Choose up to 25 setup records.' using errcode='22023';end if;
 select(now() at time zone time_zone)::date into day from public.organisations where id=p_organisation_id;
 if p_kind='MATERIAL' then
 select coalesce(jsonb_object_agg(i.id::text,jsonb_build_object('location_id',i.location_id,'weekly_count_required',i.weekly_count_required,'supply_class',i.supply_class,
 'last_price',case when private.pp_reference_price_read(p_organisation_id) then price.cost_per_base_unit::text end,'price_date',case when private.pp_reference_price_read(p_organisation_id) then price.price_date end,
 'missing',to_jsonb(array_remove(array[case when i.base_uom_id is null then 'Base unit' end,case when price.cost_per_base_unit is null then 'Material cost / processing recipe' end,
 case when i.stock_tracked and (not exists(select 1 from public.stock_locations s where s.organisation_id=i.organisation_id and s.is_active and(i.location_id is null or s.outlet_id is null or s.outlet_id=i.location_id)) or exists(select 1 from public.stock_locations s where s.organisation_id=i.organisation_id and s.is_active and(i.location_id is null or s.outlet_id is null or s.outlet_id=i.location_id) and not private.pp_opening_ready(i.organisation_id,i.id,s.id))) then 'Opening stock' end],null)))),'{}'::jsonb) into result
 from public.items i left join lateral(select p.item_id,p.cost_per_base_unit,p.price_date,p.missing_reason from jsonb_to_record(private.pp_effective_material_cost(p_organisation_id,i.id,day,array[]::uuid[])) as x(item_id uuid,unit_cost text,price_date date,missing_reason text) cross join lateral(select x.item_id,x.unit_cost::numeric cost_per_base_unit,x.price_date,x.missing_reason)p)price on true where i.organisation_id=p_organisation_id and i.id=any(p_ids);
 elsif p_kind='RECIPE' then
 select coalesce(jsonb_object_agg(id::text,jsonb_build_object('location_id',location_id)),'{}') into result from public.recipes where organisation_id=p_organisation_id and id=any(p_ids);
 else
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Menu access denied.' using errcode='42501';end if;
 select coalesce(jsonb_object_agg(m.id::text,jsonb_build_object('location_id',m.location_id,'primary_category',m.primary_category,'subcategory',m.subcategory,
 'missing',to_jsonb(array_remove(array[case when m.primary_category is null then 'Primary category' end,case when m.subcategory='' then 'Subcategory' end,case when v.id is null then 'Final recipe' end,
 case when not exists(select 1 from public.locations l where l.organisation_id=m.organisation_id and l.is_active and l.brand_id=m.brand_id and(m.location_id is null or l.id=m.location_id)) or exists(select 1 from public.locations l where l.organisation_id=m.organisation_id and l.is_active and l.brand_id=m.brand_id and(m.location_id is null or l.id=m.location_id) and not exists(select 1 from(select distinct on(p.channel_code) p.* from public.menu_price_versions p where p.organisation_id=m.organisation_id and p.menu_item_id=m.id and p.location_id=l.id and p.effective_from<=day order by p.channel_code,p.effective_from desc,p.version desc)current_price where current_price.effective_to is null or current_price.effective_to>=day)) then 'Selling price' end,
 case when v.id is not null and(public.recipe_reference_cost_estimate(m.organisation_id,v.recipe_version_id,day,v.recipe_quantity)->>'cost_state')<>'ESTIMATED' then 'Recipe cost' end],null)))),'{}') into result
 from public.menu_items m left join lateral(select id,recipe_version_id,recipe_quantity from public.menu_item_versions where organisation_id=m.organisation_id and menu_item_id=m.id and effective_from<=day order by effective_from desc,version desc limit 1)v on true where m.organisation_id=p_organisation_id and m.id=any(p_ids);
 end if;return result;
end $$;
create or replace function private.pp_setup_progress(org uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare stages jsonb;material_count int;missing_materials int;menus int;missing_menus int;day date;begin
 select(now() at time zone time_zone)::date into day from public.organisations where id=org;
 select count(*),count(*) filter(where i.base_uom_id is null or (private.pp_effective_material_cost(org,i.id,day,array[]::uuid[])->>'unit_cost') is null or(i.stock_tracked and(not exists(select 1 from public.stock_locations s where s.organisation_id=org and s.is_active and(i.location_id is null or s.outlet_id is null or s.outlet_id=i.location_id)) or exists(select 1 from public.stock_locations s where s.organisation_id=org and s.is_active and(i.location_id is null or s.outlet_id is null or s.outlet_id=i.location_id) and not private.pp_opening_ready(org,i.id,s.id))))) into material_count,missing_materials from public.items i where i.organisation_id=org and i.is_active;
 select count(*),count(*) filter(where m.primary_category is null or m.subcategory='' or not exists(select 1 from public.menu_item_versions v where v.organisation_id=org and v.menu_item_id=m.id and v.effective_from<=day) or not exists(select 1 from public.locations l where l.organisation_id=org and l.is_active and l.brand_id=m.brand_id and(m.location_id is null or l.id=m.location_id)) or exists(select 1 from public.locations l where l.organisation_id=org and l.is_active and l.brand_id=m.brand_id and(m.location_id is null or l.id=m.location_id) and not exists(select 1 from(select distinct on(channel_code) * from public.menu_price_versions p where p.organisation_id=org and p.menu_item_id=m.id and p.location_id=l.id and p.effective_from<=day order by channel_code,effective_from desc,version desc)price where price.effective_to is null or price.effective_to>=day))) into menus,missing_menus from public.menu_items m where m.organisation_id=org and m.is_active;
 stages:=jsonb_build_array(
 jsonb_build_object('name','Reporting calendar','ready',exists(select 1 from public.organisations where id=org and reporting_week_start is not null and count_day is not null and count_cutoff is not null),'path','/workspace/setup/standards','detail','Reporting week, timezone and physical count schedule'),
 jsonb_build_object('name','Business & locations','ready',exists(select 1 from public.locations where organisation_id=org and is_active),'path','/workspace/setup','detail','Business profile and active outlets'),
 jsonb_build_object('name','Users & roles','ready',exists(select 1 from public.organisation_memberships m join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id where m.organisation_id=org and m.status='active'),'path','/workspace/team','detail','Active members with assigned roles'),
 jsonb_build_object('name','Suppliers','ready',exists(select 1 from public.suppliers where organisation_id=org and is_active),'path','/workspace/materials','detail','Active supplier catalogue'),
 jsonb_build_object('name','Materials, prices & opening stock','ready',material_count>0 and missing_materials=0,'path','/workspace/materials','detail',missing_materials||' incomplete of '||material_count||' active materials'),
 jsonb_build_object('name','Recipes','ready',exists(select 1 from public.recipes where organisation_id=org) and not exists(select 1 from public.recipes r where r.organisation_id=org and not exists(select 1 from public.recipe_versions v where v.organisation_id=org and v.recipe_id=r.id)),'path','/workspace/recipes','detail','Saved recipe versions'),
 jsonb_build_object('name','Menu mapping & selling prices','ready',menus>0 and missing_menus=0,'path','/workspace/menus','detail',missing_menus||' incomplete of '||menus||' active menu items'),
 jsonb_build_object('name','Food & beverage targets','ready',exists(select 1 from public.locations where organisation_id=org and is_active) and not exists(select 1 from public.locations l where l.organisation_id=org and l.is_active and(private.pp_cost_target(org,l.id,'FOOD') is null or private.pp_cost_target(org,l.id,'DRINK') is null)),'path','/workspace/setup/standards','detail','Business targets or location overrides'));
 return jsonb_build_object('completed',(select count(*) from jsonb_array_elements(stages)s where(s->>'ready')::boolean),'total',jsonb_array_length(stages),'stages',stages,'missing_materials',missing_materials,'missing_menus',missing_menus);
end $$;
create or replace function public.executive_profitability_briefing(p_organisation_id uuid,p_from date,p_to date,p_location_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare overview jsonb; previous jsonb; prices jsonb; waste jsonb; movements jsonb; menus jsonb;
 currency text; prior_from date; prior_to date; invoice_count integer;
begin
 -- Reuse business-wide financial authorisation and date/outlet/volume checks.
 overview:=public.executive_overview(p_organisation_id,p_from,p_to,p_location_id);
 currency:=overview->'summary'->>'currency_code';
 prior_from:=(overview->'comparison'->>'from')::date; prior_to:=p_from-1;
 if overview->'comparison'->>'reason' is null then
  previous:=public.sales_period_summary(p_organisation_id,prior_from,prior_to,p_location_id);
 end if;
 select count(*) into invoice_count from public.purchase_headers where organisation_id=p_organisation_id;
 if invoice_count>10000 then
  prices:=jsonb_build_object('unavailable','Purchase comparison exceeds 10,000 invoices. Narrowing the reporting dates cannot reduce the corrected-invoice history required.','rows','[]'::jsonb);
 else
  -- Corrections may move dates/outlets or void invoices. Never use stale source lines.
  with invoices as materialized (
   select h.id,private.pp_current_invoice(p_organisation_id,h.id) v from public.purchase_headers h where h.organisation_id=p_organisation_id
  ), lines as (
   select h.id,(v->'header'->>'date')::date as purchase_day,(v->'header'->>'location_id')::uuid outlet,
    v->'header'->>'location_name' outlet_name,v->'header'->>'supplier_name' supplier,
    (l->>'item_id')::uuid item_id,l->>'item_name' item_name,(l->>'net_amount')::numeric net,(l->>'base_quantity')::numeric qty
   from invoices h cross join lateral jsonb_array_elements(v->'lines') l
   where not coalesce((v->>'voided')::boolean,false) and v->'header'->>'currency'=currency
    and (v->'header'->>'date')::date between prior_from and p_to
    and(p_location_id is null or v->'header'->>'location_id'=p_location_id::text)
  ), grouped as (
   select item_id,min(item_name) name,outlet,min(outlet_name) outlet_name,
    string_agg(distinct supplier,', ' order by supplier) suppliers,
    sum(net) filter(where purchase_day between p_from and p_to) current_net,sum(qty) filter(where purchase_day between p_from and p_to) current_qty,
    sum(net) filter(where purchase_day between prior_from and prior_to) prior_net,sum(qty) filter(where purchase_day between prior_from and prior_to) prior_qty
   from lines group by item_id,outlet
  ), priced as (
   select g.*,i.base_uom_id,u.code unit,current_net/current_qty current_price,prior_net/prior_qty prior_price,
    current_qty*(current_net/current_qty-prior_net/prior_qty) impact
   from grouped g join public.items i on i.organisation_id=p_organisation_id and i.id=g.item_id
   join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id
   where current_qty>0 and prior_qty>0
  ), rising as(select * from priced where impact>0)
  select jsonb_build_object('unavailable',null,'total',count(*),'impact',coalesce(sum(impact),0)::text,
   'rows',coalesce((select jsonb_agg(to_jsonb(r) order by r.impact::numeric desc,r.name,r.outlet) from (
    select item_id,name,outlet,outlet_name,suppliers,unit,current_price::text,prior_price::text,impact::text,
     round((current_price/prior_price-1)*100,6)::text change_percent from rising order by rising.impact desc,name,outlet limit 5
   )r),'[]'::jsonb),'unmatched',(select count(*) from grouped where current_qty>0 and prior_qty is null),
   'excluded_currency_invoices',(select count(*) from invoices where not coalesce((v->>'voided')::boolean,false)
    and(v->'header'->>'date')::date between prior_from and p_to and v->'header'->>'currency'<>currency
    and(p_location_id is null or v->'header'->>'location_id'=p_location_id::text))) into prices from rising;
 end if;

 -- Only posted negative WASTE/COUNT ledger entries; never pending requests or transfers.
 with entries as (
  select l.id,l.location_id,l.item_id,-l.quantity quantity,l.occurred_on,d.id document_id,d.reference,d.kind,
   s.name location_name,coalesce(o.name,'Central / shared store') outlet_name,i.name item_name,u.code unit,
   case when p.currency_code=currency and p.base_uom_id=i.base_uom_id then -l.quantity*p.cost_per_base_unit end value
  from public.stock_ledger l join public.stock_documents d on d.organisation_id=l.organisation_id and d.id=l.document_id
  join public.stock_locations s on s.organisation_id=l.organisation_id and s.id=l.location_id
  left join public.locations o on o.organisation_id=s.organisation_id and o.id=s.outlet_id
  join public.items i on i.organisation_id=l.organisation_id and i.id=l.item_id
  join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id
  left join lateral(select x.base_uom_id,x.currency_code,x.unit_cost::numeric cost_per_base_unit from jsonb_to_record(private.pp_effective_material_cost(l.organisation_id,l.item_id,l.occurred_on,array[]::uuid[])) x(base_uom_id uuid,currency_code text,unit_cost text))p on true
  where l.organisation_id=p_organisation_id and l.occurred_on between prior_from and p_to and l.quantity<0
   and d.kind in ('WASTE','COUNT') and d.state='POSTED' and(p_location_id is null or s.outlet_id=p_location_id)
 ), current_rows as(select * from entries where occurred_on between p_from and p_to)
 select jsonb_build_object('lines',count(*),'unpriced',count(*) filter(where value is null),
  'known_value',coalesce(sum(value),0)::text,'waste_value',coalesce(sum(value) filter(where kind='WASTE'),0)::text,
  'shortage_value',coalesce(sum(value) filter(where kind='COUNT'),0)::text,
  'prior_lines',(select count(*) from entries where occurred_on between prior_from and prior_to),
  'prior_unpriced',(select count(*) from entries where occurred_on between prior_from and prior_to and value is null),
  'prior_value',(select coalesce(sum(value),0)::text from entries where occurred_on between prior_from and prior_to),
  'change_value',(coalesce(sum(value),0)-(select coalesce(sum(value),0) from entries where occurred_on between prior_from and prior_to))::text,
  'rows',coalesce((select jsonb_agg(to_jsonb(r) order by r.value::numeric desc nulls last,r.id) from (
   select id,document_id,reference,kind,location_id,location_name,outlet_name,item_name,unit,quantity::text,value::text
   from current_rows order by current_rows.value desc nulls last,id limit 5)r),'[]'::jsonb)) into waste from current_rows;

 -- Current unresolved accountability, deliberately independent of historical period.
 with unresolved as (
  select d.id,d.reference,d.state,d.created_at,d.created_by,d.dispatched_by,
   s.name source_name,t.name destination_name,coalesce(so.name,'Central / shared store') source_outlet,
   coalesce(ta.name,'Central / shared store') destination_outlet,
   case when d.state='REQUESTED' then 'Inventory Manager: review request'
    when d.state='APPROVED' then 'Inventory Manager: authorise dispatch'
    when d.state='DISPATCHED' then t.name||': accept or reject'
    else 'Inventory Manager: resolve rejected / incomplete handover' end next_action,
   coalesce(d.dispatched_at,d.approved_at,d.created_at) waiting_since,
   d.dispatched_at is not null and d.state in ('DISPATCHED','PARTIAL','REJECTED') handover
  from public.stock_documents d
  join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id
  join public.stock_locations t on t.organisation_id=d.organisation_id and t.id=d.destination_id
  left join public.locations so on so.organisation_id=s.organisation_id and so.id=s.outlet_id
  left join public.locations ta on ta.organisation_id=t.organisation_id and ta.id=t.outlet_id
  where d.organisation_id=p_organisation_id and d.kind in ('ISSUE','TRANSFER')
   and(d.state in ('REQUESTED','APPROVED','DISPATCHED') or(d.state in ('PARTIAL','REJECTED') and d.resolved_at is null))
   and(p_location_id is null or s.outlet_id=p_location_id or t.outlet_id=p_location_id)
 ) select jsonb_build_object('open',count(*),'handover',count(*) filter(where handover),
  'overdue',count(*) filter(where waiting_since<now()-interval '24 hours'),
  'exceptions',count(*) filter(where state in ('PARTIAL','REJECTED')),
  'rows',coalesce((select jsonb_agg(to_jsonb(r) order by case when r.state in ('PARTIAL','REJECTED') then 0 when r.overdue then 1 else 2 end,r.waiting_since,r.id) from (
   select id,reference,state,source_name,destination_name,source_outlet,destination_outlet,next_action,waiting_since,
    waiting_since<now()-interval '24 hours' overdue from unresolved
   order by case when state in ('PARTIAL','REJECTED') then 0 when waiting_since<now()-interval '24 hours' then 1 else 2 end,waiting_since,id limit 5
  )r),'[]'::jsonb)) into movements from unresolved;

 with risks as materialized(
 select v,(v->>'estimated_food_cost')::numeric cost,(v->>'net_revenue')::numeric revenue,(v->>'estimated_food_margin')::numeric margin,
 l.id location_id,l.name location_name,m.primary_category,private.pp_cost_target(p_organisation_id,l.id,m.primary_category) target
 from public.locations l cross join lateral jsonb_array_elements(public.sales_period_summary(p_organisation_id,p_from,p_to,l.id)->'menus')v
 join public.menu_items m on m.organisation_id=p_organisation_id and m.id=(v->>'menu_item_id')::uuid
 where l.organisation_id=p_organisation_id and(l.id=p_location_id or p_location_id is null)
 ), flagged as(select * from risks where margin<0 or(target is not null and cost/nullif(revenue,0)*100>target))
 select jsonb_build_object('total',(select count(*) from flagged),'target_missing',(select count(*) from risks where target is null),'rows',coalesce((select jsonb_agg(v||jsonb_build_object(
 'food_cost_percent',round(cost/nullif(revenue,0)*100,6)::text,'margin_percent',round(margin/nullif(revenue,0)*100,6)::text,'locations',location_name,'location_id',location_id,'primary_category',primary_category,'target',target::text)
 order by margin,revenue desc) from(select * from flagged order by margin,revenue desc limit 5)f),'[]'::jsonb)) into menus;
 return jsonb_build_object('from',p_from,'to',p_to,'prior_from',prior_from,'prior_to',prior_to,'currency',currency,
  'summary',overview->'summary','comparison',overview->'comparison','previous',previous,
  'food_cost_percent',round((overview->'summary'->>'estimated_food_cost')::numeric/nullif((overview->'summary'->>'net_revenue')::numeric,0)*100,6)::text,
  'food_cost_change_pp',round(((overview->'summary'->>'estimated_food_cost')::numeric/nullif((overview->'summary'->>'net_revenue')::numeric,0)
   -(previous->>'estimated_food_cost')::numeric/nullif((previous->>'net_revenue')::numeric,0))*100,6)::text,
  'food_margin_change_pp',((overview->'summary'->>'food_margin_percent')::numeric-(previous->>'food_margin_percent')::numeric)::text,
  'outlets',overview->'outlets','prices',prices,'waste',waste,'movements',movements,'menus',menus,
  'recorded_days',(select count(*) from jsonb_array_elements(overview->'daily')d where(d->>'lines')::integer>0),'refreshed_at',statement_timestamp());
end; $$;

create or replace function public.material_reference_price_coverage(p_organisation_id uuid,p_item_ids uuid[]) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;day date;
begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Financial estimate access denied.' using errcode='42501';end if;
 if p_item_ids is null or cardinality(p_item_ids)>25 then raise exception 'Supply up to 25 material IDs.' using errcode='22023';end if;
 select(now() at time zone time_zone)::date into day from public.organisations where id=p_organisation_id;
 select coalesce(jsonb_object_agg(i.id::text,(private.pp_effective_material_cost(p_organisation_id,i.id,day,array[]::uuid[])->>'unit_cost') is not null),'{}'::jsonb) into result from public.items i where i.organisation_id=p_organisation_id and i.id=any(p_item_ids);return result;
end $$;

notify pgrst,'reload schema';
commit;
