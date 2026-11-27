-- Preserve the production plan separately from measured consumption and output.
begin;
create table private.processing_plans(
 organisation_id uuid not null,document_id uuid not null,entry_mode text not null check(entry_mode in('INPUT','BATCHES','TARGET')),
 planned_quantity numeric not null check(planned_quantity>0),batch_multiplier numeric not null check(batch_multiplier>0),expected_inputs jsonb not null,
 primary key(organisation_id,document_id),foreign key(organisation_id,document_id) references public.processing_batches(organisation_id,document_id)
);
revoke all on private.processing_plans from public,anon,authenticated;
create trigger active_restaurant_write before insert or update or delete on private.processing_plans for each row execute function private.pp_require_active_restaurant();
create or replace function private.pp_prepare_processing(org uuid, token uuid, p_document jsonb,p_lines jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare p_organisation_id uuid:=org;result uuid:=gen_random_uuid();src public.stock_locations;day date;
 standard public.processing_standards;actual_lines jsonb;lines jsonb;waste jsonb;entry jsonb;output jsonb;
 primary_actual numeric;actual numeric;base_factor numeric;expected_base numeric;qty numeric;deviation numeric;
 outside boolean;reason text;usable numeric;expected numeric;input_mass numeric;waste_mass numeric;
 mass_balance numeric;measurable boolean;mode text:=coalesce(p_document->>'entry_mode','INPUT');planned_amount numeric;planned_factor numeric;planned_inputs jsonb;
begin
 if not private.pp_stock_read(org) then raise exception 'Stock access required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=org for update;
 select * into src from public.stock_locations where organisation_id=org and id=(p_document->>'source_id')::uuid and is_active;
 if src.id is null or not private.pp_stock_site(org,src.id,'request') then raise exception 'Processing access required at this centre.' using errcode='42501';end if;
 day:=(p_document->>'date')::date;
 if day is null or day>(select(now() at time zone time_zone)::date from public.organisations where id=org) then raise exception 'Choose a processing date that is not in the future.' using errcode='22023';end if;
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
   if mode not in('INPUT','BATCHES','TARGET') then raise exception 'Choose batches, target output or main input entry.' using errcode='22023';end if;
   if mode='INPUT' then planned_amount:=primary_actual;planned_factor:=primary_actual/standard.primary_quantity;
   else
    planned_amount:=private.pp_stock_number(p_document->>'planned_quantity');
    if planned_amount<>round(planned_amount,12) or planned_amount>=1e26 then raise exception 'Use a positive production plan with up to twelve decimal places.' using errcode='22023';end if;
    planned_factor:=case when mode='BATCHES' then planned_amount else planned_amount/standard.expected_output end;
    expected_base:=case when mode='TARGET' then planned_amount else round(standard.expected_output*planned_factor,12) end;
   end if;
   if exists(select 1 from jsonb_array_elements(standard.inputs) i where round((i->>'quantity')::numeric*planned_factor,12)>=1e26) then raise exception 'Planned ingredient quantities exceed supported precision.' using errcode='22023';end if;
   select jsonb_agg(i||jsonb_build_object('quantity',round((i->>'quantity')::numeric*planned_factor,12)::text) order by n) into planned_inputs from jsonb_array_elements(standard.inputs) with ordinality as e(i,n);
   if expected_base<=0 or expected_base>=1e26 or qty>=1e26 then raise exception 'Batch quantities exceed supported precision.' using errcode='22023';end if;
   deviation:=100*(qty-expected_base)/expected_base;outside:=abs(deviation)>standard.tolerance_percent;
   reason:=trim(coalesce(p_document->>'variance_reason',''));
   if length(reason)>1000 then raise exception 'Keep the optional note within 1,000 characters.' using errcode='22023';end if;
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
     -- An unexplained mass difference is retained for analysis; notes are optional.
    end if;
   end if;
   if qty=0 and coalesce(usable,0)>0 then raise exception 'Usable output weight requires usable output quantity.' using errcode='22023';end if;
   lines:=actual_lines;
   output:=jsonb_build_object('item_id',standard.output_item_id,'quantity',qty::text,'planned_output',expected_base::text,'actual_output',actual::text,'recipe_version_id',standard.recipe_version_id,'processing_standard_id',standard.id,'expected_output',expected_base::text,'output_variance',(qty-expected_base)::text,'variance_percent',round(deviation,6)::text,'outside_tolerance',outside,'variance_reason',reason,'usable_weight_kg',usable::text,'waste_included_in_inputs',true,'output_unit_basis','STOCK_BASE','entry_mode',mode,'planned_quantity',planned_amount::text);
  else raise exception 'Save a processing standard, choose its centre and record actual inputs before requesting production.' using errcode='22023';end if;

 insert into public.stock_documents(id,organisation_id,request_id,input_hash,reference,kind,source_id,recipe_version_id,document_date,note,lines,output,created_by)
 values(result,org,token,md5(jsonb_build_array(p_document,p_lines)::text),'PRC-'||upper(substr(replace(result::text,'-',''),1,12)),
 'PRODUCTION',src.id,standard.recipe_version_id,day,coalesce(nullif(trim(p_document->>'note'),''),'Material processing'),lines,output,auth.uid());
 insert into public.processing_batches values(org,result,standard.id,expected_base,qty,qty-expected_base,deviation,outside,usable,reason,primary_actual,
 private.pp_member_label(org,src.responsible_membership_id),input_mass,waste_mass,mass_balance);
 insert into private.processing_plans values(org,result,mode,planned_amount,planned_factor,planned_inputs);
 insert into public.processing_waste select org,result,(value->>'item_id')::uuid,(value->>'quantity')::numeric,trim(value->>'reason') from jsonb_array_elements(waste);
 return result;
end $$;
revoke all on function private.pp_prepare_processing(uuid,uuid,jsonb,jsonb) from public,anon,authenticated;
create or replace function public.submit_material_processing(p_organisation_id uuid,p_submission_id uuid,p_value jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare prior private.processing_submissions;row jsonb;standard public.processing_standards;doc uuid;
 docs jsonb:='[]';hash text:=md5(p_value::text);d jsonb;line jsonb;need record;
begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock access required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if p_submission_id is null or octet_length(p_value::text)>65536 or jsonb_typeof(p_value->'rows') is distinct from 'array'
 or jsonb_array_length(p_value->'rows') not between 1 and 30 then raise exception 'Enter between 1 and 30 processing materials.' using errcode='22023';end if;
 select * into prior from private.processing_submissions where organisation_id=p_organisation_id and submission_id=p_submission_id;
 if found then
  if prior.actor_id<>auth.uid() or prior.input_hash<>hash then raise exception 'This submission was already used. Refresh before recording another.' using errcode='22023';end if;
  if not private.pp_stock_site(p_organisation_id,(p_value->>'source_id')::uuid,'request') then raise exception 'Processing access required at this centre.' using errcode='42501';end if;
  return prior.document_ids;
 end if;
 if jsonb_typeof(p_value->'submitter_name') is distinct from 'string' or length(trim(coalesce(p_value->>'submitter_name',''))) not between 1 and 120
 or length(coalesce(p_value->>'note',''))>1000 then raise exception 'Enter the submitter name and a note of up to 1,000 characters.' using errcode='22023';end if;
 -- Prepare every row before posting: output produced in this submission cannot fund another row's inputs.
 for row in select value from jsonb_array_elements(p_value->'rows') loop
  select * into standard from public.processing_standards where organisation_id=p_organisation_id and id=(row->>'standard_id')::uuid and is_active;
  if not found then raise exception 'Choose an available material processing setup.' using errcode='22023';end if;
  d:=jsonb_build_object('source_id',p_value->>'source_id','date',p_value->>'date','note',p_value->>'note',
   'processing_standard_id',standard.id,'recipe_version_id',standard.recipe_version_id,'actual_output',row->>'actual_output',
   'variance_reason',coalesce(row->>'note',p_value->>'note',''),'usable_weight_kg',row->>'usable_weight_kg',
   'processing_waste',coalesce(row->'waste','[]'::jsonb),'waste_confirmed',true,
   'entry_mode',coalesce(row->>'entry_mode','INPUT'),'planned_quantity',row->>'planned_quantity');
  doc:=private.pp_prepare_processing(p_organisation_id,gen_random_uuid(),d,row->'inputs');
  docs:=docs||jsonb_build_array(doc);
 end loop;
 for need in select (l->>'item_id')::uuid item_id,sum((l->>'quantity')::numeric) quantity
 from public.stock_documents sd cross join lateral jsonb_array_elements(sd.lines) l
 where sd.organisation_id=p_organisation_id and sd.id in(select value::uuid from jsonb_array_elements_text(docs)) group by l->>'item_id' loop
  if need.quantity>private.pp_stock_balance(p_organisation_id,(p_value->>'source_id')::uuid,need.item_id)-private.pp_stock_reserved(p_organisation_id,(p_value->>'source_id')::uuid,need.item_id) then
   raise exception 'Insufficient available stock for %. Refresh balances or reduce the input quantity.',(select name from public.items where id=need.item_id) using errcode='22023';end if;
 end loop;
 for line in select value from jsonb_array_elements(docs) loop
  perform private.pp_finish_processing(p_organisation_id,(line #>> '{}')::uuid,p_value->>'submitter_name');
 end loop;
 insert into private.processing_submissions values(p_organisation_id,p_submission_id,auth.uid(),hash,docs);
 return docs;
end $$;


create function public.production_analysis(p_organisation_id uuid,p_site_id uuid,p_from date,p_to date,p_recipe_id uuid default null,p_page integer default 1) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;financial boolean:=private.pp_reference_price_read(p_organisation_id);
begin
 if not private.pp_stock_read(p_organisation_id) or(p_site_id is not null and not private.pp_stock_site(p_organisation_id,p_site_id,'read')) then raise exception 'Production reporting access required at this centre.' using errcode='42501';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>366 or p_page is null or p_page not between 1 and 100000 then raise exception 'Choose dates within 367 days and a valid page.' using errcode='22023';end if;
 if p_recipe_id is not null and not exists(select 1 from public.processing_standards st join public.processing_standard_sites ss on ss.organisation_id=st.organisation_id and ss.standard_id=st.id where st.organisation_id=p_organisation_id and st.recipe_version_id=p_recipe_id and private.pp_stock_site(p_organisation_id,ss.site_id,'read')) then raise exception 'Choose a permitted production recipe version.' using errcode='42501';end if;
 with evidence as materialized(
 select d.id,d.reference,d.document_date,d.source_id,st.recipe_version_id,(rv.name||' v'||rv.version) recipe_name,st.output_item_id,i.name output_name,u.code output_unit,c.name centre,
 b.expected_output,b.actual_output,b.outside_tolerance,d.lines actual_inputs,
 coalesce(plan.expected_inputs,(select jsonb_agg(j||jsonb_build_object('quantity',round((j->>'quantity')::numeric*b.primary_actual/st.primary_quantity,12)::text)) from jsonb_array_elements(st.inputs)j)) planned_inputs,
 coalesce(plan.entry_mode,'INPUT') entry_mode,case when financial then cost.value end costs
 from public.processing_batches b join public.stock_documents d on d.organisation_id=b.organisation_id and d.id=b.document_id
 join public.processing_standards st on st.organisation_id=b.organisation_id and st.id=b.standard_id
 join public.recipe_versions rv on rv.organisation_id=st.organisation_id and rv.id=st.recipe_version_id
 join public.items i on i.organisation_id=st.organisation_id and i.id=st.output_item_id
 join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id
 join public.stock_locations c on c.organisation_id=d.organisation_id and c.id=d.source_id
 left join private.processing_plans plan on plan.organisation_id=b.organisation_id and plan.document_id=b.document_id
 left join private.processing_batch_costs cost on cost.organisation_id=b.organisation_id and cost.document_id=b.document_id
 where b.organisation_id=p_organisation_id and d.state='POSTED' and d.document_date between p_from and p_to
 and(p_site_id is null or d.source_id=p_site_id) and(p_recipe_id is null or st.recipe_version_id=p_recipe_id)
 and private.pp_stock_site(p_organisation_id,d.source_id,'read')
 ),recipe_groups as materialized(
 select source_id,recipe_version_id,recipe_name,output_item_id,output_name,output_unit,centre,count(*) batches,count(*) filter(where outside_tolerance) exceptions,
 sum(expected_output) expected,sum(actual_output) actual,count(*) filter(where costs->>'batch_cost' is null or costs->>'standard_unit_cost' is null) unpriced,
 case when financial and bool_and(costs->>'batch_cost' is not null) then sum((costs->>'batch_cost')::numeric) end batch_cost,
 case when financial and bool_and(costs->>'batch_cost' is not null) and sum(actual_output)>0 then sum((costs->>'batch_cost')::numeric)/sum(actual_output) end actual_unit_cost,
 case when financial and bool_and(costs->>'standard_unit_cost' is not null) then sum((costs->>'standard_unit_cost')::numeric*expected_output)/sum(expected_output) end standard_unit_cost,
 count(*) filter(where entry_mode='INPUT') main_input_batches
 from evidence group by source_id,recipe_version_id,recipe_name,output_item_id,output_name,output_unit,centre
 ),paged as(select * from recipe_groups order by exceptions desc,recipe_name,centre,recipe_version_id,source_id limit 10 offset(p_page-1)*10),
 trend as(select document_date date_key,count(*) batches,count(*) filter(where outside_tolerance) exceptions from evidence group by document_date)
 select jsonb_build_object('from',p_from,'to',p_to,'financial',financial,'currency',(select currency_code from public.organisations where id=p_organisation_id),
 'recipes',coalesce((select jsonb_agg(jsonb_build_object('id',r.recipe_version_id,'name',r.name) order by r.name,r.recipe_version_id) from(select distinct st.recipe_version_id,(rv.name||' v'||rv.version) name from public.processing_standards st join public.recipe_versions rv on rv.organisation_id=st.organisation_id and rv.id=st.recipe_version_id join public.processing_standard_sites ss on ss.organisation_id=st.organisation_id and ss.standard_id=st.id where st.organisation_id=p_organisation_id and private.pp_stock_site(p_organisation_id,ss.site_id,'read') and(p_site_id is null or ss.site_id=p_site_id))r),'[]'::jsonb),
 'total',(select count(*) from recipe_groups),'batches',(select count(*) from evidence),'exceptions',(select count(*) from evidence where outside_tolerance),
 'unpriced',case when financial then(select count(*) from evidence where costs->>'batch_cost' is null) end,
 'daily',coalesce((select jsonb_agg(jsonb_build_object('day',date_key,'batches',batches,'exceptions',exceptions,'rate',round(100.0*exceptions/batches,6)::text) order by date_key) from trend),'[]'::jsonb),
 'rows',coalesce((select jsonb_agg(jsonb_build_object('site_id',g.source_id,'recipe_version_id',g.recipe_version_id,'recipe_name',g.recipe_name,'output_name',g.output_name,'unit',g.output_unit,'centre',g.centre,'batches',g.batches,'exceptions',g.exceptions,
 'expected',g.expected::text,'actual',g.actual::text,'gap',(g.actual-g.expected)::text,'achievement',round(100*g.actual/g.expected,6)::text,
 'actual_unit_cost',round(g.actual_unit_cost,12)::text,'standard_unit_cost',round(g.standard_unit_cost,12)::text,'unpriced',case when financial then g.unpriced end,'main_input_batches',g.main_input_batches,
 'inputs',coalesce((select jsonb_agg(jsonb_build_object('item_id',q.item_id,'name',q.name,'unit',q.unit,'planned',q.planned::text,'actual',q.actual::text,'gap',(q.actual-q.planned)::text,'variance',case when q.planned>0 then round(100*(q.actual-q.planned)/q.planned,6)::text end) order by q.name,q.item_id)
 from(select (a->>'item_id')::uuid item_id,max(a->>'name') name,max(a->>'unit') unit,sum((a->>'quantity')::numeric) actual,sum((p->>'quantity')::numeric) planned
 from evidence e cross join lateral jsonb_array_elements(e.actual_inputs)a join lateral jsonb_array_elements(e.planned_inputs)p on p->>'item_id'=a->>'item_id'
 where e.source_id=g.source_id and e.recipe_version_id=g.recipe_version_id group by a->>'item_id')q),'[]'::jsonb)) order by g.exceptions desc,g.recipe_name,g.centre,g.recipe_version_id,g.source_id) from paged g),'[]'::jsonb)) into result;
 return result;
end $$;
revoke all on function public.production_analysis(uuid,uuid,date,date,uuid,integer) from public,anon;
grant execute on function public.production_analysis(uuid,uuid,date,date,uuid,integer) to authenticated;
commit;
