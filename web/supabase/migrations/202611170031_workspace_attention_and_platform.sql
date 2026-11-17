-- Apply once after 030. Personal work queues and founder metadata; no PO approval stage.
begin;
create or replace function public.purchasing_report_options(p_organisation_id uuid,p_type text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare base jsonb;
begin
 if p_type is null or p_type not in ('PO','GRN') then raise exception 'Choose Purchase Orders or Goods Received Notes.' using errcode='22023'; end if;
 base:=public.operational_report_options(p_organisation_id,p_type);
 return base||jsonb_build_object('comparison',private.pp_reference_price_read(p_organisation_id),'receiving_orders',private.pp_inventory_access(p_organisation_id),
  'suppliers',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name,s.id) from public.suppliers s
   where s.organisation_id=p_organisation_id and exists(select 1 from public.purchase_orders o where o.organisation_id=s.organisation_id and o.supplier_id=s.id and private.pp_order_read(s.organisation_id,o.id))),'[]'::jsonb),
  'materials',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',i.name,'code',i.code) order by i.name,i.id) from public.items i
   where i.organisation_id=p_organisation_id and exists(select 1 from public.purchase_order_lines l join public.purchase_orders o on o.organisation_id=l.organisation_id and o.id=l.order_id
    where l.organisation_id=i.organisation_id and l.item_id=i.id and private.pp_order_read(i.organisation_id,o.id))),'[]'::jsonb),
  'users',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.label) order by a.label,a.id) from(
   select o.created_by id,min(o.created_label) label from public.purchase_orders o where p_type='PO' and o.organisation_id=p_organisation_id and private.pp_order_read(p_organisation_id,o.id) group by o.created_by
   union all select g.created_by,min(g.created_label) from public.goods_receipts g join public.purchase_orders o on o.organisation_id=g.organisation_id and o.id=g.order_id
    where p_type='GRN' and g.organisation_id=p_organisation_id and private.pp_order_read(p_organisation_id,o.id) group by g.created_by
  )a),'[]'::jsonb));
end $$;

create table private.workspace_attention_epoch(singleton boolean primary key default true check(singleton),installed_at timestamptz not null default clock_timestamp());
insert into private.workspace_attention_epoch(singleton) values(true);
revoke all on private.workspace_attention_epoch from public,anon,authenticated;
create table public.workspace_grn_reviews(
 organisation_id uuid not null,user_id uuid not null references auth.users(id),receipt_id uuid not null,reviewed_at timestamptz not null default clock_timestamp(),
 primary key(organisation_id,user_id,receipt_id),foreign key(organisation_id,receipt_id) references public.goods_receipts(organisation_id,id)
);
alter table public.workspace_grn_reviews enable row level security;
revoke all on public.workspace_grn_reviews from public,anon,authenticated;

create function private.pp_attention_rows(org uuid) returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
declare buying boolean:=private.pp_purchase_write(org);receiving boolean:=private.pp_inventory_access(org);financial boolean:=private.pp_reference_price_read(org);
begin
 if buying or receiving then
  return query with orders as materialized (
   select o.*,private.pp_inventory_access(org,o.location_id) and o.created_by<>auth.uid() and o.issued_by<>auth.uid() can_receive,
    coalesce((select bool_and(l.quantity<=coalesce((select sum(r.accepted) from public.goods_receipt_lines r where r.organisation_id=org and r.order_line_id=l.id and not private.pp_receipt_voided(org,r.receipt_id)),0)) from public.purchase_order_lines l where l.organisation_id=org and l.order_id=o.id),false) complete,
    exists(select 1 from public.goods_receipts g where g.organisation_id=org and g.order_id=o.id and not private.pp_receipt_voided(org,g.id)) has_grn
   from public.purchase_orders o where o.organisation_id=org and private.pp_order_read(org,o.id)
  ), tasks as (
   select 'PO_AWAITING_GRN' queue,o.* from orders o where receiving and o.status='ISSUED' and o.can_receive and not o.has_grn
   union all select 'PO_INCOMPLETE',o.* from orders o where o.status='ISSUED' and not o.complete and(buying or(receiving and o.can_receive))
   union all select 'PO_DRAFTS',o.* from orders o where buying and o.status='DRAFT'
   union all select 'PO_OVERDUE',o.* from orders o where buying and o.status='ISSUED' and not o.complete and o.needed_by<(select(now() at time zone time_zone)::date from public.organisations where id=org)
  ) select jsonb_build_object('id',id,'queue',queue,'reference',reference,'state',status,'date',document_date,'since',coalesce(issued_at,created_at),
   'where',payload->'header'->>'location_name','description',payload->'header'->>'supplier_name',
   'path','/workspace/purchases/orders','params',jsonb_build_object('order',id)||case when queue='PO_AWAITING_GRN' then jsonb_build_object('receive','1') else '{}'::jsonb end) from tasks;
 end if;
 if buying then
  return query select jsonb_build_object('id',g.id,'queue','NEW_GRNS','reference',g.reference,'state',case when private.pp_receipt_voided(org,g.id) then 'VOIDED' else 'DOCUMENTED' end,
   'date',g.received_on,'since',g.created_at,'where',o.payload->'header'->>'location_name','description',o.reference||' · '||(o.payload->'header'->>'supplier_name'),
   'path','/workspace/purchases/receipts','params',jsonb_build_object('order',o.id,'receipt',g.id),'reviewable',true)
   from public.goods_receipts g join public.purchase_orders o on o.organisation_id=org and o.id=g.order_id
   where g.organisation_id=org and private.pp_order_read(org,o.id)
    and g.created_at>=greatest((select installed_at from private.workspace_attention_epoch),(select m.created_at from public.organisation_memberships m where m.organisation_id=org and m.user_id=auth.uid() and m.status='active'))
    and not exists(select 1 from public.workspace_grn_reviews v where v.organisation_id=org and v.user_id=auth.uid() and v.receipt_id=g.id);
 end if;
 if financial and(buying or private.pp_finance(org)) then
  return query with candidates as materialized (
   select h.id,h.created_at,private.pp_current_invoice(org,h.id) invoice from public.purchase_headers h where h.organisation_id=org
  ), assessed as materialized (
   select c.*,public.purchase_invoice_matching(org,c.id) matching from candidates c where not(c.invoice->>'voided')::boolean
  ), tasks as (
   select 'INVOICE_ACTION' queue,a.* from assessed a where buying and a.matching->>'status' in ('ACTION_REQUIRED','CORRECTION_REQUIRED')
   union all select 'INVOICE_REVIEW',a.* from assessed a where a.matching->>'status'='NEEDS_FINANCE_REVIEW'
   union all select 'INVOICE_CORRECTIONS',a.* from assessed a where exists(select 1 from public.purchase_corrections c where c.organisation_id=org and c.purchase_id=a.id and c.state='PENDING')
  ) select jsonb_build_object('id',id,'queue',queue,'reference',invoice->'header'->>'reference','state',matching->>'status','date',invoice->'header'->>'date','since',created_at,
   'where',invoice->'header'->>'location_name','description',invoice->'header'->>'supplier_name','path','/workspace/purchases/invoices','params',jsonb_build_object('purchase',id)) from tasks;
 end if;
 if private.pp_stock_read(org) then
  return query with docs as materialized (
   select d.*,private.pp_stock_packet(org,d.id) packet,s.name source_name,t.name destination_name,t.kind destination_kind,s.kind source_kind
   from public.stock_documents d left join public.stock_locations s on s.organisation_id=org and s.id=d.source_id left join public.stock_locations t on t.organisation_id=org and t.id=d.destination_id
   where d.organisation_id=org and private.pp_stock_doc_read(org,d.id) and(d.state in ('REQUESTED','APPROVED','DISPATCHED') or(d.state in ('PARTIAL','REJECTED') and d.resolved_at is null))
  ), tasks as (
   select 'REQUEST_APPROVAL' queue,d.* from docs d where(d.packet->'actions'->>'approve')::boolean
   union all select 'READY_DISPATCH',d.* from docs d where(d.packet->'actions'->>'dispatch')::boolean
   union all select 'READY_POST',d.* from docs d where(d.packet->'actions'->>'post')::boolean
   union all select 'DEPARTMENT_CONFIRMATION',d.* from docs d where d.state='DISPATCHED' and private.pp_stock_manager(org) and d.destination_kind in ('KITCHEN','BAR','PRODUCTION') and not coalesce((d.packet->'actions'->>'receive')::boolean,false)
   union all select 'DEPARTMENT_RETURNS',d.* from docs d where(d.packet->'actions'->>'receive')::boolean and d.source_kind in ('KITCHEN','BAR','PRODUCTION') and d.destination_kind in ('STORE','WAREHOUSE')
   union all select 'INCOMING_TRANSFER',d.* from docs d where(d.packet->'actions'->>'receive')::boolean and not(d.source_kind in ('KITCHEN','BAR','PRODUCTION') and d.destination_kind in ('STORE','WAREHOUSE'))
   union all select 'STOCK_FOLLOW_UP',d.* from docs d where d.state in ('PARTIAL','REJECTED') and d.resolved_at is null and(private.pp_stock_manager(org) or d.created_by=auth.uid())
   union all select 'YOUR_PENDING_REQUESTS',d.* from docs d where d.created_by=auth.uid() and d.state in ('REQUESTED','APPROVED') and not private.pp_stock_manager(org)
  ) select jsonb_build_object('id',id,'queue',queue,'reference',reference,'state',state,'date',document_date,'since',coalesce(dispatched_at,approved_at,created_at),
   'where',concat_ws(' → ',source_name,destination_name),'description',case when queue='DEPARTMENT_CONFIRMATION' then destination_name||': accept or reject' else note end,
   'path','/workspace/inventory','params',jsonb_build_object('view','movements','document',id)) from tasks;
 end if;
end $$;

create function public.workspace_attention(p_organisation_id uuid,p_queue text default null,p_page integer default 1) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare packet jsonb;
begin
 if not exists(select 1 from public.organisation_memberships m where m.organisation_id=p_organisation_id and m.user_id=auth.uid() and m.status='active') then raise exception 'Workspace access denied.' using errcode='42501'; end if;
 if p_page is null or p_page not between 1 and 100000 or(p_queue is not null and p_queue not in ('PO_AWAITING_GRN','PO_INCOMPLETE','PO_DRAFTS','PO_OVERDUE','NEW_GRNS','INVOICE_ACTION','INVOICE_REVIEW','INVOICE_CORRECTIONS','REQUEST_APPROVAL','READY_DISPATCH','READY_POST','DEPARTMENT_CONFIRMATION','DEPARTMENT_RETURNS','INCOMING_TRANSFER','STOCK_FOLLOW_UP','YOUR_PENDING_REQUESTS')) then raise exception 'Choose a valid task queue and page.' using errcode='22023'; end if;
 with tasks as materialized(select distinct r from private.pp_attention_rows(p_organisation_id)r),
 grouped as(select r->>'queue' queue,count(distinct r->>'id') count,count(distinct r->>'id') filter(where(r->>'since')::timestamptz<statement_timestamp()-interval '24 hours') overdue from tasks group by r->>'queue'),
 filtered as(select r from tasks where p_queue is not null and r->>'queue'=p_queue),
 paged as(select r from filtered order by(r->>'since')::timestamptz,r->>'id' limit 10 offset(p_page-1)*10)
 select jsonb_build_object('queues',coalesce((select jsonb_agg(to_jsonb(g) order by queue) from grouped g),'[]'::jsonb),
  'total',(select count(*) from filtered),'records',coalesce((select jsonb_agg(r order by(r->>'since')::timestamptz,r->>'id') from paged),'[]'::jsonb),'refreshed_at',statement_timestamp()) into packet;
 return packet;
end $$;
create function public.mark_workspace_grns_reviewed(p_organisation_id uuid,p_receipts uuid[]) returns integer
language plpgsql security definer set search_path='' as $$
declare changed integer;
begin
 if not private.pp_purchase_write(p_organisation_id) then raise exception 'Procurement access is required.' using errcode='42501'; end if;
 if p_receipts is null or cardinality(p_receipts) not between 1 and 10 or exists(select 1 from unnest(p_receipts)requested(receipt_id) where requested.receipt_id is null or not exists(select 1 from public.goods_receipts g join public.purchase_orders o on o.organisation_id=g.organisation_id and o.id=g.order_id where g.organisation_id=p_organisation_id and g.id=requested.receipt_id and private.pp_order_read(p_organisation_id,o.id))) then raise exception 'Choose up to ten available GRNs.' using errcode='22023'; end if;
 insert into public.workspace_grn_reviews(organisation_id,user_id,receipt_id) select p_organisation_id,auth.uid(),id from(select distinct unnest(p_receipts)id)s on conflict do nothing;
 get diagnostics changed=row_count;return changed;
end $$;

create function public.platform_workspace(p_search text default '',p_state text default 'ALL',p_page integer default 1,p_organisation_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare packet jsonb;
begin
 if not public.is_platform_admin() then raise exception 'Platform administrator access is required.' using errcode='42501'; end if;
 if p_search is null or length(p_search)>80 or p_state is null or p_state not in ('ALL','ONBOARDING','ACCESS_REVIEW') or p_page is null or p_page not between 1 and 100000 then raise exception 'Choose valid platform filters and page.' using errcode='22023'; end if;
 if p_organisation_id is not null and not exists(select 1 from public.organisations where id=p_organisation_id) then raise exception 'Business unavailable.' using errcode='22023'; end if;
 with businesses as materialized(
  select o.id,o.name,o.created_at,o.currency_code,o.time_zone,u.email owner_email,
   (select count(*) from public.locations l where l.organisation_id=o.id) outlets,
   (select count(*) from public.organisation_memberships m where m.organisation_id=o.id and m.status='active') active_members,
   exists(select 1 from public.organisation_memberships m join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id where m.organisation_id=o.id and m.status='active' and r.role_code='restaurant_admin' and r.location_id is null) has_admin,
   (select count(*) from public.team_invitations i where i.organisation_id=o.id and i.state='PENDING' and i.expires_at<now()) expired_invitations,
   (select max(a.created_at) from public.audit_events a where a.organisation_id=o.id) last_activity
  from public.organisations o left join auth.users u on u.id=o.owner_id
 ), filtered as(select * from businesses where p_state<>'ONBOARDING' and(p_state<>'ACCESS_REVIEW' or not has_admin or expired_invitations>0) and(trim(p_search)='' or position(lower(trim(p_search)) in lower(name||' '||coalesce(owner_email,'')))>0)),
 drafts as(select d.business_name,d.step,d.updated_at,u.email owner_email from public.restaurant_setup_drafts d left join auth.users u on u.id=d.user_id where d.completed_organisation_id is null and(trim(p_search)='' or position(lower(trim(p_search)) in lower(d.business_name||' '||coalesce(u.email,'')))>0))
 select jsonb_build_object('summary',jsonb_build_object('restaurants',(select count(*) from businesses),'outlets',(select coalesce(sum(outlets),0) from businesses),'active_memberships',(select coalesce(sum(active_members),0) from businesses),'onboarding',(select count(*) from public.restaurant_setup_drafts where completed_organisation_id is null),'access_review',(select count(*) from businesses where not has_admin or expired_invitations>0)),
  'total',case when p_state='ONBOARDING' then(select count(*) from drafts) else(select count(*) from filtered) end,
  'businesses',coalesce((select jsonb_agg(to_jsonb(b) order by b.created_at desc,b.id) from(select * from filtered order by created_at desc,id limit 10 offset(p_page-1)*10)b),'[]'::jsonb),
  'drafts',case when p_state='ONBOARDING' then coalesce((select jsonb_agg(to_jsonb(d) order by updated_at desc) from(select * from drafts order by updated_at desc,owner_email limit 10 offset(p_page-1)*10)d),'[]'::jsonb) else '[]'::jsonb end,
  'selected',case when p_organisation_id is not null then(select to_jsonb(b)||jsonb_build_object('roles',coalesce((select jsonb_agg(to_jsonb(r)) from(select mr.role_code,count(*) assignments from public.membership_roles mr join public.organisation_memberships m on m.organisation_id=mr.organisation_id and m.id=mr.membership_id where mr.organisation_id=b.id and m.status='active' group by mr.role_code order by mr.role_code)r),'[]'::jsonb)) from businesses b where b.id=p_organisation_id) end,
  'refreshed_at',statement_timestamp()) into packet;
 return packet;
end $$;
revoke all on function private.pp_attention_rows(uuid) from public,anon,authenticated;
revoke all on function public.workspace_attention(uuid,text,integer),public.mark_workspace_grns_reviewed(uuid,uuid[]),public.platform_workspace(text,text,integer,uuid) from public,anon;
grant execute on function public.workspace_attention(uuid,text,integer),public.mark_workspace_grns_reviewed(uuid,uuid[]),public.platform_workspace(text,text,integer,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
