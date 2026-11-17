-- Apply ONCE after 009. Paid standard-menu sales; no stock or accounting postings.
begin;
create function private.pp_sales_read(target_org uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisation_memberships m join public.membership_roles r
 on r.organisation_id=m.organisation_id and r.membership_id=m.id
 where m.organisation_id=target_org and m.user_id=(select auth.uid()) and m.status='active'
 and r.location_id is null and r.role_code in ('restaurant_admin','ceo','finance'));
$$;
revoke all on function private.pp_sales_read(uuid) from public,anon;
grant execute on function private.pp_sales_read(uuid) to authenticated;
create function public.sales_import_access(p_organisation_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('read',private.pp_sales_read(p_organisation_id),'write',private.pp_menu_write(p_organisation_id));
$$;
create table public.sales_import_batches (
 id uuid primary key default gen_random_uuid(), organisation_id uuid not null references public.organisations(id),
 request_id uuid not null, input_hash text not null, source_hash text not null,
 filename text not null check(length(filename) between 1 and 180), source_csv text not null check(octet_length(source_csv)<=131072),
 source_organisation_code text not null check(length(source_organisation_code) between 1 and 40),
 net_basis text not null check(net_basis in ('EXCLUSIVE','INCLUSIVE','GROSS_INCLUSIVE')),
 currency_code text not null, mappings jsonb not null, contract_version text not null default 'SALES_CSV_V1',
 state text not null check(state in ('INVALID','REVIEW','POSTED','CANCELLED')), report jsonb not null, controls jsonb,
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 posted_by uuid references auth.users(id), posted_at timestamptz,
 unique(organisation_id,id), unique(organisation_id,request_id)
);
create table public.sales_headers (
 id uuid primary key default gen_random_uuid(), organisation_id uuid not null references public.organisations(id),
 source_system text not null, location_id uuid not null, transaction_ref text not null, sale_date date not null,
 channel_code text not null check(channel_code in ('DINE_IN','TAKEAWAY','DELIVERY')), currency_code text not null,
 source_status text not null check(source_status='PAID'), net_basis text not null,
 receipt_total numeric(38,12) not null check(receipt_total>=0),
 import_batch_id uuid not null, created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 unique(organisation_id,id), unique(organisation_id,source_system,location_id,transaction_ref),
 foreign key(organisation_id,location_id) references public.locations(organisation_id,id),
 foreign key(organisation_id,import_batch_id) references public.sales_import_batches(organisation_id,id)
);
create table public.sales_lines (
 id uuid primary key default gen_random_uuid(), organisation_id uuid not null references public.organisations(id),
 sale_id uuid not null, line_ref text not null, menu_item_id uuid not null, menu_version_id uuid not null,
 quantity numeric(20,6) not null check(quantity>0),
 gross_sales numeric(20,6) not null check(gross_sales>=0), discount numeric(20,6) not null check(discount>=0),
 tax numeric(20,6) not null check(tax>=0), source_net_sales numeric(20,6) not null check(source_net_sales>=0),
 net_revenue numeric(38,12) not null check(net_revenue>=0), customer_total numeric(38,12) not null check(customer_total>=0),
 source_row integer not null, source_input jsonb not null, source_fingerprint text not null, import_batch_id uuid not null,
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 unique(organisation_id,id), unique(organisation_id,sale_id,line_ref),
 foreign key(organisation_id,sale_id) references public.sales_headers(organisation_id,id),
 foreign key(organisation_id,menu_item_id) references public.menu_items(organisation_id,id),
 foreign key(organisation_id,menu_version_id) references public.menu_item_versions(organisation_id,id),
 foreign key(organisation_id,import_batch_id) references public.sales_import_batches(organisation_id,id)
);
create index pp_sales_period on public.sales_headers(organisation_id,sale_date,location_id);
create index pp_sales_history on public.sales_import_batches(organisation_id,created_at desc,id);
do $$ declare t text; begin
 foreach t in array array['sales_import_batches','sales_headers','sales_lines'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  if t<>'sales_import_batches' then
   execute format('grant select on public.%I to authenticated',t);
   execute format('create policy sales_financial_read on public.%I for select to authenticated using(private.pp_sales_read(organisation_id))',t);
  end if;
 end loop;
end; $$;

create function private.pp_sales_csv(p_csv text)
returns jsonb language plpgsql immutable set search_path='' as $$
declare headers text[]:=array['Organisation_Code','Source_System','Location_Code','Sale_Date','Transaction_Ref','Line_Ref','Menu_Code','Quantity','Gross_Sales','Discount','Tax','Net_Sales','Channel_Code','Line_Type','Parent_Line_Ref','Status'];
 text_input text:=p_csv; cell text:=''; cells text[]:='{}'; quoted boolean:=false; closed boolean:=false;
 i integer:=1; ch text; row_number integer:=0; result jsonb:='[]'; obj jsonb; k integer;
begin
 if p_csv is null or octet_length(p_csv)>131072 then raise exception 'Use a UTF-8 CSV under 128 KB.' using errcode='22023'; end if;
 if left(text_input,1)=chr(65279) then text_input:=substr(text_input,2); end if;
 text_input:=text_input||chr(10);
 while i<=length(text_input) loop
  ch:=substr(text_input,i,1);
  if quoted then
   if ch='"' and substr(text_input,i+1,1)='"' then cell:=cell||'"'; i:=i+1;
   elsif ch='"' then quoted:=false; closed:=true; else cell:=cell||ch; end if;
  elsif ch=',' or ch=chr(10) or ch=chr(13) then
   cells:=array_append(cells,trim(cell)); cell:=''; closed:=false;
   if ch<>',' then
    if ch=chr(13) and substr(text_input,i+1,1)=chr(10) then i:=i+1; end if;
    if exists(select 1 from unnest(cells) v where v<>'') then
     row_number:=row_number+1;
     if row_number=1 then
      if cells<>headers then raise exception 'Use the exact Sales_Import template headers and order.' using errcode='22023'; end if;
     else
      if row_number>101 then raise exception 'Import at most 100 sales rows at a time.' using errcode='22023'; end if;
      if cardinality(cells)<>16 then raise exception 'Data row %: expected 16 columns. Quote values containing commas.',row_number-1 using errcode='22023'; end if;
      obj:='{}'; for k in 1..16 loop obj:=obj||jsonb_build_object(headers[k],cells[k]); end loop;
      result:=result||jsonb_build_array(obj);
     end if;
    end if;
    cells:='{}';
   end if;
  elsif ch='"' then
   if cell<>'' or closed then raise exception 'A CSV quote is misplaced.' using errcode='22023'; end if; quoted:=true;
  else
   if closed then raise exception 'Unexpected text after a quoted CSV value.' using errcode='22023'; end if; cell:=cell||ch;
  end if;
  i:=i+1;
 end loop;
 if quoted then raise exception 'The CSV contains an unclosed quote.' using errcode='22023'; end if;
 if jsonb_array_length(result)=0 then raise exception 'Include the header and at least one data row.' using errcode='22023'; end if;
 return result;
end; $$;
revoke all on function private.pp_sales_csv(text) from public,anon,authenticated;

create function private.pp_validate_sales_csv(p_org uuid,p_csv text,p_source_org text,p_basis text,p_currency text,p_maps jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare input_rows jsonb; r jsonb; output jsonb:='[]'; prepared jsonb; problems jsonb; warnings jsonb;
 org public.organisations%rowtype; loc public.locations%rowtype; menu public.menu_items%rowtype; version_row public.menu_item_versions%rowtype;
 existing public.sales_headers%rowtype; old_line public.sales_lines%rowtype;
 n integer:=0; accepted integer:=0; duplicates integer:=0; rejected integer:=0;
 qty numeric; gross numeric; discount numeric; tax numeric; source_net numeric; net numeric; total numeric;
 day date; menu_code text; location_code text; channel text; doc_key text; identity_key text; fingerprint text; disposition text;
 seen text[]:='{}'; documents jsonb:='{}'; doc jsonb; signatures jsonb:='{}'; signature jsonb;
begin
 if jsonb_typeof(p_maps) is distinct from 'object' or octet_length(p_maps::text)>32768 then raise exception 'Invalid code mappings.' using errcode='22023'; end if;
 select * into org from public.organisations where id=p_org;
 if p_currency<>org.currency_code then raise exception 'Confirm the file uses the business reporting currency. No currency conversion is performed.' using errcode='22023'; end if;
 begin input_rows:=private.pp_sales_csv(p_csv);
 exception when sqlstate '22023' then return jsonb_build_object('file_error',sqlerrm,'rows','[]'::jsonb,'receipts','[]'::jsonb,'ready',0,'duplicates',0,'rejected',0,'can_post',false); end;
 for r in select value from jsonb_array_elements(input_rows) loop
  n:=n+1; problems:='[]'; warnings:='[]'; prepared:=null; disposition:='READY';
  begin
   if r->>'Organisation_Code'<>p_source_org then raise exception 'Organisation_Code does not match your selected source organisation code.' using errcode='22023'; end if;
   if length(r->>'Source_System') not between 1 and 60 or length(r->>'Transaction_Ref') not between 1 and 100 or length(r->>'Line_Ref') not between 1 and 60
    then raise exception 'Source system, transaction reference and line reference are required (maximum 60, 100 and 60 characters).' using errcode='22023'; end if;
   if r->>'Status'<>'PAID' then raise exception 'Only PAID sales are supported. Refunds, voids and unpaid receipts need separate handling.' using errcode='22023'; end if;
   if r->>'Line_Type'<>'NORMAL' or r->>'Parent_Line_Ref'<>'' then raise exception 'Only NORMAL lines with a blank Parent_Line_Ref are supported. Combo parent/child lines are blocked to prevent double counting.' using errcode='22023'; end if;
   location_code:=coalesce(nullif(p_maps->'locations'->>(r->>'Location_Code'),''),r->>'Location_Code');
   menu_code:=coalesce(nullif(p_maps->'menu_items'->>(r->>'Menu_Code'),''),r->>'Menu_Code');
   channel:=coalesce(nullif(p_maps->'channels'->>(r->>'Channel_Code'),''),r->>'Channel_Code');
   if channel not in ('DINE_IN','TAKEAWAY','DELIVERY') then raise exception 'Unknown sales channel. Map it to DINE_IN, TAKEAWAY or DELIVERY.' using errcode='22023'; end if;
   select * into loc from public.locations where organisation_id=p_org and code=location_code;
   if not found then raise exception 'Unknown location code: %. Map it to an existing business location.',r->>'Location_Code' using errcode='22023'; end if;
   if r->>'Sale_Date' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Use a sale date in YYYY-MM-DD format.' using errcode='22023'; end if;
   begin day:=(r->>'Sale_Date')::date;
   exception when datetime_field_overflow or invalid_datetime_format then raise exception 'Sale date is invalid.' using errcode='22023'; end;
   if day>(now() at time zone loc.timezone)::date then raise exception 'Sale date cannot be in the future at the selected location.' using errcode='22023'; end if;
   select * into menu from public.menu_items where organisation_id=p_org and code=menu_code and brand_id=loc.brand_id;
   if not found then raise exception 'Unknown menu code or menu brand does not match this location: %. Map to an existing recipe-linked menu.',r->>'Menu_Code' using errcode='22023'; end if;
   select * into version_row from public.menu_item_versions where organisation_id=p_org and menu_item_id=menu.id and effective_from<=day order by effective_from desc,version desc limit 1;
   if not found then raise exception 'No saved menu version is effective on the sale date. Review the menu setup and dates.' using errcode='22023'; end if;
   if not menu.is_active then warnings:=warnings||jsonb_build_array('This menu is currently inactive; the dated sale is retained as historical source data.'); end if;
   if not loc.is_active then warnings:=warnings||jsonb_build_array('This location is currently inactive; the dated sale is retained as historical source data.'); end if;
   if r->>'Quantity' !~ '^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' or r->>'Gross_Sales' !~ '^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$'
    or r->>'Discount' !~ '^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' or r->>'Tax' !~ '^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$'
    or r->>'Net_Sales' !~ '^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$'
    then raise exception 'Enter quantity, gross sales, discount, tax and net sales explicitly with up to six decimals, without commas or formulas.' using errcode='22023'; end if;
   qty:=(r->>'Quantity')::numeric; gross:=(r->>'Gross_Sales')::numeric; discount:=(r->>'Discount')::numeric;
   tax:=(r->>'Tax')::numeric; source_net:=(r->>'Net_Sales')::numeric;
   if qty<=0 then raise exception 'Quantity must be positive; returns and reversals are not supported in this import.' using errcode='22023'; end if;
   if source_net<>(gross-discount-(case when p_basis='GROSS_INCLUSIVE' then tax else 0 end)) then raise exception 'Net_Sales does not reconcile with Gross_Sales, Discount and Tax under the selected source format.' using errcode='22023'; end if;
   net:=source_net-case when p_basis='INCLUSIVE' then tax else 0 end;
   total:=source_net+case when p_basis='INCLUSIVE' then 0 else tax end;
   if net<0 or total>=1e26 then raise exception 'Tax/discount exceed the receipt line value or the amount exceeds supported precision.' using errcode='22023'; end if;
   doc_key:=md5(jsonb_build_array(r->>'Source_System',loc.id,r->>'Transaction_Ref')::text);
   identity_key:=doc_key||':'||(r->>'Line_Ref');
   if identity_key=any(seen) then raise exception 'Duplicate source/location/receipt/line identity inside this file.' using errcode='22023'; end if;
   seen:=array_append(seen,identity_key);
   signature:=jsonb_build_array(day,channel,p_currency,p_basis);
   if signatures ? doc_key and signatures->doc_key<>signature then raise exception 'Lines of one receipt must use the same sale date, channel, currency and source tax format.' using errcode='22023'; end if;
   signatures:=signatures||jsonb_build_object(doc_key,signature);
   fingerprint:=md5(jsonb_build_array(r->>'Source_System',loc.id,r->>'Transaction_Ref',r->>'Line_Ref',day,menu.id,
    trim_scale(qty),trim_scale(gross),trim_scale(discount),trim_scale(tax),trim_scale(source_net),channel,p_currency,p_basis,'NORMAL','PAID')::text);
   select * into existing from public.sales_headers where organisation_id=p_org and source_system=r->>'Source_System' and location_id=loc.id and transaction_ref=r->>'Transaction_Ref';
   if found then
    select * into old_line from public.sales_lines where organisation_id=p_org and sale_id=existing.id and line_ref=r->>'Line_Ref';
    if not found or old_line.source_fingerprint<>fingerprint then raise exception 'This receipt already has different or additional source lines. Use a correction workflow; recorded sales will not be overwritten.' using errcode='22023'; end if;
    disposition:='DUPLICATE';
   end if;
   prepared:=jsonb_build_object('receipt_key',doc_key,'source_system',r->>'Source_System','location_id',loc.id,'location_code',loc.code,'location_name',loc.name,
    'transaction_ref',r->>'Transaction_Ref','line_ref',r->>'Line_Ref','sale_date',day,'channel_code',channel,'currency_code',p_currency,
    'menu_item_id',menu.id,'menu_code',menu.code,'menu_name',version_row.name,'menu_version_id',version_row.id,'menu_version',version_row.version,
    'quantity',qty::text,'gross_sales',gross::text,'discount',discount::text,'tax',tax::text,'source_net_sales',source_net::text,
    'net_revenue',net::text,'customer_total',total::text,'fingerprint',fingerprint);
   doc:=coalesce(documents->doc_key,jsonb_build_object('key',doc_key,'transaction_ref',r->>'Transaction_Ref','source_system',r->>'Source_System',
    'location_name',loc.name,'sale_date',day,'channel_code',channel,'currency_code',p_currency,'total','0','net_revenue','0','lines',0,'duplicate',disposition='DUPLICATE'));
   if (doc->>'total')::numeric+total>=1e26 then raise exception 'Receipt total exceeds supported precision.' using errcode='22023'; end if;
   doc:=doc||jsonb_build_object('total',((doc->>'total')::numeric+total)::text,'net_revenue',((doc->>'net_revenue')::numeric+net)::text,'lines',(doc->>'lines')::integer+1);
   documents:=documents||jsonb_build_object(doc_key,doc);
  exception when sqlstate '22023' then problems:=jsonb_build_array(sqlerrm); disposition:='REJECTED'; end;
  if disposition='REJECTED' then rejected:=rejected+1; elsif disposition='DUPLICATE' then duplicates:=duplicates+1; else accepted:=accepted+1; end if;
  output:=output||jsonb_build_array(jsonb_build_object('row',n,'source',r,'state',disposition,'findings',problems,'warnings',warnings,'prepared',prepared));
 end loop;
 return jsonb_build_object('rows',output,'receipts',coalesce((select jsonb_agg(value order by key) from jsonb_each(documents)),'[]'::jsonb),
  'ready',accepted,'duplicates',duplicates,'rejected',rejected,'can_post',rejected=0,'file_error',null);
end; $$;
revoke all on function private.pp_validate_sales_csv(uuid,text,text,text,text,jsonb) from public,anon,authenticated;

create function public.stage_sales_import(p_organisation_id uuid,p_request_id uuid,p_filename text,p_csv text,p_source_org text,p_net_basis text,p_currency text,p_mappings jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare batch uuid; previous public.sales_import_batches%rowtype; report jsonb; digest text;
begin
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Sales import editing requires an organisation-wide restaurant administrator.' using errcode='42501'; end if;
 if p_request_id is null or p_filename is null or length(p_filename) not between 1 and 180 or p_csv is null or octet_length(p_csv)>131072
  or p_source_org is null or length(trim(p_source_org)) not between 1 and 40 or p_currency is null
  or p_net_basis is null or p_net_basis not in ('EXCLUSIVE','INCLUSIVE','GROSS_INCLUSIVE') then raise exception 'Check the file, source organisation, currency declaration and source tax format.' using errcode='22023'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 digest:=md5(jsonb_build_array(p_filename,p_csv,p_source_org,p_net_basis,p_currency,p_mappings)::text);
 select * into previous from public.sales_import_batches where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then
  if previous.input_hash<>digest then raise exception 'This upload request was already used. Refresh before uploading different details.' using errcode='22023'; end if;
  return previous.id;
 end if;
 report:=private.pp_validate_sales_csv(p_organisation_id,p_csv,trim(p_source_org),p_net_basis,p_currency,p_mappings);
 insert into public.sales_import_batches(organisation_id,request_id,input_hash,source_hash,filename,source_csv,source_organisation_code,net_basis,currency_code,mappings,state,report,created_by)
 values(p_organisation_id,p_request_id,digest,encode(sha256(convert_to(p_csv,'UTF8')),'hex'),p_filename,p_csv,trim(p_source_org),p_net_basis,p_currency,p_mappings,
  case when (report->>'can_post')::boolean then 'REVIEW' else 'INVALID' end,report,auth.uid()) returning id into batch;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'sales_import.staged',auth.uid(),batch,jsonb_build_object('ready',report->'ready','rejected',report->'rejected'));
 return batch;
end; $$;

create function public.post_sales_import(p_organisation_id uuid,p_batch_id uuid,p_controls jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare batch public.sales_import_batches%rowtype; fresh_report jsonb; doc jsonb; row jsonb; p jsonb; header_id uuid; expected text; posted integer:=0;
begin
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Sales import access denied.' using errcode='42501'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into batch from public.sales_import_batches where organisation_id=p_organisation_id and id=p_batch_id for update;
 if not found then raise exception 'Import unavailable.' using errcode='42501'; end if;
 if batch.state='POSTED' then return jsonb_build_object('posted',true,'already_posted',true); end if;
 if batch.state='CANCELLED' then raise exception 'This import was cancelled.' using errcode='22023'; end if;
 fresh_report:=private.pp_validate_sales_csv(p_organisation_id,batch.source_csv,batch.source_organisation_code,batch.net_basis,batch.currency_code,batch.mappings);
 if fresh_report is distinct from batch.report then
  update public.sales_import_batches set report=fresh_report,state=case when (fresh_report->>'can_post')::boolean then 'REVIEW' else 'INVALID' end where id=batch.id;
  return jsonb_build_object('posted',false,'message','Review updated menu bindings, catalogue changes or duplicate findings before saving again.');
 end if;
 if not (fresh_report->>'can_post')::boolean then raise exception 'Fix all findings before recording sales.' using errcode='22023'; end if;
 if jsonb_typeof(p_controls) is distinct from 'object' or octet_length(p_controls::text)>32768 then raise exception 'Enter source receipt totals for reconciliation.' using errcode='22023'; end if;
 for doc in select value from jsonb_array_elements(fresh_report->'receipts') loop
  if not (doc->>'duplicate')::boolean then
   expected:=p_controls->>(doc->>'key');
   if expected is null or expected !~ '^(0|[1-9][0-9]{0,25})(\.[0-9]{1,12})?$' then raise exception 'Enter the customer total from receipt % (no commas).',doc->>'transaction_ref' using errcode='22023'; end if;
   if expected::numeric<>(doc->>'total')::numeric then raise exception 'Receipt total does not reconcile for %. Check all source lines and the selected tax format.',doc->>'transaction_ref' using errcode='22023'; end if;
  end if;
 end loop;
 for row in select value from jsonb_array_elements(fresh_report->'rows') loop
  if row->>'state'<>'READY' then continue; end if;
  p:=row->'prepared';
  select id into header_id from public.sales_headers where organisation_id=p_organisation_id and source_system=p->>'source_system' and location_id=(p->>'location_id')::uuid and transaction_ref=p->>'transaction_ref';
  if not found then
   select value into doc from jsonb_array_elements(fresh_report->'receipts') where value->>'key'=p->>'receipt_key';
   insert into public.sales_headers(organisation_id,source_system,location_id,transaction_ref,sale_date,channel_code,currency_code,source_status,net_basis,receipt_total,import_batch_id,created_by)
   values(p_organisation_id,p->>'source_system',(p->>'location_id')::uuid,p->>'transaction_ref',(p->>'sale_date')::date,p->>'channel_code',batch.currency_code,'PAID',batch.net_basis,(doc->>'total')::numeric,batch.id,auth.uid()) returning id into header_id;
  end if;
  insert into public.sales_lines(organisation_id,sale_id,line_ref,menu_item_id,menu_version_id,quantity,gross_sales,discount,tax,source_net_sales,net_revenue,customer_total,source_row,source_input,source_fingerprint,import_batch_id,created_by)
  values(p_organisation_id,header_id,p->>'line_ref',(p->>'menu_item_id')::uuid,(p->>'menu_version_id')::uuid,(p->>'quantity')::numeric,
   (p->>'gross_sales')::numeric,(p->>'discount')::numeric,(p->>'tax')::numeric,(p->>'source_net_sales')::numeric,(p->>'net_revenue')::numeric,
   (p->>'customer_total')::numeric,(row->>'row')::integer,row->'source',p->>'fingerprint',batch.id,auth.uid()); posted:=posted+1;
 end loop;
 update public.sales_import_batches set state='POSTED',controls=p_controls,posted_at=now(),posted_by=auth.uid() where id=batch.id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'sales_import.posted',auth.uid(),batch.id,jsonb_build_object('new_lines',posted,'duplicates',fresh_report->'duplicates'));
 return jsonb_build_object('posted',true,'new_lines',posted,'duplicates',fresh_report->'duplicates');
end; $$;

create function public.sales_import_history(p_organisation_id uuid,p_page integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_sales_read(p_organisation_id) then raise exception 'Sales access denied.' using errcode='42501'; end if;
 if p_page is null or p_page not between 1 and 100000 then raise exception 'Invalid page.' using errcode='22023'; end if;
 select jsonb_build_object('total',(select count(*) from public.sales_import_batches where organisation_id=p_organisation_id),
 'batches',coalesce((select jsonb_agg(to_jsonb(b) order by b.created_at desc,b.id) from (
  select id,filename,state,created_at,report->'ready' as ready,report->'duplicates' as duplicates,report->'rejected' as rejected
  from public.sales_import_batches where organisation_id=p_organisation_id order by created_at desc,id limit 25 offset (p_page-1)*25) b),'[]'::jsonb)) into result;
 return result;
end; $$;
create function public.get_sales_import(p_organisation_id uuid,p_batch_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_sales_read(p_organisation_id) then raise exception 'Sales access denied.' using errcode='42501'; end if;
 select to_jsonb(b)-'source_csv'-'input_hash'-'request_id' into result from public.sales_import_batches b where organisation_id=p_organisation_id and id=p_batch_id;
 if result is null then raise exception 'Import unavailable.' using errcode='42501'; end if; return result;
end; $$;
create function public.sales_import_source(p_organisation_id uuid,p_batch_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_sales_read(p_organisation_id) then raise exception 'Sales access denied.' using errcode='42501'; end if;
 select jsonb_build_object('filename',filename,'csv',source_csv,'sha256',source_hash) into result from public.sales_import_batches where organisation_id=p_organisation_id and id=p_batch_id;
 if result is null then raise exception 'Import unavailable.' using errcode='42501'; end if; return result;
end; $$;
create function public.cancel_sales_import(p_organisation_id uuid,p_batch_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Sales access denied.' using errcode='42501'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 update public.sales_import_batches set state='CANCELLED' where organisation_id=p_organisation_id and id=p_batch_id and state in ('REVIEW','INVALID');
 if not found then raise exception 'Only an unposted import can be cancelled.' using errcode='22023'; end if;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'sales_import.cancelled',auth.uid(),p_batch_id,'{}');
end; $$;

create function private.pp_sales_cost(p_org uuid,p_menu_version uuid,p_day date,p_quantity numeric)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v public.menu_item_versions%rowtype; estimate jsonb; cost numeric;
begin
 select * into v from public.menu_item_versions where organisation_id=p_org and id=p_menu_version;
 if not found then return jsonb_build_object('cost',null,'reason','Menu binding unavailable'); end if;
 begin
  estimate:=public.recipe_reference_cost_estimate(p_org,v.recipe_version_id,p_day,v.recipe_quantity);
  if estimate->>'cost_state'='MISSING' then return jsonb_build_object('cost',null,'reason','Ingredient reference prices missing'); end if;
  cost:=round((estimate->>'target_cost')::numeric*p_quantity,12);
  if cost<=0 or cost>=1e26 then return jsonb_build_object('cost',null,'reason','Cost exceeds supported precision'); end if;
  return jsonb_build_object('cost',cost::text,'reason',null);
 exception when sqlstate '22023' then return jsonb_build_object('cost',null,'reason','Cost date or quantity exceeds supported precision'); end;
end; $$;
revoke all on function private.pp_sales_cost(uuid,uuid,date,numeric) from public,anon,authenticated;

create function public.sales_period_summary(p_organisation_id uuid,p_from date,p_to date,p_location_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; count_lines integer; currency text;
begin
 if not private.pp_sales_read(p_organisation_id) then raise exception 'Sales access denied.' using errcode='42501'; end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>92 or p_to>(select (now() at time zone time_zone)::date from public.organisations where id=p_organisation_id)
  then raise exception 'Choose up to 93 days, ending no later than the current business date.' using errcode='22023'; end if;
 if p_location_id is not null and not exists(select 1 from public.locations where organisation_id=p_organisation_id and id=p_location_id) then raise exception 'Location unavailable.' using errcode='42501'; end if;
 select currency_code into currency from public.organisations where id=p_organisation_id;
 select count(*) into count_lines from public.sales_lines l join public.sales_headers h on h.organisation_id=l.organisation_id and h.id=l.sale_id
  where l.organisation_id=p_organisation_id and h.sale_date between p_from and p_to and (p_location_id is null or h.location_id=p_location_id);
 if count_lines>1000 then raise exception 'This live preview supports up to 1,000 lines. Narrow the date range or select one location.' using errcode='22023'; end if;
 if exists(select 1 from public.sales_headers where organisation_id=p_organisation_id and sale_date between p_from and p_to
  and (p_location_id is null or location_id=p_location_id) and currency_code<>currency) then raise exception 'The selected period contains a different recorded currency. Currency conversion is not inferred.' using errcode='22023'; end if;
 with priced as materialized (
  select l.*,h.location_id,h.sale_date,i.name as menu_name,i.code,
   private.pp_sales_cost(p_organisation_id,l.menu_version_id,h.sale_date,l.quantity) as estimate
  from public.sales_lines l join public.sales_headers h on h.organisation_id=l.organisation_id and h.id=l.sale_id
  join public.menu_item_versions v on v.organisation_id=l.organisation_id and v.id=l.menu_version_id
  join public.menu_items i on i.organisation_id=l.organisation_id and i.id=l.menu_item_id
  where l.organisation_id=p_organisation_id and h.sale_date between p_from and p_to and (p_location_id is null or h.location_id=p_location_id)
 ), costs as (
  select *, (estimate->>'cost')::numeric as cost from priced
 ), totals as (
  select count(*)::integer as lines,count(distinct sale_id)::integer as receipts,count(cost)::integer as priced_lines,
   coalesce(sum(quantity),0) as quantity,coalesce(sum(net_revenue),0) as revenue,coalesce(sum(tax),0) as tax,
   coalesce(sum(discount),0) as discounts,coalesce(sum(customer_total),0) as customer_total,sum(cost) as known_subtotal,
   case when count(*)>0 and count(cost)=count(*) then sum(cost) else null end as full_cost from costs
 ), grouped as (
  select menu_item_id,code,min(menu_name) as name,count(*)::integer as lines,count(cost)::integer as priced_lines,
   sum(quantity) as quantity,sum(net_revenue) as revenue,
   case when count(cost)=count(*) then sum(cost) else null end as full_cost from costs group by menu_item_id,code
 ) select jsonb_build_object('currency_code',currency,'from',p_from,'to',p_to,'lines',t.lines,'receipts',t.receipts,
  'priced_lines',t.priced_lines,'missing_lines',t.lines-t.priced_lines,'quantity',t.quantity::text,'net_revenue',t.revenue::text,
  'tax',t.tax::text,'discounts',t.discounts::text,'customer_total',t.customer_total::text,'known_subtotal',t.known_subtotal::text,
  'estimated_food_cost',t.full_cost::text,'estimated_food_margin',(t.revenue-t.full_cost)::text,
  'food_margin_percent',round((t.revenue-t.full_cost)/nullif(t.revenue,0)*100,6)::text,
  'menus',coalesce((select jsonb_agg(jsonb_build_object('menu_item_id',menu_item_id,'code',code,'name',name,'lines',lines,'priced_lines',priced_lines,
   'quantity',quantity::text,'net_revenue',revenue::text,'estimated_food_cost',full_cost::text,'estimated_food_margin',(revenue-full_cost)::text) order by name,code) from grouped),'[]'::jsonb),
  'missing',coalesce((select jsonb_agg(jsonb_build_object('menu_version_id',menu_version_id,'menu_item_id',menu_item_id,'menu_name',menu_name,'sale_date',sale_date,'reason',estimate->>'reason'))
   from costs where cost is null),'[]'::jsonb)) into result from totals t;
 return result;
end; $$;

revoke all on function public.sales_import_access(uuid) from public,anon;
revoke all on function public.stage_sales_import(uuid,uuid,text,text,text,text,text,jsonb) from public,anon;
revoke all on function public.post_sales_import(uuid,uuid,jsonb) from public,anon;
revoke all on function public.sales_import_history(uuid,integer) from public,anon;
revoke all on function public.get_sales_import(uuid,uuid) from public,anon;
revoke all on function public.sales_import_source(uuid,uuid) from public,anon;
revoke all on function public.cancel_sales_import(uuid,uuid) from public,anon;
revoke all on function public.sales_period_summary(uuid,date,date,uuid) from public,anon;
grant execute on function public.sales_import_access(uuid) to authenticated;
grant execute on function public.stage_sales_import(uuid,uuid,text,text,text,text,text,jsonb) to authenticated;
grant execute on function public.post_sales_import(uuid,uuid,jsonb) to authenticated;
grant execute on function public.sales_import_history(uuid,integer) to authenticated;
grant execute on function public.get_sales_import(uuid,uuid) to authenticated;
grant execute on function public.sales_import_source(uuid,uuid) to authenticated;
grant execute on function public.cancel_sales_import(uuid,uuid) to authenticated;
grant execute on function public.sales_period_summary(uuid,date,date,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
