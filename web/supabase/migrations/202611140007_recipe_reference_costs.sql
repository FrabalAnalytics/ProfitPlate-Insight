-- Apply ONCE after 006. Read-only reference estimate; no inventory valuation policy.
begin;
create function public.recipe_reference_cost_estimate(
 p_organisation_id uuid,p_version_id uuid,p_as_of date,p_output_quantity numeric
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare output_row public.recipe_outputs%rowtype; version_row public.recipe_versions%rowtype;
 org public.organisations%rowtype; lines jsonb; missing integer; known integer;
 batch_cost numeric; unit_cost numeric; target_cost numeric; partial_cost numeric;
 invalid_precision boolean;
begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Financial estimate access denied.' using errcode='42501'; end if;
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
  select t.*,u.code as unit_code,p.id as price_id,p.version as price_version,p.price_date,p.source_note,
   case when p.currency_code=org.currency_code then p.cost_per_base_unit end as reference_unit_cost,
   case when p.id is null then 'NO_REFERENCE_PRICE'
    when p.currency_code<>org.currency_code then 'CURRENCY_MISMATCH'
    when p.base_uom_id<>t.base_uom_id then 'UNIT_MISMATCH' else null end as missing_reason
   from totals t join public.units_of_measure u on u.organisation_id=p_organisation_id and u.id=t.base_uom_id
   left join lateral(select p.* from public.material_reference_prices p
    where p.organisation_id=p_organisation_id and p.item_id=t.item_id and p.price_date<=p_as_of
    order by p.price_date desc,p.version desc limit 1) p on true
 ), costs as (
  select *,case when missing_reason is null then quantity*reference_unit_cost end as cost from priced
 ) select coalesce(jsonb_agg(jsonb_build_object('item_id',item_id,'name',name,'code',code,'item_type',item_type,
  'quantity',round(quantity,12)::text,'quantity_below_precision',round(quantity,12)=0,'unit_code',unit_code,
  'price_id',price_id,'price_version',price_version,'price_date',price_date,'source_note',source_note,
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
  'method','REFERENCE_ESTIMATE_V1','as_of',p_as_of,'currency_code',org.currency_code,
  'recipe_version_id',p_version_id,'batch_yield',output_row.quantity::text,
  'yield_unit_code',(select code from public.units_of_measure where organisation_id=p_organisation_id and id=output_row.uom_id),
  'output_quantity',p_output_quantity::text,'missing_count',missing,'priced_count',known,'lines',lines,
  'batch_cost',batch_cost::text,'cost_per_output_unit',unit_cost::text,'target_cost',target_cost::text,
  'known_subtotal',round(partial_cost,12)::text);
end; $$;
revoke all on function public.recipe_reference_cost_estimate(uuid,uuid,date,numeric) from public,anon;
grant execute on function public.recipe_reference_cost_estimate(uuid,uuid,date,numeric) to authenticated;
notify pgrst,'reload schema';
commit;
