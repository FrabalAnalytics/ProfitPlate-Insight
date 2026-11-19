-- Single-step, centre-owned processing. All submitted materials post atomically.
-- Existing pending batches remain unchanged until their original recorder completes them.
begin;
create table private.processing_submissions (
 organisation_id uuid not null references public.organisations(id),
 submission_id uuid not null, actor_id uuid not null references auth.users(id),
 input_hash text not null, document_ids jsonb not null,
 primary key(organisation_id,submission_id)
);
alter table private.processing_submissions enable row level security;
revoke all on private.processing_submissions from public,anon,authenticated;

-- Reuse the measured-baseline validation, without an approval requirement or mandatory variance note.
create function private.pp_prepare_processing(org uuid, token uuid, p_document jsonb,p_lines jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare p_organisation_id uuid:=org;result uuid:=gen_random_uuid();src public.stock_locations;day date;
 standard public.processing_standards;actual_lines jsonb;lines jsonb;waste jsonb;entry jsonb;output jsonb;
 primary_actual numeric;actual numeric;base_factor numeric;expected_base numeric;qty numeric;deviation numeric;
 outside boolean;reason text;usable numeric;expected numeric;input_mass numeric;waste_mass numeric;
 mass_balance numeric;measurable boolean;
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
   output:=jsonb_build_object('item_id',standard.output_item_id,'quantity',qty::text,'planned_output',expected_base::text,'actual_output',actual::text,'recipe_version_id',standard.recipe_version_id,'processing_standard_id',standard.id,'expected_output',expected_base::text,'output_variance',(qty-expected_base)::text,'variance_percent',round(deviation,6)::text,'outside_tolerance',outside,'variance_reason',reason,'usable_weight_kg',usable::text,'waste_included_in_inputs',true,'output_unit_basis','STOCK_BASE');
  else raise exception 'Save a processing standard, choose its centre and record actual inputs before requesting production.' using errcode='22023';end if;

 insert into public.stock_documents(id,organisation_id,request_id,input_hash,reference,kind,source_id,recipe_version_id,document_date,note,lines,output,created_by)
 values(result,org,token,md5(jsonb_build_array(p_document,p_lines)::text),'PRC-'||upper(substr(replace(result::text,'-',''),1,12)),
 'PRODUCTION',src.id,standard.recipe_version_id,day,coalesce(nullif(trim(p_document->>'note'),''),'Material processing'),lines,output,auth.uid());
 insert into public.processing_batches values(org,result,standard.id,expected_base,qty,qty-expected_base,deviation,outside,usable,reason,primary_actual,
 private.pp_member_label(org,src.responsible_membership_id),input_mass,waste_mass,mass_balance);
 insert into public.processing_waste select org,result,(value->>'item_id')::uuid,(value->>'quantity')::numeric,trim(value->>'reason') from jsonb_array_elements(waste);
 return result;
end $$;
revoke all on function private.pp_prepare_processing(uuid,uuid,jsonb,jsonb) from public,anon,authenticated;

create function private.pp_finish_processing(org uuid,doc uuid,submitter text) returns uuid
language plpgsql security definer set search_path='' as $$
declare d public.stock_documents;line jsonb;name text:=trim(submitter);
begin
 if not private.pp_stock_read(org) then raise exception 'Stock access required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=org for update;
 select * into d from public.stock_documents where organisation_id=org and id=doc and kind='PRODUCTION';
 if not found or d.created_by<>auth.uid() or not private.pp_stock_site(org,d.source_id,'request') then raise exception 'Only the recorder with processing access at this centre can submit this entry.' using errcode='42501';end if;
 if name is null or length(name) not between 1 and 120 or name ~ '[[:cntrl:]]' then raise exception 'Enter the submitter name (up to 120 characters).' using errcode='22023';end if;
 if d.state='POSTED' and d.submitter_name=name then return d.id;end if;
 if d.state not in ('REQUESTED','APPROVED') then raise exception 'This processing entry is already completed or closed.' using errcode='22023';end if;
 if not exists(select 1 from public.processing_batches b join public.processing_standards st on st.organisation_id=b.organisation_id and st.id=b.standard_id
 join public.processing_standard_sites ss on ss.organisation_id=b.organisation_id and ss.standard_id=b.standard_id and ss.site_id=d.source_id
 join public.stock_locations s on s.organisation_id=ss.organisation_id and s.id=ss.site_id
 join public.organisation_memberships m on m.organisation_id=s.organisation_id and m.id=s.responsible_membership_id and m.status='active'
 where b.organisation_id=org and b.document_id=doc and st.is_active and s.is_active and s.processing_enabled) then raise exception 'This centre or its processing baseline is no longer available. Check setup.' using errcode='22023';end if;
 for line in select value from jsonb_array_elements(d.lines) loop
  perform private.pp_stock_entry(org,doc,d.source_id,(line->>'item_id')::uuid,-(line->>'quantity')::numeric,d.document_date);
 end loop;
 perform private.pp_stock_entry(org,doc,d.source_id,(d.output->>'item_id')::uuid,(d.output->>'quantity')::numeric,d.document_date);
 update public.stock_documents set submitter_name=name,state='POSTED',completed_by=auth.uid(),completed_at=clock_timestamp() where id=doc;
 insert into private.processing_batch_costs values(org,doc,private.pp_processing_cost_snapshot(org,doc),now()) on conflict do nothing;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details)
 values(org,'PROCESSING_RECORDED',auth.uid(),doc,jsonb_build_object('centre',d.source_id,'submitter_name',name,'approval_required',false));
 return doc;
end $$;
revoke all on function private.pp_finish_processing(uuid,uuid,text) from public,anon,authenticated;

create function public.submit_material_processing(p_organisation_id uuid,p_submission_id uuid,p_value jsonb) returns jsonb
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
   'processing_waste',coalesce(row->'waste','[]'::jsonb),'waste_confirmed',true);
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
revoke all on function public.submit_material_processing(uuid,uuid,jsonb) from public,anon;
grant execute on function public.submit_material_processing(uuid,uuid,jsonb) to authenticated;

-- Explicit completion of older pending entries; no historical stock is changed by this migration.
create function public.complete_processing_record(p_organisation_id uuid,p_document_id uuid,p_submitter_name text) returns uuid
language sql security definer set search_path='' as $$select private.pp_finish_processing(p_organisation_id,p_document_id,p_submitter_name)$$;
revoke all on function public.complete_processing_record(uuid,uuid,text) from public,anon;
grant execute on function public.complete_processing_record(uuid,uuid,text) to authenticated;

-- Expose the original account separately from the required human submitter name.
alter function public.processing_activity(uuid,uuid,date,date,text,integer,text) rename to pp_processing_activity_before_direct;
alter function public.pp_processing_activity_before_direct(uuid,uuid,date,date,text,integer,text) set schema private;
revoke all on function private.pp_processing_activity_before_direct(uuid,uuid,date,date,text,integer,text) from public,anon,authenticated;
create function public.processing_activity(p_organisation_id uuid,p_site_id uuid,p_from date,p_to date,p_kind text default 'BATCHES',p_page integer default 1,p_state text default 'ALL') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 result:=private.pp_processing_activity_before_direct(p_organisation_id,p_site_id,p_from,p_to,p_kind,p_page,p_state);
 if p_kind='BATCHES' then
  result:=jsonb_set(result,'{rows}',coalesce((select jsonb_agg(r||jsonb_build_object('submitter_name',d.submitter_name,
  'can_complete',d.created_by=auth.uid() and d.state in ('REQUESTED','APPROVED') and private.pp_stock_site(p_organisation_id,d.source_id,'request')) order by n)
  from jsonb_array_elements(result->'rows') with ordinality rows(r,n) join public.stock_documents d on d.id=(r->>'id')::uuid and d.organisation_id=p_organisation_id),'[]'::jsonb));
 end if;
 return result;
end $$;
revoke all on function public.processing_activity(uuid,uuid,date,date,text,integer,text) from public,anon;
grant execute on function public.processing_activity(uuid,uuid,date,date,text,integer,text) to authenticated;
commit;
