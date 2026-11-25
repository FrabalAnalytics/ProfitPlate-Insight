-- Scoped executive approvals, line decisions and actionable dispatch shortages.
-- Requests retain their original quantities; only approved quantities dispatch.
begin;
alter table public.stock_documents add column requested_lines jsonb;
alter table public.stock_documents add column approval_decisions jsonb;
alter table public.stock_documents add column approval_revision integer not null default 0;

create function private.pp_requisition_approver(org uuid,doc uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.stock_documents d
 join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id
 join public.stock_locations t on t.organisation_id=d.organisation_id and t.id=d.destination_id
 join public.stock_routes r on r.organisation_id=d.organisation_id and r.id=d.route_id
 where d.organisation_id=org and d.id=doc and d.kind in('TRANSFER','ISSUE') and r.is_active
 and private.pp_stock_doc_read(org,doc) and(
 private.pp_stock_route_approver(org,s.id,r.approval_role)
 or private.pp_stock_role(org,'ceo',null)
 or private.pp_stock_role(org,'restaurant_admin',null)
 or(private.pp_stock_role(org,'finance',coalesce(s.outlet_id,t.outlet_id)) and(t.outlet_id is null or private.pp_stock_role(org,'finance',t.outlet_id)))
 or((private.pp_operations_site(org,s.id) or(s.outlet_id is null and private.pp_operations_site(org,t.id)))
 and(t.outlet_id is null or private.pp_operations_site(org,t.id)))
 ));
$$;
revoke all on function private.pp_requisition_approver(uuid,uuid) from public,anon,authenticated;

create function private.pp_review_requisition(org uuid,doc uuid,decision text,review_note text,review jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare d public.stock_documents;original jsonb;l jsonb;r jsonb;choices jsonb;approved jsonb:='[]';decisions jsonb:='[]';qty numeric;requested numeric;item uuid;reason text;current_unit text;
begin
 perform 1 from public.organisations where id=org and access_state='ACTIVE' for update;
 if not found or not private.pp_requisition_approver(org,doc) then raise exception 'Authorised requisition approval access is required within this restaurant and centre scope.' using errcode='42501';end if;
 select * into d from public.stock_documents where organisation_id=org and id=doc for update;
 if d.created_by=auth.uid() then raise exception 'A different authorised colleague must review this request.' using errcode='42501';end if;
 if length(trim(coalesce(review_note,''))) not between 1 and 1000 then raise exception 'Enter a review note.' using errcode='22023';end if;
 if decision='REVISE_APPROVAL' and d.state<>'APPROVED' or decision in('APPROVE','DECLINE') and d.state<>'REQUESTED' then raise exception 'This requisition changed. Refresh before reviewing it again.' using errcode='22023';end if;
 if decision not in('APPROVE','DECLINE','REVISE_APPROVAL') then raise exception 'Choose a valid requisition review.' using errcode='22023';end if;
 original:=coalesce(d.requested_lines,d.lines);
 -- Earlier app versions sent receipt-shaped arrays with every decision.
 if jsonb_typeof(review)='array' and decision<>'REVISE_APPROVAL' then review:=null;end if;
 if review is not null then
  if jsonb_typeof(review) is distinct from 'object' or coalesce(review->>'revision','')!~'^[0-9]{1,9}$' or (review->>'revision')::integer<>d.approval_revision then raise exception 'The approved quantities changed. Refresh and review the latest version.' using errcode='22023';end if;
  choices:=review->'lines';
  if jsonb_typeof(choices) is distinct from 'array' or jsonb_array_length(choices)<>jsonb_array_length(original) or octet_length(choices::text)>65536 then raise exception 'Review every requested material exactly once.' using errcode='22023';end if;
 elsif decision='REVISE_APPROVAL' then raise exception 'Review the latest approved quantities before changing them.' using errcode='22023';end if;
 for l in select value from jsonb_array_elements(original) loop
  item:=(l->>'item_id')::uuid;requested:=(l->>'quantity')::numeric;
  if decision='DECLINE' then qty:=0;reason:=left(review_note,500);
  elsif review is null then qty:=requested;reason:='';
  else
   if(select count(*) from jsonb_array_elements(choices)x where x->>'item_id'=item::text)<>1 then raise exception 'Review every requested material exactly once.' using errcode='22023';end if;
   select value into r from jsonb_array_elements(choices) where value->>'item_id'=item::text;
   qty:=private.pp_stock_number(r->>'quantity',true);reason:=trim(coalesce(r->>'reason',''));
  end if;
  if qty>requested then raise exception 'Approved quantities cannot exceed the original request. Raise a new request for additional stock.' using errcode='22023';end if;
  if length(reason)>500 or(qty<requested and length(reason)=0) then raise exception 'Explain each reduced or declined material line.' using errcode='22023';end if;
  if qty>0 then
   select u.code into current_unit from public.items i join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id where i.organisation_id=org and i.id=item and i.is_active and i.stock_tracked;
   if current_unit is null or current_unit is distinct from l->>'unit' then raise exception 'A requested material or its unit changed. Raise a fresh request using the current catalogue.' using errcode='22023';end if;
   approved:=approved||jsonb_build_array(l||jsonb_build_object('quantity',qty::text));
  end if;
  decisions:=decisions||jsonb_build_array(jsonb_build_object('item_id',item,'requested',requested::text,'quantity',qty::text,'reason',reason));
 end loop;
 update public.stock_documents set requested_lines=original,approval_decisions=decisions,approval_revision=d.approval_revision+1,lines=approved,
 state=case when jsonb_array_length(approved)=0 then 'REJECTED' else 'APPROVED' end,approved_by=auth.uid(),approved_at=clock_timestamp(),decision_note=review_note,
 completed_by=case when jsonb_array_length(approved)=0 then auth.uid() end,completed_at=case when jsonb_array_length(approved)=0 then clock_timestamp() end
 where id=doc;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(org,'STOCK_'||decision,auth.uid(),doc,jsonb_build_object('note',review_note,'requested_lines',original,'decisions',decisions,'previous_decisions',d.approval_decisions,'revision',d.approval_revision+1));
 return doc;
end $$;
revoke all on function private.pp_review_requisition(uuid,uuid,text,text,jsonb) from public,anon,authenticated;

alter function public.stock_document_action(uuid,uuid,text,text,jsonb) rename to pp_stock_action_before_line_reviews;
alter function public.pp_stock_action_before_line_reviews(uuid,uuid,text,text,jsonb) set schema private;
revoke all on function private.pp_stock_action_before_line_reviews(uuid,uuid,text,text,jsonb) from public,anon,authenticated;
create function public.stock_document_action(p_organisation_id uuid,p_document_id uuid,p_action text,p_note text,p_received jsonb default null) returns uuid language plpgsql security definer set search_path='' as $$
declare d public.stock_documents;l jsonb;held numeric;reserved numeric;available numeric;site_name text;
begin
 if p_action in('APPROVE','DECLINE','REVISE_APPROVAL') and exists(select 1 from public.stock_documents where organisation_id=p_organisation_id and id=p_document_id and kind in('TRANSFER','ISSUE')) then return private.pp_review_requisition(p_organisation_id,p_document_id,p_action,p_note,p_received);end if;
 if p_action='DISPATCH' then
  perform 1 from public.organisations where id=p_organisation_id and access_state='ACTIVE' for update;
  if not found then raise exception 'An active restaurant is required.' using errcode='42501';end if;
  select * into d from public.stock_documents where organisation_id=p_organisation_id and id=p_document_id;
  if d.id is not null and d.kind in('TRANSFER','ISSUE') and d.state='APPROVED' and private.pp_stock_doc_read(p_organisation_id,d.id) and private.pp_stock_site(p_organisation_id,d.source_id,'dispatch') then
   select name into site_name from public.stock_locations where organisation_id=p_organisation_id and id=d.source_id;
   for l in select value from jsonb_array_elements(d.lines) loop
    held:=private.pp_stock_balance(p_organisation_id,d.source_id,(l->>'item_id')::uuid);
    reserved:=private.pp_stock_reserved(p_organisation_id,d.source_id,(l->>'item_id')::uuid,d.id);available:=held-reserved;
    if available<(l->>'quantity')::numeric then raise exception 'Insufficient stock for % at %: dispatch needs % %, on hand % %, reserved for other transfers % %, available % %. Review source movements and outstanding transfers, or revise approved quantities.',l->>'name',site_name,l->>'quantity',l->>'unit',trim_scale(held),l->>'unit',trim_scale(reserved),l->>'unit',trim_scale(available),l->>'unit' using errcode='22023';end if;
   end loop;
  end if;
 end if;
 return private.pp_stock_action_before_line_reviews(p_organisation_id,p_document_id,p_action,p_note,p_received);
end $$;
revoke all on function public.stock_document_action(uuid,uuid,text,text,jsonb) from public,anon;
grant execute on function public.stock_document_action(uuid,uuid,text,text,jsonb) to authenticated;

alter function private.pp_stock_packet(uuid,uuid) rename to pp_stock_packet_before_line_reviews;
revoke all on function private.pp_stock_packet_before_line_reviews(uuid,uuid) from public,anon,authenticated;
create function private.pp_stock_packet(org uuid,doc uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare r jsonb;permitted boolean;begin
 r:=private.pp_stock_packet_before_line_reviews(org,doc);
 if r is not null and r->>'kind' in('TRANSFER','ISSUE') then
  permitted:=private.pp_requisition_approver(org,doc) and(r->>'created_by')::uuid<>auth.uid();
  if permitted and r->>'state'='REQUESTED' then r:=r||jsonb_build_object('actions',(r->'actions')||jsonb_build_object('approve',true,'decline',true));end if;
  if permitted and r->>'state'='APPROVED' then r:=r||jsonb_build_object('actions',(r->'actions')||jsonb_build_object('revise_approval',true));end if;
 end if;return r;
end $$;
revoke all on function private.pp_stock_packet(uuid,uuid) from public,anon,authenticated;

create function public.requisition_availability(p_organisation_id uuid,p_document_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d public.stock_documents;result jsonb;
begin
 select * into d from public.stock_documents where organisation_id=p_organisation_id and id=p_document_id and kind in('TRANSFER','ISSUE');
 if d.id is null or not private.pp_stock_doc_read(p_organisation_id,d.id) or not(private.pp_stock_site(p_organisation_id,d.source_id,'read') or private.pp_requisition_approver(p_organisation_id,d.id)) then raise exception 'Source-stock visibility is restricted to authorised reviewers and source-centre users.' using errcode='42501';end if;
 select jsonb_build_object('source',(select name from public.stock_locations where organisation_id=p_organisation_id and id=d.source_id),'checked_at',now(),
 'items',coalesce((select jsonb_agg(jsonb_build_object('item_id',l->>'item_id','name',l->>'name','unit',l->>'unit','on_hand',private.pp_stock_balance(p_organisation_id,d.source_id,(l->>'item_id')::uuid)::text,
 'reserved',private.pp_stock_reserved(p_organisation_id,d.source_id,(l->>'item_id')::uuid,d.id)::text,
 'available',(private.pp_stock_balance(p_organisation_id,d.source_id,(l->>'item_id')::uuid)-private.pp_stock_reserved(p_organisation_id,d.source_id,(l->>'item_id')::uuid,d.id))::text,
 'reservations',coalesce((select jsonb_agg(x.entry order by x.created_at,x.id) from(select r.id,r.created_at,jsonb_build_object('id',r.id,'reference',r.reference,'state',r.state) entry from public.stock_documents r where r.organisation_id=p_organisation_id and r.id<>d.id and r.source_id=d.source_id and r.kind in('TRANSFER','ISSUE') and((r.state='DISPATCHED' and r.posting_policy='ON_ACCEPT') or(r.state in('PARTIAL','REJECTED') and r.resolved_at is null and r.dispatched_at is not null)) and exists(select 1 from jsonb_array_elements(r.lines)line where line->>'item_id'=l->>'item_id') and private.pp_stock_doc_read(p_organisation_id,r.id) order by r.created_at,r.id limit 10)x),'[]'::jsonb)) order by l->>'name') from jsonb_array_elements(coalesce(d.requested_lines,d.lines))l),'[]'::jsonb)) into result;
 return result;
end $$;
revoke all on function public.requisition_availability(uuid,uuid) from public,anon;
grant execute on function public.requisition_availability(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
