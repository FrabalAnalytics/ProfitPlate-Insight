-- Apply ONCE after 017. Orders, confirmed receipts and invoice exception review.
begin;
create table public.purchase_orders(
 id uuid primary key default gen_random_uuid(),organisation_id uuid not null references public.organisations(id),
 reference text not null,request_id uuid not null,input_hash text not null,input_document jsonb not null,input_lines jsonb not null,
 status text not null default 'DRAFT' check(status in ('DRAFT','ISSUED')),revision integer not null default 1,
 supplier_id uuid not null,location_id uuid not null,document_date date not null,needed_by date,notes text not null,
 payload jsonb not null,created_by uuid not null references auth.users(id),created_label text not null,
 created_at timestamptz not null default statement_timestamp(),issued_by uuid references auth.users(id),issued_label text,issued_at timestamptz,
 unique(organisation_id,id),unique(organisation_id,reference),unique(organisation_id,request_id),
 foreign key(organisation_id,supplier_id) references public.suppliers(organisation_id,id),
 foreign key(organisation_id,location_id) references public.locations(organisation_id,id)
);
create table public.purchase_order_lines(
 id uuid primary key default gen_random_uuid(),organisation_id uuid not null,order_id uuid not null,position integer not null,
 item_id uuid not null,uom_id uuid not null,quantity numeric(20,6) not null check(quantity>0),payload jsonb not null,
 unique(organisation_id,order_id,id),unique(organisation_id,order_id,position),
 foreign key(organisation_id,order_id) references public.purchase_orders(organisation_id,id),
 foreign key(organisation_id,item_id) references public.items(organisation_id,id),
 foreign key(organisation_id,uom_id) references public.units_of_measure(organisation_id,id)
);
create table public.goods_receipts(
 id uuid primary key default gen_random_uuid(),organisation_id uuid not null,order_id uuid not null,request_id uuid not null,
 reference text not null,received_on date not null,delivery_reference text not null,notes text not null,input_hash text not null,
 created_by uuid not null references auth.users(id),created_label text not null,created_at timestamptz not null default statement_timestamp(),
 unique(organisation_id,id),unique(organisation_id,order_id,id),unique(organisation_id,request_id),unique(organisation_id,reference),
 unique(organisation_id,order_id,delivery_reference),foreign key(organisation_id,order_id) references public.purchase_orders(organisation_id,id)
);
create table public.goods_receipt_lines(
 id uuid primary key default gen_random_uuid(),organisation_id uuid not null,receipt_id uuid not null,order_id uuid not null,order_line_id uuid not null,
 accepted numeric(20,6) not null check(accepted>=0),rejected numeric(20,6) not null check(rejected>=0),rejection_reason text not null,
 check(accepted+rejected>0),check(rejected=0 or length(trim(rejection_reason)) between 1 and 500),
 unique(organisation_id,receipt_id,order_line_id),
 foreign key(organisation_id,order_id,receipt_id) references public.goods_receipts(organisation_id,order_id,id),
 foreign key(organisation_id,order_id,order_line_id) references public.purchase_order_lines(organisation_id,order_id,id)
);
create table public.goods_receipt_void_requests(
 id uuid primary key default gen_random_uuid(),organisation_id uuid not null,receipt_id uuid not null,request_id uuid not null,
 reason text not null check(length(trim(reason)) between 1 and 1000),state text not null default 'PENDING' check(state in ('PENDING','APPROVED','REJECTED')),
 created_by uuid not null references auth.users(id),created_label text not null,created_at timestamptz not null default statement_timestamp(),
 decided_by uuid references auth.users(id),decided_label text,decided_at timestamptz,decision_note text,
 unique(organisation_id,id),unique(organisation_id,request_id),foreign key(organisation_id,receipt_id) references public.goods_receipts(organisation_id,id)
);
create unique index pp_receipt_void_pending on public.goods_receipt_void_requests(organisation_id,receipt_id) where state='PENDING';
create unique index pp_delivery_reference on public.goods_receipts(organisation_id,order_id,lower(delivery_reference));
create table public.invoice_procurement_contexts(
 id uuid primary key default gen_random_uuid(),organisation_id uuid not null,purchase_id uuid not null,request_id uuid not null,
 version integer not null,invoice_revision integer not null,route text not null check(route in ('PO','DIRECT')),order_id uuid,
 reason text not null,evidence text not null,mappings jsonb not null,created_by uuid not null references auth.users(id),
 created_label text not null,created_at timestamptz not null default statement_timestamp(),
 check((route='PO' and order_id is not null) or(route='DIRECT' and order_id is null and length(trim(reason)) between 1 and 1000 and length(trim(evidence)) between 1 and 500)),
 unique(organisation_id,id),unique(organisation_id,purchase_id,version),unique(organisation_id,request_id),
 foreign key(organisation_id,purchase_id) references public.purchase_headers(organisation_id,id),
 foreign key(organisation_id,order_id) references public.purchase_orders(organisation_id,id)
);
create table public.purchase_batch_contexts(
 organisation_id uuid not null,batch_id uuid not null,context jsonb not null,mappings jsonb not null,
 primary key(organisation_id,batch_id),foreign key(organisation_id,batch_id) references public.purchase_import_batches(organisation_id,id)
);
create table public.invoice_exception_reviews(
 id uuid primary key default gen_random_uuid(),organisation_id uuid not null,purchase_id uuid not null,request_id uuid not null,
 fingerprint text not null,decision text not null check(decision in ('ACKNOWLEDGED','CORRECTION_REQUIRED')),
 note text not null check(length(trim(note)) between 1 and 1000),created_by uuid not null references auth.users(id),
 created_label text not null,created_at timestamptz not null default statement_timestamp(),
 unique(organisation_id,id),unique(organisation_id,request_id),foreign key(organisation_id,purchase_id) references public.purchase_headers(organisation_id,id)
);
create index pp_invoice_context_latest on public.invoice_procurement_contexts(organisation_id,purchase_id,version desc);
create index pp_invoice_context_order on public.invoice_procurement_contexts(organisation_id,order_id,purchase_id,version desc);
create index pp_receipts_order on public.goods_receipts(organisation_id,order_id);
create index pp_receipt_line_order on public.goods_receipt_lines(organisation_id,order_line_id);
create index pp_receipt_void_history on public.goods_receipt_void_requests(organisation_id,receipt_id,created_at desc,id);
create index pp_exception_review_history on public.invoice_exception_reviews(organisation_id,purchase_id,created_at desc,id);
do $$declare t text;begin
 foreach t in array array['purchase_orders','purchase_order_lines','goods_receipts','goods_receipt_lines','goods_receipt_void_requests','invoice_procurement_contexts','purchase_batch_contexts','invoice_exception_reviews'] loop
  execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);
 end loop;
end;$$;
create function private.pp_procurement_immutable() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'Confirmed procurement evidence cannot be changed or deleted.' using errcode='42501';end;$$;
revoke all on function private.pp_procurement_immutable() from public,anon,authenticated;
do $$declare t text;begin
 foreach t in array array['goods_receipts','goods_receipt_lines','invoice_procurement_contexts','invoice_exception_reviews','purchase_batch_contexts'] loop
  execute format('create trigger pp_immutable before update or delete on public.%I for each row execute function private.pp_procurement_immutable()',t);
 end loop;
end;$$;
create function private.pp_order_protect() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='purchase_orders' then
  if old.status='ISSUED' or tg_op='DELETE' then raise exception 'Issued orders cannot be edited or deleted.' using errcode='42501';end if;
 else
  if exists(select 1 from public.purchase_orders where organisation_id=coalesce(new.organisation_id,old.organisation_id) and id=coalesce(new.order_id,old.order_id) and status='ISSUED') or exists(select 1 from public.purchase_orders where organisation_id=old.organisation_id and id=old.order_id and status='ISSUED') then raise exception 'Issued order lines cannot be changed.' using errcode='42501';end if;
 end if;
 if tg_op='DELETE' then return old;end if;return new;
end;$$;
revoke all on function private.pp_order_protect() from public,anon,authenticated;
create trigger pp_order_protect before update or delete on public.purchase_orders for each row execute function private.pp_order_protect();
create trigger pp_order_line_protect before insert or update or delete on public.purchase_order_lines for each row execute function private.pp_order_protect();

create function public.save_purchase_order(p_organisation_id uuid,p_order_id uuid,p_request_id uuid,p_revision integer,p_document jsonb,p_lines jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare prior public.purchase_orders;result uuid;ref text;digest text;prepared jsonb;line jsonb;n integer:=0;due date;
begin
 if not private.pp_purchase_write(p_organisation_id) then raise exception 'Procurement access is required.' using errcode='42501';end if;
 if p_request_id is null or jsonb_typeof(p_document) is distinct from 'object' or octet_length(p_document::text)>8192 or length(coalesce(p_document->>'notes',''))>1000 then raise exception 'Check the order details.' using errcode='22023';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 digest:=md5(jsonb_build_array(p_document,p_lines)::text);
 select * into prior from public.purchase_orders where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then
  if prior.input_hash<>digest or prior.created_by<>auth.uid() or (p_order_id is not null and p_order_id<>prior.id) then raise exception 'This save request was already used. Refresh before changing the order.' using errcode='22023';end if;return prior.id;
 end if;
 if p_order_id is not null then
  select * into prior from public.purchase_orders where organisation_id=p_organisation_id and id=p_order_id for update;
  if not found then raise exception 'Order unavailable.' using errcode='42501';end if;
  if prior.status<>'DRAFT' or p_revision is distinct from prior.revision then raise exception 'This draft changed or was already issued. Refresh to review it.' using errcode='22023';end if;
  result:=prior.id;ref:=prior.reference;
 else result:=gen_random_uuid();ref:='PO-'||upper(substr(replace(result::text,'-',''),1,12));end if;
 begin due:=nullif(p_document->>'needed_by','')::date;exception when others then raise exception 'Choose a valid delivery-needed date.' using errcode='22023';end;
 prepared:=private.pp_prepare_invoice(p_organisation_id,p_document||jsonb_build_object('reference',ref),p_lines,'ORDER_'||result::text);
 if due is not null and due<(prepared->'header'->>'date')::date then raise exception 'Delivery-needed date cannot precede the order date.' using errcode='22023';end if;
 if p_order_id is null then
  insert into public.purchase_orders(id,organisation_id,reference,request_id,input_hash,input_document,input_lines,supplier_id,location_id,document_date,needed_by,notes,payload,created_by,created_label)
  values(result,p_organisation_id,ref,p_request_id,digest,p_document,p_lines,(prepared->'header'->>'supplier_id')::uuid,(prepared->'header'->>'location_id')::uuid,(prepared->'header'->>'date')::date,due,coalesce(p_document->>'notes',''),prepared-'csv'-'report',auth.uid(),coalesce((select email from auth.users where id=auth.uid()),auth.uid()::text));
 else
  update public.purchase_orders set request_id=p_request_id,input_hash=digest,input_document=p_document,input_lines=p_lines,supplier_id=(prepared->'header'->>'supplier_id')::uuid,location_id=(prepared->'header'->>'location_id')::uuid,document_date=(prepared->'header'->>'date')::date,needed_by=due,notes=coalesce(p_document->>'notes',''),payload=prepared-'csv'-'report',revision=revision+1 where id=result;
  delete from public.purchase_order_lines where organisation_id=p_organisation_id and order_id=result;
 end if;
 for line in select value from jsonb_array_elements(prepared->'lines') loop
  n:=n+1;insert into public.purchase_order_lines(organisation_id,order_id,position,item_id,uom_id,quantity,payload) values(p_organisation_id,result,n,(line->>'item_id')::uuid,(line->>'uom_id')::uuid,(line->>'quantity')::numeric,line);
 end loop;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id) values(p_organisation_id,'PURCHASE_ORDER_SAVED',auth.uid(),result);return result;
end;$$;
create function public.issue_purchase_order(p_organisation_id uuid,p_order_id uuid,p_revision integer,p_confirmed boolean) returns void
language plpgsql security definer set search_path='' as $$
declare doc public.purchase_orders;prepared jsonb;
begin
 if not private.pp_purchase_write(p_organisation_id) then raise exception 'Procurement access is required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into doc from public.purchase_orders where organisation_id=p_organisation_id and id=p_order_id for update;
 if not found then raise exception 'Order unavailable.' using errcode='42501';end if;
 if p_confirmed is distinct from true then raise exception 'Confirm the order before issuing.' using errcode='22023';end if;
 if doc.status='ISSUED' then
  if p_revision=doc.revision-1 then return;end if;raise exception 'This order was already issued.' using errcode='22023';end if;
 if p_revision is distinct from doc.revision then raise exception 'This draft changed. Refresh before issuing.' using errcode='22023';end if;
 prepared:=private.pp_prepare_invoice(p_organisation_id,doc.input_document||jsonb_build_object('reference',doc.reference),doc.input_lines,'ORDER_'||doc.id::text);
 if doc.payload is distinct from prepared-'csv'-'report' then raise exception 'Catalogue or quotation details changed. Review and save the draft again before issuing.' using errcode='22023';end if;
 update public.purchase_orders set status='ISSUED',revision=revision+1,issued_by=auth.uid(),issued_label=coalesce((select email from auth.users where id=auth.uid()),auth.uid()::text),issued_at=clock_timestamp() where id=doc.id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id) values(p_organisation_id,'PURCHASE_ORDER_ISSUED',auth.uid(),doc.id);
end;$$;

create function private.pp_receipt_voided(target_org uuid,target_receipt uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.goods_receipt_void_requests where organisation_id=target_org and receipt_id=target_receipt and state='APPROVED');
$$;
revoke all on function private.pp_receipt_voided(uuid,uuid) from public,anon,authenticated;
create function public.record_goods_receipt(p_organisation_id uuid,p_order_id uuid,p_request_id uuid,p_document jsonb,p_lines jsonb,p_confirmed boolean)
returns uuid language plpgsql security definer set search_path='' as $$
declare doc public.purchase_orders;prior public.goods_receipts;line jsonb;ordered public.purchase_order_lines;result uuid:=gen_random_uuid();digest text;day date;accepted numeric;rejected numeric;previous_qty numeric;seen uuid[]:='{}';
begin
 if not private.pp_purchase_write(p_organisation_id) then raise exception 'Procurement access is required.' using errcode='42501';end if;
 if p_request_id is null or p_confirmed is distinct from true or jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) not between 1 and 50 or octet_length(p_lines::text)>65536 or length(trim(coalesce(p_document->>'delivery_reference',''))) not between 1 and 100 or length(coalesce(p_document->>'notes',''))>1000 then raise exception 'Confirm delivery and enter a delivery reference with up to 50 lines.' using errcode='22023';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into doc from public.purchase_orders where organisation_id=p_organisation_id and id=p_order_id and status='ISSUED';
 if not found then raise exception 'Choose an issued order in this business.' using errcode='42501';end if;
 digest:=md5(jsonb_build_array(p_order_id,p_document,p_lines)::text);
 select * into prior from public.goods_receipts where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then if prior.input_hash<>digest or prior.created_by<>auth.uid() then raise exception 'This delivery request was already used.' using errcode='22023';end if;return prior.id;end if;
 begin day:=(p_document->>'date')::date;exception when others then raise exception 'Choose a valid received date.' using errcode='22023';end;
 if day is null or day<doc.document_date or day>(select(now() at time zone time_zone)::date from public.organisations where id=p_organisation_id) then raise exception 'Delivery date must be from the order date through the current business date.' using errcode='22023';end if;
 if exists(select 1 from public.goods_receipts where organisation_id=p_organisation_id and order_id=p_order_id and lower(delivery_reference)=lower(trim(p_document->>'delivery_reference'))) then raise exception 'This delivery reference is already recorded for this order.' using errcode='22023';end if;
 insert into public.goods_receipts(id,organisation_id,order_id,request_id,reference,received_on,delivery_reference,notes,input_hash,created_by,created_label)
 values(result,p_organisation_id,p_order_id,p_request_id,'GRN-'||upper(substr(replace(result::text,'-',''),1,12)),day,trim(p_document->>'delivery_reference'),coalesce(p_document->>'notes',''),digest,auth.uid(),coalesce((select email from auth.users where id=auth.uid()),auth.uid()::text));
 for line in select value from jsonb_array_elements(p_lines) loop
  if coalesce(line->>'accepted','')!~'^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' or coalesce(line->>'rejected','')!~'^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' then raise exception 'Enter accepted and rejected quantities with up to six decimal places.' using errcode='22023';end if;
  accepted:=(line->>'accepted')::numeric;rejected:=(line->>'rejected')::numeric;
  begin select * into ordered from public.purchase_order_lines where organisation_id=p_organisation_id and order_id=p_order_id and id=(line->>'order_line_id')::uuid;exception when invalid_text_representation then raise exception 'Choose a valid order line.' using errcode='22023';end;
  if ordered.id is null or ordered.id=any(seen) then raise exception 'Each delivery line must refer to a different line of this order.' using errcode='22023';end if;seen:=array_append(seen,ordered.id);
  if accepted+rejected<=0 or length(coalesce(line->>'reason',''))>500 or(rejected>0 and trim(coalesce(line->>'reason',''))='') then raise exception 'Enter a received quantity and explain rejected goods.' using errcode='22023';end if;
  select coalesce(sum(l.accepted),0) into previous_qty from public.goods_receipt_lines l where l.organisation_id=p_organisation_id and l.order_line_id=ordered.id and not private.pp_receipt_voided(p_organisation_id,l.receipt_id);
  if accepted+previous_qty>ordered.quantity then raise exception 'Accepted quantities exceed the remaining ordered quantity. Record excess goods as rejected, with a reason.' using errcode='22023';end if;
  insert into public.goods_receipt_lines(organisation_id,receipt_id,order_id,order_line_id,accepted,rejected,rejection_reason) values(p_organisation_id,result,p_order_id,ordered.id,accepted,rejected,coalesce(line->>'reason',''));
 end loop;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'GOODS_RECEIPT_CONFIRMED',auth.uid(),result,jsonb_build_object('order_id',p_order_id));return result;
end;$$;

create function public.review_goods_receipt_void(p_organisation_id uuid,p_receipt_id uuid,p_request_id uuid,p_reason text,p_decision text,p_note text)
returns uuid language plpgsql security definer set search_path='' as $$
declare prior public.goods_receipt_void_requests;result uuid;
begin
 if p_decision='REQUEST' then
  if not private.pp_purchase_write(p_organisation_id) then raise exception 'Procurement access is required.' using errcode='42501';end if;
 else if not private.pp_finance(p_organisation_id) then raise exception 'Finance must decide delivery corrections.' using errcode='42501';end if;end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if not exists(select 1 from public.goods_receipts where organisation_id=p_organisation_id and id=p_receipt_id) then raise exception 'GRN unavailable.' using errcode='42501';end if;
 if p_decision='REQUEST' then
  if p_request_id is null or length(trim(coalesce(p_reason,''))) not between 1 and 1000 then raise exception 'Enter a reason for voiding the GRN.' using errcode='22023';end if;
  select * into prior from public.goods_receipt_void_requests where organisation_id=p_organisation_id and request_id=p_request_id;
  if found then if prior.receipt_id<>p_receipt_id or prior.reason<>trim(p_reason) or prior.created_by<>auth.uid() then raise exception 'This request was already used.' using errcode='22023';end if;return prior.id;end if;
  if exists(select 1 from public.goods_receipt_void_requests where organisation_id=p_organisation_id and receipt_id=p_receipt_id and state in ('PENDING','APPROVED')) then raise exception 'This GRN is already voided or awaiting a void decision.' using errcode='22023';end if;
  insert into public.goods_receipt_void_requests(organisation_id,receipt_id,request_id,reason,created_by,created_label) values(p_organisation_id,p_receipt_id,p_request_id,trim(p_reason),auth.uid(),coalesce((select email from auth.users where id=auth.uid()),auth.uid()::text)) returning id into result;
 else
  if p_decision is null or p_decision not in ('APPROVE','REJECT') or length(trim(coalesce(p_note,''))) not between 1 and 1000 then raise exception 'Choose a decision and enter its reason.' using errcode='22023';end if;
  select * into prior from public.goods_receipt_void_requests where organisation_id=p_organisation_id and receipt_id=p_receipt_id and id=p_request_id for update;
  if not found then raise exception 'GRN correction unavailable.' using errcode='42501';end if;
  if prior.state<>'PENDING' then
   if prior.decided_by=auth.uid() and prior.state=(case when p_decision='APPROVE' then 'APPROVED' else 'REJECTED' end) and prior.decision_note=trim(p_note) then return prior.id;end if;
   raise exception 'This GRN correction was already decided. Refresh to review its status.' using errcode='22023';end if;
  update public.goods_receipt_void_requests set state=case when p_decision='APPROVE' then 'APPROVED' else 'REJECTED' end,decided_by=auth.uid(),decided_label=coalesce((select email from auth.users where id=auth.uid()),auth.uid()::text),decided_at=clock_timestamp(),decision_note=trim(p_note) where id=prior.id;result:=prior.id;
 end if;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'GRN_VOID_REVIEW',auth.uid(),p_receipt_id,jsonb_build_object('request_id',result,'decision',p_decision));return result;
end;$$;
create function private.pp_delivery_correction_protect() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='DELETE' then raise exception 'GRN correction history cannot be deleted.' using errcode='42501';end if;
 if old.state<>'PENDING' or new.state not in ('APPROVED','REJECTED') or (to_jsonb(old)-'state'-'decided_by'-'decided_label'-'decided_at'-'decision_note') is distinct from (to_jsonb(new)-'state'-'decided_by'-'decided_label'-'decided_at'-'decision_note') then raise exception 'GRN correction evidence cannot be rewritten.' using errcode='42501';end if;return new;
end;$$;
revoke all on function private.pp_delivery_correction_protect() from public,anon,authenticated;
create trigger pp_delivery_correction_protect before update or delete on public.goods_receipt_void_requests for each row execute function private.pp_delivery_correction_protect();

create function public.get_purchase_order(p_organisation_id uuid,p_order_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare doc jsonb;lines jsonb;receipts jsonb;
begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Purchase access denied.' using errcode='42501';end if;
 select to_jsonb(o)-'input_hash'-'request_id' into doc from public.purchase_orders o where organisation_id=p_organisation_id and id=p_order_id;
 if doc is null then raise exception 'Order unavailable.' using errcode='42501';end if;
 select coalesce(jsonb_agg(l.payload||jsonb_build_object('id',l.id,'accepted',coalesce((select sum(r.accepted) from public.goods_receipt_lines r where r.organisation_id=p_organisation_id and r.order_line_id=l.id and not private.pp_receipt_voided(p_organisation_id,r.receipt_id)),0)::text,'remaining',(l.quantity-coalesce((select sum(r.accepted) from public.goods_receipt_lines r where r.organisation_id=p_organisation_id and r.order_line_id=l.id and not private.pp_receipt_voided(p_organisation_id,r.receipt_id)),0))::text) order by l.position),'[]') into lines from public.purchase_order_lines l where l.organisation_id=p_organisation_id and l.order_id=p_order_id;
 select coalesce(jsonb_agg(to_jsonb(g)||jsonb_build_object('voided',private.pp_receipt_voided(p_organisation_id,g.id),'void_requests',coalesce((select jsonb_agg(to_jsonb(v) order by v.created_at desc,v.id) from public.goods_receipt_void_requests v where v.organisation_id=p_organisation_id and v.receipt_id=g.id),'[]'),
  'lines',(select jsonb_agg(to_jsonb(r)||jsonb_build_object('item_name',l.payload->>'item_name','unit_code',l.payload->>'unit_code') order by l.position) from public.goods_receipt_lines r join public.purchase_order_lines l on l.organisation_id=r.organisation_id and l.order_id=r.order_id and l.id=r.order_line_id where r.organisation_id=p_organisation_id and r.receipt_id=g.id)) order by g.created_at desc,g.id),'[]') into receipts from public.goods_receipts g where g.organisation_id=p_organisation_id and g.order_id=p_order_id;
 return jsonb_build_object('order',doc,'lines',lines,'receipts',receipts);
end;$$;
create function public.list_purchase_orders(p_organisation_id uuid,p_page integer) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;
begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Purchase access denied.' using errcode='42501';end if;
 if p_page is null or p_page not between 1 and 100000 then raise exception 'Choose a valid order page.' using errcode='22023';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'reference',reference,'status',status,'date',document_date,'header',payload->'header') order by created_at desc,id),'[]') into rows from (select * from public.purchase_orders where organisation_id=p_organisation_id order by created_at desc,id limit 20 offset(p_page-1)*20)s;
 return jsonb_build_object('total',(select count(*) from public.purchase_orders where organisation_id=p_organisation_id),'orders',rows);
end;$$;
create function public.purchase_order_choices(p_organisation_id uuid,p_search text default '',p_selected uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Purchase access denied.' using errcode='42501';end if;
 if length(coalesce(p_search,''))>100 then raise exception 'Search with up to 100 characters.' using errcode='22023';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'reference',o.reference,'header',o.payload->'header','lines',(select jsonb_agg(jsonb_build_object('id',l.id,'item_id',l.item_id,'item_name',l.payload->>'item_name','uom_id',l.uom_id,'unit_code',l.payload->>'unit_code','quantity',l.payload->>'quantity','unit_price',l.payload->>'unit_price','line_discount',l.payload->>'line_discount','tax',l.payload->>'tax') order by l.position) from public.purchase_order_lines l where l.organisation_id=o.organisation_id and l.order_id=o.id)) order by(o.id is distinct from p_selected),o.issued_at desc,o.id) from (
 select * from public.purchase_orders where organisation_id=p_organisation_id and status='ISSUED' and(coalesce(trim(p_search),'')='' or reference ilike '%'||trim(p_search)||'%' or payload->'header'->>'supplier_name' ilike '%'||trim(p_search)||'%' or id=p_selected)
 order by(id is distinct from p_selected),issued_at desc,id limit 50)o),'[]');
end;$$;
-- Invoice classification and matching are added in migration 019.
revoke all on function public.save_purchase_order(uuid,uuid,uuid,integer,jsonb,jsonb),public.issue_purchase_order(uuid,uuid,integer,boolean),public.record_goods_receipt(uuid,uuid,uuid,jsonb,jsonb,boolean),public.review_goods_receipt_void(uuid,uuid,uuid,text,text,text),public.get_purchase_order(uuid,uuid),public.list_purchase_orders(uuid,integer),public.purchase_order_choices(uuid,text,uuid) from public,anon;
grant execute on function public.save_purchase_order(uuid,uuid,uuid,integer,jsonb,jsonb),public.issue_purchase_order(uuid,uuid,integer,boolean),public.record_goods_receipt(uuid,uuid,uuid,jsonb,jsonb,boolean),public.review_goods_receipt_void(uuid,uuid,uuid,text,text,text),public.get_purchase_order(uuid,uuid),public.list_purchase_orders(uuid,integer),public.purchase_order_choices(uuid,text,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
