-- Apply ONCE after 018. Operational matching and Finance exception acknowledgement, not payment approval.
begin;
create table public.invoice_procurement_lines(
 organisation_id uuid not null,context_id uuid not null,order_id uuid not null,invoice_line integer not null check(invoice_line between 1 and 100),order_line_id uuid,
 primary key(organisation_id,context_id,invoice_line),foreign key(organisation_id,context_id) references public.invoice_procurement_contexts(organisation_id,id),
 foreign key(organisation_id,order_id,order_line_id) references public.purchase_order_lines(organisation_id,order_id,id)
);
alter table public.invoice_procurement_lines enable row level security;
revoke all on public.invoice_procurement_lines from public,anon,authenticated;
create trigger pp_immutable before update or delete on public.invoice_procurement_lines for each row execute function private.pp_procurement_immutable();

create function private.pp_invoice_context_check(target_org uuid,invoice jsonb,context jsonb,mappings jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare po public.purchase_orders;row jsonb;n integer;seen integer[]:='{}';mapped uuid;clean jsonb:='[]';
begin
 if jsonb_typeof(context) is distinct from 'object' or octet_length(context::text)>8192 or context->>'route' is null or context->>'route' not in ('PO','DIRECT') then raise exception 'Choose a PO-backed purchase or a purchase without PO.' using errcode='22023';end if;
 if context->>'route'='DIRECT' then
  if length(trim(coalesce(context->>'reason',''))) not between 1 and 1000 or length(trim(coalesce(context->>'evidence',''))) not between 1 and 500 then raise exception 'A purchase without PO needs a reason and an evidence reference.' using errcode='22023';end if;
  return jsonb_build_object('route','DIRECT','order_id',null,'reason',trim(context->>'reason'),'evidence',trim(context->>'evidence'),'mappings','[]'::jsonb);
 end if;
 begin select * into po from public.purchase_orders where organisation_id=target_org and id=(context->>'order_id')::uuid and status='ISSUED';exception when invalid_text_representation then raise exception 'Choose an issued PO.' using errcode='22023';end;
 if po.id is null then raise exception 'Choose an issued PO in this business.' using errcode='22023';end if;
 if invoice->'header'->>'supplier_id'<>po.supplier_id::text or invoice->'header'->>'location_id'<>po.location_id::text or invoice->'header'->>'currency'<>po.payload->'header'->>'currency' then raise exception 'The invoice supplier, outlet and currency must match the selected PO. Record a source correction or choose the correct PO.' using errcode='22023';end if;
 if jsonb_typeof(mappings) is distinct from 'array' or jsonb_array_length(mappings)>100 or octet_length(mappings::text)>16384 then raise exception 'Check the invoice-to-order line links.' using errcode='22023';end if;
 for row in select value from jsonb_array_elements(mappings) loop
  begin n:=(row->>'line')::integer;mapped:=nullif(row->>'order_line_id','')::uuid;exception when others then raise exception 'Check the invoice-to-order line links.' using errcode='22023';end;
  if n is null or n not between 1 and jsonb_array_length(invoice->'lines') or n=any(seen) then raise exception 'Each invoice line can have only one PO line link.' using errcode='22023';end if;seen:=array_append(seen,n);
  if mapped is not null and not exists(select 1 from public.purchase_order_lines where organisation_id=target_org and order_id=po.id and id=mapped) then raise exception 'A linked line does not belong to the selected PO.' using errcode='42501';end if;
  clean:=clean||jsonb_build_array(jsonb_build_object('line',n,'order_line_id',mapped));
 end loop;
 return jsonb_build_object('route','PO','order_id',po.id,'reason','','evidence','','mappings',clean);
end;$$;
revoke all on function private.pp_invoice_context_check(uuid,jsonb,jsonb,jsonb) from public,anon,authenticated;

create function public.set_invoice_procurement_context(p_organisation_id uuid,p_purchase_id uuid,p_request_id uuid,p_invoice_revision integer,p_context jsonb,p_mappings jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare invoice jsonb;clean jsonb;prior public.invoice_procurement_contexts;result uuid;version integer;row jsonb;
begin
 if not private.pp_purchase_write(p_organisation_id) then raise exception 'Procurement must provide the invoice links or no-PO reason.' using errcode='42501';end if;
 if p_request_id is null then raise exception 'Refresh before saving invoice links.' using errcode='22023';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 invoice:=private.pp_current_invoice(p_organisation_id,p_purchase_id);
 clean:=private.pp_invoice_context_check(p_organisation_id,invoice,p_context,p_mappings);
 select * into prior from public.invoice_procurement_contexts where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then
  if prior.purchase_id<>p_purchase_id or prior.invoice_revision is distinct from p_invoice_revision or prior.created_by<>auth.uid() or prior.route<>clean->>'route' or prior.order_id is distinct from (clean->>'order_id')::uuid or prior.reason<>clean->>'reason' or prior.evidence<>clean->>'evidence' or prior.mappings<>clean->'mappings' then raise exception 'This link request was already used. Refresh to review current links.' using errcode='22023';end if;return prior.id;
 end if;
 if (invoice->>'voided')::boolean or p_invoice_revision is distinct from (invoice->>'revision')::integer then raise exception 'The invoice changed or was voided. Refresh before linking it.' using errcode='22023';end if;
 select coalesce(max(c.version),0)+1 into version from public.invoice_procurement_contexts c where organisation_id=p_organisation_id and purchase_id=p_purchase_id;
 insert into public.invoice_procurement_contexts(organisation_id,purchase_id,request_id,version,invoice_revision,route,order_id,reason,evidence,mappings,created_by,created_label)
 values(p_organisation_id,p_purchase_id,p_request_id,version,p_invoice_revision,clean->>'route',(clean->>'order_id')::uuid,clean->>'reason',clean->>'evidence',clean->'mappings',auth.uid(),coalesce((select email from auth.users where id=auth.uid()),auth.uid()::text)) returning id into result;
 if clean->>'route'='PO' then
  for row in select value from jsonb_array_elements(clean->'mappings') loop
   insert into public.invoice_procurement_lines(organisation_id,context_id,order_id,invoice_line,order_line_id) values(p_organisation_id,result,(clean->>'order_id')::uuid,(row->>'line')::integer,(row->>'order_line_id')::uuid);
  end loop;
 end if;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'INVOICE_PROCUREMENT_LINKED',auth.uid(),p_purchase_id,jsonb_build_object('context_id',result,'version',version));return result;
end;$$;

-- Keep the existing source validation/posting engines and wrap only the public entry points.
alter function public.stage_manual_purchase(uuid,uuid,jsonb,jsonb) rename to pp_stage_manual_purchase_017;
alter function public.pp_stage_manual_purchase_017(uuid,uuid,jsonb,jsonb) set schema private;
revoke all on function private.pp_stage_manual_purchase_017(uuid,uuid,jsonb,jsonb) from public,anon,authenticated;
create function public.stage_manual_purchase(p_organisation_id uuid,p_request_id uuid,p_invoice jsonb,p_lines jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare prepared jsonb;clean jsonb;maps jsonb;result uuid;prior public.purchase_batch_contexts;
begin
 if not private.pp_purchase_write(p_organisation_id) then raise exception 'Procurement access is required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 prepared:=private.pp_prepare_invoice(p_organisation_id,p_invoice,p_lines,'MANUAL_INVOICE');
 select coalesce(jsonb_agg(jsonb_build_object('line',ord,'order_line_id',nullif(value->>'po_line_id','')) order by ord),'[]') into maps from jsonb_array_elements(p_lines) with ordinality a(value,ord);
 clean:=private.pp_invoice_context_check(p_organisation_id,prepared,jsonb_build_object('route',p_invoice->>'route','order_id',p_invoice->>'order_id','reason',p_invoice->>'direct_reason','evidence',p_invoice->>'evidence'),maps);
 result:=private.pp_stage_manual_purchase_017(p_organisation_id,p_request_id,p_invoice,p_lines);
 select * into prior from public.purchase_batch_contexts where organisation_id=p_organisation_id and batch_id=result;
 if found then
  if prior.context is distinct from clean-'mappings' or prior.mappings is distinct from clean->'mappings' then raise exception 'The saved invoice route differs. Refresh before changing an entry request.' using errcode='22023';end if;
 else insert into public.purchase_batch_contexts(organisation_id,batch_id,context,mappings) values(p_organisation_id,result,clean-'mappings',clean->'mappings');end if;
 return result;
end;$$;
alter function public.post_purchase_import(uuid,uuid,jsonb) rename to pp_post_purchase_import_017;
alter function public.pp_post_purchase_import_017(uuid,uuid,jsonb) set schema private;
revoke all on function private.pp_post_purchase_import_017(uuid,uuid,jsonb) from public,anon,authenticated;
create function public.post_purchase_import(p_organisation_id uuid,p_batch_id uuid,p_controls jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;context public.purchase_batch_contexts;purchase_id uuid;invoice jsonb;
begin
 if not private.pp_purchase_write(p_organisation_id) then raise exception 'Procurement access is required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 result:=private.pp_post_purchase_import_017(p_organisation_id,p_batch_id,p_controls);
 if (result->>'posted')::boolean then
  select * into context from public.purchase_batch_contexts where organisation_id=p_organisation_id and batch_id=p_batch_id;
  if found and not exists(select 1 from public.invoice_procurement_contexts where organisation_id=p_organisation_id and request_id=p_batch_id) then
   select id into purchase_id from public.purchase_headers where organisation_id=p_organisation_id and import_batch_id=p_batch_id order by id limit 1;
   if purchase_id is not null then invoice:=private.pp_current_invoice(p_organisation_id,purchase_id);
    perform public.set_invoice_procurement_context(p_organisation_id,purchase_id,p_batch_id,(invoice->>'revision')::integer,context.context,context.mappings);
   end if;
  end if;
 end if;return result;
end;$$;

create function public.purchase_invoice_matching(p_organisation_id uuid,p_purchase_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare invoice jsonb;ctx public.invoice_procurement_contexts;po public.purchase_orders;exceptions jsonb:='[]';comparison jsonb:='[]';receipts jsonb:='[]';others jsonb:='[]';
 row jsonb;mapped public.purchase_order_lines;line_number integer:=0;mapping jsonb;accepted numeric;billed numeric;ordered numeric;pending integer;blocked boolean:=false;
 fingerprint text;review public.invoice_exception_reviews;other record;other_invoice jsonb;status text;
begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Purchase access denied.' using errcode='42501';end if;
 invoice:=private.pp_current_invoice(p_organisation_id,p_purchase_id);
 select * into ctx from public.invoice_procurement_contexts where organisation_id=p_organisation_id and purchase_id=p_purchase_id order by version desc limit 1;
 if (invoice->>'voided')::boolean then exceptions:=exceptions||jsonb_build_array('This invoice is voided.');blocked:=true;end if;
 select count(*)::integer into pending from public.purchase_corrections where organisation_id=p_organisation_id and purchase_id=p_purchase_id and state='PENDING';
 if pending>0 then exceptions:=exceptions||jsonb_build_array('A financial correction is awaiting Finance approval. Resolve it before acknowledging invoice exceptions.');blocked:=true;end if;
 if ctx.id is null then exceptions:=exceptions||jsonb_build_array('Procurement has not declared a PO link or a purchase-without-PO reason.');blocked:=true;
 elsif ctx.invoice_revision<>(invoice->>'revision')::integer then exceptions:=exceptions||jsonb_build_array('The invoice was corrected after its links were saved. Procurement must review and save the links again.');blocked:=true;
 elsif ctx.route='DIRECT' then exceptions:=exceptions||jsonb_build_array('Purchase without PO: review the recorded reason and evidence reference. Delivery and payment are not confirmed by this bill.');
 else
  select * into po from public.purchase_orders where organisation_id=p_organisation_id and id=ctx.order_id;
  if (invoice->'header'->>'date')::date<po.document_date then exceptions:=exceptions||jsonb_build_array('The supplier invoice is dated before the linked Purchase Order.');end if;
  if invoice->'header'->>'supplier_id'<>po.supplier_id::text or invoice->'header'->>'location_id'<>po.location_id::text or invoice->'header'->>'currency'<>po.payload->'header'->>'currency' then exceptions:=exceptions||jsonb_build_array('The invoice supplier, outlet or currency differs from the linked PO.');blocked:=true;end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',g.id,'reference',g.reference,'date',g.received_on,'voided',private.pp_receipt_voided(p_organisation_id,g.id),
   'lines',(select jsonb_agg(jsonb_build_array(l.order_line_id,l.accepted::text,l.rejected::text) order by l.order_line_id) from public.goods_receipt_lines l where l.organisation_id=p_organisation_id and l.receipt_id=g.id),
   'corrections',coalesce((select jsonb_agg(jsonb_build_array(v.id,v.state,v.decided_at) order by v.created_at,v.id) from public.goods_receipt_void_requests v where v.organisation_id=p_organisation_id and v.receipt_id=g.id),'[]')) order by g.id),'[]') into receipts from public.goods_receipts g where g.organisation_id=p_organisation_id and g.order_id=po.id;
  if exists(select 1 from public.goods_receipt_void_requests v join public.goods_receipts g on g.organisation_id=v.organisation_id and g.id=v.receipt_id where v.organisation_id=p_organisation_id and g.order_id=po.id and v.state='PENDING') then exceptions:=exceptions||jsonb_build_array('A GRN void request is awaiting Finance review. Resolve the delivery correction first.');blocked:=true;end if;
  for other in select c.* from public.invoice_procurement_contexts c where c.organisation_id=p_organisation_id and c.order_id=po.id and c.id=(select x.id from public.invoice_procurement_contexts x where x.organisation_id=c.organisation_id and x.purchase_id=c.purchase_id order by x.version desc limit 1) order by c.purchase_id loop
   other_invoice:=private.pp_current_invoice(p_organisation_id,other.purchase_id);
   if (other_invoice->>'voided')::boolean then continue;end if;
   others:=others||jsonb_build_array(jsonb_build_object('purchase_id',other.purchase_id,'context_id',other.id,'invoice',other_invoice,'mappings',other.mappings));
   if other.invoice_revision<>(other_invoice->>'revision')::integer then exceptions:=exceptions||jsonb_build_array('Another invoice against this PO has stale links after a correction. Review its links before relying on cumulative quantities.');blocked:=true;end if;
  end loop;
  for row in select value from jsonb_array_elements(invoice->'lines') loop
   line_number:=line_number+1;select value into mapping from jsonb_array_elements(ctx.mappings) where (value->>'line')::integer=line_number;
   select * into mapped from public.purchase_order_lines where organisation_id=p_organisation_id and order_id=po.id and id=(mapping->>'order_line_id')::uuid;
   if mapped.id is null then exceptions:=exceptions||jsonb_build_array(format('Invoice line %s has no linked PO line.',line_number));continue;end if;
   if row->>'item_id'<>mapped.item_id::text then exceptions:=exceptions||jsonb_build_array(format('Invoice line %s bills a different material from its PO line.',line_number));end if;
   if row->>'uom_id'<>mapped.uom_id::text then exceptions:=exceptions||jsonb_build_array(format('Invoice line %s uses a different unit. Quantity comparisons use the saved base-unit conversions.',line_number));end if;
   ordered:=(mapped.payload->>'base_quantity')::numeric;
   select coalesce(sum(l.accepted*(mapped.payload->>'conversion_factor')::numeric),0) into accepted from public.goods_receipt_lines l where l.organisation_id=p_organisation_id and l.order_line_id=mapped.id and not private.pp_receipt_voided(p_organisation_id,l.receipt_id);
   select coalesce(sum((li.value->>'base_quantity')::numeric),0) into billed from jsonb_array_elements(others) o cross join lateral jsonb_array_elements(o.value->'invoice'->'lines') with ordinality li(value,ord)
    where exists(select 1 from jsonb_array_elements(o.value->'mappings') m where (m.value->>'line')::integer=li.ord and m.value->>'order_line_id'=mapped.id::text);
   if billed>ordered then exceptions:=exceptions||jsonb_build_array(format('Invoice line %s: cumulative billed quantity exceeds the ordered quantity.',line_number));end if;
   if billed>accepted then exceptions:=exceptions||jsonb_build_array(format('Invoice line %s: cumulative billed quantity exceeds accepted deliveries.',line_number));end if;
   if (row->>'net_amount')::numeric*ordered<>(mapped.payload->>'net_amount')::numeric*(row->>'base_quantity')::numeric then exceptions:=exceptions||jsonb_build_array(format('Invoice line %s: the price after discount, excluding tax, differs from the PO.',line_number));end if;
   if (row->>'tax')::numeric*ordered<>(mapped.payload->>'tax')::numeric*(row->>'base_quantity')::numeric then exceptions:=exceptions||jsonb_build_array(format('Invoice line %s: tax per base unit differs from the PO.',line_number));end if;
   comparison:=comparison||jsonb_build_array(jsonb_build_object('line',line_number,'item',row->>'item_name','unit',mapped.payload->>'base_unit_code','ordered',ordered::text,'accepted',accepted::text,'billed',billed::text));
  end loop;
 end if;
 fingerprint:=encode(sha256(convert_to(jsonb_build_array(invoice,ctx.id,ctx.version,ctx.invoice_revision,ctx.route,ctx.order_id,ctx.reason,ctx.evidence,ctx.mappings,po.payload,receipts,others,pending)::text,'UTF8')),'hex');
 select * into review from public.invoice_exception_reviews where organisation_id=p_organisation_id and purchase_id=p_purchase_id order by created_at desc,id desc limit 1;
 status:=case when blocked then 'ACTION_REQUIRED' when jsonb_array_length(exceptions)=0 then 'MATCHED' when review.fingerprint=fingerprint and review.decision='ACKNOWLEDGED' then 'EXCEPTIONS_REVIEWED' when review.fingerprint=fingerprint and review.decision='CORRECTION_REQUIRED' then 'CORRECTION_REQUIRED' else 'NEEDS_FINANCE_REVIEW' end;
 return jsonb_build_object('context',case when ctx.id is null then null else to_jsonb(ctx) end,'order_reference',po.reference,'invoice_revision',invoice->'revision','exceptions',exceptions,'comparisons',comparison,'receipts',receipts,'fingerprint',fingerprint,'blocked',blocked,'status',status,
  'review',case when review.id is null then null else to_jsonb(review)||jsonb_build_object('valid',review.fingerprint=fingerprint) end,
  'history',jsonb_build_object('contexts',coalesce((select jsonb_agg(to_jsonb(c) order by c.version desc) from(select * from public.invoice_procurement_contexts where organisation_id=p_organisation_id and purchase_id=p_purchase_id order by version desc limit 20)c),'[]'),
  'reviews',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc,r.id) from(select * from public.invoice_exception_reviews where organisation_id=p_organisation_id and purchase_id=p_purchase_id order by created_at desc,id limit 20)r),'[]')));
end;$$;
create or replace function public.purchase_invoice_list(p_organisation_id uuid,p_page integer) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;total integer;
begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Purchase access denied.' using errcode='42501';end if;
 if p_page is null or p_page not between 1 and 100000 then raise exception 'Choose a valid invoice page.' using errcode='22023';end if;
 select count(*)::integer into total from public.purchase_headers where organisation_id=p_organisation_id;
 select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'invoice',s.current_value,'pending',(select count(*) from public.purchase_corrections c where c.organisation_id=p_organisation_id and c.purchase_id=s.id and c.state='PENDING'),'matching_status',s.matching->>'status','exception_count',jsonb_array_length(s.matching->'exceptions')) order by s.created_at desc,s.id),'[]') into rows from (
 select h.id,h.created_at,private.pp_current_invoice(p_organisation_id,h.id)-'lines' as current_value,public.purchase_invoice_matching(p_organisation_id,h.id) as matching from public.purchase_headers h where organisation_id=p_organisation_id order by h.created_at desc,h.id limit 20 offset(p_page-1)*20)s;
 return jsonb_build_object('total',total,'invoices',rows);
end;$$;
create function public.review_invoice_exceptions(p_organisation_id uuid,p_purchase_id uuid,p_request_id uuid,p_fingerprint text,p_decision text,p_note text,p_confirmed boolean) returns uuid
language plpgsql security definer set search_path='' as $$
declare matching jsonb;prior public.invoice_exception_reviews;result uuid;
begin
 if not private.pp_finance(p_organisation_id) then raise exception 'Finance must review invoice exceptions.' using errcode='42501';end if;
 if p_request_id is null or p_decision is null or p_decision not in ('ACKNOWLEDGED','CORRECTION_REQUIRED') or length(trim(coalesce(p_note,''))) not between 1 and 1000 or p_confirmed is distinct from true then raise exception 'Choose a decision, enter a reason and confirm your review.' using errcode='22023';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 matching:=public.purchase_invoice_matching(p_organisation_id,p_purchase_id);
 select * into prior from public.invoice_exception_reviews where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then
  if prior.purchase_id<>p_purchase_id or prior.created_by<>auth.uid() or prior.fingerprint<>p_fingerprint or prior.decision<>p_decision or prior.note<>trim(p_note) then raise exception 'This review request was already used. Refresh before reviewing again.' using errcode='22023';end if;return prior.id;
 end if;
 if p_fingerprint is distinct from matching->>'fingerprint' then raise exception 'The invoice, links or deliveries changed. Refresh before reviewing.' using errcode='22023';end if;
 if p_decision='ACKNOWLEDGED' and (matching->>'blocked')::boolean then raise exception 'Resolve the required invoice links or procurement corrections before acknowledging exceptions.' using errcode='22023';end if;
 if jsonb_array_length(matching->'exceptions')=0 then raise exception 'This invoice currently matches its PO and accepted deliveries. No exception acknowledgement is required.' using errcode='22023';end if;
 insert into public.invoice_exception_reviews(organisation_id,purchase_id,request_id,fingerprint,decision,note,created_by,created_label) values(p_organisation_id,p_purchase_id,p_request_id,p_fingerprint,p_decision,trim(p_note),auth.uid(),coalesce((select email from auth.users where id=auth.uid()),auth.uid()::text)) returning id into result;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'INVOICE_EXCEPTIONS_REVIEWED',auth.uid(),p_purchase_id,jsonb_build_object('review_id',result,'decision',p_decision));return result;
end;$$;
revoke all on function public.set_invoice_procurement_context(uuid,uuid,uuid,integer,jsonb,jsonb),public.stage_manual_purchase(uuid,uuid,jsonb,jsonb),public.post_purchase_import(uuid,uuid,jsonb),public.purchase_invoice_matching(uuid,uuid),public.review_invoice_exceptions(uuid,uuid,uuid,text,text,text,boolean) from public,anon;
grant execute on function public.set_invoice_procurement_context(uuid,uuid,uuid,integer,jsonb,jsonb),public.stage_manual_purchase(uuid,uuid,jsonb,jsonb),public.post_purchase_import(uuid,uuid,jsonb),public.purchase_invoice_matching(uuid,uuid),public.review_invoice_exceptions(uuid,uuid,uuid,text,text,text,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
