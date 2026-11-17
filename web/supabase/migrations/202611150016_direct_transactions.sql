-- Apply ONCE after 015. Direct entry and Finance-approved procurement corrections.
begin;
create function private.pp_finance(target_org uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisation_memberships m join public.membership_roles r
 on r.organisation_id=m.organisation_id and r.membership_id=m.id
 where m.organisation_id=target_org and m.user_id=auth.uid() and m.status='active' and r.location_id is null and r.role_code='finance');
$$;
create function private.pp_purchase_write(target_org uuid) returns boolean
language sql stable security definer set search_path='' as $$select private.pp_catalogue_write(target_org) or private.pp_finance(target_org);$$;
create function private.pp_expense_write(target_org uuid) returns boolean
language sql stable security definer set search_path='' as $$select private.pp_menu_write(target_org) or private.pp_finance(target_org);$$;
revoke all on function private.pp_finance(uuid),private.pp_purchase_write(uuid),private.pp_expense_write(uuid) from public,anon,authenticated;
create or replace function public.purchase_import_access(p_organisation_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$select jsonb_build_object('read',private.pp_reference_price_read(p_organisation_id),'write',private.pp_purchase_write(p_organisation_id),'approve_corrections',private.pp_finance(p_organisation_id));$$;
create or replace function public.expense_access(p_organisation_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$select jsonb_build_object('read',private.pp_sales_read(p_organisation_id),'write',private.pp_expense_write(p_organisation_id),'manage_categories',private.pp_menu_write(p_organisation_id));$$;

alter table public.purchase_import_batches add column entry_method text not null default 'CSV' check(entry_method in ('CSV','MANUAL'));
alter table public.purchase_headers drop constraint purchase_headers_source_status_check;
alter table public.purchase_headers add constraint purchase_headers_source_status_check check(source_status in ('RECEIVED','INVOICED'));
-- Retain the existing validation, reconciliation, duplicate and posting algorithms.
-- Replace only the named transaction guards; master-data permissions stay intact.
do $$ declare sig text; definition text; updated text; begin
 foreach sig in array array['public.stage_purchase_import(uuid,uuid,text,text,text,text,jsonb)','public.post_purchase_import(uuid,uuid,jsonb)','public.cancel_purchase_import(uuid,uuid)'] loop
  definition:=pg_get_functiondef(sig::regprocedure);updated:=replace(definition,'private.pp_catalogue_write(p_organisation_id)','private.pp_purchase_write(p_organisation_id)');
  if updated=definition then raise exception 'Purchase permission guard not found: %',sig;end if;
  if sig='public.post_purchase_import(uuid,uuid,jsonb)' then
   updated:=replace(updated,'''currency_code'',''RECEIVED'',batch.price_basis','''currency_code'',case when batch.entry_method=''MANUAL'' then ''INVOICED'' else ''RECEIVED'' end,batch.price_basis');
  end if;
  execute updated;
 end loop;
 foreach sig in array array['public.stage_expense_import(uuid,uuid,text,text,text)','public.post_expense_import(uuid,uuid,text)','public.void_expense_entry(uuid,uuid,text)','public.review_expense_coverage(uuid,date,date,uuid,text,boolean)'] loop
  definition:=pg_get_functiondef(sig::regprocedure);updated:=replace(definition,'private.pp_menu_write(p_organisation_id)','private.pp_expense_write(p_organisation_id)');
  if updated=definition then raise exception 'Expense permission guard not found: %',sig;end if;execute updated;
 end loop;
end; $$;

create function private.pp_csv_cell(value text) returns text language sql immutable set search_path='' as $$select '"'||replace(coalesce(value,''),'"','""')||'"';$$;
revoke all on function private.pp_csv_cell(text) from public,anon,authenticated;
create function private.pp_prepare_invoice(target_org uuid,invoice jsonb,lines jsonb,source text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare supplier public.suppliers;loc public.locations;item public.items;unit public.units_of_measure;
 currency text;csv text:='Organisation_Code,Source_System,Purchase_Date,Purchase_Ref,Line_Ref,Supplier_Code,Item_Code,Quantity,Purchase_UOM,Unit_Price,Line_Discount,Tax,Location_Code,Currency,Status';
 line jsonb;report jsonb;row_number integer:=0;values_row text[];invoice_total text:=invoice->>'total';
begin
 if jsonb_typeof(invoice) is distinct from 'object' or octet_length(invoice::text)>8192 or jsonb_typeof(lines) is distinct from 'array' or jsonb_array_length(lines) not between 1 and 50 or octet_length(lines::text)>65536 then raise exception 'Enter between 1 and 50 invoice lines with valid supplier details.' using errcode='22023';end if;
 select currency_code into currency from public.organisations where id=target_org;
 begin
  select * into supplier from public.suppliers where organisation_id=target_org and id=(invoice->>'supplier_id')::uuid and is_active;
  select * into loc from public.locations where organisation_id=target_org and id=(invoice->>'location_id')::uuid and is_active;
 exception when invalid_text_representation then raise exception 'Choose a supplier and outlet in this business.' using errcode='22023';end;
 if supplier.id is null or loc.id is null then raise exception 'Choose an active supplier and outlet in this business.' using errcode='22023';end if;
 if invoice_total is null or invoice_total!~'^(0|[1-9][0-9]{0,25})(\.[0-9]{1,12})?$' or invoice_total::numeric<=0 then raise exception 'Enter the supplier invoice total without commas.' using errcode='22023';end if;
 if invoice->>'price_basis' is null or invoice->>'price_basis' not in ('EXCLUSIVE','INCLUSIVE') then raise exception 'Choose whether unit prices include tax.' using errcode='22023';end if;
 for line in select value from jsonb_array_elements(lines) loop
  row_number:=row_number+1;
  begin
   select * into item from public.items where organisation_id=target_org and id=(line->>'item_id')::uuid and is_active;
   select * into unit from public.units_of_measure where organisation_id=target_org and id=(line->>'uom_id')::uuid;
  exception when invalid_text_representation then raise exception 'Choose a material and unit for every line.' using errcode='22023';end;
  if item.id is null or unit.id is null then raise exception 'Choose a material and unit in this business for every line.' using errcode='22023';end if;
  values_row:=array['MANUAL',source,invoice->>'date',trim(invoice->>'reference'),row_number::text,supplier.code,item.code,line->>'quantity',unit.code,line->>'unit_price',coalesce(line->>'discount','0'),coalesce(line->>'tax','0'),loc.code,currency,'RECEIVED'];
  csv:=csv||E'\n'||(select string_agg(private.pp_csv_cell(v),',' order by ord) from unnest(values_row) with ordinality a(v,ord));
 end loop;
 report:=private.pp_validate_purchase_csv(target_org,csv,'MANUAL',invoice->>'price_basis','{}'::jsonb);
 if report->>'file_error' is not null or (report->>'rejected')::integer>0 then
  raise exception '%',coalesce(report->>'file_error',report->'rows'->0->'findings'->>0,(select value->'findings'->>0 from jsonb_array_elements(report->'rows') where value->>'state'='REJECTED' limit 1),'Check all invoice lines.') using errcode='22023';end if;
 if jsonb_array_length(report->'documents')<>1 or (report->'documents'->0->>'total')::numeric<>invoice_total::numeric then raise exception 'The line totals do not match the supplier invoice total. Check quantity, prices, discounts and tax.' using errcode='22023';end if;
 return jsonb_build_object('csv',csv,'report',report,'header',jsonb_build_object('supplier_id',supplier.id,'supplier_name',supplier.name,'location_id',loc.id,'location_name',loc.name,'date',invoice->>'date','reference',trim(invoice->>'reference'),'currency',currency,'price_basis',invoice->>'price_basis','total',report->'documents'->0->>'total'),
 'lines',(select jsonb_agg(value->'prepared' order by (value->>'row')::integer) from jsonb_array_elements(report->'rows')));
end; $$;
revoke all on function private.pp_prepare_invoice(uuid,jsonb,jsonb,text) from public,anon,authenticated;

create function public.stage_manual_purchase(p_organisation_id uuid,p_request_id uuid,p_invoice jsonb,p_lines jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare prepared jsonb;result uuid;
begin
 if not private.pp_purchase_write(p_organisation_id) then raise exception 'Purchase entry access denied.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 prepared:=private.pp_prepare_invoice(p_organisation_id,p_invoice,p_lines,'MANUAL_INVOICE');
 result:=public.stage_purchase_import(p_organisation_id,p_request_id,'Supplier invoice.csv',prepared->>'csv','MANUAL',p_invoice->>'price_basis','{}');
 update public.purchase_import_batches set entry_method='MANUAL',controls=case when state in ('REVIEW','INVALID') then jsonb_build_object(prepared->'report'->'documents'->0->>'key',p_invoice->>'total') else controls end where organisation_id=p_organisation_id and id=result;
 return result;
end; $$;

create table public.purchase_corrections(
 id uuid primary key default gen_random_uuid(),organisation_id uuid not null,purchase_id uuid not null,request_id uuid not null,
 base_revision integer not null,kind text not null check(kind in ('REPLACE','VOID')),reason text not null check(length(trim(reason)) between 1 and 1000),
 input_invoice jsonb,input_lines jsonb,proposal jsonb not null,before_value jsonb not null,
 state text not null default 'PENDING' check(state in ('PENDING','APPROVED','REJECTED')),
 created_by uuid not null references auth.users(id),created_label text not null,created_at timestamptz not null default statement_timestamp(),
 decided_by uuid references auth.users(id),decided_label text,decided_at timestamptz,decision_note text,
 unique(organisation_id,id),unique(organisation_id,request_id),foreign key(organisation_id,purchase_id) references public.purchase_headers(organisation_id,id)
);
create unique index pp_pending_purchase_correction on public.purchase_corrections(organisation_id,purchase_id) where state='PENDING';
alter table public.purchase_corrections enable row level security;
revoke all on public.purchase_corrections from public,anon,authenticated;
create function private.pp_protect_correction() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='DELETE' then raise exception 'Procurement correction history cannot be deleted.' using errcode='42501';end if;
 if old.state<>'PENDING' or new.state not in ('APPROVED','REJECTED') or
  (to_jsonb(old)-'state'-'decided_by'-'decided_label'-'decided_at'-'decision_note') is distinct from (to_jsonb(new)-'state'-'decided_by'-'decided_label'-'decided_at'-'decision_note')
 then raise exception 'Procurement correction evidence cannot be rewritten.' using errcode='42501';end if;
 return new;
end;$$;
revoke all on function private.pp_protect_correction() from public,anon,authenticated;
create trigger pp_protect_correction before update or delete on public.purchase_corrections for each row execute function private.pp_protect_correction();

create function private.pp_current_invoice(target_org uuid,target_purchase uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;replacement jsonb;revision integer;
begin
 select jsonb_build_object('header',jsonb_build_object('supplier_id',h.supplier_id,'supplier_name',s.name,'location_id',h.location_id,'location_name',l.name,'date',h.purchase_date,'reference',h.purchase_ref,'currency',h.currency_code,'price_basis',h.price_basis,'total',h.invoice_total::text),
 'lines',(select jsonb_agg(jsonb_build_object('item_id',p.item_id,'item_name',i.name,'uom_id',p.uom_id,'unit_code',u.code,'quantity',p.quantity::text,'unit_price',p.unit_price::text,'line_discount',p.line_discount::text,'tax',p.tax::text,'invoice_amount',p.invoice_amount::text,'net_amount',p.net_amount::text,'base_quantity',p.base_quantity::text,'conversion_factor',p.conversion_factor::text) order by p.source_row,p.id)
 from public.purchase_lines p join public.items i on i.organisation_id=p.organisation_id and i.id=p.item_id join public.units_of_measure u on u.organisation_id=p.organisation_id and u.id=p.uom_id where p.organisation_id=target_org and p.purchase_id=h.id),
 'voided',false) into result from public.purchase_headers h join public.suppliers s on s.organisation_id=h.organisation_id and s.id=h.supplier_id join public.locations l on l.organisation_id=h.organisation_id and l.id=h.location_id where h.organisation_id=target_org and h.id=target_purchase;
 if result is null then raise exception 'Invoice unavailable.' using errcode='42501';end if;
 select count(*)::integer into revision from public.purchase_corrections where organisation_id=target_org and purchase_id=target_purchase and state='APPROVED';
 select proposal into replacement from public.purchase_corrections where organisation_id=target_org and purchase_id=target_purchase and state='APPROVED' order by decided_at desc,id desc limit 1;
 return coalesce(replacement,result)||jsonb_build_object('revision',revision);
end; $$;
revoke all on function private.pp_current_invoice(uuid,uuid) from public,anon,authenticated;

create function private.pp_invoice_conflict(target_org uuid,target_supplier uuid,target_reference text,exclude_purchase uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.purchase_headers h where h.organisation_id=target_org and h.id is distinct from exclude_purchase and (
  (h.supplier_id=target_supplier and h.purchase_ref=target_reference) or
  (private.pp_current_invoice(target_org,h.id)->'header'->>'supplier_id'=target_supplier::text and private.pp_current_invoice(target_org,h.id)->'header'->>'reference'=target_reference)));
$$;
revoke all on function private.pp_invoice_conflict(uuid,uuid,text,uuid) from public,anon,authenticated;

create function public.request_purchase_correction(p_organisation_id uuid,p_purchase_id uuid,p_request_id uuid,p_revision integer,p_kind text,p_reason text,p_invoice jsonb,p_lines jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare current_value jsonb;prepared jsonb;prior public.purchase_corrections;result uuid;
begin
 if not private.pp_purchase_write(p_organisation_id) then raise exception 'Purchase entry access denied.' using errcode='42501';end if;
 if p_request_id is null or p_kind is null or p_kind not in ('REPLACE','VOID') or p_reason is null or length(trim(p_reason)) not between 1 and 1000 then raise exception 'Choose a correction type and enter a reason of up to 1,000 characters.' using errcode='22023';end if;
 if octet_length(coalesce(p_invoice::text,''))>8192 or octet_length(coalesce(p_lines::text,''))>65536 then raise exception 'The correction is too large. Use up to 50 invoice lines.' using errcode='22023';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 current_value:=private.pp_current_invoice(p_organisation_id,p_purchase_id);
 select * into prior from public.purchase_corrections where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then
  if prior.purchase_id<>p_purchase_id or prior.created_by<>auth.uid() or prior.base_revision is distinct from p_revision or prior.kind<>p_kind or prior.reason<>trim(p_reason) or prior.input_invoice is distinct from p_invoice or prior.input_lines is distinct from p_lines then raise exception 'This correction request was already used. Refresh and try again.' using errcode='22023';end if;return prior.id;end if;
 if p_revision is distinct from (current_value->>'revision')::integer then raise exception 'This invoice has changed. Refresh before requesting a correction.' using errcode='22023';end if;
 if exists(select 1 from public.purchase_corrections where organisation_id=p_organisation_id and purchase_id=p_purchase_id and state='PENDING') then raise exception 'This invoice already has a correction awaiting Finance approval.' using errcode='22023';end if;
 if p_kind='REPLACE' then
  if private.pp_invoice_conflict(p_organisation_id,(p_invoice->>'supplier_id')::uuid,trim(p_invoice->>'reference'),p_purchase_id) then raise exception 'This supplier invoice already exists. Correct the existing record instead of duplicating it.' using errcode='22023';end if;
  prepared:=private.pp_prepare_invoice(p_organisation_id,p_invoice,p_lines,'CORRECTION_'||p_request_id::text);
  prepared:=jsonb_build_object('header',prepared->'header','lines',prepared->'lines','voided',false);
 else prepared:=current_value-'revision';prepared:=prepared||jsonb_build_object('voided',true);end if;
 insert into public.purchase_corrections(organisation_id,purchase_id,request_id,base_revision,kind,reason,input_invoice,input_lines,proposal,before_value,created_by,created_label)
 values(p_organisation_id,p_purchase_id,p_request_id,p_revision,p_kind,trim(p_reason),p_invoice,p_lines,prepared,current_value,auth.uid(),coalesce((select email from auth.users where id=auth.uid()),auth.uid()::text)) returning id into result;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'PURCHASE_CORRECTION_REQUESTED',auth.uid(),p_purchase_id,jsonb_build_object('correction_id',result,'kind',p_kind));
 return result;
end; $$;

create function public.decide_purchase_correction(p_organisation_id uuid,p_correction_id uuid,p_approve boolean,p_note text)
returns void language plpgsql security definer set search_path='' as $$
declare correction public.purchase_corrections;current_value jsonb;prepared jsonb;
begin
 if not private.pp_finance(p_organisation_id) then raise exception 'An organisation-wide Finance member must approve or reject procurement corrections.' using errcode='42501';end if;
 if p_approve is null or p_note is null or length(trim(p_note))>1000 or(not p_approve and trim(p_note)='') then raise exception 'Enter a decision note of up to 1,000 characters; a rejection needs a reason.' using errcode='22023';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into correction from public.purchase_corrections where organisation_id=p_organisation_id and id=p_correction_id for update;
 if not found then raise exception 'Correction unavailable.' using errcode='42501';end if;
 if correction.state<>'PENDING' then
  if correction.decided_by=auth.uid() and correction.state=(case when p_approve then 'APPROVED' else 'REJECTED' end) and correction.decision_note=trim(p_note) then return;end if;
  raise exception 'This correction has already been decided. Refresh to see the outcome.' using errcode='22023';end if;
 current_value:=private.pp_current_invoice(p_organisation_id,correction.purchase_id);
 if p_approve and correction.base_revision<>(current_value->>'revision')::integer then raise exception 'This invoice changed after the correction was requested. Reject the stale request and prepare another.' using errcode='22023';end if;
 if p_approve and correction.kind='REPLACE' then
  if private.pp_invoice_conflict(p_organisation_id,(correction.input_invoice->>'supplier_id')::uuid,trim(correction.input_invoice->>'reference'),correction.purchase_id) then raise exception 'Another recorded invoice uses this supplier and reference. Reject this request and review the duplicate.' using errcode='22023';end if;
  prepared:=private.pp_prepare_invoice(p_organisation_id,correction.input_invoice,correction.input_lines,'CORRECTION_'||correction.request_id::text);
  if correction.proposal is distinct from jsonb_build_object('header',prepared->'header','lines',prepared->'lines','voided',false) then raise exception 'Material, supplier, outlet or conversion details changed. Reject this request and submit an updated correction.' using errcode='22023';end if;
 end if;
 update public.purchase_corrections set state=case when p_approve then 'APPROVED' else 'REJECTED' end,decided_by=auth.uid(),decided_label=coalesce((select email from auth.users where id=auth.uid()),auth.uid()::text),decided_at=clock_timestamp(),decision_note=trim(p_note) where organisation_id=p_organisation_id and id=correction.id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'PURCHASE_CORRECTION_DECIDED',auth.uid(),correction.purchase_id,jsonb_build_object('correction_id',correction.id,'approved',p_approve));
end; $$;

create function public.purchase_invoice_detail(p_organisation_id uuid,p_purchase_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare current_value jsonb;changes jsonb;batch_id uuid;
begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Purchase access denied.' using errcode='42501';end if;
 current_value:=private.pp_current_invoice(p_organisation_id,p_purchase_id);
 select import_batch_id into batch_id from public.purchase_headers where organisation_id=p_organisation_id and id=p_purchase_id;
 select coalesce(jsonb_agg(to_jsonb(c)-'input_invoice'-'input_lines' order by c.created_at desc,c.id),'[]') into changes from public.purchase_corrections c where c.organisation_id=p_organisation_id and c.purchase_id=p_purchase_id;
 return jsonb_build_object('current',current_value,'corrections',changes,'batch_id',batch_id);
end; $$;
create function public.purchase_invoice_list(p_organisation_id uuid,p_page integer) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;total integer;
begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Purchase access denied.' using errcode='42501';end if;
 if p_page is null or p_page not between 1 and 100000 then raise exception 'Choose a valid invoice page.' using errcode='22023';end if;
 select count(*)::integer into total from public.purchase_headers where organisation_id=p_organisation_id;
 select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'invoice',s.current_value,'pending',(select count(*) from public.purchase_corrections c where c.organisation_id=p_organisation_id and c.purchase_id=s.id and c.state='PENDING')) order by s.created_at desc,s.id),'[]') into rows from (
 select h.id,h.created_at,private.pp_current_invoice(p_organisation_id,h.id)-'lines' as current_value from public.purchase_headers h where organisation_id=p_organisation_id order by h.created_at desc,h.id limit 20 offset(p_page-1)*20)s;
 return jsonb_build_object('total',total,'invoices',rows);
end; $$;
create function private.pp_check_invoice_sources(target_org uuid,report jsonb) returns void
language plpgsql stable security definer set search_path='' as $$
declare row jsonb;existing_id uuid;
begin
 for row in select value->'prepared' from jsonb_array_elements(report->'rows') where value->>'state' in ('READY','DUPLICATE') loop
  select id into existing_id from public.purchase_headers where organisation_id=target_org and source_system=row->>'source_system' and supplier_id=(row->>'supplier_id')::uuid and purchase_ref=row->>'purchase_ref';
  if private.pp_invoice_conflict(target_org,(row->>'supplier_id')::uuid,row->>'purchase_ref',existing_id) then raise exception 'This supplier invoice is already recorded under another source. Use the correction workflow.' using errcode='22023';end if;
 end loop;
end;$$;
revoke all on function private.pp_check_invoice_sources(uuid,jsonb) from public,anon,authenticated;
-- Check at staging and again at posting, under the existing organisation lock.
do $$ declare sig text;definition text;needle text;begin
 foreach sig in array array['public.stage_purchase_import(uuid,uuid,text,text,text,text,jsonb)','public.post_purchase_import(uuid,uuid,jsonb)'] loop
  definition:=pg_get_functiondef(sig::regprocedure);
  if sig like 'public.stage%' then
   needle:='report:=private.pp_validate_purchase_csv(p_organisation_id,p_csv,trim(p_source_org),p_price_basis,p_mappings);';
   if position(needle in definition)=0 then raise exception 'Stage validation not found.';end if;
   execute replace(definition,needle,needle||' perform private.pp_check_invoice_sources(p_organisation_id,report);');
  else
   needle:='current_report:=private.pp_validate_purchase_csv(p_organisation_id,batch.source_csv,batch.source_organisation_code,batch.price_basis,batch.mappings);';
   if position(needle in definition)=0 then raise exception 'Posting validation not found.';end if;
   execute replace(definition,needle,needle||' perform private.pp_check_invoice_sources(p_organisation_id,current_report);');
  end if;
 end loop;
end;$$;
revoke all on function public.stage_manual_purchase(uuid,uuid,jsonb,jsonb),public.request_purchase_correction(uuid,uuid,uuid,integer,text,text,jsonb,jsonb),public.decide_purchase_correction(uuid,uuid,boolean,text),public.purchase_invoice_detail(uuid,uuid),public.purchase_invoice_list(uuid,integer) from public,anon;
grant execute on function public.stage_manual_purchase(uuid,uuid,jsonb,jsonb),public.request_purchase_correction(uuid,uuid,uuid,integer,text,text,jsonb,jsonb),public.decide_purchase_correction(uuid,uuid,boolean,text),public.purchase_invoice_detail(uuid,uuid),public.purchase_invoice_list(uuid,integer) to authenticated;
notify pgrst,'reload schema';
commit;
