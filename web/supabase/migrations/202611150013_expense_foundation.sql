-- Apply ONCE after 012. Management expense schedules, not a statutory ledger.
begin;
-- Preserve legacy amounts without inventing a labour classification or coverage
-- schedule. Freeze their old direct-write path and restrict financial reads.
revoke insert,update,delete on public.expenses,public.expense_categories from authenticated;
alter policy tenant_read on public.expenses using(private.pp_sales_read(organisation_id));
alter policy tenant_read on public.expense_categories using(private.pp_sales_read(organisation_id));
create function public.expense_access(p_organisation_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('read',private.pp_sales_read(p_organisation_id),'write',private.pp_menu_write(p_organisation_id));
$$;
create table public.management_expense_categories(
 id uuid primary key default gen_random_uuid(),organisation_id uuid not null references public.organisations(id),
 code text not null check(code~'^[A-Z0-9][A-Z0-9_-]{0,39}$'),name text not null check(length(trim(name)) between 1 and 90),
 kind text not null check(kind in ('LABOUR','OPERATING')),is_active boolean not null default true,
 created_by uuid references auth.users(id),created_at timestamptz not null default now(),unique(organisation_id,id),unique(organisation_id,code)
);
create function private.pp_seed_expense_categories(target_org uuid) returns void language sql security definer set search_path='' as $$
 insert into public.management_expense_categories(organisation_id,code,name,kind)
 select target_org,code,name,kind from(values
 ('WAGES','Wages and salaries','LABOUR'),('EMPLOYER_COSTS','Employer-related labour costs','LABOUR'),('OTHER_LABOUR','Other recorded labour','LABOUR'),
 ('RENT','Rent','OPERATING'),('UTILITIES','Utilities','OPERATING'),('ADMIN','Administration','OPERATING'),('MARKETING','Marketing','OPERATING'),
 ('CHANNEL_FEES','Channel and payment fees','OPERATING'),('OTHER_OPERATING','Other operating expenses','OPERATING')) v(code,name,kind)
 on conflict(organisation_id,code) do nothing;
$$;
revoke all on function private.pp_seed_expense_categories(uuid) from public,anon,authenticated;
create function private.pp_new_expense_categories() returns trigger language plpgsql security definer set search_path='' as $$
begin perform private.pp_seed_expense_categories(new.id);return new;end;$$;
revoke all on function private.pp_new_expense_categories() from public,anon,authenticated;
create trigger pp_new_expense_categories after insert on public.organisations for each row execute function private.pp_new_expense_categories();
select private.pp_seed_expense_categories(id) from public.organisations;

create table public.expense_import_batches(
 id uuid primary key default gen_random_uuid(),organisation_id uuid not null references public.organisations(id),request_id uuid not null,
 filename text not null check(length(filename) between 1 and 180),source_csv text not null check(octet_length(source_csv)<=131072),
 source_hash text not null,input_hash text not null,source_organisation_code text not null,
 contract_version text not null default 'EXPENSE_CSV_V1',
 state text not null check(state in ('INVALID','REVIEW','POSTED')),report jsonb not null,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),posted_at timestamptz,source_control numeric,
 unique(organisation_id,id),unique(organisation_id,request_id)
);
create table public.expense_entries(
 id uuid primary key default gen_random_uuid(),organisation_id uuid not null references public.organisations(id),
 import_batch_id uuid not null,source_system text not null,expense_ref text not null,line_ref text not null,source_row integer not null,
 category_id uuid not null,location_id uuid,expense_from date not null,expense_to date not null,
 recognition_method text not null check(recognition_method in ('ON_DATE','DAILY')),payment_date date,
 amount numeric(20,6) not null check(amount>0),currency_code text not null,description text not null,
 fingerprint text not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 voided_at timestamptz,voided_by uuid references auth.users(id),void_reason text,
 foreign key(organisation_id,import_batch_id) references public.expense_import_batches(organisation_id,id),
 foreign key(organisation_id,category_id) references public.management_expense_categories(organisation_id,id),
 foreign key(organisation_id,location_id) references public.locations(organisation_id,id),
 check(expense_to>=expense_from and expense_to-expense_from<=3659),check(recognition_method='DAILY' or expense_from=expense_to),
 unique(organisation_id,source_system,expense_ref,line_ref)
);
create index pp_expenses_period on public.expense_entries(organisation_id,expense_from,expense_to,location_id);
create table public.expense_coverage_reviews(
 id uuid primary key default gen_random_uuid(),organisation_id uuid not null references public.organisations(id),
 period_from date not null,period_to date not null,location_id uuid,kind text not null check(kind in ('LABOUR','OPERATING')),
 fingerprint text not null,reviewed_by uuid not null references auth.users(id),reviewed_at timestamptz not null default now(),
 foreign key(organisation_id,location_id) references public.locations(organisation_id,id)
);
do $$declare t text;begin
 foreach t in array array['management_expense_categories','expense_import_batches','expense_entries','expense_coverage_reviews'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 end loop;
end;$$;

create function public.list_expense_categories(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.pp_sales_read(p_organisation_id) then raise exception 'Expense access denied.' using errcode='42501';end if;
 return(select coalesce(jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'kind',kind,'is_active',is_active) order by kind,name),'[]') from public.management_expense_categories where organisation_id=p_organisation_id);
end;$$;
create function public.create_expense_category(p_organisation_id uuid,p_code text,p_name text,p_kind text) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 perform 1 from public.organisations where id=p_organisation_id for update;
 if not private.pp_menu_write(p_organisation_id) then raise exception 'An organisation-wide administrator is required.' using errcode='42501';end if;
 if p_code is null or upper(trim(p_code))!~'^[A-Z0-9][A-Z0-9_-]{0,39}$' or p_name is null or length(trim(p_name)) not between 1 and 90 or p_kind is null or p_kind not in ('LABOUR','OPERATING') then raise exception 'Check the category code, name and type.' using errcode='22023';end if;
 if(select count(*) from public.management_expense_categories where organisation_id=p_organisation_id)>=100 then raise exception 'Use at most 100 expense categories.' using errcode='22023';end if;
 if exists(select 1 from public.management_expense_categories where organisation_id=p_organisation_id and code=upper(trim(p_code))) then raise exception 'This category code already exists.' using errcode='22023';end if;
 insert into public.management_expense_categories(organisation_id,code,name,kind,created_by) values(p_organisation_id,upper(trim(p_code)),trim(p_name),p_kind,auth.uid()) returning id into result;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id) values(p_organisation_id,'EXPENSE_CATEGORY_CREATED',auth.uid(),result);
 return result;
end;$$;

-- Allocation uses cumulative rounding, so adjacent slices reconcile to the source
-- amount at six decimal places. DAILY is an explicitly chosen management allocation.
create function private.pp_expense_slice(amount numeric,coverage_from date,coverage_to date,selection_from date,selection_to date)
returns numeric language sql immutable set search_path='' as $$
 select case when coverage_to<selection_from or coverage_from>selection_to then 0 else
 round(amount*(least(coverage_to,selection_to)-coverage_from+1)/(coverage_to-coverage_from+1),6)
 -round(amount*(greatest(coverage_from,selection_from)-coverage_from)/(coverage_to-coverage_from+1),6) end;
$$;
revoke all on function private.pp_expense_slice(numeric,date,date,date,date) from public,anon,authenticated;

create function private.pp_expense_csv(p_csv text)
returns jsonb language plpgsql immutable set search_path='' as $$
declare headers text[]:=array['Organisation_Code','Source_System','Expense_Ref','Line_Ref','Category_Code','Scope','Location_Code','Expense_From','Expense_To','Recognition_Method','Payment_Date','Amount','Currency','Description'];
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
      if cells<>headers then raise exception 'Use the exact Expense_Import template headers and order.' using errcode='22023'; end if;
     else
      if row_number>101 then raise exception 'Import at most 100 expense rows at a time.' using errcode='22023'; end if;
      if cardinality(cells)<>14 then raise exception 'Data row %: expected 14 columns. Quote values containing commas.',row_number-1 using errcode='22023'; end if;
      obj:='{}'; for k in 1..14 loop obj:=obj||jsonb_build_object(headers[k],cells[k]); end loop;
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
revoke all on function private.pp_expense_csv(text) from public,anon,authenticated;

create function private.pp_validate_expenses(target_org uuid,input_csv text,source_org text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare input_rows jsonb;r jsonb;out_rows jsonb:='[]';issues jsonb;prepared jsonb;row_no integer:=0;
 cat public.management_expense_categories;loc public.locations;old public.expense_entries;start_day date;end_day date;paid_day date;value numeric(20,6);
 identity_key text;seen text[]:='{}';digest text;row_state text;currency text;total numeric:=0;ready integer:=0;duplicates integer:=0;rejected integer:=0;
begin
 select currency_code into currency from public.organisations where id=target_org;
 begin input_rows:=private.pp_expense_csv(input_csv);
 exception when sqlstate '22023' then return jsonb_build_object('file_error',sqlerrm,'rows','[]'::jsonb,'ready',0,'duplicates',0,'rejected',0,'can_post',false,'source_total',null);end;
 for r in select * from jsonb_array_elements(input_rows) loop
  row_no:=row_no+1;issues:='[]';prepared:=null;value:=null;start_day:=null;end_day:=null;paid_day:=null;cat:=null;loc:=null;
  begin
   if r->>'Organisation_Code' is distinct from source_org then raise exception 'Organisation_Code must match the declared source organisation.' using errcode='22023';end if;
   if length(r->>'Source_System') not between 1 and 60 or length(r->>'Expense_Ref') not between 1 and 100 or length(r->>'Line_Ref') not between 1 and 60
    or (r->>'Source_System')~'[[:cntrl:]]' or(r->>'Expense_Ref')~'[[:cntrl:]]' or(r->>'Line_Ref')~'[[:cntrl:]]' then raise exception 'Supply stable source, expense and line references without control characters.' using errcode='22023';end if;
   select * into cat from public.management_expense_categories where organisation_id=target_org and code=r->>'Category_Code' and is_active;
   if not found then raise exception 'Choose an active expense category code in this business.' using errcode='22023';end if;
   if r->>'Scope'='LOCATION' then
    select * into loc from public.locations where organisation_id=target_org and code=r->>'Location_Code';
    if not found then raise exception 'Location code is unavailable in this business.' using errcode='22023';end if;
   elsif r->>'Scope'<>'CENTRAL' or r->>'Location_Code'<>'' then raise exception 'Use LOCATION with a location code, or CENTRAL with a blank location code.' using errcode='22023';end if;
   if r->>'Currency'<>currency then raise exception 'Expense currency must match the business reporting currency. No conversion is inferred.' using errcode='22023';end if;
   if r->>'Expense_From'!~'^\d{4}-\d{2}-\d{2}$' or r->>'Expense_To'!~'^\d{4}-\d{2}-\d{2}$' then raise exception 'Coverage dates must use YYYY-MM-DD.' using errcode='22023';end if;
   start_day:=(r->>'Expense_From')::date;end_day:=(r->>'Expense_To')::date;
   if end_day<start_day or end_day-start_day>3659 then raise exception 'Coverage must span between 1 and 3,660 calendar days.' using errcode='22023';end if;
   if r->>'Recognition_Method' not in ('ON_DATE','DAILY') or(r->>'Recognition_Method'='ON_DATE' and start_day<>end_day) then raise exception 'Choose ON_DATE for one date, or explicitly choose DAILY to spread across the coverage period.' using errcode='22023';end if;
   if r->>'Payment_Date'<>'' then
    if r->>'Payment_Date'!~'^\d{4}-\d{2}-\d{2}$' then raise exception 'Payment date must use YYYY-MM-DD, or be blank when unknown.' using errcode='22023';end if;
    paid_day:=(r->>'Payment_Date')::date;
    if paid_day>(select(now() at time zone time_zone)::date from public.organisations where id=target_org) then raise exception 'A recorded payment date cannot be in the future.' using errcode='22023';end if;
   end if;
   if r->>'Amount'!~'^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' then raise exception 'Amount must be positive, with up to six decimal places and no currency symbol or commas.' using errcode='22023';end if;
   value:=(r->>'Amount')::numeric(20,6);if value<=0 then raise exception 'Expense amount must be greater than zero.' using errcode='22023';end if;
   if length(r->>'Description') not between 1 and 500 then raise exception 'Add a description of 1 to 500 characters.' using errcode='22023';end if;
   identity_key:=jsonb_build_array(r->>'Source_System',r->>'Expense_Ref',r->>'Line_Ref')::text;
   if identity_key=any(seen) then raise exception 'This source expense line is repeated within the file.' using errcode='22023';end if;seen:=array_append(seen,identity_key);
   prepared:=jsonb_build_object('source_system',r->>'Source_System','expense_ref',r->>'Expense_Ref','line_ref',r->>'Line_Ref',
    'category_id',cat.id,'location_id',loc.id,'expense_from',start_day,'expense_to',end_day,'recognition_method',r->>'Recognition_Method',
    'payment_date',paid_day,'amount',value::text,'currency_code',currency,'description',r->>'Description');
   digest:=encode(sha256(convert_to(prepared::text,'UTF8')),'hex');row_state:='READY';
   select * into old from public.expense_entries where organisation_id=target_org and source_system=r->>'Source_System' and expense_ref=r->>'Expense_Ref' and line_ref=r->>'Line_Ref';
   if found then if old.fingerprint<>digest then raise exception 'This source line already exists with different details. Void and replace it using a new reference; recorded expenses are never overwritten.' using errcode='22023';end if;row_state:='DUPLICATE';duplicates:=duplicates+1;else ready:=ready+1;end if;
   prepared:=prepared||jsonb_build_object('fingerprint',digest,'category_name',cat.name,'kind',cat.kind,'location_name',coalesce(loc.name,'Central / unallocated'),'previously_voided',old.voided_at is not null);
   total:=total+value;
  exception when sqlstate '22023' or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
   issues:=jsonb_build_array(sqlerrm);prepared:=null;row_state:='REJECTED';rejected:=rejected+1;
  end;
  out_rows:=out_rows||jsonb_build_array(jsonb_build_object('row',row_no,'source',r,'state',row_state,'prepared',prepared,'findings',issues));
 end loop;
 return jsonb_build_object('file_error',null,'rows',out_rows,'ready',ready,'duplicates',duplicates,'rejected',rejected,'can_post',rejected=0,'source_total',case when rejected=0 then total::text else null end);
end;$$;
revoke all on function private.pp_validate_expenses(uuid,text,text) from public,anon,authenticated;

create function public.stage_expense_import(p_organisation_id uuid,p_request_id uuid,p_filename text,p_csv text,p_source_org text) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid;hash text;old public.expense_import_batches;review jsonb;
begin
 perform 1 from public.organisations where id=p_organisation_id for update;
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Expense write access denied.' using errcode='42501';end if;
 if p_request_id is null or p_filename is null or length(p_filename) not between 1 and 180 or p_csv is null or octet_length(p_csv)>131072
  or p_source_org is null or length(trim(p_source_org)) not between 1 and 40 then raise exception 'Check the CSV, filename and source organisation code.' using errcode='22023';end if;
 hash:=encode(sha256(convert_to(jsonb_build_array(p_filename,p_csv,p_source_org)::text,'UTF8')),'hex');
 select * into old from public.expense_import_batches where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then if old.input_hash<>hash then raise exception 'This request was already used. Refresh before uploading again.' using errcode='22023';end if;return old.id;end if;
 review:=private.pp_validate_expenses(p_organisation_id,p_csv,p_source_org);
 insert into public.expense_import_batches(organisation_id,request_id,filename,source_csv,source_hash,input_hash,source_organisation_code,state,report,created_by)
 values(p_organisation_id,p_request_id,p_filename,p_csv,encode(sha256(convert_to(p_csv,'UTF8')),'hex'),hash,p_source_org,case when(review->>'can_post')::boolean then 'REVIEW' else 'INVALID' end,review,auth.uid()) returning id into result;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id) values(p_organisation_id,'EXPENSE_IMPORT_STAGED',auth.uid(),result);
 return result;
end;$$;
create function public.get_expense_import(p_organisation_id uuid,p_batch_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.pp_sales_read(p_organisation_id) then raise exception 'Expense access denied.' using errcode='42501';end if;
 return(select to_jsonb(b)-'source_csv'-'input_hash' from public.expense_import_batches b where b.organisation_id=p_organisation_id and b.id=p_batch_id);
end;$$;
create function public.expense_import_source(p_organisation_id uuid,p_batch_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.pp_sales_read(p_organisation_id) then raise exception 'Expense access denied.' using errcode='42501';end if;
 return(select jsonb_build_object('filename',filename,'csv',source_csv) from public.expense_import_batches where organisation_id=p_organisation_id and id=p_batch_id);
end;$$;
create function public.expense_import_history(p_organisation_id uuid,p_page integer) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.pp_sales_read(p_organisation_id) then raise exception 'Expense access denied.' using errcode='42501';end if;
 if p_page is null or p_page not between 1 and 100000 then raise exception 'Choose a valid history page.' using errcode='22023';end if;
 return jsonb_build_object('total',(select count(*) from public.expense_import_batches where organisation_id=p_organisation_id),'batches',coalesce((select jsonb_agg(v order by created_at desc,id) from(select id,created_at,jsonb_build_object('id',id,'filename',filename,'state',state,'created_at',created_at) v from public.expense_import_batches where organisation_id=p_organisation_id order by created_at desc,id limit 25 offset(p_page-1)*25)s),'[]'));
end;$$;
create function public.post_expense_import(p_organisation_id uuid,p_batch_id uuid,p_source_control text) returns jsonb language plpgsql security definer set search_path='' as $$
declare batch public.expense_import_batches;fresh jsonb;r jsonb;p jsonb;added integer:=0;
begin
 perform 1 from public.organisations where id=p_organisation_id for update;
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Expense write access denied.' using errcode='42501';end if;
 select * into batch from public.expense_import_batches where organisation_id=p_organisation_id and id=p_batch_id for update;
 if not found then raise exception 'Expense import unavailable.' using errcode='22023';end if;
 if batch.state='POSTED' then return jsonb_build_object('posted',true,'already_posted',true);end if;
 fresh:=private.pp_validate_expenses(p_organisation_id,batch.source_csv,batch.source_organisation_code);
 if fresh<>batch.report then
  update public.expense_import_batches set report=fresh,state=case when(fresh->>'can_post')::boolean then 'REVIEW' else 'INVALID' end where id=batch.id;
  return jsonb_build_object('posted',false);
 end if;
 if not(fresh->>'can_post')::boolean then raise exception 'Resolve every finding before recording expenses.' using errcode='22023';end if;
 if p_source_control is null or p_source_control!~'^[0-9]{1,17}(\.[0-9]{1,6})?$' or p_source_control::numeric<>(fresh->>'source_total')::numeric then raise exception 'The source total does not reconcile. Enter the total of every uploaded line, including duplicates.' using errcode='22023';end if;
 for r in select * from jsonb_array_elements(fresh->'rows') where value->>'state'='READY' loop
  p:=r->'prepared';
  insert into public.expense_entries(organisation_id,import_batch_id,source_system,expense_ref,line_ref,source_row,category_id,location_id,expense_from,expense_to,recognition_method,payment_date,amount,currency_code,description,fingerprint,created_by)
  values(p_organisation_id,batch.id,p->>'source_system',p->>'expense_ref',p->>'line_ref',(r->>'row')::integer,(p->>'category_id')::uuid,(p->>'location_id')::uuid,(p->>'expense_from')::date,(p->>'expense_to')::date,p->>'recognition_method',(p->>'payment_date')::date,(p->>'amount')::numeric,p->>'currency_code',p->>'description',p->>'fingerprint',auth.uid());added:=added+1;
 end loop;
 update public.expense_import_batches set state='POSTED',posted_at=now(),source_control=p_source_control::numeric where id=batch.id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'EXPENSE_IMPORT_RECORDED',auth.uid(),batch.id,jsonb_build_object('new_lines',added));
 return jsonb_build_object('posted',true,'new_lines',added);
end;$$;
create function public.void_expense_entry(p_organisation_id uuid,p_entry_id uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare entry public.expense_entries;
begin
 perform 1 from public.organisations where id=p_organisation_id for update;
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Expense write access denied.' using errcode='42501';end if;
 if p_reason is null or length(trim(p_reason)) not between 5 and 500 then raise exception 'Provide a void reason of 5 to 500 characters.' using errcode='22023';end if;
 select * into entry from public.expense_entries where organisation_id=p_organisation_id and id=p_entry_id for update;
 if not found then raise exception 'Expense unavailable.' using errcode='22023';end if;if entry.voided_at is not null then return;end if;
 update public.expense_entries set voided_at=now(),voided_by=auth.uid(),void_reason=trim(p_reason) where id=entry.id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'EXPENSE_VOIDED',auth.uid(),entry.id,jsonb_build_object('reason',trim(p_reason)));
end;$$;

create function private.pp_expense_window(target_org uuid,date_from date,date_to date,target_location uuid) returns void
language plpgsql stable security definer set search_path='' as $$
begin
 if not private.pp_sales_read(target_org) then raise exception 'Expense access denied.' using errcode='42501';end if;
 if date_from is null or date_to is null or date_to<date_from or date_to-date_from>92 or date_to>(select(now() at time zone time_zone)::date from public.organisations where id=target_org) then raise exception 'Choose up to 93 days, ending no later than the current business date.' using errcode='22023';end if;
 if target_location is not null and not exists(select 1 from public.locations where organisation_id=target_org and id=target_location) then raise exception 'Location unavailable.' using errcode='42501';end if;
 if(select count(*) from public.expense_entries where organisation_id=target_org and expense_from<=date_to and expense_to>=date_from and(target_location is null or location_id=target_location))>2000 then raise exception 'This expense preview supports up to 2,000 entries. Narrow the period or select an outlet.' using errcode='22023';end if;
 if(select count(*) from public.expenses x where x.organisation_id=target_org and x.expense_date between date_from and date_to and(target_location is null or x.branch_id=(select legacy_branch_id from public.locations where organisation_id=target_org and id=target_location)))>2000 then raise exception 'Legacy reconciliation exceeds 2,000 entries. Narrow the period or select an outlet.' using errcode='22023';end if;
 if exists(select 1 from public.expense_entries e join public.organisations o on o.id=e.organisation_id where e.organisation_id=target_org and e.voided_at is null and e.expense_from<=date_to and e.expense_to>=date_from and(target_location is null or e.location_id=target_location) and e.currency_code<>o.currency_code) then raise exception 'The expense selection contains a different recorded currency. Currency conversion is not inferred.' using errcode='22023';end if;
end;$$;
revoke all on function private.pp_expense_window(uuid,date,date,uuid) from public,anon,authenticated;
create function private.pp_expense_fingerprint(target_org uuid,date_from date,date_to date,target_location uuid,target_kind text) returns text
language sql stable security definer set search_path='' as $$
 select encode(sha256(convert_to(jsonb_build_array(
  (select currency_code from public.organisations where id=target_org),
  (select coalesce(jsonb_agg(id order by id),'[]') from public.locations where organisation_id=target_org and(target_location is null or id=target_location)),
  (select coalesce(jsonb_agg(jsonb_build_array(e.id,e.amount,e.currency_code,e.expense_from,e.expense_to,e.recognition_method,e.category_id,c.kind,e.location_id,e.voided_at) order by e.id),'[]')
   from public.expense_entries e join public.management_expense_categories c on c.organisation_id=e.organisation_id and c.id=e.category_id
   where e.organisation_id=target_org and c.kind=target_kind and e.expense_from<=date_to and e.expense_to>=date_from and(target_location is null or e.location_id=target_location)),
  (select coalesce(jsonb_agg(jsonb_build_array(x.id,x.amount,x.expense_date,x.branch_id,x.category_id) order by x.id),'[]') from public.expenses x
   where x.organisation_id=target_org and x.expense_date between date_from and date_to and(target_location is null or x.branch_id=(select legacy_branch_id from public.locations where organisation_id=target_org and id=target_location)))
 )::text,'UTF8')),'hex');
$$;
revoke all on function private.pp_expense_fingerprint(uuid,date,date,uuid,text) from public,anon,authenticated;
create function private.pp_expense_coverage(target_org uuid,date_from date,date_to date,target_location uuid,target_kind text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare review public.expense_coverage_reviews;
begin
 select * into review from public.expense_coverage_reviews where organisation_id=target_org and period_from=date_from and period_to=date_to
 and location_id is not distinct from target_location and kind=target_kind order by reviewed_at desc,id desc limit 1;
 return jsonb_build_object('valid',coalesce(review.fingerprint=private.pp_expense_fingerprint(target_org,date_from,date_to,target_location,target_kind),false),'reviewed_at',review.reviewed_at);
end;$$;
revoke all on function private.pp_expense_coverage(uuid,date,date,uuid,text) from public,anon,authenticated;
create function public.review_expense_coverage(p_organisation_id uuid,p_from date,p_to date,p_location_id uuid,p_kind text,p_confirmed boolean) returns void
language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 perform 1 from public.organisations where id=p_organisation_id for update;
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Expense write access denied.' using errcode='42501';end if;
 perform private.pp_expense_window(p_organisation_id,p_from,p_to,p_location_id);
 if p_kind is null or p_kind not in ('LABOUR','OPERATING') or p_confirmed is distinct from true then raise exception 'Explicitly confirm that the selected cost type is complete for this exact period and scope, including known zero costs.' using errcode='22023';end if;
 insert into public.expense_coverage_reviews(organisation_id,period_from,period_to,location_id,kind,fingerprint,reviewed_by,reviewed_at)
 values(p_organisation_id,p_from,p_to,p_location_id,p_kind,private.pp_expense_fingerprint(p_organisation_id,p_from,p_to,p_location_id,p_kind),auth.uid(),clock_timestamp()) returning id into result;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'EXPENSE_COVERAGE_REVIEWED',auth.uid(),result,jsonb_build_object('from',p_from,'to',p_to,'location_id',p_location_id,'kind',p_kind));
end;$$;
create function public.expense_period_report(p_organisation_id uuid,p_from date,p_to date,p_location_id uuid,p_page integer) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare labour numeric;operating numeric;central numeric;categories jsonb;entry_rows jsonb;entry_total integer;active_count integer;allocated_count integer;
 labour_count integer;operating_count integer;excluded_central integer;legacy_count integer;labour_review jsonb;operating_review jsonb;sales jsonb;sales_error text;prime numeric;currency text;
begin
 perform private.pp_expense_window(p_organisation_id,p_from,p_to,p_location_id);
 if p_page is null or p_page not between 1 and 100000 then raise exception 'Choose a valid expense page.' using errcode='22023';end if;
 select currency_code into currency from public.organisations where id=p_organisation_id;
 with selected as materialized(
  select e.*,c.name as category_name,c.code as category_code,c.kind,private.pp_expense_slice(e.amount,e.expense_from,e.expense_to,p_from,p_to) as period_amount
  from public.expense_entries e join public.management_expense_categories c on c.organisation_id=e.organisation_id and c.id=e.category_id
  where e.organisation_id=p_organisation_id and e.voided_at is null and e.expense_from<=p_to and e.expense_to>=p_from and(p_location_id is null or e.location_id=p_location_id)
 ),grouped as(select category_id,category_code,category_name,kind,sum(period_amount) as total,count(*) as entries from selected group by category_id,category_code,category_name,kind)
 select coalesce(sum(period_amount) filter(where kind='LABOUR'),0),coalesce(sum(period_amount) filter(where kind='OPERATING'),0),coalesce(sum(period_amount) filter(where location_id is null),0),count(*)::integer,
 count(*) filter(where recognition_method='DAILY')::integer,count(*) filter(where kind='LABOUR')::integer,count(*) filter(where kind='OPERATING')::integer,
 (select coalesce(jsonb_agg(jsonb_build_object('code',category_code,'name',category_name,'kind',kind,'amount',total::text,'entries',entries) order by kind,category_name),'[]') from grouped)
 into labour,operating,central,active_count,allocated_count,labour_count,operating_count,categories from selected;
 select count(*)::integer into entry_total from public.expense_entries where organisation_id=p_organisation_id and expense_from<=p_to and expense_to>=p_from and(p_location_id is null or location_id=p_location_id);
 select coalesce(jsonb_agg(v order by expense_from desc,created_at desc,id),'[]') into entry_rows from(
  select e.expense_from,e.created_at,e.id,jsonb_build_object('id',e.id,'batch_id',e.import_batch_id,'source_system',e.source_system,'expense_ref',e.expense_ref,'line_ref',e.line_ref,
  'category_name',c.name,'kind',c.kind,'location_name',coalesce(l.name,'Central / unallocated'),'location_id',e.location_id,'expense_from',e.expense_from,'expense_to',e.expense_to,
  'recognition_method',e.recognition_method,'payment_date',e.payment_date,'amount',e.amount::text,'period_amount',case when e.voided_at is null then private.pp_expense_slice(e.amount,e.expense_from,e.expense_to,p_from,p_to)::text else null end,
  'currency_code',e.currency_code,'description',e.description,'voided_at',e.voided_at,'void_reason',e.void_reason) v
  from public.expense_entries e join public.management_expense_categories c on c.organisation_id=e.organisation_id and c.id=e.category_id left join public.locations l on l.organisation_id=e.organisation_id and l.id=e.location_id
  where e.organisation_id=p_organisation_id and e.expense_from<=p_to and e.expense_to>=p_from and(p_location_id is null or e.location_id=p_location_id)
  order by e.expense_from desc,e.created_at desc,e.id limit 25 offset(p_page-1)*25)s;
 labour_review:=private.pp_expense_coverage(p_organisation_id,p_from,p_to,p_location_id,'LABOUR');
 operating_review:=private.pp_expense_coverage(p_organisation_id,p_from,p_to,p_location_id,'OPERATING');
 begin sales:=public.sales_period_summary(p_organisation_id,p_from,p_to,p_location_id);
 exception when sqlstate '22023' then sales_error:=sqlerrm;sales:=null;end;
 if(labour_review->>'valid')::boolean and(sales->>'lines')::integer>0 and sales->>'estimated_food_cost' is not null then prime:=(sales->>'estimated_food_cost')::numeric+labour;end if;
 select count(*)::integer into excluded_central from public.expense_entries where organisation_id=p_organisation_id and location_id is null and voided_at is null and expense_from<=p_to and expense_to>=p_from;
 select count(*)::integer into legacy_count from public.expenses x where x.organisation_id=p_organisation_id and x.expense_date between p_from and p_to
 and(p_location_id is null or x.branch_id=(select legacy_branch_id from public.locations where organisation_id=p_organisation_id and id=p_location_id));
 return jsonb_build_object('currency_code',currency,'labour_amount',labour::text,'operating_amount',operating::text,'central_amount',central::text,
 'active_entries',active_count,'daily_allocated_entries',allocated_count,'labour_entries',labour_count,'operating_entries',operating_count,
 'excluded_central_entries',case when p_location_id is null then 0 else excluded_central end,'legacy_entries',legacy_count,'categories',categories,'entries',entry_rows,'entry_total',entry_total,
 'labour_coverage',labour_review,'operating_coverage',operating_review,'sales',sales,'sales_error',sales_error,'estimated_prime_cost',prime::text,
 'prime_cost_percent',round(prime/nullif((sales->>'net_revenue')::numeric,0)*100,6)::text,
 'labour_cost_percent',case when(labour_review->>'valid')::boolean and(sales->>'lines')::integer>0 then round(labour/nullif((sales->>'net_revenue')::numeric,0)*100,6)::text else null end,
 'refreshed_at',statement_timestamp());
end;$$;

create or replace function public.workspace_navigation_access(p_organisation_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('overview',private.pp_sales_read(p_organisation_id),'expenses',private.pp_sales_read(p_organisation_id),
 'sales',private.pp_sales_read(p_organisation_id),'purchases',private.pp_reference_price_read(p_organisation_id),
 'menus',private.pp_reference_price_read(p_organisation_id),'recipes',private.pp_catalogue_read(p_organisation_id),
 'catalogue',private.pp_catalogue_read(p_organisation_id),'team',private.pp_team_manage(p_organisation_id));
$$;
revoke all on function public.expense_access(uuid),public.list_expense_categories(uuid),public.create_expense_category(uuid,text,text,text),
 public.stage_expense_import(uuid,uuid,text,text,text),public.get_expense_import(uuid,uuid),public.expense_import_source(uuid,uuid),public.expense_import_history(uuid,integer),
 public.post_expense_import(uuid,uuid,text),public.void_expense_entry(uuid,uuid,text),public.review_expense_coverage(uuid,date,date,uuid,text,boolean),public.expense_period_report(uuid,date,date,uuid,integer) from public,anon;
grant execute on function public.expense_access(uuid),public.list_expense_categories(uuid),public.create_expense_category(uuid,text,text,text),
 public.stage_expense_import(uuid,uuid,text,text,text),public.get_expense_import(uuid,uuid),public.expense_import_source(uuid,uuid),public.expense_import_history(uuid,integer),
 public.post_expense_import(uuid,uuid,text),public.void_expense_entry(uuid,uuid,text),public.review_expense_coverage(uuid,date,date,uuid,text,boolean),public.expense_period_report(uuid,date,date,uuid,integer) to authenticated;
notify pgrst,'reload schema';
commit;
