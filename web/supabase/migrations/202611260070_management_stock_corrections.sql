-- Balance corrections require management authority. Normal operational movements retain their controls.
begin;
create function private.pp_stock_adjustment_role(org uuid,site uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.pp_inventory_report_site(org,site) and (
 private.pp_stock_role(org,'restaurant_admin',null) or private.pp_stock_role(org,'ceo',(select outlet_id from public.stock_locations where organisation_id=org and id=site))
 or private.pp_stock_role(org,'finance',(select outlet_id from public.stock_locations where organisation_id=org and id=site)) or private.pp_operations_site(org,site));
$$;
revoke all on function private.pp_stock_adjustment_role(uuid,uuid) from public,anon,authenticated;
create or replace function private.pp_count_review_role(org uuid,site uuid) returns boolean language sql stable security definer set search_path='' as $$select private.pp_stock_adjustment_role(org,site);$$;

create function public.request_stock_correction(p_organisation_id uuid,p_request_id uuid,p_document jsonb,p_lines jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare site uuid;day date;today date;doc uuid:=gen_random_uuid();prior public.stock_documents;lines jsonb;digest text:=md5(jsonb_build_array(p_document,p_lines)::text);
begin
 if not private.pp_stock_role(p_organisation_id,'restaurant_admin',null) then raise exception 'Restaurant Administrator access is required to submit a balance correction.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id and access_state='ACTIVE' for update;
 if not found then raise exception 'An active restaurant is required.' using errcode='42501';end if;
 if p_request_id is null or p_document is null or p_document->>'kind' is distinct from 'COUNT' or length(trim(coalesce(p_document->>'note',''))) not between 5 and 1000 then raise exception 'Choose a centre, enter the verified quantities and explain the correction.' using errcode='22023';end if;
 select * into prior from public.stock_documents where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then if prior.created_by<>auth.uid() or prior.input_hash<>digest then raise exception 'Refresh before changing a submitted correction.' using errcode='22023';end if;return prior.id;end if;
 begin site:=(p_document->>'source_id')::uuid;day:=(p_document->>'date')::date;exception when others then raise exception 'Choose a valid centre and count date.' using errcode='22023';end;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 if day is distinct from today then raise exception 'For an immediate correction, count the stock today and use today as the date. Use scheduled counts for historical count reconciliation.' using errcode='22023';end if;
 if not exists(select 1 from public.stock_locations where organisation_id=p_organisation_id and id=site and is_active) or not private.pp_stock_adjustment_role(p_organisation_id,site) then raise exception 'Choose an active centre within your access.' using errcode='42501';end if;
 if exists(select 1 from public.stock_documents where organisation_id=p_organisation_id and (source_id=site or destination_id=site) and dispatched_at is not null and state in('DISPATCHED','PARTIAL','REJECTED') and resolved_at is null) then raise exception 'Resolve outstanding stock handovers before correcting this centre balance.' using errcode='22023';end if;
 lines:=private.pp_stock_lines(p_organisation_id,p_lines);
 if lines is null or jsonb_array_length(lines)=0 then raise exception 'Enter at least one counted material.' using errcode='22023';end if;
 select jsonb_agg(value||jsonb_build_object('book_at_count',private.pp_stock_balance(p_organisation_id,site,(value->>'item_id')::uuid)::text)) into lines from jsonb_array_elements(lines);
 insert into public.stock_documents(id,organisation_id,request_id,input_hash,reference,kind,source_id,document_date,note,lines,count_fingerprint,created_by)
 values(doc,p_organisation_id,p_request_id,digest,'COR-'||upper(substr(replace(doc::text,'-',''),1,12)),'COUNT',site,day,trim(p_document->>'note'),lines,private.pp_stock_fingerprint(p_organisation_id,site),auth.uid());
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_CORRECTION_SUBMITTED',auth.uid(),doc,jsonb_build_object('centre',site,'stock_changed',false));return doc;
end $$;
revoke all on function public.request_stock_correction(uuid,uuid,jsonb,jsonb) from public,anon;
grant execute on function public.request_stock_correction(uuid,uuid,jsonb,jsonb) to authenticated;

alter function public.stock_document_action(uuid,uuid,text,text,jsonb) rename to pp_stock_action_before_management_corrections;
alter function public.pp_stock_action_before_management_corrections(uuid,uuid,text,text,jsonb) set schema private;
revoke all on function private.pp_stock_action_before_management_corrections(uuid,uuid,text,text,jsonb) from public,anon,authenticated;
create function public.stock_document_action(p_organisation_id uuid,p_document_id uuid,p_action text,p_note text,p_received jsonb default null) returns uuid language plpgsql security definer set search_path='' as $$
declare d public.stock_documents;l jsonb;delta numeric;
begin
 perform 1 from public.organisations where id=p_organisation_id and access_state='ACTIVE' for update;
 if not found then raise exception 'An active restaurant is required.' using errcode='42501';end if;
 select * into d from public.stock_documents where organisation_id=p_organisation_id and id=p_document_id;
 if d.id is null or not private.pp_stock_doc_read(p_organisation_id,d.id) then raise exception 'Stock document is outside your access.' using errcode='42501';end if;
 if d.kind in('OPENING','COUNT') and p_action in('APPROVE','DECLINE','POST') and not private.pp_stock_adjustment_role(p_organisation_id,coalesce(d.source_id,d.destination_id)) then raise exception 'Only CEO, Finance, Operations Manager or Restaurant Administrator may approve or post balance adjustments. Inventory may submit physical counts.' using errcode='42501';end if;
 if d.kind='COUNT' and p_action in('APPROVE','DECLINE','POST') then
  if length(trim(coalesce(p_note,''))) not between 5 and 1000 then raise exception 'Explain the stock correction decision.' using errcode='22023';end if;
  if p_action in('APPROVE','DECLINE') then
   if d.created_by=auth.uid() then raise exception 'A different authorised colleague must review this count.' using errcode='42501';end if;
   if d.state<>'REQUESTED' then raise exception 'Only a pending count can be reviewed.' using errcode='22023';end if;
   update public.stock_documents set state=case when p_action='APPROVE' then 'APPROVED' else 'REJECTED' end,approved_by=auth.uid(),approved_at=clock_timestamp(),decision_note=p_note where id=d.id;
  else
   if d.state<>'APPROVED' or d.approved_by is null or d.approved_by=d.created_by then raise exception 'An independent authorised colleague must approve the count before posting.' using errcode='22023';end if;
   if not exists(select 1 from public.stock_locations where organisation_id=p_organisation_id and id=d.source_id and is_active) then raise exception 'This centre is inactive.' using errcode='22023';end if;
   if d.count_fingerprint is distinct from private.pp_stock_fingerprint(p_organisation_id,d.source_id) then raise exception 'Stock changed after this count. Cancel this correction and recount before posting.' using errcode='22023';end if;
   if exists(select 1 from public.stock_documents where organisation_id=p_organisation_id and(source_id=d.source_id or destination_id=d.source_id) and dispatched_at is not null and state in('DISPATCHED','PARTIAL','REJECTED') and resolved_at is null) then raise exception 'Resolve outstanding handovers before posting the count.' using errcode='22023';end if;
   if exists(select 1 from private.sales_stock_jobs j where j.organisation_id=p_organisation_id and j.state='PENDING' and(j.site_id=d.source_id or j.site_id is null)) then raise exception 'Resolve pending sales stock consumption before posting this correction.' using errcode='22023';end if;
   for l in select value from jsonb_array_elements(private.pp_stock_lines(p_organisation_id,d.lines)) loop
    perform private.pp_assert_centre_material(p_organisation_id,d.source_id,(l->>'item_id')::uuid);
    delta:=(l->>'quantity')::numeric-private.pp_stock_balance(p_organisation_id,d.source_id,(l->>'item_id')::uuid);
    perform private.pp_stock_entry(p_organisation_id,d.id,d.source_id,(l->>'item_id')::uuid,delta,d.document_date);
   end loop;
   update public.stock_documents set state='POSTED',completed_by=auth.uid(),completed_at=clock_timestamp(),decision_note=p_note where id=d.id;
  end if;
  insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_'||p_action,auth.uid(),d.id,jsonb_build_object('note',p_note,'correction',true));return d.id;
 end if;
 return private.pp_stock_action_before_management_corrections(p_organisation_id,p_document_id,p_action,p_note,p_received);
end $$;
revoke all on function public.stock_document_action(uuid,uuid,text,text,jsonb) from public,anon;
grant execute on function public.stock_document_action(uuid,uuid,text,text,jsonb) to authenticated;
alter function private.pp_stock_packet(uuid,uuid) rename to pp_stock_packet_before_management_corrections;
revoke all on function private.pp_stock_packet_before_management_corrections(uuid,uuid) from public,anon,authenticated;
create function private.pp_stock_packet(org uuid,doc uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare r jsonb;allowed boolean;begin
 r:=private.pp_stock_packet_before_management_corrections(org,doc);
 if r is not null and r->>'kind' in('COUNT','OPENING') then
  allowed:=private.pp_stock_adjustment_role(org,coalesce((r->>'source_id')::uuid,(r->>'destination_id')::uuid));
  if not allowed then r:=r||jsonb_build_object('actions',(r->'actions')-array['approve','decline','post']);
  elsif r->>'kind'='COUNT' then
   r:=r||jsonb_build_object('actions',(r->'actions')-array['approve','decline','post']);
   if r->>'state'='REQUESTED' and(r->>'created_by')::uuid<>auth.uid() then r:=r||jsonb_build_object('actions',(r->'actions')||jsonb_build_object('approve',true,'decline',true));end if;
   if r->>'state'='APPROVED' then r:=r||jsonb_build_object('actions',(r->'actions')||jsonb_build_object('post',true));end if;
  elsif r->>'kind'='OPENING' and r->>'state' in('REQUESTED','APPROVED') and private.pp_stock_role(org,'restaurant_admin',null) then
   r:=r||jsonb_build_object('actions',(r->'actions')||jsonb_build_object('post',true));
  end if;
 end if;return r;
end $$;
revoke all on function private.pp_stock_packet(uuid,uuid) from public,anon,authenticated;

create or replace function public.weekly_count_action(p_organisation_id uuid,p_count_id uuid,p_revision integer,p_request_id uuid,p_action text,p_reason text default '') returns uuid language plpgsql security definer set search_path='' as $$
declare c private.weekly_counts;old private.weekly_count_requests;reviewer boolean;line record;doc uuid;today date;digest text:=md5(jsonb_build_array(p_count_id,p_revision,p_action,p_reason)::text);begin
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into c from private.weekly_counts where organisation_id=p_organisation_id and id=p_count_id;
 if c.id is null or not private.pp_inventory_report_site(p_organisation_id,c.site_id) then raise exception 'Weekly count access required.' using errcode='42501';end if;
 reviewer:=private.pp_count_review_role(p_organisation_id,c.site_id);
 if (p_action in('APPROVE','REVIEW_ONLY') and(not reviewer or c.submitted_by=auth.uid())) or(p_action='POST' and not private.pp_stock_adjustment_role(p_organisation_id,c.site_id)) or(p_action in('REOPEN','RECOUNT') and not(private.pp_weekly_write(p_organisation_id,c.site_id) or reviewer)) then raise exception 'An authorised colleague must review; stock adjustments need CEO, Finance, Operations Manager or Restaurant Administrator authority.' using errcode='42501';end if;
 select * into old from private.weekly_count_requests where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then if old.actor_id<>auth.uid() or old.digest<>digest then raise exception 'This action request was already used.' using errcode='22023';end if;return c.id;end if;
 if p_request_id is null or p_action is null or p_action not in('APPROVE','POST','REOPEN','RECOUNT','REVIEW_ONLY') or c.revision is distinct from p_revision or length(coalesce(p_reason,''))>1000 then raise exception 'Refresh and choose a valid count action.' using errcode='22023';end if;
 if c.state in('POSTED','REVIEWED') then raise exception 'This count review is complete. Its history is retained.' using errcode='22023';end if;
 if p_action in('REOPEN','RECOUNT','REVIEW_ONLY') and length(trim(coalesce(p_reason,'')))<3 then raise exception 'Explain this count decision.' using errcode='22023';end if;
 perform private.pp_archive_weekly_count(c.id);
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 if p_action='APPROVE' then
  if c.state<>'SUBMITTED' then raise exception 'Only a submitted complete count can be approved.' using errcode='22023';end if;
  update private.weekly_counts set state='APPROVED',reviewed_by=auth.uid(),reviewed_at=clock_timestamp(),review_note=p_reason where id=c.id;
 elsif p_action='REVIEW_ONLY' then
  if c.state not in('SUBMITTED','APPROVED') then raise exception 'Submit the physical counts before completing review.' using errcode='22023';end if;
  update private.weekly_counts set state='REVIEWED',reviewed_by=auth.uid(),reviewed_at=clock_timestamp(),review_note=p_reason where id=c.id;
 elsif p_action in('REOPEN','RECOUNT') then
  if p_action='RECOUNT' then
   if c.daily_boundary is null and exists(select 1 from public.stock_ledger e join public.stock_documents d on d.id=e.document_id where e.organisation_id=p_organisation_id and e.location_id=c.site_id and e.occurred_on=c.count_date and d.kind='SALES') then raise exception 'Confirm this count daily boundary before refreshing a same-day sales snapshot.' using errcode='22023';end if;
   update private.weekly_count_lines l set book=coalesce((select sum(quantity) from public.stock_ledger where organisation_id=p_organisation_id and location_id=c.site_id and item_id=l.item_id and(occurred_on<c.count_date or(occurred_on=c.count_date and case when c.daily_boundary='AFTER_CLOSING' then true when c.daily_boundary='BEFORE_OPENING' then false else created_at<=c.cutoff end))),0),physical=null,note='' where count_id=c.id;
   update private.weekly_counts set snapshot_at=clock_timestamp(),ledger_watermark=coalesce((select max(id) from public.stock_ledger where organisation_id=p_organisation_id and location_id=c.site_id),0) where id=c.id;
  end if;
  update private.weekly_counts set state='DRAFT',submitted_by=null,submitted_at=null,reviewed_by=null,reviewed_at=null,review_note=p_reason where id=c.id;
 elsif p_action='POST' then
  if c.daily_boundary is null and exists(select 1 from public.stock_ledger e join public.stock_documents d on d.id=e.document_id where e.organisation_id=p_organisation_id and e.location_id=c.site_id and e.occurred_on=c.count_date and d.kind='SALES') then raise exception 'Confirm this count daily boundary before adjusting stock that includes same-day imported sales.' using errcode='22023';end if;
  if exists(select 1 from private.sales_stock_jobs j join public.sales_lines l on l.id=j.sale_line_id join public.sales_headers h on h.id=l.sale_id where j.organisation_id=p_organisation_id and j.state='PENDING' and (j.site_id=c.site_id or(j.site_id is null and ((select outlet_id from public.stock_locations where id=c.site_id) is null or (select outlet_id from public.stock_locations where id=c.site_id)=h.location_id))) and (h.sale_date<c.count_date or(h.sale_date=c.count_date and(c.daily_boundary='AFTER_CLOSING' or(c.daily_boundary is null and document_id in(select id from public.stock_documents where organisation_id=p_organisation_id and kind='SALES')))))) then raise exception 'Resolve pending sales consumption through this count boundary before adjusting stock.' using errcode='22023';end if;
  if c.state<>'APPROVED' or c.reviewed_by is null or c.reviewed_by=c.submitted_by then raise exception 'A different authorised colleague must approve this count first.' using errcode='22023';end if;
  if jsonb_array_length(c.cutoff_warnings)>0 then raise exception 'A stock handover crossed this cutoff. Reconcile it and complete review without an automatic adjustment.' using errcode='22023';end if;
  if not exists(select 1 from public.stock_locations where id=c.site_id and is_active) then raise exception 'The centre is inactive. Review without a stock adjustment or reactivate through setup.' using errcode='22023';end if;
  if exists(select 1 from public.stock_documents where organisation_id=p_organisation_id and source_id=c.site_id and dispatched_at is not null and state in('DISPATCHED','PARTIAL','REJECTED') and resolved_at is null) then raise exception 'Resolve outgoing transfers before posting a count adjustment.' using errcode='22023';end if;
  if exists(select 1 from public.stock_ledger where organisation_id=p_organisation_id and location_id=c.site_id and id>c.ledger_watermark and(occurred_on<c.count_date or(occurred_on=c.count_date and(c.daily_boundary='AFTER_CLOSING' or(c.daily_boundary is null and document_id in(select id from public.stock_documents where organisation_id=p_organisation_id and kind='SALES')))))) then raise exception 'Backdated stock changed this cutoff. Recount and review before posting.' using errcode='22023';end if;
  if exists(select 1 from public.stock_ledger e join public.stock_documents d on d.id=e.document_id and d.organisation_id=e.organisation_id where e.organisation_id=p_organisation_id and e.location_id=c.site_id and e.created_at>c.cutoff and d.kind='COUNT') then raise exception 'Another count adjustment was posted after this cutoff. Reconcile it and use review without adjustment to avoid correcting twice.' using errcode='22023';end if;
  if c.monthly_date is not null and not exists(select 1 from private.weekly_count_lines where count_id=c.id) then
   if not c.no_stock_confirmed then raise exception 'An empty count requires a no-stock declaration.' using errcode='22023';end if;
   update private.weekly_counts set state='REVIEWED',posted_by=auth.uid(),posted_at=clock_timestamp() where id=c.id;
  else
  doc:=gen_random_uuid();
  insert into public.stock_documents(id,organisation_id,request_id,input_hash,reference,kind,source_id,document_date,note,lines,output,state,created_by,approved_by,approved_at,completed_by,completed_at)
  select doc,p_organisation_id,p_request_id,digest,(case when c.monthly_date is null then 'WC-' else 'MC-' end)||upper(substr(replace(c.id::text,'-',''),1,12)),'COUNT',c.site_id,today,(case when c.monthly_date is null then 'Weekly count ' else 'Monthly count ' end)||c.count_date::text||': post the approved variance; preserve movements after cutoff',jsonb_agg(jsonb_build_object('item_id',item_id,'quantity',physical::text,'book_at_cutoff',book::text,'variance',(physical-book)::text)),jsonb_build_object('weekly_count_id',c.id,'cutoff',c.cutoff,'adjustment_policy','APPROVED_VARIANCE'),'POSTED',c.submitted_by,c.reviewed_by,c.reviewed_at,auth.uid(),clock_timestamp() from private.weekly_count_lines where count_id=c.id;
  for line in select * from private.weekly_count_lines where count_id=c.id loop
   if line.physical is null then raise exception 'Incomplete count cannot be posted.' using errcode='22023';end if;
   if line.physical<>line.book then perform private.pp_stock_entry(p_organisation_id,doc,c.site_id,line.item_id,line.physical-line.book,today);end if;
  end loop;
  update private.weekly_counts set state='POSTED',stock_document_id=doc,posted_by=auth.uid(),posted_at=clock_timestamp() where id=c.id;
  end if;
 end if;
 update private.weekly_counts set revision=revision+1 where id=c.id;
 insert into private.weekly_count_requests values(p_organisation_id,p_request_id,auth.uid(),digest,c.id);
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,(case when c.monthly_date is null then 'WEEKLY_COUNT_' else 'MONTHLY_COUNT_' end)||p_action,auth.uid(),c.id,jsonb_build_object('reason',p_reason,'revision',c.revision+1,'stock_document',doc));return c.id;
end $$;

create or replace function public.weekly_count_detail(p_organisation_id uuid,p_count_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare c private.weekly_counts;financial boolean;begin
 select * into c from private.weekly_counts where organisation_id=p_organisation_id and id=p_count_id;
 if c.id is null or not private.pp_inventory_report_site(p_organisation_id,c.site_id) then raise exception 'This weekly count is outside your access.' using errcode='42501';end if;
 financial:=(private.pp_reference_price_read(p_organisation_id) or private.pp_operations_any(p_organisation_id));
 return(to_jsonb(c)-'ledger_watermark')||jsonb_build_object('centre',(select name from public.stock_locations where id=c.site_id),'financial',financial,'currency',(select currency_code from public.organisations where id=p_organisation_id),'can_record',private.pp_weekly_write(p_organisation_id,c.site_id),'can_review',private.pp_count_review_role(p_organisation_id,c.site_id) and c.submitted_by is distinct from auth.uid(),'can_post',private.pp_stock_adjustment_role(p_organisation_id,c.site_id),
 'sales_reconciliations',coalesce((select jsonb_agg(jsonb_build_object('item_id',item_id,'book_delta',book_delta::text,'approved_at',approved_at)) from private.sales_count_reconciliations where count_id=c.id),'[]'::jsonb),'stale',exists(select 1 from public.stock_ledger where organisation_id=p_organisation_id and location_id=c.site_id and id>c.ledger_watermark and(occurred_on<c.count_date or(occurred_on=c.count_date and(c.daily_boundary='AFTER_CLOSING' or(c.daily_boundary is null and document_id in(select id from public.stock_documents where organisation_id=p_organisation_id and kind='SALES')))))),
 'lines',coalesce((select jsonb_agg(jsonb_build_object('item_id',item_id,'name',name,'code',code,'unit',unit,'book',book::text,'physical',physical::text,'variance',(physical-book)::text,'variance_percent',case when book<>0 then(100*(physical-book)/abs(book))::text end,'note',note,'unit_cost',case when financial then unit_cost::text end,'estimated_variance_value',case when financial then((physical-book)*unit_cost)::text end,'price_basis',case when financial then price_basis end) order by name,item_id) from private.weekly_count_lines where count_id=c.id),'[]'::jsonb));
end $$;

-- Approval/posting task counts follow effective authority; stock staff retain report visibility.
create or replace function public.weekly_counts_workspace(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;today date;first_day date;backlog integer;waiting integer;posting integer;tasks jsonb;begin
 if not exists(select 1 from public.stock_locations where organisation_id=p_organisation_id and private.pp_inventory_report_site(p_organisation_id,id)) then return null;end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 result:=public.weekly_counts_report(p_organisation_id,null,today-6,today+7,1);
 select coalesce(min(effective_from),today) into first_day from private.weekly_count_programmes where organisation_id=p_organisation_id;
 with rows as materialized(select value from private.pp_weekly_rows(p_organisation_id,first_day,today+7,null)value),attention as(select value from rows where(value->>'overdue')::boolean or value->>'state' in('SUBMITTED','APPROVED','DRAFT','NOT_STARTED','UPCOMING') order by(value->>'overdue')::boolean desc,value->>'day',value->>'centre' limit 8)
 select (select count(*) from rows where(value->>'overdue')::boolean),(select count(*) from rows where value->>'state'='SUBMITTED' and private.pp_stock_adjustment_role(p_organisation_id,(value->>'site_id')::uuid)),(select count(*) from rows where value->>'state'='APPROVED' and private.pp_stock_adjustment_role(p_organisation_id,(value->>'site_id')::uuid)),coalesce((select jsonb_agg(value) from attention),'[]'::jsonb) into backlog,waiting,posting,tasks;
 return jsonb_build_object('summary',result->'summary','calendar_gaps',result->'calendar_gaps','backlog',backlog,'review_waiting',waiting,'posting_waiting',posting,'rows',tasks);end $$;
create or replace function public.monthly_counts_workspace(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare today date;first_day date;last_day date;result jsonb;backlog integer;waiting integer;posting integer;tasks jsonb;begin
 if not exists(select 1 from public.stock_locations where organisation_id=p_organisation_id and private.pp_inventory_report_site(p_organisation_id,id)) then return null;end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 last_day:=(date_trunc('month',today)+interval '1 month - 1 day')::date;
 select coalesce(min(effective_from),today) into first_day from private.monthly_count_programmes where organisation_id=p_organisation_id;
 result:=public.monthly_counts_report(p_organisation_id,null,date_trunc('month',today)::date,last_day,1);
 with rows as materialized(select value from private.pp_monthly_rows(p_organisation_id,first_day,greatest(last_day,today+7),null)value),attention as(select value from rows where(value->>'overdue')::boolean or value->>'state' in('SUBMITTED','APPROVED','DRAFT','NOT_STARTED','UPCOMING') order by(value->>'overdue')::boolean desc,value->>'day',value->>'centre' limit 8)
 select(select count(*) from rows where(value->>'overdue')::boolean),(select count(*) from rows where value->>'state'='SUBMITTED' and private.pp_stock_adjustment_role(p_organisation_id,(value->>'site_id')::uuid)),(select count(*) from rows where value->>'state'='APPROVED' and private.pp_stock_adjustment_role(p_organisation_id,(value->>'site_id')::uuid)),coalesce((select jsonb_agg(value) from attention),'[]'::jsonb) into backlog,waiting,posting,tasks;
 return jsonb_build_object('summary',result->'summary','calendar_gaps',0,'backlog',backlog,'review_waiting',waiting,'posting_waiting',posting,'rows',tasks);
end $$;
create or replace function public.count_action_queue(p_organisation_id uuid,p_frequency text,p_state text,p_site_id uuid default null,p_page integer default 1) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;begin
 if not private.pp_stock_read(p_organisation_id) or(p_site_id is not null and not private.pp_inventory_report_site(p_organisation_id,p_site_id)) then raise exception 'Stock-count access required at this centre.' using errcode='42501';end if;
 if p_frequency is null or p_frequency not in('WEEKLY','MONTHLY') or p_state is null or p_state not in('SUBMITTED','APPROVED') or p_page is null or p_page not between 1 and 100000 then raise exception 'Choose the count frequency and a pending review or posting queue.' using errcode='22023';end if;
 with counts as materialized(
  select c.*,s.name centre,(select count(*) from private.weekly_count_lines where count_id=c.id) expected,(select count(*) from private.weekly_count_lines where count_id=c.id and physical is not null) entered
  from private.weekly_counts c join public.stock_locations s on s.organisation_id=c.organisation_id and s.id=c.site_id
  where c.organisation_id=p_organisation_id and c.state=p_state and(p_site_id is null or c.site_id=p_site_id) and private.pp_inventory_report_site(p_organisation_id,c.site_id) and private.pp_stock_adjustment_role(p_organisation_id,c.site_id) and(p_state<>'SUBMITTED' or c.submitted_by<>auth.uid())
  and case when p_frequency='MONTHLY' then c.monthly_date is not null else exists(select 1 from private.pp_weekly_rows(p_organisation_id,c.count_date,c.count_date,c.site_id)r where r->>'count_id'=c.id::text) end
 ),paged as(select * from counts order by cutoff,centre,id limit 25 offset(p_page-1)*25)
 select jsonb_build_object('centres',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.stock_locations where organisation_id=p_organisation_id and private.pp_inventory_report_site(p_organisation_id,id)),'[]'::jsonb),'manage',private.pp_stock_manager(p_organisation_id),'calendar_gaps',0,'total',(select count(*) from counts),
 'summary',jsonb_build_object('expected',(select count(*) from counts),'submitted',(select count(*) from counts),'overdue',0,'late',(select count(*) from counts where submitted_at>deadline),'reviewed',0),
 'rows',coalesce((select jsonb_agg(jsonb_build_object('site_id',site_id,'centre',centre,'day',case when p_frequency='MONTHLY' then monthly_date else count_date end,'count_id',id,'state',state,'expected',expected,'entered',entered,'cutoff',cutoff,'deadline',deadline,'time_zone',time_zone,'owner',owner_name,'submitter',submitter_name,'submitted_at',submitted_at,'late',submitted_at>deadline,'overdue',false,'revision',revision,'can_record',private.pp_weekly_write(p_organisation_id,site_id)) order by cutoff,centre,id) from paged),'[]'::jsonb)) into result;
 return result;
end $$;
create or replace function public.stock_workspace_alerts(p_organisation_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock access denied.' using errcode='42501';end if;
 with relevant as (
  select d.id,d.reference,d.state,d.created_at,d.dispatched_at,
   case when d.state='REQUESTED' and coalesce((private.pp_stock_packet(p_organisation_id,d.id)->'actions'->>'approve')::boolean,false) then 'Approval needed'
    when d.state='APPROVED' and(coalesce((private.pp_stock_packet(p_organisation_id,d.id)->'actions'->>'post')::boolean,false) or coalesce((private.pp_stock_packet(p_organisation_id,d.id)->'actions'->>'dispatch')::boolean,false)) then 'Ready to dispatch / post'
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

-- Recipe-output links affect processed material costs and therefore stock valuation.
alter function public.save_stock_configuration(uuid,text,jsonb) rename to pp_stock_config_before_cost_controls;
alter function public.pp_stock_config_before_cost_controls(uuid,text,jsonb) set schema private;
revoke all on function private.pp_stock_config_before_cost_controls(uuid,text,jsonb) from public,anon,authenticated;
create function public.save_stock_configuration(p_organisation_id uuid,p_kind text,p_value jsonb) returns uuid language plpgsql security definer set search_path='' as $$begin
 if p_kind='BINDING' and not private.pp_recipe_write(p_organisation_id) then raise exception 'Recipe setup authority is required to change a produced material cost link. Inventory Managers cannot edit valuation inputs.' using errcode='42501';end if;
 return private.pp_stock_config_before_cost_controls(p_organisation_id,p_kind,p_value);
end $$;
revoke all on function public.save_stock_configuration(uuid,text,jsonb) from public,anon;
grant execute on function public.save_stock_configuration(uuid,text,jsonb) to authenticated;
alter function public.stock_workspace_v2(uuid,uuid,integer,text,text,uuid) rename to pp_stock_workspace_before_cost_controls;
alter function public.pp_stock_workspace_before_cost_controls(uuid,uuid,integer,text,text,uuid) set schema private;
revoke all on function private.pp_stock_workspace_before_cost_controls(uuid,uuid,integer,text,text,uuid) from public,anon,authenticated;
create function public.stock_workspace_v2(p_organisation_id uuid,p_location_id uuid default null,p_page integer default 1,p_status text default 'ALL',p_search text default '',p_document_id uuid default null) returns jsonb language sql stable security definer set search_path='' as $$
 select private.pp_stock_workspace_before_cost_controls(p_organisation_id,p_location_id,p_page,p_status,p_search,p_document_id)||jsonb_build_object('can_cost_bindings',private.pp_stock_manager(p_organisation_id) and private.pp_recipe_write(p_organisation_id));
$$;
revoke all on function public.stock_workspace_v2(uuid,uuid,integer,text,text,uuid) from public,anon;
grant execute on function public.stock_workspace_v2(uuid,uuid,integer,text,text,uuid) to authenticated;

notify pgrst,'reload schema';
commit;
