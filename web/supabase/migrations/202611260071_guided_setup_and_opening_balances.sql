-- Unified verified initial balances and reviewed centre assignments. No existing stock is rewritten.
begin;
create table private.opening_entry_requests(
 organisation_id uuid not null references public.organisations(id),request_id uuid not null,actor_id uuid not null references auth.users(id),
 digest text not null,document_id uuid,zeros integer not null,created_at timestamptz not null default clock_timestamp(),primary key(organisation_id,request_id)
);
revoke all on private.opening_entry_requests from public,anon,authenticated;
create trigger active_restaurant_write before insert or update or delete on private.opening_entry_requests for each row execute function private.pp_require_active_restaurant();
alter function public.record_admin_opening(uuid,uuid,jsonb,jsonb) rename to pp_record_opening_before_unified;
alter function public.pp_record_opening_before_unified(uuid,uuid,jsonb,jsonb) set schema private;
revoke all on function private.pp_record_opening_before_unified(uuid,uuid,jsonb,jsonb) from public,anon,authenticated;
create function public.record_admin_opening(p_organisation_id uuid,p_request_id uuid,p_document jsonb,p_lines jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare prior private.opening_entry_requests;legacy public.stock_documents;site uuid;day date;lines jsonb;positive jsonb;l jsonb;doc uuid;zeros integer;digest text:=md5(jsonb_build_array(p_document,p_lines)::text);
begin
 if not private.pp_stock_role(p_organisation_id,'restaurant_admin',null) then raise exception 'Restaurant Administrator access is required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id and access_state='ACTIVE' for update;
 if not found then raise exception 'An active restaurant is required.' using errcode='42501';end if;
 if p_request_id is null or p_document->>'kind' is distinct from 'OPENING' or octet_length(coalesce(p_document::text,''))>65536 then raise exception 'Choose a valid opening stock record.' using errcode='22023';end if;
 select * into prior from private.opening_entry_requests where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then if prior.actor_id<>auth.uid() or prior.digest<>digest then raise exception 'Refresh before changing a recorded opening.' using errcode='22023';end if;return prior.document_id;end if;
 -- Preserve retries of entries recorded before this update.
 select * into legacy from public.stock_documents where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then return private.pp_record_opening_before_unified(p_organisation_id,p_request_id,p_document,p_lines);end if;
 begin site:=(p_document->>'destination_id')::uuid;day:=(p_document->>'date')::date;exception when others then raise exception 'Choose a valid centre and opening date.' using errcode='22023';end;
 if day is null or day>(select(now() at time zone time_zone)::date from public.organisations where id=p_organisation_id) or length(trim(coalesce(p_document->>'note',''))) not between 1 and 300 then raise exception 'Enter a past or current opening date and a verification note of 1 to 300 characters.' using errcode='22023';end if;
 if not exists(select 1 from public.stock_locations where organisation_id=p_organisation_id and id=site and is_active) then raise exception 'Choose an active centre in this restaurant.' using errcode='42501';end if;
 lines:=private.pp_stock_lines(p_organisation_id,p_lines);
 if lines is null or jsonb_array_length(lines)=0 then raise exception 'Enter at least one verified quantity; zero is valid and blank means unknown.' using errcode='22023';end if;
 for l in select value from jsonb_array_elements(lines) loop
  perform private.pp_assert_centre_material(p_organisation_id,site,(l->>'item_id')::uuid);
  if exists(select 1 from public.zero_opening_confirmations where organisation_id=p_organisation_id and item_id=(l->>'item_id')::uuid and stock_location_id=site)
   or exists(select 1 from public.stock_ledger where organisation_id=p_organisation_id and location_id=site and item_id=(l->>'item_id')::uuid) then
   raise exception 'An opening or stock history already exists for % at this centre. Use Correct stock balance for a verified mistake, or record the actual delivery/transfer.',l->>'name' using errcode='22023';end if;
  if exists(select 1 from private.master_opening_items i join private.master_opening_batches b on b.organisation_id=i.organisation_id and b.id=i.batch_id where i.organisation_id=p_organisation_id and i.site_id=site and i.item_id=(l->>'item_id')::uuid and not b.completed and b.id<>p_request_id) then
   raise exception 'An imported opening is already prepared for %. Use Review imported opening stock instead of creating another opening.',l->>'name' using errcode='22023';end if;
 end loop;
 select count(*) into zeros from jsonb_array_elements(lines) where(value->>'quantity')::numeric=0;
 select jsonb_agg(value) into positive from jsonb_array_elements(lines) where(value->>'quantity')::numeric>0;
 if positive is not null then doc:=private.pp_record_opening_before_unified(p_organisation_id,p_request_id,p_document,case when zeros=0 then p_lines else positive end);end if;
 for l in select value from jsonb_array_elements(lines) where(value->>'quantity')::numeric=0 loop
  perform public.confirm_zero_opening(p_organisation_id,(l->>'item_id')::uuid,site,day,p_document->>'note');
 end loop;
 insert into private.opening_entry_requests(organisation_id,request_id,actor_id,digest,document_id,zeros) values(p_organisation_id,p_request_id,auth.uid(),digest,doc,zeros);
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'OPENING_BATCH_VERIFIED',auth.uid(),coalesce(doc,p_request_id),jsonb_build_object('centre',site,'zero_confirmations',zeros,'document',doc));return doc;
end $$;
revoke all on function public.record_admin_opening(uuid,uuid,jsonb,jsonb) from public,anon;
grant execute on function public.record_admin_opening(uuid,uuid,jsonb,jsonb) to authenticated;

create or replace function private.pp_apply_material_import(org uuid,site uuid,token uuid,rows jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;first_row jsonb;result jsonb:='[]';n integer:=0;problem text;warnings text;item uuid;unit_id uuid;centre uuid;batch uuid;price_rows jsonb;price_plan jsonb;old public.items;qty numeric;day date;assigned boolean;assignment_ids jsonb;assignment_revision integer;
begin
 for r in select value from jsonb_array_elements(rows) loop
  n:=n+1;problem:=null;warnings:=null;assigned:=false;
  begin
   if jsonb_typeof(r)<>'object' or exists(select 1 from jsonb_each(r) where jsonb_typeof(value)<>'string') then raise exception 'Every field must be text.';end if;
   if coalesce(r->>'action','') not in('CREATE','UPDATE') or coalesce(r->>'material_code','')!~'^[A-Z0-9][A-Z0-9_-]{0,39}$' then raise exception 'Use CREATE or UPDATE and a valid material code.';end if;
   if coalesce(r->>'stock_tracked','') not in('true','false') or coalesce(r->>'weekly_count_required','') not in('true','false') or coalesce(r->>'requires_processing','') not in('true','false') then raise exception 'Use true or false for stock tracking, weekly count and processing flags.';end if;
   select value into first_row from jsonb_array_elements(rows) where value->>'material_code'=r->>'material_code' limit 1;
   if (r-'centre_code'-'opening_quantity'-'opening_date') is distinct from (first_row-'centre_code'-'opening_quantity'-'opening_date') then raise exception 'Repeat the same material details and price on every centre row.';end if;
   select id into unit_id from public.units_of_measure where organisation_id=org and code=r->>'base_unit';
   if unit_id is null then raise exception 'Unknown base unit. Create the unit first.';end if;
   -- A repeated code is only valid for distinct centre openings; save its master/price once.
   if not exists(select 1 from jsonb_array_elements(rows) with ordinality a(value,ord) where ord<n and value->>'material_code'=r->>'material_code') then
    select * into old from public.items where organisation_id=org and code=r->>'material_code';
    if r->>'action'='CREATE' and old.id is not null then raise exception 'Material exists. Choose UPDATE explicitly.';end if;
    if r->>'action'='UPDATE' and (old.id is null or not old.is_active) then raise exception 'UPDATE requires an active material in this restaurant.';end if;
    item:=public.save_material_setup(org,jsonb_build_object('id',old.id,'code',r->>'material_code','name',r->>'material_name','item_type',r->>'material_type','category',coalesce(r->>'category',''),'base_uom_id',unit_id,'stock_tracked',r->>'stock_tracked','is_active',true,'location_id',site,'weekly_count_required',r->>'weekly_count_required','supply_class',r->>'supply_source','requires_processing',r->>'requires_processing'));
    if coalesce(r->>'last_purchase_unit_price','')<>'' then
     if r->>'supply_source'='PROCESSED' then raise exception 'Processed-only output costs come from the linked recipe; leave purchase price blank.';end if;
     perform private.pp_import_number(r->>'last_purchase_unit_price');perform private.pp_import_date(r->>'last_purchase_date');
     price_rows:=jsonb_build_array(jsonb_build_object('material_code',r->>'material_code','quantity','1','unit_code',r->>'base_unit','total_price',r->>'last_purchase_unit_price','price_date',r->>'last_purchase_date','source_note','Known last purchase price supplied during onboarding; reference estimate only.'));
     price_plan:=public.preview_material_reference_prices(org,price_rows);
     perform public.save_material_reference_prices(org,md5(token::text||':price:'||(r->>'material_code'))::uuid,'CSV',price_rows,price_plan);
    elsif coalesce(r->>'last_purchase_date','')<>'' then raise exception 'Supply the purchase price with its date, or leave both blank.';
    end if;
   else
    if coalesce(r->>'centre_code','')='' then raise exception 'Repeated material code needs a distinct centre opening on every row.';end if;
    select id into item from public.items where organisation_id=org and code=r->>'material_code';
    if item is null then raise exception 'Fix the earlier row for this material first.';end if;
   end if;
   if coalesce(r->>'opening_quantity','')<>'' then
    if not private.pp_stock_manager(org) then raise exception 'Only restaurant administrators or Inventory Managers can prepare opening stock. Import masters without openings or ask your administrator.';end if;
    qty:=private.pp_import_number(r->>'opening_quantity',true);day:=private.pp_import_date(r->>'opening_date');
    if day>(select(now() at time zone time_zone)::date from public.organisations where id=org) then raise exception 'Opening date cannot be in the future.';end if;
    if r->>'stock_tracked'<>'true' then raise exception 'Opening quantity requires stock tracking.';end if;
    select id into centre from public.stock_locations where organisation_id=org and code=r->>'centre_code' and is_active and(site is null or outlet_id is null or outlet_id=site);
    if centre is null then raise exception 'Choose an active, compatible centre code from this restaurant.';end if;
    if coalesce(r->>'_assign_centres','false') not in('true','false') then raise exception 'Review the opening material assignment choice.';end if;
    if not private.pp_centre_material(org,centre,item) then
     if coalesce(r->>'_assign_centres','false')<>'true' then raise exception '% is not assigned to %. Select Assign opening materials to their centres before reviewing, or update the centre material list.',r->>'material_name',r->>'centre_code';end if;
     select coalesce(revision,0) into assignment_revision from private.centre_catalogues where organisation_id=org and site_id=centre;
     select coalesce(jsonb_agg(id),'[]'::jsonb) into assignment_ids from public.items where organisation_id=org and stock_tracked and private.pp_centre_material(org,centre,id);
     perform public.save_centre_materials(org,centre,coalesce(assignment_revision,0),md5(token::text||':assign:'||centre::text||':'||item::text)::uuid,assignment_ids||jsonb_build_array(item));assigned:=true;
    end if;
    if exists(select 1 from private.master_opening_items where organisation_id=org and item_id=item and site_id=centre) or exists(select 1 from public.zero_opening_confirmations where organisation_id=org and item_id=item and stock_location_id=centre) or exists(select 1 from public.stock_ledger where organisation_id=org and item_id=item and location_id=centre) or exists(select 1 from public.stock_documents d cross join lateral jsonb_array_elements(d.lines) l where d.organisation_id=org and d.kind='OPENING' and d.destination_id=centre and d.state not in('CANCELLED','REJECTED') and l->>'item_id'=item::text) then raise exception 'Opening already prepared, declared or posted for this material/centre. Use the existing record or a reviewed count to correct stock.';end if;
    batch:=md5(token::text||':opening:'||centre::text||':'||day::text)::uuid;
    insert into private.master_opening_batches(id,organisation_id,site_id,opening_date,created_by) values(batch,org,centre,day,auth.uid()) on conflict(id) do nothing;
    insert into private.master_opening_items values(org,batch,item,centre,qty);
    warnings:=case when assigned then 'ASSIGN to '||(r->>'centre_code')||'; ' else '' end||'Opening ready for Administrator recording; no stock posted. Verified zero is retained.';
   elsif coalesce(r->>'centre_code','')<>'' or coalesce(r->>'opening_date','')<>'' then raise exception 'Supply centre, opening quantity and date together; blank quantity means unknown, not zero.';
   else warnings:='No opening supplied; complete it later where required.';
   end if;
   if coalesce(r->>'last_purchase_unit_price','')='' then warnings:=warnings||' No purchase price supplied.';end if;
  exception when others then problem:=sqlerrm;end;
  result:=result||jsonb_build_array(jsonb_build_object('row',n,'code',r->>'material_code','name',r->>'material_name','action',case when problem is null then r->>'action' else 'ERROR' end,'detail',coalesce(nullif(r->>'centre_code','')||' / '||nullif(r->>'opening_quantity','')||' '||coalesce(r->>'base_unit',''),'Master data only'),'error',problem,'warning',warnings));
 end loop;
 return result;
end $$;

create function public.setup_next_actions(p_organisation_id uuid,p_category text default 'ALL',p_page integer default 1) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;today date;begin
 if not private.pp_team_manage(p_organisation_id) or not exists(select 1 from public.organisations where id=p_organisation_id and access_state='ACTIVE') then raise exception 'Active restaurant setup access required.' using errcode='42501';end if;
 if p_category is null or p_category not in('ALL','CENTRES','MATERIALS','OPENINGS','PROCESSING','OTHER') or p_page is null or p_page not between 1 and 100000 then raise exception 'Choose a setup area and page.' using errcode='22023';end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 with materials as materialized(select i.*,case when i.base_uom_id is not null then private.pp_effective_material_cost(p_organisation_id,i.id,today,array[]::uuid[])->>'unit_cost' end unit_cost from public.items i where i.organisation_id=p_organisation_id and i.is_active),
 actions as materialized(
 select 'centre:'||s.id id,'CENTRES' kind,s.name title,'Assign an active responsible colleague' detail,'Administrator' responsible,null::text centre_owner,'/workspace/setup/centres' path,jsonb_build_object('edit',s.id) params,0 priority
 from public.stock_locations s left join public.organisation_memberships m on m.organisation_id=s.organisation_id and m.id=s.responsible_membership_id and m.status='active'
 where s.organisation_id=p_organisation_id and s.is_active and m.id is null
 union all
 select 'material:'||i.id||':'||v.field,'MATERIALS',i.name,v.field||' needed','Administrator',null,'/workspace/materials',jsonb_build_object('edit',i.id),1 from materials i cross join lateral(values('Base unit',i.base_uom_id is null),('Category',i.category_id is null),('Cost or processing link',i.base_uom_id is not null and i.unit_cost is null),('Centre assignment',i.stock_tracked and not exists(select 1 from public.stock_locations s where s.organisation_id=i.organisation_id and s.is_active and private.pp_centre_material(i.organisation_id,s.id,i.id))))v(field,missing) where v.missing
 union all
 select 'opening:'||i.id||':'||s.id,'OPENINGS',i.name||' / '||s.name,
 case when exists(select 1 from private.master_opening_items x join private.master_opening_batches b on b.id=x.batch_id and b.organisation_id=x.organisation_id where x.organisation_id=i.organisation_id and x.site_id=s.id and x.item_id=i.id and not b.completed) then 'Imported quantity is ready to record' else 'Verify a starting quantity, including zero' end,
 'Administrator',private.pp_member_label(p_organisation_id,s.responsible_membership_id),
 case when exists(select 1 from private.master_opening_items x join private.master_opening_batches b on b.id=x.batch_id and b.organisation_id=x.organisation_id where x.organisation_id=i.organisation_id and x.site_id=s.id and x.item_id=i.id and not b.completed) then '/workspace/inventory/openings' else '/workspace/inventory' end,
 jsonb_build_object('view','movements','new','OPENING','location',s.id,'opening_centre',s.id,'opening_item',i.id),2
 from materials i join public.stock_locations s on s.organisation_id=i.organisation_id and s.is_active and private.pp_centre_material(i.organisation_id,s.id,i.id)
 where i.stock_tracked and not private.pp_opening_ready(i.organisation_id,i.id,s.id)
 union all
 select 'processing:'||i.id,'PROCESSING',i.name,'Save an active production baseline and permitted centres','Administrator',null,'/workspace/setup/production','{}'::jsonb,3 from materials i where i.requires_processing and not exists(select 1 from public.processing_standards st join public.processing_standard_sites ss on ss.organisation_id=st.organisation_id and ss.standard_id=st.id join public.stock_locations s on s.organisation_id=ss.organisation_id and s.id=ss.site_id and s.is_active and s.processing_enabled where st.organisation_id=i.organisation_id and st.primary_item_id=i.id and st.is_active)
 union all
 select 'stage:'||(value->>'name'),'OTHER',value->>'name',value->>'detail','Administrator',null,value->>'path','{}'::jsonb,case when value->>'name' in('Business & locations','Reporting calendar','Users & roles','Stock centres') then 0 when value->>'name' in('Suppliers','Materials, prices & opening stock') then 1 else 4 end from jsonb_array_elements(public.setup_workspace(p_organisation_id)->'progress'->'stages')value where not(value->>'ready')::boolean and (value->>'name' not in('Stock centres','Materials, prices & opening stock','Processing baselines') or(value->>'name'='Stock centres' and not exists(select 1 from public.stock_locations where organisation_id=p_organisation_id and is_active)) or(value->>'name'='Materials, prices & opening stock' and not exists(select 1 from materials)))
 ),filtered as(select * from actions where p_category='ALL' or kind=p_category),paged as(select * from filtered order by priority,title,id limit 20 offset(p_page-1)*20)
 select jsonb_build_object('total',(select count(*) from filtered),'remaining',(select count(*) from actions),'summary',coalesce((select jsonb_agg(to_jsonb(x)) from(select kind,count(*) total from actions group by kind order by kind)x),'[]'::jsonb),'next',(select to_jsonb(x) from(select * from actions order by priority,title,id limit 1)x),'rows',coalesce((select jsonb_agg(to_jsonb(p) order by priority,title,id) from paged p),'[]'::jsonb)) into result;return result;
end $$;
revoke all on function public.setup_next_actions(uuid,text,integer) from public,anon;
grant execute on function public.setup_next_actions(uuid,text,integer) to authenticated;
notify pgrst,'reload schema';
commit;
