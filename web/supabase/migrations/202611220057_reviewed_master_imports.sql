-- Reviewed onboarding. No upload posts stock or replaces published recipe history.
begin;

create table private.master_opening_batches(
 id uuid primary key, organisation_id uuid not null references public.organisations(id),
 site_id uuid not null, opening_date date not null, created_by uuid not null references auth.users(id),
 document_id uuid, completed boolean not null default false, created_at timestamptz not null default now(),
 unique(organisation_id,id), foreign key(organisation_id,site_id) references public.stock_locations(organisation_id,id)
);
create table private.master_opening_items(
 organisation_id uuid not null, batch_id uuid not null, item_id uuid not null, site_id uuid not null,
 quantity numeric not null check(quantity>=0), primary key(organisation_id,item_id,site_id),
 foreign key(organisation_id,batch_id) references private.master_opening_batches(organisation_id,id),
 foreign key(organisation_id,item_id) references public.items(organisation_id,id),
 foreign key(organisation_id,site_id) references public.stock_locations(organisation_id,id)
);
revoke all on private.master_opening_batches,private.master_opening_items from public,anon,authenticated;
create trigger active_restaurant_write before insert or update or delete on private.master_opening_batches for each row execute function private.pp_require_active_restaurant();
create trigger active_restaurant_write before insert or update or delete on private.master_opening_items for each row execute function private.pp_require_active_restaurant();

create function private.pp_master_import_access(org uuid,kind text) returns void language plpgsql security definer set search_path='' as $$begin
 if not coalesce(case kind when 'MATERIAL' then private.pp_catalogue_write(org) when 'RECIPE' then private.pp_recipe_write(org) else false end,false)
 or not exists(select 1 from public.organisations where id=org and access_state='ACTIVE') then raise exception 'Active restaurant and matching setup permission required.' using errcode='42501';end if;
end $$;
create function private.pp_import_number(v text,allow_zero boolean default false) returns numeric language plpgsql immutable set search_path='' as $$begin
 if coalesce(v,'')!~'^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' or (v::numeric<=0 and not allow_zero) then raise exception 'Use a positive number, up to six decimals, without commas (zero only for opening stock).' using errcode='22023';end if;return v::numeric;
end $$;
create function private.pp_import_date(v text) returns date language plpgsql immutable set search_path='' as $$begin
 if coalesce(v,'')!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or to_char(v::date,'YYYY-MM-DD')<>v then raise exception 'Use a valid date in YYYY-MM-DD format.' using errcode='22023';end if;return v::date;
end $$;

-- Constant-time review revisions avoid serialising an entire restaurant's stock history.
create table private.master_import_revisions(organisation_id uuid primary key references public.organisations(id),revision bigint not null default 0);
revoke all on private.master_import_revisions from public,anon,authenticated;
create trigger active_restaurant_write before insert or update or delete on private.master_import_revisions for each row execute function private.pp_require_active_restaurant();
create function private.pp_bump_master_import_revision() returns trigger language plpgsql security definer set search_path='' as $$begin
 insert into private.master_import_revisions(organisation_id,revision) values(coalesce(new.organisation_id,old.organisation_id),1)
 on conflict(organisation_id) do update set revision=private.master_import_revisions.revision+1;
 return coalesce(new,old);
end $$;
do $$declare relation text;begin
 foreach relation in array array['public.items','public.units_of_measure','public.item_uom_conversions','public.item_categories','public.locations','public.stock_locations','public.material_reference_prices','public.recipes','public.recipe_versions','public.recipe_components','public.recipe_outputs','public.stock_documents','public.stock_ledger','public.zero_opening_confirmations','private.master_opening_items','private.master_opening_batches'] loop
 execute format('create trigger master_import_revision after insert or update or delete on %s for each row execute function private.pp_bump_master_import_revision()',relation);
 end loop;
end $$;
create function private.pp_master_import_revision(org uuid) returns text language sql stable security definer set search_path='' as $$
 select coalesce((select revision::text from private.master_import_revisions where organisation_id=org),'0');
$$;

create function private.pp_apply_material_import(org uuid,site uuid,token uuid,rows jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;first_row jsonb;result jsonb:='[]';n integer:=0;problem text;warnings text;item uuid;unit_id uuid;centre uuid;batch uuid;price_rows jsonb;price_plan jsonb;old public.items;qty numeric;day date;
begin
 for r in select value from jsonb_array_elements(rows) loop
  n:=n+1;problem:=null;warnings:=null;
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
    if exists(select 1 from private.master_opening_items where organisation_id=org and item_id=item and site_id=centre) or exists(select 1 from public.zero_opening_confirmations where organisation_id=org and item_id=item and stock_location_id=centre) or exists(select 1 from public.stock_ledger where organisation_id=org and item_id=item and location_id=centre) or exists(select 1 from public.stock_documents d cross join lateral jsonb_array_elements(d.lines) l where d.organisation_id=org and d.kind='OPENING' and d.destination_id=centre and d.state not in('CANCELLED','REJECTED') and l->>'item_id'=item::text) then raise exception 'Opening already prepared, declared or posted for this material/centre. Use the existing record or a reviewed count to correct stock.';end if;
    batch:=md5(token::text||':opening:'||centre::text||':'||day::text)::uuid;
    insert into private.master_opening_batches(id,organisation_id,site_id,opening_date,created_by) values(batch,org,centre,day,auth.uid()) on conflict(id) do nothing;
    insert into private.master_opening_items values(org,batch,item,centre,qty);
    warnings:='Opening prepared for stock review; no ledger change. Explicit zero is retained.';
   elsif coalesce(r->>'centre_code','')<>'' or coalesce(r->>'opening_date','')<>'' then raise exception 'Supply centre, opening quantity and date together; blank quantity means unknown, not zero.';
   else warnings:='No opening supplied; complete it later where required.';
   end if;
   if coalesce(r->>'last_purchase_unit_price','')='' then warnings:=warnings||' No purchase price supplied.';end if;
  exception when others then problem:=sqlerrm;end;
  result:=result||jsonb_build_array(jsonb_build_object('row',n,'code',r->>'material_code','name',r->>'material_name','action',case when problem is null then r->>'action' else 'ERROR' end,'detail',coalesce(nullif(r->>'centre_code','')||' / '||nullif(r->>'opening_quantity','')||' '||coalesce(r->>'base_unit',''),'Master data only'),'error',problem,'warning',warnings));
 end loop;
 return result;
end $$;

create function private.pp_apply_recipe_import(org uuid,site uuid,token uuid,rows jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare code text;r jsonb;c jsonb;done text[]:='{}';keys text[];result jsonb:='[]';components jsonb;problem text;dependency uuid;root uuid;output_unit uuid;unit_id uuid;day date;quantity numeric;pass integer;progress boolean;version_id uuid;version_no integer;line_no integer;
begin
 select array_agg(distinct value->>'recipe_code') into keys from jsonb_array_elements(rows);
 for pass in 1..51 loop
  progress:=false;
  foreach code in array keys loop
   if code=any(done) then continue;end if;
   select value into r from jsonb_array_elements(rows) where value->>'recipe_code'=code limit 1;
   -- The file can be unsorted. Publish every in-file child before its parents.
   if exists(select 1 from jsonb_array_elements(rows) a where a->>'recipe_code'=code and a->>'component_kind'='RECIPE' and a->>'component_code'=any(keys) and not(a->>'component_code'=any(done))) then continue;end if;
   problem:=null;version_no:=null;
   select min(ord)::integer into line_no from jsonb_array_elements(rows) with ordinality a(value,ord) where value->>'recipe_code'=code;
   begin
    if coalesce(code,'')!~'^[A-Z0-9][A-Z0-9_-]{0,39}$' or coalesce(r->>'action','') not in('CREATE','NEW_VERSION') then raise exception 'Use a valid recipe code and CREATE or NEW_VERSION.';end if;
    if exists(select 1 from jsonb_array_elements(rows) a where a->>'recipe_code'=code and (a-'component_kind'-'component_code'-'component_version'-'component_quantity'-'component_unit') is distinct from (r-'component_kind'-'component_code'-'component_version'-'component_quantity'-'component_unit')) then raise exception 'Repeat identical recipe header details on every component row.';end if;
    select id into root from public.recipes where organisation_id=org and public.recipes.code=code;
    if r->>'action'='CREATE' and root is not null then raise exception 'Recipe exists. Use NEW_VERSION to preserve history.';end if;
    if r->>'action'='NEW_VERSION' and root is null then raise exception 'NEW_VERSION requires an existing recipe in this restaurant.';end if;
    day:=private.pp_import_date(r->>'effective_from');quantity:=private.pp_import_number(r->>'yield_quantity');
    select id into output_unit from public.units_of_measure where organisation_id=org and public.units_of_measure.code=r->>'yield_unit';
    if output_unit is null then raise exception 'Unknown yield unit.';end if;
    components:='[]';
    for c in select value from jsonb_array_elements(rows) where value->>'recipe_code'=code loop
     if jsonb_typeof(c)<>'object' or exists(select 1 from jsonb_each(c) where jsonb_typeof(value)<>'string') then raise exception 'Every field must be text.';end if;
     perform private.pp_import_number(c->>'component_quantity');
     select id into unit_id from public.units_of_measure where organisation_id=org and public.units_of_measure.code=c->>'component_unit';
     if unit_id is null then raise exception 'Unknown component unit for %.',c->>'component_code';end if;
     if c->>'component_kind'='ITEM' then
      if coalesce(c->>'component_version','')<>'' then raise exception 'Materials do not have recipe versions.';end if;
      select id into dependency from public.items where organisation_id=org and public.items.code=c->>'component_code' and is_active;
     elsif c->>'component_kind'='RECIPE' then
      if coalesce(c->>'component_version','')<>'' and c->>'component_version'!~'^[1-9][0-9]{0,8}$' then raise exception 'Use a positive version number or leave blank for the latest eligible sub-recipe.';end if;
      select v.id into dependency from public.recipe_versions v join public.recipes a on a.organisation_id=v.organisation_id and a.id=v.recipe_id where a.organisation_id=org and a.code=c->>'component_code' and a.recipe_type='SUB_RECIPE' and v.effective_from<=day and(coalesce(c->>'component_version','')='' or v.version::text=c->>'component_version') order by v.effective_from desc,v.version desc limit 1;
     else raise exception 'Choose ITEM or RECIPE for each component.';
     end if;
     if dependency is null then raise exception 'Component % or its eligible version is unavailable in this restaurant. Fix the child recipe first.',c->>'component_code';end if;
     if exists(select 1 from jsonb_array_elements(components) a where a->>'target_id'=dependency::text and a->>'kind'=c->>'component_kind') then raise exception 'Duplicate component %. Consolidate its quantity.',c->>'component_code';end if;
     components:=components||jsonb_build_array(jsonb_build_object('kind',c->>'component_kind','target_id',dependency,'quantity',c->>'component_quantity','uom_id',unit_id));
    end loop;
    version_id:=public.publish_recipe_setup(org,md5(token::text||':recipe:'||code)::uuid,jsonb_build_object('recipe_id',root,'code',code,'name',r->>'recipe_name','recipe_type',r->>'recipe_type','location_id',site,'effective_from',day,'yield_quantity',quantity,'yield_uom_id',output_unit,'notes',coalesce(r->>'notes','')),components);
    select version into version_no from public.recipe_versions where id=version_id;
   exception when others then problem:=sqlerrm;end;
   result:=result||jsonb_build_array(jsonb_build_object('row',line_no,'code',code,'name',r->>'recipe_name','action',case when problem is null then r->>'action' else 'ERROR' end,'detail',coalesce('Version '||version_no::text,'Not published'),'error',problem,'warning',case when problem is null then 'Published versions are preserved; costing uses these saved component versions.' end));
   done:=array_append(done,code);progress:=true;
  end loop;
  exit when cardinality(done)=cardinality(keys) or not progress;
 end loop;
 foreach code in array keys loop
  if not(code=any(done)) then result:=result||jsonb_build_array(jsonb_build_object('row',0,'code',code,'name',code,'action','ERROR','detail','','error','Circular or unresolved in-file recipe dependency.','warning',null));end if;
 end loop;
 return result;
end $$;

-- Run the real validation/save path inside a rollback-only subtransaction. Preview never
-- leaves master records, audits, prices, opening declarations or recipe versions behind.
create function public.preview_master_import(p_organisation_id uuid,p_kind text,p_location_id uuid,p_rows jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;revision text;begin
 perform private.pp_master_import_access(p_organisation_id,p_kind);perform private.pp_setup_location(p_organisation_id,p_location_id);
 if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) not between 1 and 500 or octet_length(p_rows::text)>524288 then raise exception 'Import 1 to 500 rows, under 512 KB of reviewed data.' using errcode='22023';end if;
 if p_kind='MATERIAL' and (select count(distinct value->>'material_code') from jsonb_array_elements(p_rows))>100 or p_kind='RECIPE' and(select count(distinct value->>'recipe_code') from jsonb_array_elements(p_rows))>50 then raise exception 'Use at most 100 materials or 50 recipes per file.' using errcode='22023';end if;
 revision:=private.pp_master_import_revision(p_organisation_id);
 begin
  if p_kind='MATERIAL' then result:=private.pp_apply_material_import(p_organisation_id,p_location_id,gen_random_uuid(),p_rows);else result:=private.pp_apply_recipe_import(p_organisation_id,p_location_id,gen_random_uuid(),p_rows);end if;
  raise exception using errcode='P0099',message='Preview rollback';
 exception when sqlstate 'P0099' then null;end;
 return jsonb_build_object('rows',result,'revision',revision,'valid',not exists(select 1 from jsonb_array_elements(result) a where a->>'error' is not null));
end $$;
create function public.post_master_import(p_organisation_id uuid,p_kind text,p_location_id uuid,p_request_id uuid,p_rows jsonb,p_preview jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare plan jsonb;result jsonb;old private.setup_requests;digest text:=md5(jsonb_build_array(p_kind,p_location_id,p_rows,p_preview)::text);begin
 perform private.pp_master_import_access(p_organisation_id,p_kind);
 if p_request_id is null then raise exception 'Import request required.' using errcode='22023';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into old from private.setup_requests where organisation_id=p_organisation_id and request_id=p_request_id and kind=p_kind||'_IMPORT';
 if found then if old.input_hash<>digest then raise exception 'Refresh and review changed data.' using errcode='22023';end if;return 0;end if;
 plan:=public.preview_master_import(p_organisation_id,p_kind,p_location_id,p_rows);
 if plan is distinct from p_preview or not coalesce((plan->>'valid')::boolean,false) then raise exception 'Data changed or the file has errors. Review it again before saving.' using errcode='22023';end if;
 if p_kind='MATERIAL' then result:=private.pp_apply_material_import(p_organisation_id,p_location_id,p_request_id,p_rows);else result:=private.pp_apply_recipe_import(p_organisation_id,p_location_id,p_request_id,p_rows);end if;
 if exists(select 1 from jsonb_array_elements(result) a where a->>'error' is not null) then raise exception 'Import could not be completed. Nothing saved. Review again.' using errcode='22023';end if;
 insert into private.setup_requests values(p_organisation_id,p_request_id,p_kind||'_IMPORT',digest,p_request_id);
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'MASTER_DATA_IMPORTED',auth.uid(),p_request_id,jsonb_build_object('kind',p_kind,'location',p_location_id,'records',jsonb_array_length(result)));
 return jsonb_array_length(result);
end $$;

create function public.import_opening_queue(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock access required.' using errcode='42501';end if;
 select coalesce(jsonb_agg(x order by x->>'centre',x->>'date'),'[]'::jsonb) into result from(
 select jsonb_build_object('id',b.id,'centre',s.name,'date',b.opening_date,'completed',b.completed,'document_id',b.document_id,'can_submit',private.pp_stock_site(p_organisation_id,b.site_id,'inventory') and private.pp_stock_site(p_organisation_id,b.site_id,'request') and(not exists(select 1 from private.master_opening_items i where i.batch_id=b.id and i.quantity=0) or private.pp_stock_manager(p_organisation_id)),
 'lines',(select jsonb_agg(jsonb_build_object('name',m.name,'code',m.code,'quantity',i.quantity::text,'unit',u.code) order by m.name) from private.master_opening_items i join public.items m on m.organisation_id=i.organisation_id and m.id=i.item_id join public.units_of_measure u on u.organisation_id=m.organisation_id and u.id=m.base_uom_id where i.batch_id=b.id)) x
 from private.master_opening_batches b join public.stock_locations s on s.organisation_id=b.organisation_id and s.id=b.site_id
 where b.organisation_id=p_organisation_id and private.pp_stock_site(p_organisation_id,b.site_id,'read') and not b.completed order by b.created_at limit 100) q;
 return result;
end $$;
create function public.submit_import_opening(p_organisation_id uuid,p_batch_id uuid) returns uuid language plpgsql security definer set search_path='' as $$declare b private.master_opening_batches;lines jsonb;r record;doc uuid;begin
 perform 1 from public.organisations where id=p_organisation_id and access_state='ACTIVE' for update;
 select * into b from private.master_opening_batches where organisation_id=p_organisation_id and id=p_batch_id;
 if b.id is null or not(private.pp_stock_site(p_organisation_id,b.site_id,'inventory') and private.pp_stock_site(p_organisation_id,b.site_id,'request')) then raise exception 'Inventory request access required at this centre.' using errcode='42501';end if;
 if b.completed then return b.document_id;end if;
 for r in select * from private.master_opening_items where organisation_id=p_organisation_id and batch_id=b.id and quantity=0 loop
  perform public.confirm_zero_opening(p_organisation_id,r.item_id,b.site_id,b.opening_date,'Explicit zero opening supplied in reviewed onboarding import.');
 end loop;
 select jsonb_agg(jsonb_build_object('item_id',item_id,'quantity',quantity::text) order by item_id) into lines from private.master_opening_items where organisation_id=p_organisation_id and batch_id=b.id and quantity>0;
 if lines is not null then doc:=public.request_stock_document(p_organisation_id,b.id,jsonb_build_object('kind','OPENING','destination_id',b.site_id,'date',b.opening_date,'note','Opening stock from reviewed material import; verify physical quantities before approval and posting.'),lines);end if;
 update private.master_opening_batches set completed=true,document_id=doc where id=b.id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'IMPORTED_OPENING_SUBMITTED',auth.uid(),b.id,jsonb_build_object('document',doc));return doc;
end $$;

revoke all on function private.pp_bump_master_import_revision() from public,anon,authenticated;
revoke all on function private.pp_master_import_access(uuid,text),private.pp_import_number(text,boolean),private.pp_import_date(text),private.pp_master_import_revision(uuid),private.pp_apply_material_import(uuid,uuid,uuid,jsonb),private.pp_apply_recipe_import(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.preview_master_import(uuid,text,uuid,jsonb),public.post_master_import(uuid,text,uuid,uuid,jsonb,jsonb),public.import_opening_queue(uuid),public.submit_import_opening(uuid,uuid) from public,anon;
grant execute on function public.preview_master_import(uuid,text,uuid,jsonb),public.post_master_import(uuid,text,uuid,uuid,jsonb,jsonb),public.import_opening_queue(uuid),public.submit_import_opening(uuid,uuid) to authenticated;
-- Blank menu recipe_version now resolves to the latest eligible imported final recipe.
create or replace function private.pp_menu_import_plan(org uuid,site uuid,rows jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;v jsonb;outlet public.locations;m public.menu_items;rv uuid;n integer:=0;result jsonb:='[]';problem text;unchanged boolean;state jsonb;
begin
 if not private.pp_menu_write(org) then raise exception 'Menu editing access denied.' using errcode='42501';end if;
 select * into outlet from public.locations where organisation_id=org and id=site and is_active;
 if not found then raise exception 'Choose an active outlet.' using errcode='22023';end if;
 if rows is null or jsonb_typeof(rows)<>'array' or jsonb_array_length(rows) not between 1 and 100 or octet_length(rows::text)>262144 then raise exception 'Import 1 to 100 menu rows at a time.' using errcode='22023';end if;
 for r in select value from jsonb_array_elements(rows) loop
  n:=n+1;problem:=null;v:=null;state:=null;unchanged:=false;rv:=null;m:=null;
  begin
   if exists(select 1 from jsonb_each(r) where jsonb_typeof(value)<>'string') then raise exception 'All CSV fields must be text.';end if;
   if coalesce(r->>'action','') not in('CREATE','UPDATE') then raise exception 'Action must be CREATE or UPDATE.';end if;
   if coalesce(r->>'menu_code','')!~'^[A-Z0-9][A-Z0-9_-]{0,39}$' or length(trim(coalesce(r->>'menu_name',''))) not between 1 and 120 then raise exception 'Enter a menu code and name.';end if;
   if (select count(*) from jsonb_array_elements(rows) a where a->>'menu_code'=r->>'menu_code')>1 then raise exception 'Menu code occurs more than once in this file.';end if;
   select * into m from public.menu_items where organisation_id=org and code=r->>'menu_code';
   if r->>'action'='CREATE' and m.id is not null then raise exception 'Code already exists. Use UPDATE deliberately or remove the duplicate.';end if;
   if r->>'action'='UPDATE' and(m.id is null or not m.is_active or m.brand_id<>outlet.brand_id or(m.location_id is not null and m.location_id<>site)) then raise exception 'Active menu code is unavailable in this outlet/brand.';end if;
   if r->>'major_category' not in('FOOD','DRINK') or not exists(select 1 from public.restaurant_menu_categories where organisation_id=org and major=r->>'major_category' and name=r->>'subcategory' and is_active) then raise exception 'Choose Food/Drink and an active matching subcategory from Menu categories.';end if;
   if coalesce(r->>'recipe_code','')<>'' then
    select v.id into rv from public.recipe_versions v join public.recipes a on a.organisation_id=v.organisation_id and a.id=v.recipe_id where a.organisation_id=org and a.code=r->>'recipe_code' and a.recipe_type='FINAL' and(a.location_id is null or a.location_id=site) and (coalesce(r->>'recipe_version','')='' or v.version::text=r->>'recipe_version') and v.effective_from<=(r->>'effective_from')::date order by v.effective_from desc,v.version desc limit 1;
    if rv is null then raise exception 'Final recipe code/version is unavailable in this outlet on the selected date.';end if;
    if coalesce(r->>'recipe_quantity','')!~'^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' or(r->>'recipe_quantity')::numeric<=0 then raise exception 'Recipe quantity must be positive, up to six decimals.';end if;
   elsif coalesce(r->>'recipe_version','')<>'' or coalesce(r->>'recipe_quantity','')<>'' then raise exception 'Supply recipe code and quantity together; version is optional. Leave all blank for an incomplete item.';
   end if;
   if coalesce(r->>'effective_from','')!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or to_char((r->>'effective_from')::date,'YYYY-MM-DD')<>r->>'effective_from' then raise exception 'Use a valid effective date (YYYY-MM-DD).';end if;
   if coalesce(r->>'selling_price','')<>'' then
    if r->>'selling_price'!~'^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' or(r->>'selling_price')::numeric<=0 or coalesce(r->>'tax_setting','') not in('NONE','INCLUSIVE','EXCLUSIVE') or coalesce(r->>'tax_percent','')!~'^(0|[1-9][0-9]{0,2})(\.[0-9]{1,6})?$' or(r->>'tax_percent')::numeric>100 or(r->>'tax_setting'='NONE' and(r->>'tax_percent')::numeric<>0) then raise exception 'Check the positive selling price and explicit tax treatment/rate.';end if;
   elsif coalesce(r->>'tax_setting','')<>'' or coalesce(r->>'tax_percent','')<>'' then raise exception 'Leave tax fields blank when no price is supplied.';
   end if;
   if rv is not null and exists(select 1 from public.recipe_versions where id=rv and effective_from>(r->>'effective_from')::date) then raise exception 'Menu date is earlier than its recipe version.';end if;
   if m.id is not null then
    state:=jsonb_build_object('menu',to_jsonb(m),'version',(select to_jsonb(x) from public.menu_item_versions x where organisation_id=org and menu_item_id=m.id order by version desc limit 1),'price',(select to_jsonb(x) from public.menu_price_versions x where organisation_id=org and menu_item_id=m.id and location_id=site and channel_code='STANDARD' order by effective_from desc,version desc limit 1));
    unchanged:=m.name=trim(r->>'menu_name') and m.primary_category=r->>'major_category' and m.subcategory=r->>'subcategory'
     and((rv is null and state->'version'='null'::jsonb) or(state->'version'->>'recipe_version_id'=rv::text and(state->'version'->>'recipe_quantity')::numeric=(r->>'recipe_quantity')::numeric and state->'version'->>'effective_from'=r->>'effective_from'))
     and(coalesce(r->>'selling_price','')='' or((state->'price'->>'price')::numeric=(r->>'selling_price')::numeric and state->'price'->>'tax_setting'=r->>'tax_setting' and(state->'price'->>'tax_percent')::numeric=(r->>'tax_percent')::numeric and state->'price'->>'effective_from'=r->>'effective_from' and state->'price'->>'effective_to' is null));
   end if;
   v:=jsonb_build_object('menu_id',m.id,'code',r->>'menu_code','name',trim(r->>'menu_name'),'brand_id',outlet.brand_id,'location_id',m.location_id,'primary_category',r->>'major_category','category',r->>'subcategory','recipe_version_id',rv,'recipe_quantity',r->>'recipe_quantity','effective_from',r->>'effective_from','price',r->>'selling_price','price_location_id',site,'tax_setting',r->>'tax_setting','tax_percent',r->>'tax_percent','price_date',r->>'effective_from');
  exception when others then problem:=sqlerrm;end;
  result:=result||jsonb_build_array(jsonb_build_object('row',n,'code',r->>'menu_code','name',r->>'menu_name','major',r->>'major_category','subcategory',r->>'subcategory','price',r->>'selling_price','action',case when problem is not null then 'ERROR' when coalesce(unchanged,false) then 'UNCHANGED' else r->>'action' end,'error',problem,'warning',case when problem is null and rv is null then 'Recipe missing: saves as incomplete.' when problem is null and coalesce(r->>'selling_price','')='' then 'No new selling price supplied; existing prices are retained.' end,'value',v,'fingerprint',md5(coalesce(state::text,'NEW'))));
 end loop;
 return jsonb_build_object('rows',result,'valid',not exists(select 1 from jsonb_array_elements(result) a where a->>'error' is not null));
end $$;
notify pgrst,'reload schema';
commit;
