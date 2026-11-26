-- Read-only task handoffs and an auditable operational close checklist. No stock is posted here.
begin;
-- Corrections have their own actionable queue; do not count them twice as material requisitions.
alter function private.pp_attention_rows(uuid) rename to pp_attention_rows_before_balance_queue;
revoke all on function private.pp_attention_rows_before_balance_queue(uuid) from public,anon,authenticated;
create function private.pp_attention_rows(org uuid) returns setof jsonb language sql stable security definer set search_path='' as $$
 select r from private.pp_attention_rows_before_balance_queue(org) r where not exists(select 1 from public.stock_documents d where d.organisation_id=org and d.id::text=r->>'id' and d.kind in('OPENING','COUNT') and r->>'path'='/workspace/inventory');
$$;
revoke all on function private.pp_attention_rows(uuid) from public,anon,authenticated;
create function public.stock_correction_queue(p_organisation_id uuid,p_state text default 'ACTION',p_page integer default 1) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;begin
 if private.pp_review_member(p_organisation_id) is null then raise exception 'Active restaurant access required.' using errcode='42501';end if;
 if p_state is null or p_state not in('ACTION','WAITING','ALL') or p_page is null or p_page not between 1 and 100000 then raise exception 'Choose a task view and page.' using errcode='22023';end if;
 with docs as materialized(
 select d.*,s.name centre,private.pp_stock_packet(p_organisation_id,d.id) packet
 from public.stock_documents d join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=coalesce(d.source_id,d.destination_id)
 where d.organisation_id=p_organisation_id and d.kind in('COUNT','OPENING') and d.state in('REQUESTED','APPROVED') and private.pp_stock_doc_read(p_organisation_id,d.id)
 ),tasks as materialized(select id,reference,kind,state,centre,created_at,created_by=auth.uid() own,
 coalesce((packet->'actions'->>'approve')::boolean,false) can_review,coalesce((packet->'actions'->>'post')::boolean,false) can_post,
 case when kind='OPENING' and coalesce((packet->'actions'->>'post')::boolean,false) then 'Administrator verifies and records opening stock' when state='APPROVED' then 'Management posts the approved balance' else 'A different authorised management colleague reviews' end next_action,
 coalesce((select jsonb_agg(distinct coalesce(nullif(m.display_name,''),r.name)) from public.organisation_memberships m join public.membership_roles mr on mr.organisation_id=m.organisation_id and mr.membership_id=m.id join public.roles r on r.code=mr.role_code
 where m.organisation_id=p_organisation_id and m.status='active' and m.user_id<>docs.created_by and mr.role_code in('ceo','finance','restaurant_admin','operations')
 and (mr.location_id is null or mr.location_id=(select outlet_id from public.stock_locations where organisation_id=p_organisation_id and id=coalesce(docs.source_id,docs.destination_id)))
 and (mr.role_code<>'restaurant_admin' or mr.location_id is null)
 and (mr.role_code<>'operations' or not exists(select 1 from public.stock_member_access a where a.organisation_id=m.organisation_id and a.membership_id=m.id and a.mode='ASSIGNED') or exists(select 1 from public.stock_member_locations a where a.organisation_id=m.organisation_id and a.membership_id=m.id and a.location_id=coalesce(docs.source_id,docs.destination_id)))),'[]'::jsonb) reviewers
 from docs),visible as materialized(select * from tasks where can_review or can_post or own),filtered as(select * from visible where p_state='ALL' or(p_state='ACTION' and(can_review or can_post)) or(p_state='WAITING' and own and not can_review and not can_post)),paged as(select * from filtered order by created_at,id limit 20 offset(p_page-1)*20)
 select jsonb_build_object('review',(select count(*) from visible where can_review),'post',(select count(*) from visible where can_post),'waiting',(select count(*) from visible where own and not can_review and not can_post),'total',(select count(*) from filtered),'rows',coalesce((select jsonb_agg(to_jsonb(p) order by created_at,id) from paged p),'[]'::jsonb)) into result;return result;
end $$;
revoke all on function public.stock_correction_queue(uuid,text,integer) from public,anon;
grant execute on function public.stock_correction_queue(uuid,text,integer) to authenticated;

create table private.monthly_close_reviews(
 id uuid primary key default gen_random_uuid(),organisation_id uuid not null references public.organisations(id),month date not null,site_id uuid,
 actor_id uuid not null references auth.users(id),request_id uuid not null,digest text not null,evidence text not null,confirmations jsonb not null,note text not null,payload jsonb not null,created_at timestamptz not null default clock_timestamp(),unique(organisation_id,request_id),
 foreign key(organisation_id,site_id) references public.stock_locations(organisation_id,id)
);
revoke all on private.monthly_close_reviews from public,anon,authenticated;
create trigger active_restaurant_write before insert or update or delete on private.monthly_close_reviews for each row execute function private.pp_require_active_restaurant();
create function private.pp_close_access(org uuid,site uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisations o join public.organisation_memberships m on m.organisation_id=o.id join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id where o.id=org and o.access_state='ACTIVE' and m.user_id=auth.uid() and m.status='active' and r.role_code in('ceo','finance','restaurant_admin','operations'))
 and (site is null or private.pp_stock_adjustment_role(org,site));
$$;
revoke all on function private.pp_close_access(uuid,uuid) from public,anon,authenticated;
create function public.monthly_close_checklist(p_organisation_id uuid,p_month date,p_site_id uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare today date;last_day date;through date;checks jsonb;sites jsonb;evidence text;source_stamp text;saved private.monthly_close_reviews;result jsonb;begin
 if not private.pp_close_access(p_organisation_id,p_site_id) then raise exception 'CEO, Finance, Operations Manager or Restaurant Administrator access required.' using errcode='42501';end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 if p_month is null or p_month<date '2000-01-01' or extract(day from p_month)<>1 or p_month>today then raise exception 'Choose a month from 2000 through this month.' using errcode='22023';end if;
 last_day:=(p_month+interval '1 month - 1 day')::date;through:=least(last_day,today);
 select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name,s.id),'[]') into sites from public.stock_locations s where s.organisation_id=p_organisation_id and s.is_active and private.pp_stock_adjustment_role(p_organisation_id,s.id);
 with centres as materialized(select s.* from public.stock_locations s where s.organisation_id=p_organisation_id and s.is_active and(p_site_id is null or s.id=p_site_id) and private.pp_stock_adjustment_role(p_organisation_id,s.id) and (coalesce((select min(start_day) from(select effective_from as start_day from private.monthly_count_programmes where organisation_id=p_organisation_id and site_id=s.id union all select effective_from from private.waste_schedules where organisation_id=p_organisation_id and site_id=s.id)start_days),p_month)<=through)),
 obligations as materialized(select s.id,coalesce((select p.active from private.monthly_count_programmes p where p.organisation_id=p_organisation_id and p.site_id=s.id and p.effective_from<=last_day order by p.effective_from desc limit 1),false) scheduled,
 exists(select 1 from private.weekly_counts c where c.organisation_id=p_organisation_id and c.site_id=s.id and coalesce(c.reporting_month,date_trunc('month',c.monthly_date)::date)=p_month and c.state in('POSTED','REVIEWED')) finished from centres s),
 waste as materialized(select r.* from private.pp_waste_daily_rows(p_organisation_id,p_month,through,null) r join centres s on s.id=r.site_id),
 transfers as materialized(select d.id from public.stock_documents d where d.organisation_id=p_organisation_id and d.document_date<=through and d.dispatched_at is not null and d.state in('DISPATCHED','PARTIAL','REJECTED') and d.resolved_at is null and private.pp_stock_doc_read(p_organisation_id,d.id) and exists(select 1 from centres s where s.id=d.source_id or s.id=d.destination_id)),
 sales as materialized(select j.id from private.sales_stock_jobs j join public.sales_lines l on l.organisation_id=j.organisation_id and l.id=j.sale_line_id join public.sales_headers h on h.organisation_id=l.organisation_id and h.id=l.sale_id where j.organisation_id=p_organisation_id and j.state='PENDING' and h.sale_date<=through and private.pp_sales_job_read(p_organisation_id,j.id) and exists(select 1 from centres s where s.id=j.site_id or(j.site_id is null and(s.outlet_id is null or s.outlet_id=h.location_id)))),
 adjustments as materialized(select d.id from public.stock_documents d where d.organisation_id=p_organisation_id and d.kind in('OPENING','COUNT') and d.document_date<=through and d.state in('REQUESTED','APPROVED') and private.pp_stock_doc_read(p_organisation_id,d.id) and exists(select 1 from centres s where s.id=coalesce(d.source_id,d.destination_id))),
 rows as(
 select 'centres' id,'Stock centres configured' label,case when exists(select 1 from centres) then 0 else 1 end::bigint pending,'/workspace/setup/centres' path,'{}'::jsonb params
 union all select 'calendar','Monthly count schedule',count(*) filter(where not scheduled),'/workspace/setup/standards','{}' from obligations
 union all select 'counts','Monthly counts reviewed and posted',count(*) filter(where not finished),'/workspace/inventory/counts',jsonb_build_object('frequency','MONTHLY','from',p_month,'to',(last_day+interval '1 month')::date) from obligations
 union all select 'waste-calendar','Waste reporting schedule',count(*),'/workspace/inventory/waste/daily','{}' from centres s where not exists(select 1 from private.waste_schedules w where w.organisation_id=p_organisation_id and w.site_id=s.id and w.effective_from<=through)
 union all select 'waste','Daily waste declarations',count(*) filter(where expected and state not like 'COMPLETE_%' and state<>'CLOSED'),'/workspace/inventory/waste/daily',jsonb_build_object('from',p_month,'to',through) from waste
 union all select 'transfers','Unresolved stock handovers',count(*),'/workspace/requisitions',jsonb_build_object('status','FOLLOW_UP') from transfers
 union all select 'sales','Sales consumption exceptions',count(*),'/workspace/inventory/sales-consumption','{}' from sales
 union all select 'adjustments','Balance adjustments awaiting completion',count(*),'/workspace/inventory/corrections','{}' from adjustments
 )select jsonb_agg(to_jsonb(r) order by id) into checks from rows r;
 -- Conservative refresh: a subsequent restaurant record change invalidates earlier coverage attestations.
 select count(*)::text||':'||coalesce(max(created_at)::text,'') into source_stamp from public.audit_events where organisation_id=p_organisation_id and event_type<>'MONTHLY_CLOSE_REVIEW_SAVED';
 evidence:=md5(jsonb_build_array(p_month,p_site_id,sites,checks,source_stamp)::text);
 select * into saved from private.monthly_close_reviews where organisation_id=p_organisation_id and month=p_month and site_id is not distinct from p_site_id order by created_at desc,id desc limit 1;
 result:=jsonb_build_object('month',p_month,'through',through,'ended',last_day<today,'site_id',p_site_id,'centres',sites,'can_setup',private.pp_team_manage(p_organisation_id),'scope','Selected permitted centres','checks',checks,'pending',(select sum((value->>'pending')::integer) from jsonb_array_elements(checks)),'evidence',evidence,
 'saved',case when saved.id is not null then jsonb_build_object('id',saved.id,'at',saved.created_at,'name',coalesce((select nullif(m.display_name,'') from public.organisation_memberships m where m.organisation_id=p_organisation_id and m.user_id=saved.actor_id),'Management colleague'),'current',saved.evidence=evidence,'confirmations',saved.confirmations,'note',saved.note,'ready',saved.payload->'ready') end);
 return result;
end $$;
create function public.save_monthly_close_review(p_organisation_id uuid,p_month date,p_site_id uuid,p_request_id uuid,p_evidence text,p_confirmations jsonb,p_note text) returns uuid language plpgsql security definer set search_path='' as $$
declare packet jsonb;prior private.monthly_close_reviews;result uuid;digest text:=md5(jsonb_build_array(p_month,p_site_id,p_evidence,p_confirmations,p_note)::text);ready boolean;begin
 if not private.pp_close_access(p_organisation_id,p_site_id) then raise exception 'Management close access required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id and access_state='ACTIVE' for update;
 if not found then raise exception 'Active restaurant access required.' using errcode='42501';end if;
 if p_request_id is null then raise exception 'Refresh the checklist before saving.' using errcode='22023';end if;
 select * into prior from private.monthly_close_reviews where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then if prior.actor_id<>auth.uid() or prior.digest<>digest then raise exception 'Refresh before changing a saved review.' using errcode='22023';end if;return prior.id;end if;
 if p_confirmations is null or jsonb_typeof(p_confirmations)<>'object' or p_confirmations-'sales'-'invoices'-'expenses'<>'{}'::jsonb or exists(select 1 from jsonb_each(p_confirmations) where jsonb_typeof(value)<>'boolean') or not(p_confirmations ?& array['sales','invoices','expenses']) or length(trim(coalesce(p_note,''))) not between 5 and 2000 then raise exception 'Review the three coverage confirmations and enter a note or source reference (5 to 2000 characters).' using errcode='22023';end if;
 packet:=public.monthly_close_checklist(p_organisation_id,p_month,p_site_id);
 if p_evidence is distinct from packet->>'evidence' then raise exception 'Restaurant records changed. Refresh the checklist and review the updated checks before saving.' using errcode='22023';end if;
 ready:=(packet->>'ended')::boolean and(packet->>'pending')::integer=0 and(p_confirmations->>'sales')::boolean and(p_confirmations->>'invoices')::boolean and(p_confirmations->>'expenses')::boolean;
 insert into private.monthly_close_reviews(organisation_id,month,site_id,actor_id,request_id,digest,evidence,confirmations,note,payload) values(p_organisation_id,p_month,p_site_id,auth.uid(),p_request_id,digest,p_evidence,p_confirmations,trim(p_note),packet||jsonb_build_object('ready',ready)) returning id into result;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'MONTHLY_CLOSE_REVIEW_SAVED',auth.uid(),result,jsonb_build_object('month',p_month,'site',p_site_id,'ready',ready,'stock_changed',false));return result;
end $$;
revoke all on function public.monthly_close_checklist(uuid,date,uuid),public.save_monthly_close_review(uuid,date,uuid,uuid,text,jsonb,text) from public,anon;
grant execute on function public.monthly_close_checklist(uuid,date,uuid),public.save_monthly_close_review(uuid,date,uuid,uuid,text,jsonb,text) to authenticated;
notify pgrst,'reload schema';
commit;
