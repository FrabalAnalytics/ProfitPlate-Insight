-- A focused, permission-scoped register for inter-centre requisitions.
-- Reuses existing requests, decisions, stock reservations and acceptance posting.
begin;
create function public.requisition_workspace(p_organisation_id uuid,p_location_id uuid default null,p_page integer default 1,p_status text default 'ALL',p_search text default '',p_document_id uuid default null,p_queue text default 'ALL') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare base jsonb; result jsonb; selected jsonb;
begin
 if p_queue is null or p_queue not in('ALL','APPROVAL','DISPATCH','ACCEPTANCE','FOLLOW_UP') then raise exception 'Choose a valid requisition queue.' using errcode='22023';end if;
 -- Validates membership, centre access, pagination and filters; supplies permitted
 -- routes and the reviewed centre material catalogue, including zero-stock items.
 base:=public.stock_workspace_v2(p_organisation_id,p_location_id,p_page,p_status,p_search,null);
 with visible as materialized (
  select d.id,d.created_at,d.state,d.resolved_at,case when d.state in('REQUESTED','APPROVED','DISPATCHED') then private.pp_stock_packet(p_organisation_id,d.id)->'actions' else '{}'::jsonb end actions
  from public.stock_documents d where d.organisation_id=p_organisation_id and d.kind in('TRANSFER','ISSUE')
  and private.pp_stock_doc_read(p_organisation_id,d.id)
  and(p_location_id is null or d.source_id=p_location_id or d.destination_id=p_location_id)
  and(trim(p_search)='' or position(lower(trim(p_search)) in lower(d.reference||' '||d.note))>0)
 ), flagged as materialized (
  select *,coalesce((actions->>'approve')::boolean,false) approval,
  coalesce((actions->>'dispatch')::boolean,false) dispatch,
  coalesce((actions->>'receive')::boolean,false) acceptance,
  (state in('PARTIAL','REJECTED') and resolved_at is null) follow_up from visible
 ), filtered as materialized (
  select * from flagged where private.pp_stock_status(state,p_status) and(p_status<>'FOLLOW_UP' or resolved_at is null)
  and(case p_queue when 'APPROVAL' then approval when 'DISPATCH' then dispatch when 'ACCEPTANCE' then acceptance when 'FOLLOW_UP' then follow_up else true end)
 ), paged as (select * from filtered order by created_at desc,id limit 10 offset(p_page-1)*10)
 select jsonb_build_object('total',(select count(*) from filtered),
 'documents',coalesce((select jsonb_agg(private.pp_stock_packet(p_organisation_id,id) order by created_at desc,id) from paged),'[]'::jsonb),
 'queues',(select jsonb_build_object('APPROVAL',count(*) filter(where approval),'DISPATCH',count(*) filter(where dispatch),'ACCEPTANCE',count(*) filter(where acceptance),'FOLLOW_UP',count(*) filter(where follow_up)) from flagged)) into result;
 if p_document_id is not null and exists(select 1 from public.stock_documents d where d.organisation_id=p_organisation_id and d.id=p_document_id and d.kind in('TRANSFER','ISSUE') and private.pp_stock_doc_read(p_organisation_id,d.id) and(p_location_id is null or d.source_id=p_location_id or d.destination_id=p_location_id)) then selected:=private.pp_stock_packet(p_organisation_id,p_document_id);end if;
 return (base-array['suppliers','recipes','grns','balances','ledger','alerts','documents','total','selected_document'])||result||jsonb_build_object('selected_document',selected);
end $$;
revoke all on function public.requisition_workspace(uuid,uuid,integer,text,text,uuid,text) from public,anon;
grant execute on function public.requisition_workspace(uuid,uuid,integer,text,text,uuid,text) to authenticated;
-- Existing workspace notifications now open transfer/issue records in their
-- focused module; approvals for openings and other stock documents stay intact.
alter function public.workspace_attention(uuid,text,integer) rename to pp_attention_before_requisitions;
alter function public.pp_attention_before_requisitions(uuid,text,integer) set schema private;
revoke all on function private.pp_attention_before_requisitions(uuid,text,integer) from public,anon,authenticated;
create function public.workspace_attention(p_organisation_id uuid,p_queue text default null,p_page integer default 1) returns jsonb language plpgsql stable security definer set search_path='' as $$declare r jsonb;begin
 r:=private.pp_attention_before_requisitions(p_organisation_id,p_queue,p_page);
 return r||jsonb_build_object('records',coalesce((select jsonb_agg(case when entry->>'path'='/workspace/inventory' and exists(select 1 from public.stock_documents d where d.organisation_id=p_organisation_id and d.id=(entry->>'id')::uuid and d.kind in('TRANSFER','ISSUE')) then entry||jsonb_build_object('path','/workspace/requisitions','params',jsonb_build_object('document',entry->>'id')) else entry end order by n) from jsonb_array_elements(r->'records') with ordinality x(entry,n)),'[]'::jsonb));
end $$;
revoke all on function public.workspace_attention(uuid,text,integer) from public,anon;
grant execute on function public.workspace_attention(uuid,text,integer) to authenticated;
notify pgrst,'reload schema';
commit;
