-- Apply ONCE after 007. Imported invoice evidence, separate from stock and cost policy.
begin;
create function public.purchase_import_access(p_organisation_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('read',private.pp_reference_price_read(p_organisation_id),'write',private.pp_catalogue_write(p_organisation_id));
$$;

create table public.purchase_import_batches (
 id uuid primary key default gen_random_uuid(), organisation_id uuid not null references public.organisations(id),
 request_id uuid not null, input_hash text not null, source_hash text not null,
 filename text not null check(length(filename) between 1 and 180),
 source_csv text not null check(octet_length(source_csv)<=131072),
 source_organisation_code text not null check(length(source_organisation_code) between 1 and 40),
 price_basis text not null check(price_basis in ('EXCLUSIVE','INCLUSIVE')),
 mappings jsonb not null default '{}', contract_version text not null default 'PURCHASE_CSV_V1',
 state text not null check(state in ('INVALID','REVIEW','POSTED','CANCELLED')),
 report jsonb not null, controls jsonb,
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 posted_by uuid references auth.users(id), posted_at timestamptz,
 unique(organisation_id,id), unique(organisation_id,request_id)
);
create table public.purchase_headers (
 id uuid primary key default gen_random_uuid(), organisation_id uuid not null references public.organisations(id),
 source_system text not null, purchase_ref text not null, supplier_id uuid not null, location_id uuid not null,
 purchase_date date not null, currency_code text not null, source_status text not null check(source_status='RECEIVED'),
 price_basis text not null check(price_basis in ('EXCLUSIVE','INCLUSIVE')),
 invoice_total numeric(38,12) not null check(invoice_total>0),
 import_batch_id uuid not null, created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 unique(organisation_id,id), unique(organisation_id,source_system,supplier_id,purchase_ref),
 foreign key(organisation_id,supplier_id) references public.suppliers(organisation_id,id),
 foreign key(organisation_id,location_id) references public.locations(organisation_id,id),
 foreign key(organisation_id,import_batch_id) references public.purchase_import_batches(organisation_id,id)
);
create table public.purchase_lines (
 id uuid primary key default gen_random_uuid(), organisation_id uuid not null references public.organisations(id),
 purchase_id uuid not null, line_ref text not null, item_id uuid not null, uom_id uuid not null, base_uom_id uuid not null,
 quantity numeric(20,6) not null check(quantity>0), unit_price numeric(20,6) not null check(unit_price>0),
 line_discount numeric(20,6) not null check(line_discount>=0), tax numeric(20,6) not null check(tax>=0),
 net_amount numeric(38,12) not null check(net_amount>0), invoice_amount numeric(38,12) not null check(invoice_amount>0),
 base_quantity numeric(38,12) not null check(base_quantity>0), conversion_factor numeric(38,12) not null check(conversion_factor>0),
 conversion_id uuid, source_row integer not null, source_input jsonb not null, source_fingerprint text not null,
 import_batch_id uuid not null, created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 unique(organisation_id,id), unique(organisation_id,purchase_id,line_ref),
 foreign key(organisation_id,purchase_id) references public.purchase_headers(organisation_id,id),
 foreign key(organisation_id,item_id) references public.items(organisation_id,id),
 foreign key(organisation_id,uom_id) references public.units_of_measure(organisation_id,id),
 foreign key(organisation_id,base_uom_id) references public.units_of_measure(organisation_id,id),
 foreign key(organisation_id,conversion_id) references public.item_uom_conversions(organisation_id,id),
 foreign key(organisation_id,import_batch_id) references public.purchase_import_batches(organisation_id,id)
);
create index pp_purchase_batches_history on public.purchase_import_batches(organisation_id,created_at desc,id);
do $$ declare t text; begin
 foreach t in array array['purchase_import_batches','purchase_headers','purchase_lines'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  -- Batch sources are available only through explicit authorised functions.
  if t<>'purchase_import_batches' then
   execute format('grant select on public.%I to authenticated',t);
   execute format('create policy purchase_financial_read on public.%I for select to authenticated using(private.pp_reference_price_read(organisation_id))',t);
  end if;
 end loop;
end; $$;

create function private.pp_purchase_csv(p_csv text)
returns jsonb language plpgsql immutable set search_path='' as $$
declare headers text[]:=array['Organisation_Code','Source_System','Purchase_Date','Purchase_Ref','Line_Ref','Supplier_Code','Item_Code','Quantity','Purchase_UOM','Unit_Price','Line_Discount','Tax','Location_Code','Currency','Status'];
 text_input text:=p_csv; cell text:=''; cells text[]:='{}'; quoted boolean:=false; closed boolean:=false;
 i integer:=1; ch text; row_number integer:=0; result jsonb:='[]'; obj jsonb; k integer;
begin
 if p_csv is null or octet_length(p_csv)>131072 then raise exception 'Use a UTF-8 CSV under 128 KB.' using errcode='22023'; end if;
 if left(text_input,1)=chr(65279) then text_input:=substr(text_input,2); end if;
 -- Appending a newline terminates the final record, even without a file newline.
 text_input:=text_input||chr(10);
 while i<=length(text_input) loop
  ch:=substr(text_input,i,1);
  if quoted then
   if ch='"' and substr(text_input,i+1,1)='"' then cell:=cell||'"'; i:=i+1;
   elsif ch='"' then quoted:=false; closed:=true;
   else cell:=cell||ch; end if;
  elsif ch=',' or ch=chr(10) or ch=chr(13) then
   cells:=array_append(cells,trim(cell)); cell:=''; closed:=false;
   if ch<>',' then
    if ch=chr(13) and substr(text_input,i+1,1)=chr(10) then i:=i+1; end if;
    if exists(select 1 from unnest(cells) v where v<>'') then
     row_number:=row_number+1;
     if row_number=1 then
      if cells<>headers then raise exception 'Use the exact Purchases_Import template headers and order.' using errcode='22023'; end if;
     else
      if row_number>101 then raise exception 'Import at most 100 purchase rows at a time.' using errcode='22023'; end if;
      if cardinality(cells)<>15 then raise exception 'Data row %: expected 15 columns. Quote values containing commas.',row_number-1 using errcode='22023'; end if;
      obj:='{}'; for k in 1..15 loop obj:=obj||jsonb_build_object(headers[k],cells[k]); end loop;
      result:=result||jsonb_build_array(obj);
     end if;
    end if;
    cells:='{}';
   end if;
  elsif ch='"' then
   if cell<>'' or closed then raise exception 'A CSV quote is misplaced.' using errcode='22023'; end if;
   quoted:=true;
  else
   if closed then raise exception 'Unexpected text after a quoted CSV value.' using errcode='22023'; end if;
   cell:=cell||ch;
  end if;
  i:=i+1;
 end loop;
 if quoted then raise exception 'The CSV contains an unclosed quote.' using errcode='22023'; end if;
 if jsonb_array_length(result)=0 then raise exception 'Include the template header and at least one data row.' using errcode='22023'; end if;
 return result;
end; $$;
revoke all on function private.pp_purchase_csv(text) from public,anon,authenticated;

create function private.pp_validate_purchase_csv(p_org uuid,p_csv text,p_source_org text,p_basis text,p_maps jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare input_rows jsonb; r jsonb; output jsonb:='[]'; prepared jsonb; problems jsonb;
 org public.organisations%rowtype; material public.items%rowtype; supplier public.suppliers%rowtype;
 loc public.locations%rowtype; source_unit public.units_of_measure%rowtype; base_unit public.units_of_measure%rowtype;
 conversion public.item_uom_conversions%rowtype; existing public.purchase_headers%rowtype; old_line public.purchase_lines%rowtype;
 n integer:=0; accepted integer:=0; duplicates integer:=0; rejected integer:=0;
 qty numeric; price numeric; discount numeric; tax numeric; net numeric; amount numeric; normalized numeric; factor numeric;
 day date; item_code text; supplier_code text; location_code text; identity_key text; doc_key text; fingerprint text; disposition text;
 seen text[]:='{}'; documents jsonb:='{}'; doc jsonb; doc_signature jsonb; doc_signatures jsonb:='{}';
begin
 if jsonb_typeof(p_maps) is distinct from 'object' or octet_length(p_maps::text)>32768 then raise exception 'Invalid code mappings.' using errcode='22023'; end if;
 select * into org from public.organisations where id=p_org;
 begin input_rows:=private.pp_purchase_csv(p_csv);
 exception when sqlstate '22023' then return jsonb_build_object('file_error',sqlerrm,'rows','[]'::jsonb,'documents','[]'::jsonb,'ready',0,'duplicates',0,'rejected',0,'can_post',false); end;
 for r in select value from jsonb_array_elements(input_rows) loop
  n:=n+1; problems:='[]'; prepared:=null; disposition:='READY'; conversion:=null; factor:=null;
  begin
   if r->>'Organisation_Code'<>p_source_org then raise exception 'Organisation_Code does not match the source organisation code you selected.' using errcode='22023'; end if;
   if length(r->>'Source_System') not between 1 and 60 or length(r->>'Purchase_Ref') not between 1 and 100
    or length(r->>'Line_Ref') not between 1 and 60 then raise exception 'Source system, purchase reference and line reference are required (maximum 60, 100 and 60 characters).' using errcode='22023'; end if;
   if r->>'Status'<>'RECEIVED' then raise exception 'Only RECEIVED invoices are supported. Orders, returns and credit notes need a separate workflow.' using errcode='22023'; end if;
   if r->>'Currency'<>org.currency_code then raise exception 'Currency must match the business reporting currency; no currency conversion is performed.' using errcode='22023'; end if;
   if r->>'Purchase_Date' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Use a purchase date in YYYY-MM-DD format.' using errcode='22023'; end if;
   begin day:=(r->>'Purchase_Date')::date;
   exception when datetime_field_overflow or invalid_datetime_format then raise exception 'Purchase date is invalid.' using errcode='22023'; end;
   item_code:=coalesce(nullif(p_maps->'items'->>(r->>'Item_Code'),''),r->>'Item_Code');
   supplier_code:=coalesce(nullif(p_maps->'suppliers'->>(r->>'Supplier_Code'),''),r->>'Supplier_Code');
   location_code:=coalesce(nullif(p_maps->'locations'->>(r->>'Location_Code'),''),r->>'Location_Code');
   select * into material from public.items where organisation_id=p_org and code=item_code and is_active;
   if not found then raise exception 'Unknown or inactive material code: %. Map it to an existing active material.',r->>'Item_Code' using errcode='22023'; end if;
   select * into supplier from public.suppliers where organisation_id=p_org and code=supplier_code and is_active;
   if not found then raise exception 'Unknown or inactive supplier code: %. Map it to an existing active supplier.',r->>'Supplier_Code' using errcode='22023'; end if;
   select * into loc from public.locations where organisation_id=p_org and code=location_code and is_active;
   if not found then raise exception 'Unknown or inactive location code: %. Map it to an existing active location.',r->>'Location_Code' using errcode='22023'; end if;
   if day>(now() at time zone loc.timezone)::date then raise exception 'Purchase date cannot be in the future at this location.' using errcode='22023'; end if;
   if r->>'Quantity' !~ '^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$'
    or r->>'Unit_Price' !~ '^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$'
    or r->>'Line_Discount' !~ '^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$'
    or r->>'Tax' !~ '^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$'
    then raise exception 'Enter quantity, unit price, discount and tax explicitly as numbers with up to six decimals; no commas or formulas.' using errcode='22023'; end if;
   qty:=(r->>'Quantity')::numeric; price:=(r->>'Unit_Price')::numeric; discount:=(r->>'Line_Discount')::numeric; tax:=(r->>'Tax')::numeric;
   if qty<=0 or price<=0 then raise exception 'Quantity and unit price must be positive; free lines and returns are not supported yet.' using errcode='22023'; end if;
   net:=qty*price-discount-case when p_basis='INCLUSIVE' then tax else 0 end; amount:=net+tax;
   if net<=0 or amount>=1e26 then raise exception 'Discount/tax exceed the line value, or the amount exceeds supported precision.' using errcode='22023'; end if;
   select * into source_unit from public.units_of_measure where organisation_id=p_org and code=r->>'Purchase_UOM';
   if not found then raise exception 'Unknown purchase unit code.' using errcode='22023'; end if;
   select * into base_unit from public.units_of_measure where organisation_id=p_org and id=material.base_uom_id;
   if source_unit.dimension='PACKAGE' then
    select * into conversion from public.item_uom_conversions where organisation_id=p_org and item_id=material.id
     and from_uom_id=source_unit.id and effective_from<=day order by effective_from desc limit 1;
    if not found then raise exception 'Missing package conversion effective on the purchase date. Define the item-specific package size first.' using errcode='22023'; end if;
    factor:=conversion.factor;
   elsif source_unit.dimension=base_unit.dimension then factor:=source_unit.canonical_factor/base_unit.canonical_factor;
   else raise exception 'Purchase unit dimension does not match the material base unit.' using errcode='22023'; end if;
   normalized:=round(qty*factor,12);
   if normalized<=0 or normalized>=1e26 then raise exception 'Converted quantity exceeds supported precision.' using errcode='22023'; end if;
   doc_key:=md5(jsonb_build_array(r->>'Source_System',supplier.id,r->>'Purchase_Ref')::text);
   identity_key:=doc_key||':'||(r->>'Line_Ref');
   if identity_key=any(seen) then raise exception 'Duplicate source invoice/line identity inside this file.' using errcode='22023'; end if;
   seen:=array_append(seen,identity_key);
   doc_signature:=jsonb_build_array(day,loc.id,org.currency_code,p_basis);
   if doc_signatures ? doc_key and doc_signatures->doc_key<>doc_signature then raise exception 'Lines of one supplier invoice must have the same date, location, currency and price basis.' using errcode='22023'; end if;
   doc_signatures:=doc_signatures||jsonb_build_object(doc_key,doc_signature);
   fingerprint:=md5(jsonb_build_array(r->>'Source_System',supplier.id,r->>'Purchase_Ref',r->>'Line_Ref',day,loc.id,
    material.id,source_unit.id,trim_scale(qty),trim_scale(price),trim_scale(discount),trim_scale(tax),org.currency_code,p_basis,'RECEIVED')::text);
   select * into existing from public.purchase_headers where organisation_id=p_org and source_system=r->>'Source_System' and supplier_id=supplier.id and purchase_ref=r->>'Purchase_Ref';
   if found then
    select * into old_line from public.purchase_lines where organisation_id=p_org and purchase_id=existing.id and line_ref=r->>'Line_Ref';
    if not found or old_line.source_fingerprint<>fingerprint then raise exception 'This invoice already exists with different or additional lines. It needs a correction workflow; existing purchases will not be overwritten.' using errcode='22023'; end if;
    disposition:='DUPLICATE';
   end if;
   prepared:=jsonb_build_object('document_key',doc_key,'source_system',r->>'Source_System','purchase_ref',r->>'Purchase_Ref',
    'line_ref',r->>'Line_Ref','purchase_date',day,'supplier_id',supplier.id,'supplier_code',supplier.code,'supplier_name',supplier.name,
    'location_id',loc.id,'location_code',loc.code,'location_name',loc.name,'item_id',material.id,'item_code',material.code,'item_name',material.name,
    'uom_id',source_unit.id,'unit_code',source_unit.code,'base_uom_id',base_unit.id,'base_unit_code',base_unit.code,
    'quantity',qty::text,'unit_price',price::text,'line_discount',discount::text,'tax',tax::text,'net_amount',net::text,'invoice_amount',amount::text,
    'base_quantity',normalized::text,'conversion_factor',factor::text,'conversion_id',conversion.id,'currency_code',org.currency_code,'fingerprint',fingerprint);
   doc:=coalesce(documents->doc_key,jsonb_build_object('key',doc_key,'purchase_ref',r->>'Purchase_Ref','source_system',r->>'Source_System',
    'supplier_name',supplier.name,'location_name',loc.name,'currency_code',org.currency_code,'total','0','lines',0,'duplicate',disposition='DUPLICATE'));
   if (doc->>'total')::numeric+amount>=1e26 then raise exception 'Invoice total exceeds supported precision.' using errcode='22023'; end if;
   doc:=doc||jsonb_build_object('total',((doc->>'total')::numeric+amount)::text,'lines',(doc->>'lines')::integer+1);
   documents:=documents||jsonb_build_object(doc_key,doc);
  exception when sqlstate '22023' then problems:=jsonb_build_array(sqlerrm); disposition:='REJECTED'; end;
  if disposition='REJECTED' then rejected:=rejected+1; elsif disposition='DUPLICATE' then duplicates:=duplicates+1; else accepted:=accepted+1; end if;
  output:=output||jsonb_build_array(jsonb_build_object('row',n,'source',r,'state',disposition,'findings',problems,'prepared',prepared));
 end loop;
 return jsonb_build_object('rows',output,'documents',coalesce((select jsonb_agg(value order by key) from jsonb_each(documents)),'[]'::jsonb),
  'ready',accepted,'duplicates',duplicates,'rejected',rejected,'can_post',rejected=0,'file_error',null);
end; $$;
revoke all on function private.pp_validate_purchase_csv(uuid,text,text,text,jsonb) from public,anon,authenticated;

create function public.stage_purchase_import(p_organisation_id uuid,p_request_id uuid,p_filename text,p_csv text,p_source_org text,p_price_basis text,p_mappings jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare batch uuid; previous public.purchase_import_batches%rowtype; report jsonb; digest text;
begin
 if not private.pp_catalogue_write(p_organisation_id) then raise exception 'Purchase import access denied.' using errcode='42501'; end if;
 if p_request_id is null or p_filename is null or length(p_filename) not between 1 and 180 or p_csv is null or octet_length(p_csv)>131072
  or p_source_org is null or length(trim(p_source_org)) not between 1 and 40 or p_price_basis is null or p_price_basis not in ('EXCLUSIVE','INCLUSIVE')
  then raise exception 'Check the file, source organisation code and unit-price tax setting.' using errcode='22023'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 digest:=md5(jsonb_build_array(p_filename,p_csv,p_source_org,p_price_basis,p_mappings)::text);
 select * into previous from public.purchase_import_batches where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then
  if previous.input_hash<>digest then raise exception 'This upload request has already been used. Refresh before uploading different details.' using errcode='22023'; end if;
  return previous.id;
 end if;
 report:=private.pp_validate_purchase_csv(p_organisation_id,p_csv,trim(p_source_org),p_price_basis,p_mappings);
 insert into public.purchase_import_batches(organisation_id,request_id,input_hash,source_hash,filename,source_csv,source_organisation_code,price_basis,mappings,state,report,created_by)
 values(p_organisation_id,p_request_id,digest,encode(sha256(convert_to(p_csv,'UTF8')),'hex'),p_filename,p_csv,trim(p_source_org),p_price_basis,p_mappings,
  case when (report->>'can_post')::boolean then 'REVIEW' else 'INVALID' end,report,auth.uid()) returning id into batch;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'purchase_import.staged',auth.uid(),batch,jsonb_build_object('ready',report->'ready','rejected',report->'rejected'));
 return batch;
end; $$;

create function public.post_purchase_import(p_organisation_id uuid,p_batch_id uuid,p_controls jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare batch public.purchase_import_batches%rowtype; current_report jsonb; doc jsonb; row jsonb; p jsonb; header_id uuid;
 posted integer:=0; expected text;
begin
 if not private.pp_catalogue_write(p_organisation_id) then raise exception 'Purchase import access denied.' using errcode='42501'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into batch from public.purchase_import_batches where organisation_id=p_organisation_id and id=p_batch_id for update;
 if not found then raise exception 'Import not available.' using errcode='42501'; end if;
 if batch.state='POSTED' then return jsonb_build_object('posted',true,'already_posted',true); end if;
 if batch.state='CANCELLED' then raise exception 'This import was cancelled.' using errcode='22023'; end if;
 current_report:=private.pp_validate_purchase_csv(p_organisation_id,batch.source_csv,batch.source_organisation_code,batch.price_basis,batch.mappings);
 if current_report is distinct from batch.report then
  update public.purchase_import_batches set report=current_report,state=case when (current_report->>'can_post')::boolean then 'REVIEW' else 'INVALID' end where id=batch.id;
  return jsonb_build_object('posted',false,'message','The purchase records or catalogue changed. Review the updated findings before saving again.');
 end if;
 if not (current_report->>'can_post')::boolean then raise exception 'Fix all validation findings before saving purchases.' using errcode='22023'; end if;
 if jsonb_typeof(p_controls) is distinct from 'object' or octet_length(p_controls::text)>32768 then raise exception 'Enter the supplier invoice totals to reconcile this import.' using errcode='22023'; end if;
 for doc in select value from jsonb_array_elements(current_report->'documents') loop
  if not (doc->>'duplicate')::boolean then
   expected:=p_controls->>(doc->>'key');
   if expected is null or expected !~ '^(0|[1-9][0-9]{0,25})(\.[0-9]{1,12})?$' then raise exception 'Enter the invoice total for % (up to 12 decimals, no commas).',doc->>'purchase_ref' using errcode='22023'; end if;
   if expected::numeric<>(doc->>'total')::numeric then raise exception 'Invoice total does not reconcile for %. Compare the source invoice with all lines in this file.',doc->>'purchase_ref' using errcode='22023'; end if;
  end if;
 end loop;
 for row in select value from jsonb_array_elements(current_report->'rows') loop
  if row->>'state'<>'READY' then continue; end if;
  p:=row->'prepared';
  select id into header_id from public.purchase_headers where organisation_id=p_organisation_id and source_system=p->>'source_system' and supplier_id=(p->>'supplier_id')::uuid and purchase_ref=p->>'purchase_ref';
  if not found then
   select value into doc from jsonb_array_elements(current_report->'documents') where value->>'key'=p->>'document_key';
   insert into public.purchase_headers(organisation_id,source_system,purchase_ref,supplier_id,location_id,purchase_date,currency_code,source_status,price_basis,invoice_total,import_batch_id,created_by)
   values(p_organisation_id,p->>'source_system',p->>'purchase_ref',(p->>'supplier_id')::uuid,(p->>'location_id')::uuid,(p->>'purchase_date')::date,p->>'currency_code','RECEIVED',batch.price_basis,(doc->>'total')::numeric,batch.id,auth.uid()) returning id into header_id;
  end if;
  insert into public.purchase_lines(organisation_id,purchase_id,line_ref,item_id,uom_id,base_uom_id,quantity,unit_price,line_discount,tax,net_amount,invoice_amount,base_quantity,conversion_factor,conversion_id,source_row,source_input,source_fingerprint,import_batch_id,created_by)
  values(p_organisation_id,header_id,p->>'line_ref',(p->>'item_id')::uuid,(p->>'uom_id')::uuid,(p->>'base_uom_id')::uuid,
   (p->>'quantity')::numeric,(p->>'unit_price')::numeric,(p->>'line_discount')::numeric,(p->>'tax')::numeric,
   (p->>'net_amount')::numeric,(p->>'invoice_amount')::numeric,(p->>'base_quantity')::numeric,(p->>'conversion_factor')::numeric,
   (p->>'conversion_id')::uuid,(row->>'row')::integer,row->'source',p->>'fingerprint',batch.id,auth.uid());
  posted:=posted+1;
 end loop;
 update public.purchase_import_batches set state='POSTED',controls=p_controls,posted_at=now(),posted_by=auth.uid() where id=batch.id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details)
 values(p_organisation_id,'purchase_import.posted',auth.uid(),batch.id,jsonb_build_object('new_lines',posted,'duplicate_lines',current_report->'duplicates'));
 return jsonb_build_object('posted',true,'new_lines',posted,'duplicates',current_report->'duplicates');
end; $$;

create function public.purchase_import_history(p_organisation_id uuid,p_page integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Purchase import access denied.' using errcode='42501'; end if;
 if p_page is null or p_page not between 1 and 100000 then raise exception 'Invalid page.' using errcode='22023'; end if;
 select jsonb_build_object('total',(select count(*) from public.purchase_import_batches where organisation_id=p_organisation_id),
  'batches',coalesce((select jsonb_agg(to_jsonb(b) order by b.created_at desc,b.id) from (
   select id,filename,state,created_at,posted_at,report->'ready' as ready,report->'duplicates' as duplicates,report->'rejected' as rejected
   from public.purchase_import_batches where organisation_id=p_organisation_id order by created_at desc,id limit 25 offset (p_page-1)*25) b),'[]'::jsonb)) into result;
 return result;
end; $$;
create function public.get_purchase_import(p_organisation_id uuid,p_batch_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Purchase import access denied.' using errcode='42501'; end if;
 select to_jsonb(b)-'source_csv'-'input_hash'-'request_id' into result from public.purchase_import_batches b where organisation_id=p_organisation_id and id=p_batch_id;
 if result is null then raise exception 'Import not available.' using errcode='42501'; end if;
 return result;
end; $$;
create function public.purchase_import_source(p_organisation_id uuid,p_batch_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Purchase import access denied.' using errcode='42501'; end if;
 select jsonb_build_object('filename',filename,'csv',source_csv,'sha256',source_hash) into result from public.purchase_import_batches where organisation_id=p_organisation_id and id=p_batch_id;
 if result is null then raise exception 'Import not available.' using errcode='42501'; end if;
 return result;
end; $$;
create function public.cancel_purchase_import(p_organisation_id uuid,p_batch_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.pp_catalogue_write(p_organisation_id) then raise exception 'Purchase import access denied.' using errcode='42501'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 update public.purchase_import_batches set state='CANCELLED' where organisation_id=p_organisation_id and id=p_batch_id and state in ('REVIEW','INVALID');
 if not found then raise exception 'Only an unposted import can be cancelled.' using errcode='22023'; end if;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'purchase_import.cancelled',auth.uid(),p_batch_id,'{}');
end; $$;

revoke all on function public.purchase_import_access(uuid) from public,anon;
revoke all on function public.stage_purchase_import(uuid,uuid,text,text,text,text,jsonb) from public,anon;
revoke all on function public.post_purchase_import(uuid,uuid,jsonb) from public,anon;
revoke all on function public.purchase_import_history(uuid,integer) from public,anon;
revoke all on function public.get_purchase_import(uuid,uuid) from public,anon;
revoke all on function public.purchase_import_source(uuid,uuid) from public,anon;
revoke all on function public.cancel_purchase_import(uuid,uuid) from public,anon;
grant execute on function public.purchase_import_access(uuid) to authenticated;
grant execute on function public.stage_purchase_import(uuid,uuid,text,text,text,text,jsonb) to authenticated;
grant execute on function public.post_purchase_import(uuid,uuid,jsonb) to authenticated;
grant execute on function public.purchase_import_history(uuid,integer) to authenticated;
grant execute on function public.get_purchase_import(uuid,uuid) to authenticated;
grant execute on function public.purchase_import_source(uuid,uuid) to authenticated;
grant execute on function public.cancel_purchase_import(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
