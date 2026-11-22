-- Actual physical-count dates are separate from the monthly compliance schedule.
begin;
alter table private.weekly_counts drop constraint monthly_date_matches_sheet;
alter table private.weekly_counts add column reporting_month date,add column scheduled_cutoff timestamptz,add column schedule_exception text;
create function public.start_monthly_count_actual(p_organisation_id uuid,p_site_id uuid,p_day date,p_actual date,p_boundary text,p_reason text default '',p_reporting_month date default null) returns uuid language plpgsql security definer set search_path='' as $$declare r jsonb;c private.weekly_counts;result_id uuid;actual_cutoff timestamptz;begin
 if not private.pp_weekly_write(p_organisation_id,p_site_id) then raise exception 'Stock count entry access required at this centre.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 select value into r from private.pp_monthly_rows(p_organisation_id,p_day,p_day,p_site_id)value;
 if (p_reporting_month is not null and (extract(day from p_reporting_month)<>1 or abs((extract(year from p_reporting_month)*12+extract(month from p_reporting_month))-(extract(year from p_day)*12+extract(month from p_day)))>1)) then raise exception 'Choose the reporting month being closed, within one month of the scheduled count.' using errcode='22023';end if;
 if r is null or p_actual is null or abs(p_actual-p_day)>7 or p_boundary is null or p_boundary not in('BEFORE_OPENING','AFTER_CLOSING') then raise exception 'Choose the scheduled count, an actual date within seven days and a daily boundary.' using errcode='22023';end if;
 if p_actual<>p_day and length(trim(coalesce(p_reason,'')))<5 then raise exception 'Explain the early or late physical count.' using errcode='22023';end if;
 actual_cutoff:=((p_actual+case when p_boundary='AFTER_CLOSING' then 1 else 0 end)::timestamp) at time zone (r->>'time_zone');
 if actual_cutoff>clock_timestamp() then raise exception 'The actual physical-count boundary has not passed yet.' using errcode='22023';end if;
 if exists(select 1 from private.weekly_counts where organisation_id=p_organisation_id and site_id=p_site_id and monthly_date=p_day) then return(select id from private.weekly_counts where organisation_id=p_organisation_id and site_id=p_site_id and monthly_date=p_day);end if;
 if(r->>'expected')::integer>1000 then raise exception 'This centre exceeds the 1,000-material sheet limit. Review its material availability.' using errcode='22023';end if;
 -- One shared submission uses the earlier deadline; a monthly window cannot extend weekly duty.
 select jsonb_set(r,'{deadline}',to_jsonb(least((r->>'deadline')::timestamptz,((p_day+p.count_cutoff) at time zone p.time_zone)+make_interval(hours=>p.submission_hours)))) into r from (select * from private.weekly_count_programmes where organisation_id=p_organisation_id and site_id=p_site_id and effective_from<=p_day order by effective_from desc limit 1)p where p.active and p.count_day=extract(dow from p_day)::integer and((p_day+p.count_cutoff) at time zone p.time_zone)=(r->>'cutoff')::timestamptz and exists(select 1 from private.pp_weekly_items(p_organisation_id,p_site_id,p_day)) order by p.effective_from desc limit 1;
 if r is null then select value into r from private.pp_monthly_rows(p_organisation_id,p_day,p_day,p_site_id)value;end if;
 select * into c from private.weekly_counts where organisation_id=p_organisation_id and site_id=p_site_id and cutoff=actual_cutoff;
 if c.id is not null and c.count_date<>p_actual then raise exception 'An existing weekly count uses this same boundary under a different count date. Use its date and daily boundary to share the sheet safely.' using errcode='22023';end if;
 if c.id is not null and c.monthly_date is not null then return c.id;end if;
 if c.id is null then
  if exists(select 1 from private.weekly_counts where organisation_id=p_organisation_id and site_id=p_site_id and count_date<p_actual and state in('DRAFT','SUBMITTED','APPROVED')) then raise exception 'Finish earlier count reviews at this centre before starting another.' using errcode='22023';end if;
  insert into private.weekly_counts(organisation_id,site_id,count_date,monthly_date,cutoff,deadline,time_zone,owner_name,created_by,ledger_watermark) values(p_organisation_id,p_site_id,p_actual,p_day,actual_cutoff,(r->>'deadline')::timestamptz,r->>'time_zone',r->>'owner',auth.uid(),coalesce((select max(id) from public.stock_ledger where organisation_id=p_organisation_id and location_id=p_site_id),0)) returning * into c;
  update private.weekly_counts set cutoff_warnings=coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'reference',d.reference)) from public.stock_documents d where d.organisation_id=p_organisation_id and(d.source_id=p_site_id or d.destination_id=p_site_id) and d.dispatched_at<=c.cutoff and(d.completed_at is null or d.completed_at>c.cutoff or(d.state in('PARTIAL','REJECTED') and(d.resolved_at is null or d.resolved_at>c.cutoff)))),'[]'::jsonb) where id=c.id;
 elsif c.state<>'DRAFT' and exists(select 1 from private.pp_monthly_items(p_organisation_id,p_site_id,p_actual)m where not exists(select 1 from private.weekly_count_lines where count_id=c.id and item_id=m.item_id)) then raise exception 'The existing weekly submission lacks monthly materials. Reopen and complete its full sheet before sharing it.' using errcode='22023';
 else
  perform private.pp_archive_weekly_count(c.id);
  update private.weekly_counts set monthly_date=p_day,count_date=p_actual,revision=revision+1,deadline=least(deadline,(r->>'deadline')::timestamptz) where id=c.id;
 end if;
 insert into private.weekly_count_lines(count_id,item_id,name,code,unit,book,unit_cost,price_basis)
 select c.id,i.id,i.name,i.code,u.code,coalesce((select sum(quantity) from public.stock_ledger where organisation_id=p_organisation_id and location_id=p_site_id and item_id=i.id and(occurred_on<p_actual or(occurred_on=p_actual and p_boundary='AFTER_CLOSING'))),0),(cost->>'unit_cost')::numeric,cost
 from private.pp_monthly_items(p_organisation_id,p_site_id,p_actual)m join public.items i on i.organisation_id=p_organisation_id and i.id=m.item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id cross join lateral(select private.pp_effective_material_cost(p_organisation_id,i.id,p_actual) cost)p on conflict(count_id,item_id) do nothing;
 update private.weekly_counts set reporting_month=coalesce(p_reporting_month,date_trunc('month',p_day)::date),daily_boundary=p_boundary,scheduled_cutoff=(r->>'cutoff')::timestamptz,schedule_exception=p_reason where id=c.id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'MONTHLY_COUNT_STARTED',auth.uid(),c.id,jsonb_build_object('centre',p_site_id,'date',p_day,'cutoff',c.cutoff,'shared_weekly_sheet',c.monthly_date is null));return c.id;
end $$;
create or replace function public.weekly_count_action(p_organisation_id uuid,p_count_id uuid,p_revision integer,p_request_id uuid,p_action text,p_reason text default '') returns uuid language plpgsql security definer set search_path='' as $$
declare c private.weekly_counts;old private.weekly_count_requests;reviewer boolean;line record;doc uuid;today date;digest text:=md5(jsonb_build_array(p_count_id,p_revision,p_action,p_reason)::text);begin
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into c from private.weekly_counts where organisation_id=p_organisation_id and id=p_count_id;
 if c.id is null or not private.pp_inventory_report_site(p_organisation_id,c.site_id) then raise exception 'Weekly count access required.' using errcode='42501';end if;
 reviewer:=private.pp_count_review_role(p_organisation_id,c.site_id);
 if (p_action in('APPROVE','REVIEW_ONLY') and(not reviewer or c.submitted_by=auth.uid())) or(p_action='POST' and not private.pp_stock_site(p_organisation_id,c.site_id,'inventory')) or(p_action in('REOPEN','RECOUNT') and not(private.pp_weekly_write(p_organisation_id,c.site_id) or reviewer)) then raise exception 'An authorised colleague must review; stock posting needs Inventory authority.' using errcode='42501';end if;
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
 return(to_jsonb(c)-'ledger_watermark')||jsonb_build_object('centre',(select name from public.stock_locations where id=c.site_id),'financial',financial,'currency',(select currency_code from public.organisations where id=p_organisation_id),'can_record',private.pp_weekly_write(p_organisation_id,c.site_id),'can_review',private.pp_count_review_role(p_organisation_id,c.site_id) and c.submitted_by is distinct from auth.uid(),'can_post',private.pp_stock_site(p_organisation_id,c.site_id,'inventory'),
 'sales_reconciliations',coalesce((select jsonb_agg(jsonb_build_object('item_id',item_id,'book_delta',book_delta::text,'approved_at',approved_at)) from private.sales_count_reconciliations where count_id=c.id),'[]'::jsonb),'stale',exists(select 1 from public.stock_ledger where organisation_id=p_organisation_id and location_id=c.site_id and id>c.ledger_watermark and(occurred_on<c.count_date or(occurred_on=c.count_date and(c.daily_boundary='AFTER_CLOSING' or(c.daily_boundary is null and document_id in(select id from public.stock_documents where organisation_id=p_organisation_id and kind='SALES')))))),
 'lines',coalesce((select jsonb_agg(jsonb_build_object('item_id',item_id,'name',name,'code',code,'unit',unit,'book',book::text,'physical',physical::text,'variance',(physical-book)::text,'variance_percent',case when book<>0 then(100*(physical-book)/abs(book))::text end,'note',note,'unit_cost',case when financial then unit_cost::text end,'estimated_variance_value',case when financial then((physical-book)*unit_cost)::text end,'price_basis',case when financial then price_basis end) order by name,item_id) from private.weekly_count_lines where count_id=c.id),'[]'::jsonb));
end $$;
create function public.clarify_count_sales_boundary(p_organisation_id uuid,p_count_id uuid,p_boundary text,p_reason text) returns void language plpgsql security definer set search_path='' as $$declare c private.weekly_counts;begin
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into c from private.weekly_counts where organisation_id=p_organisation_id and id=p_count_id;
 if c.id is null or not private.pp_count_review_role(p_organisation_id,c.site_id) or c.submitted_by=auth.uid() then raise exception 'Independent count-review access required.' using errcode='42501';end if;
 if p_boundary is null or p_boundary not in('BEFORE_OPENING','AFTER_CLOSING') or length(trim(coalesce(p_reason,'')))<5 or c.daily_boundary is not null then raise exception 'Explain the actual daily count boundary. An existing declaration cannot be overwritten.' using errcode='22023';end if;
 perform private.pp_archive_weekly_count(c.id);
 update private.weekly_counts set daily_boundary=p_boundary,revision=revision+1 where id=c.id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'COUNT_SALES_BOUNDARY',auth.uid(),c.id,jsonb_build_object('boundary',p_boundary,'reason',p_reason,'stock_changed',false));
end $$;
revoke all on function public.start_monthly_count_actual(uuid,uuid,date,date,text,text,date),public.clarify_count_sales_boundary(uuid,uuid,text,text) from public,anon;
grant execute on function public.start_monthly_count_actual(uuid,uuid,date,date,text,text,date),public.clarify_count_sales_boundary(uuid,uuid,text,text) to authenticated;
create or replace function public.monthly_count_analysis(p_organisation_id uuid,p_site_id uuid,p_from date,p_to date,p_page integer default 1) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;financial boolean;today date;begin
 if not private.pp_stock_read(p_organisation_id) or(p_site_id is not null and not private.pp_inventory_report_site(p_organisation_id,p_site_id)) then raise exception 'Monthly count analysis access required.' using errcode='42501';end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 if p_from is null or p_to is null or p_from>p_to or p_to>today+62 or p_to-p_from>366 or p_page is null or p_page not between 1 and 100000 then raise exception 'Choose a valid monthly analysis period.' using errcode='22023';end if;
 financial:=private.pp_reference_price_read(p_organisation_id) or private.pp_operations_any(p_organisation_id);
 with sheets as materialized(select * from private.weekly_counts c where c.organisation_id=p_organisation_id and coalesce(c.reporting_month,c.monthly_date) between date_trunc('month',p_from)::date and p_to and(p_site_id is null or c.site_id=p_site_id) and private.pp_inventory_report_site(p_organisation_id,c.site_id) and c.state in('SUBMITTED','APPROVED','POSTED','REVIEWED')),
 lines as materialized(select l.count_id,l.item_id,l.name,l.code,l.unit,l.book+coalesce((select sum(z.book_delta) from private.sales_count_reconciliations z where z.count_id=l.count_id and z.item_id=l.item_id),0) book,l.physical,l.note,l.unit_cost,l.price_basis,coalesce(c.reporting_month,c.monthly_date) monthly_date from sheets c join private.weekly_count_lines l on l.count_id=c.id),
 latest as(select distinct on(site_id) id from sheets order by site_id,cutoff desc),
 materials as(select item_id,min(name) name,min(code) code,min(unit) unit,count(*) filter(where physical<>book) occurrences,count(distinct date_trunc('month',monthly_date)) filter(where physical<>book) months_affected,sum(greatest(book-physical,0)) shortage,sum(greatest(physical-book,0)) surplus,sum((physical-book)*unit_cost) estimated_variance,count(*) filter(where unit_cost is null and physical<>book) unpriced from lines group by item_id having bool_or(physical<>book)),
 paged as(select * from materials order by occurrences desc,name,item_id limit 25 offset(p_page-1)*25),
 trend as(select date_trunc('month',monthly_date)::date month_start,sum(book*unit_cost) book_value,sum(physical*unit_cost) physical_value,sum(greatest(book-physical,0)*unit_cost) shortage,sum(greatest(physical-book,0)*unit_cost) surplus,count(distinct count_id) sheets,count(*) filter(where unit_cost is null and(book<>0 or physical<>0)) unpriced from lines group by 1)
 select jsonb_build_object('financial',financial,'currency',(select currency_code from public.organisations where id=p_organisation_id),'total',(select count(*) from materials),'sheets',(select count(*) from sheets),
 'summary',(select jsonb_build_object('book_value',case when financial then(select coalesce(sum(l.book*l.unit_cost),0)::text from lines l join latest z on z.id=l.count_id) end,'physical_value',case when financial then(select coalesce(sum(l.physical*l.unit_cost),0)::text from lines l join latest z on z.id=l.count_id) end,'shortage_value',case when financial then coalesce(sum(greatest(book-physical,0)*unit_cost),0)::text end,'surplus_value',case when financial then coalesce(sum(greatest(physical-book,0)*unit_cost),0)::text end,'unpriced',case when financial then count(*) filter(where unit_cost is null and(book<>0 or physical<>0)) end,'variance_lines',count(*) filter(where physical<>book)) from lines),
 'trend',coalesce((select jsonb_agg(jsonb_build_object('month',month_start,'sheets',sheets,'book_value',case when financial then book_value::text end,'physical_value',case when financial then physical_value::text end,'shortage',case when financial then shortage::text end,'surplus',case when financial then surplus::text end,'unpriced',case when financial then unpriced end) order by month_start) from trend),'[]'::jsonb),
 'rows',coalesce((select jsonb_agg(jsonb_build_object('item_id',item_id,'name',name,'code',code,'unit',unit,'occurrences',occurrences,'months_affected',months_affected,'shortage',shortage::text,'surplus',surplus::text,'estimated_variance',case when financial then estimated_variance::text end,'unpriced',case when financial then unpriced end)) from paged),'[]'::jsonb)) into result;return result;
end $$;
notify pgrst,'reload schema';commit;
