-- Requisition reviews belong to CEO, Operations, Finance or Administrator roles.
-- Inventory dispatch/receipt, existing decisions and non-requisition controls remain.
begin;
create or replace function private.pp_requisition_approver(org uuid,doc uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.stock_documents d
 join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id
 join public.stock_locations t on t.organisation_id=d.organisation_id and t.id=d.destination_id
 join public.stock_routes r on r.organisation_id=d.organisation_id and r.id=d.route_id
 where d.organisation_id=org and d.id=doc and d.kind in('TRANSFER','ISSUE') and r.is_active
 and private.pp_stock_doc_read(org,doc) and(
 private.pp_stock_role(org,'ceo',null)
 or private.pp_stock_role(org,'restaurant_admin',null)
 or(private.pp_stock_role(org,'finance',coalesce(s.outlet_id,t.outlet_id)) and(t.outlet_id is null or private.pp_stock_role(org,'finance',t.outlet_id)))
 or((private.pp_operations_site(org,s.id) or(s.outlet_id is null and private.pp_operations_site(org,t.id)))
 and(t.outlet_id is null or private.pp_operations_site(org,t.id)))
 ));
$$;
create or replace function private.pp_stock_packet(org uuid,doc uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare r jsonb;permitted boolean;begin
 r:=private.pp_stock_packet_before_line_reviews(org,doc);
 if r is not null and r->>'kind' in('TRANSFER','ISSUE') then
  -- Remove permissions inherited from the earlier Inventory approval policy.
  r:=r||jsonb_build_object('actions',(r->'actions')-array['approve','decline','revise_approval']);
  permitted:=private.pp_requisition_approver(org,doc) and(r->>'created_by')::uuid<>auth.uid();
  if permitted and r->>'state'='REQUESTED' then r:=r||jsonb_build_object('actions',(r->'actions')||jsonb_build_object('approve',true,'decline',true));end if;
  if permitted and r->>'state'='APPROVED' then r:=r||jsonb_build_object('actions',(r->'actions')||jsonb_build_object('revise_approval',true));end if;
 end if;return r;
end $$;
create or replace function public.stock_workspace_alerts(p_organisation_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock access denied.' using errcode='42501';end if;
 with relevant as (
  select d.id,d.reference,d.state,d.created_at,d.dispatched_at,
   case when d.state='REQUESTED' and coalesce((private.pp_stock_packet(p_organisation_id,d.id)->'actions'->>'approve')::boolean,false) then 'Approval needed'
    when d.state='APPROVED' and ((d.kind in ('ISSUE','TRANSFER') and private.pp_stock_site(p_organisation_id,d.source_id,'dispatch')) or (d.kind not in ('ISSUE','TRANSFER') and private.pp_stock_site(p_organisation_id,coalesce(d.source_id,d.destination_id),'inventory'))) then 'Ready to dispatch / post'
    when d.state='DISPATCHED' and private.pp_stock_site(p_organisation_id,d.destination_id,'receive') then 'Accept or reject incoming stock'
    when d.state='DISPATCHED' and private.pp_stock_manager(p_organisation_id) then 'Awaiting department acceptance'
    when d.state in ('PARTIAL','REJECTED') and d.resolved_at is null and private.pp_stock_manager(p_organisation_id) then 'Incomplete / rejected: follow-up needed'
    when d.created_by=auth.uid() and d.state in ('PARTIAL','REJECTED') and d.resolved_at is null then 'Your requisition needs follow-up'
    when d.created_by=auth.uid() and d.state in ('REQUESTED','APPROVED') then 'Your requisition is pending'
    else null end label
  from public.stock_documents d where d.organisation_id=p_organisation_id and private.pp_stock_doc_read(p_organisation_id,d.id)
 ) select jsonb_build_object('total',count(*) filter(where label is not null),'approval',count(*) filter(where label='Approval needed'),'incoming',count(*) filter(where label='Accept or reject incoming stock'),'follow_up',count(*) filter(where label in ('Incomplete / rejected: follow-up needed','Your requisition needs follow-up')),
 'overdue',count(*) filter(where label is not null and coalesce(dispatched_at,created_at)<statement_timestamp()-interval '24 hours'),
 'items',coalesce((select jsonb_agg(to_jsonb(q)) from (select id,reference,state,label,coalesce(dispatched_at,created_at) since,coalesce(dispatched_at,created_at)<statement_timestamp()-interval '24 hours' overdue from relevant where label is not null order by coalesce(dispatched_at,created_at),id limit 6) q),'[]')) into result from relevant;
 return result;
end $$;
notify pgrst,'reload schema';
commit;
