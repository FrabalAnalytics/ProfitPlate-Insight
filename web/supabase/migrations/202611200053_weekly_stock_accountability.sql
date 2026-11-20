-- Weekly physical counts are obligations, not automatic stock replacements.
begin;
create table private.weekly_count_settings(organisation_id uuid primary key references public.organisations(id),submission_hours integer not null default 24 check(submission_hours between 1 and 168));
create table private.weekly_count_programmes(organisation_id uuid not null,site_id uuid not null,effective_from date not null,active boolean not null,count_day integer,count_cutoff time,time_zone text not null,week_start integer,submission_hours integer not null,owner_id uuid,owner_name text,primary key(organisation_id,site_id,effective_from),foreign key(organisation_id,site_id) references public.stock_locations(organisation_id,id));
create table private.weekly_count_scope(organisation_id uuid not null,site_id uuid not null,item_id uuid not null,effective_from date not null,required boolean not null,included boolean not null default true,actor_id uuid,primary key(organisation_id,site_id,item_id,effective_from),foreign key(organisation_id,site_id) references public.stock_locations(organisation_id,id),foreign key(organisation_id,item_id) references public.items(organisation_id,id));
create table private.weekly_counts(id uuid primary key default gen_random_uuid(),organisation_id uuid not null,site_id uuid not null,count_date date not null,cutoff timestamptz not null,deadline timestamptz not null,time_zone text not null,owner_name text,state text not null default 'DRAFT' check(state in('DRAFT','SUBMITTED','APPROVED','POSTED','REVIEWED')),revision integer not null default 0,snapshot_at timestamptz not null default clock_timestamp(),ledger_watermark bigint not null default 0,created_by uuid not null,submitter_name text,submitted_by uuid,submitted_at timestamptz,reviewed_by uuid,reviewed_at timestamptz,review_note text,posted_by uuid,posted_at timestamptz,stock_document_id uuid,unique(organisation_id,site_id,count_date),foreign key(organisation_id,site_id) references public.stock_locations(organisation_id,id));
alter table private.weekly_counts add column submission_note text,add column cutoff_warnings jsonb not null default '[]';
create table private.weekly_count_lines(count_id uuid not null references private.weekly_counts(id),item_id uuid not null,name text not null,code text not null,unit text not null,book numeric(38,12) not null,physical numeric(38,12),note text not null default '',unit_cost numeric,price_basis jsonb,primary key(count_id,item_id));
create table private.weekly_count_history(id bigint generated always as identity primary key,count_id uuid not null references private.weekly_counts(id),revision integer not null,data jsonb not null,changed_by uuid not null,changed_at timestamptz not null default clock_timestamp(),unique(count_id,revision));
create table private.weekly_count_requests(organisation_id uuid not null,request_id uuid not null,actor_id uuid not null,digest text not null,count_id uuid not null references private.weekly_counts(id),primary key(organisation_id,request_id));
revoke all on private.weekly_count_settings,private.weekly_count_programmes,private.weekly_count_scope,private.weekly_counts,private.weekly_count_lines,private.weekly_count_requests,private.weekly_count_history from public,anon,authenticated;
create function private.pp_weekly_programme(org uuid,site uuid,day date) returns void language plpgsql security definer set search_path='' as $$begin
 insert into private.weekly_count_programmes select o.id,s.id,day,s.is_active,o.count_day,o.count_cutoff,o.time_zone,o.reporting_week_start,coalesce(c.submission_hours,24),s.responsible_membership_id,private.pp_member_label(o.id,s.responsible_membership_id) from public.organisations o join public.stock_locations s on s.organisation_id=o.id left join private.weekly_count_settings c on c.organisation_id=o.id where o.id=org and s.id=site
 on conflict(organisation_id,site_id,effective_from) do update set active=excluded.active,count_day=excluded.count_day,count_cutoff=excluded.count_cutoff,time_zone=excluded.time_zone,week_start=excluded.week_start,submission_hours=excluded.submission_hours,owner_id=excluded.owner_id,owner_name=excluded.owner_name;
end $$;
create function private.pp_count_scope_seed(org uuid,site uuid,item uuid,start_day date default null,force_flag boolean default false) returns void language plpgsql security definer set search_path='' as $$
declare day date;flag boolean;prior private.weekly_count_scope;begin
 select coalesce(start_day,(now() at time zone o.time_zone)::date+case when o.count_cutoff is not null and(now() at time zone o.time_zone)::time>=o.count_cutoff then 1 else 0 end),i.weekly_count_required and i.is_active and i.stock_tracked and i.base_uom_id is not null into day,flag from public.organisations o join public.items i on i.organisation_id=o.id where o.id=org and i.id=item;
 if day is null then return;end if;
 select * into prior from private.weekly_count_scope where organisation_id=org and site_id=site and item_id=item order by effective_from desc limit 1;
 if prior.item_id is not null and not force_flag then return;end if;
 if not flag and prior.item_id is null then return;end if;
 insert into private.weekly_count_scope values(org,site,item,day,flag,coalesce(prior.included,true),auth.uid()) on conflict(organisation_id,site_id,item_id,effective_from) do update set required=excluded.required;
end $$;
-- Initial obligations begin at the next eligible local cutoff; no historical arrears are invented.
do $$declare s record;e record;day date;begin
 for s in select l.*,o.time_zone,o.count_cutoff from public.stock_locations l join public.organisations o on o.id=l.organisation_id loop
 day:=(now() at time zone s.time_zone)::date+case when s.count_cutoff is not null and(now() at time zone s.time_zone)::time>=s.count_cutoff then 1 else 0 end;perform private.pp_weekly_programme(s.organisation_id,s.id,day);
 for e in select distinct item_id from public.stock_ledger where organisation_id=s.organisation_id and location_id=s.id union select item_id from public.zero_opening_confirmations where organisation_id=s.organisation_id and stock_location_id=s.id loop perform private.pp_count_scope_seed(s.organisation_id,s.id,e.item_id,day);end loop;
 end loop;
end $$;
create function private.pp_track_count_centre() returns trigger language plpgsql security definer set search_path='' as $$declare day date;begin
 if tg_op='UPDATE' and(old.is_active,old.responsible_membership_id) is not distinct from(new.is_active,new.responsible_membership_id) then return new;end if;
 select(now() at time zone time_zone)::date+case when tg_op='UPDATE' or(count_cutoff is not null and(now() at time zone time_zone)::time>=count_cutoff) then 1 else 0 end into day from public.organisations where id=new.organisation_id;
 perform private.pp_weekly_programme(new.organisation_id,new.id,day);return new;end $$;
create trigger track_count_centre after insert or update on public.stock_locations for each row execute function private.pp_track_count_centre();
create function private.pp_track_count_calendar() returns trigger language plpgsql security definer set search_path='' as $$declare s record;begin
 if(old.count_day,old.count_cutoff,old.time_zone,old.reporting_week_start) is not distinct from(new.count_day,new.count_cutoff,new.time_zone,new.reporting_week_start) then return new;end if;
 for s in select id from public.stock_locations where organisation_id=new.id loop perform private.pp_weekly_programme(new.id,s.id,(now() at time zone new.time_zone)::date+1);end loop;return new;end $$;
create trigger track_count_calendar after update on public.organisations for each row execute function private.pp_track_count_calendar();
create function private.pp_track_count_material() returns trigger language plpgsql security definer set search_path='' as $$declare s record;day date;begin
 if(old.weekly_count_required,old.is_active,old.stock_tracked) is not distinct from(new.weekly_count_required,new.is_active,new.stock_tracked) then return new;end if;
 select(now() at time zone time_zone)::date+1 into day from public.organisations where id=new.organisation_id;
 for s in select site_id from private.weekly_count_scope where organisation_id=new.organisation_id and item_id=new.id union select location_id from public.stock_ledger where organisation_id=new.organisation_id and item_id=new.id union select stock_location_id from public.zero_opening_confirmations where organisation_id=new.organisation_id and item_id=new.id loop perform private.pp_count_scope_seed(new.organisation_id,s.site_id,new.id,day,true);end loop;return new;end $$;
create trigger track_count_material after update on public.items for each row execute function private.pp_track_count_material();
create function private.pp_track_count_ledger() returns trigger language plpgsql security definer set search_path='' as $$begin
 perform private.pp_count_scope_seed(new.organisation_id,new.location_id,new.item_id);return new;end $$;
create trigger track_count_ledger after insert on public.stock_ledger for each row execute function private.pp_track_count_ledger();
create function private.pp_track_zero_count_scope() returns trigger language plpgsql security definer set search_path='' as $$begin perform private.pp_count_scope_seed(new.organisation_id,new.stock_location_id,new.item_id);return new;end $$;
create trigger track_zero_count_scope after insert on public.zero_opening_confirmations for each row execute function private.pp_track_zero_count_scope();
create function private.pp_weekly_items(org uuid,site uuid,day date) returns table(item_id uuid) language sql stable security definer set search_path='' as $$
 select q.item_id from(select distinct on(item_id) item_id,required,included from private.weekly_count_scope where organisation_id=org and site_id=site and effective_from<=day order by item_id,effective_from desc)q where required and included;
$$;
create function private.pp_weekly_write(org uuid,site uuid) returns boolean language sql stable security definer set search_path='' as $$select private.pp_inventory_report_site(org,site) and(private.pp_stock_manager(org) or private.pp_stock_site(org,site,'request'));$$;
create function private.pp_weekly_rows(org uuid,from_day date,to_day date,site uuid default null) returns setof jsonb language sql stable security definer set search_path='' as $$
 with dates as(select s.id site_id,s.name centre,d::date as day from public.stock_locations s cross join generate_series(from_day::timestamp,to_day::timestamp,'1 day')d where s.organisation_id=org and(site is null or s.id=site) and private.pp_inventory_report_site(org,s.id)),
 planned as(select d.site_id,d.centre,d.day,p.time_zone,c.id count_id,c.state,c.revision,c.submitted_at,c.submitter_name,c.stock_document_id,coalesce(c.cutoff,(d.day+p.count_cutoff) at time zone p.time_zone) cutoff_at,coalesce(c.deadline,((d.day+p.count_cutoff) at time zone p.time_zone)+make_interval(hours=>p.submission_hours)) due_at,
 case when c.id is null then(select count(*) from private.pp_weekly_items(org,d.site_id,d.day)) else(select count(*) from private.weekly_count_lines where count_id=c.id) end expected,
 (select count(*) from private.weekly_count_lines where count_id=c.id and physical is not null) entered,
 coalesce(c.owner_name,p.owner_name) owner
 from dates d left join lateral(select * from private.weekly_count_programmes where organisation_id=org and site_id=d.site_id and effective_from<=d.day order by effective_from desc limit 1)p on true left join private.weekly_counts c on c.organisation_id=org and c.site_id=d.site_id and c.count_date=d.day
 where c.id is not null or(p.active and p.count_day=extract(dow from d.day)::integer and p.count_cutoff is not null))
 select jsonb_build_object('site_id',site_id,'centre',centre,'day',day,'count_id',count_id,'state',case when state is not null then state when cutoff_at>clock_timestamp() then 'UPCOMING' else 'NOT_STARTED' end,'expected',expected,'entered',entered,'cutoff',cutoff_at,'deadline',due_at,'time_zone',time_zone,'owner',owner,'submitter',submitter_name,'submitted_at',submitted_at,'late',submitted_at>due_at,'overdue',due_at<clock_timestamp() and coalesce(state,'DRAFT')='DRAFT','revision',revision,'can_record',private.pp_weekly_write(org,site_id)) from planned where expected>0;
$$;
create function public.weekly_counts_report(p_organisation_id uuid,p_site_id uuid,p_from date,p_to date,p_page integer default 1) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;today date;begin
 if not private.pp_stock_read(p_organisation_id) or(p_site_id is not null and not private.pp_inventory_report_site(p_organisation_id,p_site_id)) then raise exception 'Weekly count report access required.' using errcode='42501';end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 if p_from is null or p_to is null or p_from>p_to or p_to>today+7 or p_to-p_from>366 or p_page is null or p_page not between 1 and 100000 then raise exception 'Choose a valid count period of up to 367 days.' using errcode='22023';end if;
 with rows as materialized(select value from private.pp_weekly_rows(p_organisation_id,p_from,p_to,p_site_id)value),paged as(select value from rows order by(value->>'overdue')::boolean desc,value->>'day' desc,value->>'centre' limit 25 offset(p_page-1)*25)
 select jsonb_build_object('centres',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.stock_locations where organisation_id=p_organisation_id and private.pp_inventory_report_site(p_organisation_id,id)),'[]'::jsonb),'manage',private.pp_stock_manager(p_organisation_id),'total',(select count(*) from rows),
 'summary',(select jsonb_build_object('expected',count(*) filter(where(value->>'cutoff')::timestamptz<=clock_timestamp()),'submitted',count(*) filter(where value->>'state' in('SUBMITTED','APPROVED','POSTED','REVIEWED')),'overdue',count(*) filter(where(value->>'overdue')::boolean),'late',count(*) filter(where(value->>'late')::boolean),'reviewed',count(*) filter(where value->>'state' in('POSTED','REVIEWED'))) from rows),
 'calendar_gaps',(select count(*) from public.stock_locations s where s.organisation_id=p_organisation_id and s.is_active and private.pp_inventory_report_site(p_organisation_id,s.id) and exists(select 1 from public.organisations o where o.id=s.organisation_id and(o.count_day is null or o.count_cutoff is null))),
 'rows',coalesce((select jsonb_agg(value) from paged),'[]'::jsonb)) into result;return result;
end $$;
create function public.weekly_count_detail(p_organisation_id uuid,p_count_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare c private.weekly_counts;financial boolean;begin
 select * into c from private.weekly_counts where organisation_id=p_organisation_id and id=p_count_id;
 if c.id is null or not private.pp_inventory_report_site(p_organisation_id,c.site_id) then raise exception 'This weekly count is outside your access.' using errcode='42501';end if;
 financial:=private.pp_reference_price_read(p_organisation_id);
 return(to_jsonb(c)-'ledger_watermark')||jsonb_build_object('centre',(select name from public.stock_locations where id=c.site_id),'financial',financial,'currency',(select currency_code from public.organisations where id=p_organisation_id),'can_record',private.pp_weekly_write(p_organisation_id,c.site_id),'can_review',(private.pp_stock_manager(p_organisation_id) or private.pp_stock_role(p_organisation_id,'finance',(select outlet_id from public.stock_locations where id=c.site_id))) and c.submitted_by is distinct from auth.uid(),'can_post',private.pp_stock_site(p_organisation_id,c.site_id,'inventory'),
 'stale',exists(select 1 from public.stock_ledger where organisation_id=p_organisation_id and location_id=c.site_id and id>c.ledger_watermark and occurred_on<c.count_date),
 'lines',coalesce((select jsonb_agg(jsonb_build_object('item_id',item_id,'name',name,'code',code,'unit',unit,'book',book::text,'physical',physical::text,'variance',(physical-book)::text,'variance_percent',case when book<>0 then(100*(physical-book)/abs(book))::text end,'note',note,'unit_cost',case when financial then unit_cost::text end,'estimated_variance_value',case when financial then((physical-book)*unit_cost)::text end,'price_basis',case when financial then price_basis end) order by name,item_id) from private.weekly_count_lines where count_id=c.id),'[]'::jsonb));
end $$;
create function public.start_weekly_count(p_organisation_id uuid,p_site_id uuid,p_day date) returns uuid language plpgsql security definer set search_path='' as $$declare r jsonb;result_id uuid;watermark bigint;line record;begin
 if not private.pp_weekly_write(p_organisation_id,p_site_id) then raise exception 'Stock count entry access required at this centre.' using errcode='42501';end if;
 perform 1 from public.organisations where organisations.id=p_organisation_id for update;
 select c.id into result_id from private.weekly_counts c where organisation_id=p_organisation_id and site_id=p_site_id and count_date=p_day;if result_id is not null then return result_id;end if;
 select value into r from private.pp_weekly_rows(p_organisation_id,p_day,p_day,p_site_id)value;
 if r is null or(r->>'cutoff')::timestamptz>clock_timestamp() then raise exception 'Start the count at or after its scheduled cutoff. Check the reporting calendar and centre count scope.' using errcode='22023';end if;
 if(r->>'expected')::integer>1000 then raise exception 'This count exceeds the 1,000-material sheet limit. Review the centre count scope.' using errcode='22023';end if;
 if exists(select 1 from private.weekly_counts where organisation_id=p_organisation_id and site_id=p_site_id and count_date<p_day and state in('DRAFT','SUBMITTED','APPROVED')) then raise exception 'Finish the earlier count review at this centre before starting another.' using errcode='22023';end if;
 select coalesce(max(e.id),0) into watermark from public.stock_ledger e where organisation_id=p_organisation_id and location_id=p_site_id;
 insert into private.weekly_counts(organisation_id,site_id,count_date,cutoff,deadline,time_zone,owner_name,created_by,ledger_watermark) values(p_organisation_id,p_site_id,p_day,(r->>'cutoff')::timestamptz,(r->>'deadline')::timestamptz,r->>'time_zone',r->>'owner',auth.uid(),watermark) returning weekly_counts.id into result_id;
 update private.weekly_counts set cutoff_warnings=coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'reference',d.reference)) from public.stock_documents d where d.organisation_id=p_organisation_id and(d.source_id=p_site_id or d.destination_id=p_site_id) and d.dispatched_at<=(r->>'cutoff')::timestamptz and(d.completed_at is null or d.completed_at>(r->>'cutoff')::timestamptz or(d.state in('PARTIAL','REJECTED') and(d.resolved_at is null or d.resolved_at>(r->>'cutoff')::timestamptz)))),'[]'::jsonb) where weekly_counts.id=result_id;
 insert into private.weekly_count_lines(count_id,item_id,name,code,unit,book,unit_cost,price_basis)
 select result_id,i.id,i.name,i.code,u.code,coalesce((select sum(quantity) from public.stock_ledger where organisation_id=p_organisation_id and location_id=p_site_id and item_id=i.id and(occurred_on<p_day or(occurred_on=p_day and created_at<=(r->>'cutoff')::timestamptz))),0),(cost->>'unit_cost')::numeric,cost
 from private.pp_weekly_items(p_organisation_id,p_site_id,p_day) x join public.items i on i.organisation_id=p_organisation_id and i.id=x.item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id cross join lateral(select private.pp_effective_material_cost(p_organisation_id,i.id,p_day) cost)priced;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'WEEKLY_COUNT_STARTED',auth.uid(),result_id,jsonb_build_object('centre',p_site_id,'count_date',p_day,'cutoff',r->'cutoff'));return result_id;
end $$;
create function private.pp_archive_weekly_count(count_id uuid) returns void language plpgsql security definer set search_path='' as $$begin
 insert into private.weekly_count_history(count_id,revision,data,changed_by)
 select c.id,c.revision,jsonb_build_object('report',to_jsonb(c),'lines',(select jsonb_agg(to_jsonb(l)||jsonb_build_object('book',l.book::text,'physical',l.physical::text,'unit_cost',l.unit_cost::text) order by l.name,l.item_id) from private.weekly_count_lines l where l.count_id=c.id)),auth.uid() from private.weekly_counts c where c.id=count_id on conflict do nothing;
end $$;
create function public.save_weekly_count(p_organisation_id uuid,p_count_id uuid,p_revision integer,p_request_id uuid,p_rows jsonb,p_submit boolean,p_submitter text,p_note text default '') returns uuid language plpgsql security definer set search_path='' as $$
declare c private.weekly_counts;old private.weekly_count_requests;entry jsonb;qty numeric;digest text:=md5(jsonb_build_array(p_count_id,p_revision,p_rows,p_submit,p_submitter,p_note)::text);begin
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into c from private.weekly_counts where organisation_id=p_organisation_id and id=p_count_id;
 if c.id is null or not private.pp_weekly_write(p_organisation_id,c.site_id) then raise exception 'Count entry access required.' using errcode='42501';end if;
 select * into old from private.weekly_count_requests where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then if old.actor_id<>auth.uid() or old.digest<>digest then raise exception 'This request was already used. Refresh before changing it.' using errcode='22023';end if;return c.id;end if;
 if p_request_id is null or c.state<>'DRAFT' or c.revision is distinct from p_revision or p_submit is null or p_rows is null or jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows)>1000 or octet_length(p_rows::text)>262144 or length(coalesce(p_note,''))>1000 then raise exception 'This count changed or has invalid entries. Refresh and review it.' using errcode='22023';end if;
 if(select count(*)<>count(distinct value->>'item_id') from jsonb_array_elements(p_rows)) or exists(select 1 from jsonb_array_elements(p_rows) r where not exists(select 1 from private.weekly_count_lines l where l.count_id=c.id and l.item_id::text=r->>'item_id')) then raise exception 'Use each expected material once. Unknown count materials are not allowed.' using errcode='22023';end if;
 perform private.pp_archive_weekly_count(c.id);
 for entry in select value from jsonb_array_elements(p_rows) loop
  qty:=case when nullif(trim(entry->>'physical'),'') is not null then private.pp_stock_number(entry->>'physical',true) end;
  if length(coalesce(entry->>'note',''))>500 then raise exception 'Keep material notes within 500 characters.' using errcode='22023';end if;
  update private.weekly_count_lines set physical=qty,note=trim(coalesce(entry->>'note','')) where count_id=c.id and item_id::text=entry->>'item_id';
 end loop;
 if p_submit then
  if p_submitter is null or length(trim(p_submitter)) not between 1 and 120 or p_submitter~'[[:cntrl:]]' then raise exception 'Enter the submitter name.' using errcode='22023';end if;
  if exists(select 1 from private.weekly_count_lines where count_id=c.id and physical is null) then raise exception 'Count every expected material. Enter an explicit zero where none is held; blanks are incomplete.' using errcode='22023';end if;
  if length(trim(coalesce(p_note,'')))<3 and exists(select 1 from private.weekly_count_lines where count_id=c.id and physical<>book and length(trim(note))<3) then raise exception 'Explain the variance, or state that it is under investigation.' using errcode='22023';end if;
 end if;
 update private.weekly_counts set revision=revision+1,state=case when p_submit then 'SUBMITTED' else 'DRAFT' end,submitter_name=case when p_submit then trim(p_submitter) else submitter_name end,submitted_by=case when p_submit then auth.uid() else submitted_by end,submitted_at=case when p_submit then clock_timestamp() else submitted_at end,submission_note=trim(coalesce(p_note,'')) where id=c.id;
 insert into private.weekly_count_requests values(p_organisation_id,p_request_id,auth.uid(),digest,c.id);
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,case when p_submit then 'WEEKLY_COUNT_SUBMITTED' else 'WEEKLY_COUNT_DRAFT' end,auth.uid(),c.id,jsonb_build_object('centre',c.site_id,'revision',c.revision+1,'stock_changed',false));return c.id;
end $$;
create function public.weekly_count_action(p_organisation_id uuid,p_count_id uuid,p_revision integer,p_request_id uuid,p_action text,p_reason text default '') returns uuid language plpgsql security definer set search_path='' as $$
declare c private.weekly_counts;old private.weekly_count_requests;reviewer boolean;line record;doc uuid;today date;digest text:=md5(jsonb_build_array(p_count_id,p_revision,p_action,p_reason)::text);begin
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into c from private.weekly_counts where organisation_id=p_organisation_id and id=p_count_id;
 if c.id is null or not private.pp_inventory_report_site(p_organisation_id,c.site_id) then raise exception 'Weekly count access required.' using errcode='42501';end if;
 reviewer:=private.pp_stock_manager(p_organisation_id) or private.pp_stock_role(p_organisation_id,'finance',(select outlet_id from public.stock_locations where id=c.site_id));
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
   update private.weekly_count_lines l set book=coalesce((select sum(quantity) from public.stock_ledger where organisation_id=p_organisation_id and location_id=c.site_id and item_id=l.item_id and(occurred_on<c.count_date or(occurred_on=c.count_date and created_at<=c.cutoff))),0),physical=null,note='' where count_id=c.id;
   update private.weekly_counts set snapshot_at=clock_timestamp(),ledger_watermark=coalesce((select max(id) from public.stock_ledger where organisation_id=p_organisation_id and location_id=c.site_id),0) where id=c.id;
  end if;
  update private.weekly_counts set state='DRAFT',submitted_by=null,submitted_at=null,reviewed_by=null,reviewed_at=null,review_note=p_reason where id=c.id;
 elsif p_action='POST' then
  if c.state<>'APPROVED' or c.reviewed_by is null or c.reviewed_by=c.submitted_by then raise exception 'A different authorised colleague must approve this count first.' using errcode='22023';end if;
  if jsonb_array_length(c.cutoff_warnings)>0 then raise exception 'A stock handover crossed this cutoff. Reconcile it and complete review without an automatic adjustment.' using errcode='22023';end if;
  if not exists(select 1 from public.stock_locations where id=c.site_id and is_active) then raise exception 'The centre is inactive. Review without a stock adjustment or reactivate through setup.' using errcode='22023';end if;
  if exists(select 1 from public.stock_documents where organisation_id=p_organisation_id and source_id=c.site_id and dispatched_at is not null and state in('DISPATCHED','PARTIAL','REJECTED') and resolved_at is null) then raise exception 'Resolve outgoing transfers before posting a count adjustment.' using errcode='22023';end if;
  if exists(select 1 from public.stock_ledger where organisation_id=p_organisation_id and location_id=c.site_id and id>c.ledger_watermark and occurred_on<c.count_date) then raise exception 'Backdated stock changed this cutoff. Recount and review before posting.' using errcode='22023';end if;
  if exists(select 1 from public.stock_ledger e join public.stock_documents d on d.id=e.document_id and d.organisation_id=e.organisation_id where e.organisation_id=p_organisation_id and e.location_id=c.site_id and e.created_at>c.cutoff and d.kind='COUNT') then raise exception 'Another count adjustment was posted after this cutoff. Reconcile it and use review without adjustment to avoid correcting twice.' using errcode='22023';end if;
  doc:=gen_random_uuid();
  insert into public.stock_documents(id,organisation_id,request_id,input_hash,reference,kind,source_id,document_date,note,lines,output,state,created_by,approved_by,approved_at,completed_by,completed_at)
  select doc,p_organisation_id,p_request_id,digest,'WC-'||upper(substr(replace(c.id::text,'-',''),1,12)),'COUNT',c.site_id,today,'Weekly count '||c.count_date::text||': post the approved variance; preserve movements after cutoff',jsonb_agg(jsonb_build_object('item_id',item_id,'quantity',physical::text,'book_at_cutoff',book::text,'variance',(physical-book)::text)),jsonb_build_object('weekly_count_id',c.id,'cutoff',c.cutoff,'adjustment_policy','APPROVED_VARIANCE'),'POSTED',c.submitted_by,c.reviewed_by,c.reviewed_at,auth.uid(),clock_timestamp() from private.weekly_count_lines where count_id=c.id;
  for line in select * from private.weekly_count_lines where count_id=c.id loop
   if line.physical is null then raise exception 'Incomplete count cannot be posted.' using errcode='22023';end if;
   if line.physical<>line.book then perform private.pp_stock_entry(p_organisation_id,doc,c.site_id,line.item_id,line.physical-line.book,today);end if;
  end loop;
  update private.weekly_counts set state='POSTED',stock_document_id=doc,posted_by=auth.uid(),posted_at=clock_timestamp() where id=c.id;
 end if;
 update private.weekly_counts set revision=revision+1 where id=c.id;
 insert into private.weekly_count_requests values(p_organisation_id,p_request_id,auth.uid(),digest,c.id);
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'WEEKLY_COUNT_'||p_action,auth.uid(),c.id,jsonb_build_object('reason',p_reason,'revision',c.revision+1,'stock_document',doc));return c.id;
end $$;
create function public.weekly_count_scope(p_organisation_id uuid,p_site_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare today date;begin
 if not private.pp_stock_manager(p_organisation_id) or not private.pp_inventory_report_site(p_organisation_id,p_site_id) then raise exception 'Stock setup access required.' using errcode='42501';end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 return jsonb_build_object('evidence',(select md5(coalesce(jsonb_agg(to_jsonb(q) order by q.item_id,q.effective_from)::text,'[]')||coalesce((select submission_hours::text from private.weekly_count_settings where organisation_id=p_organisation_id),'24')) from private.weekly_count_scope q where q.organisation_id=p_organisation_id and q.site_id=p_site_id),'submission_hours',coalesce((select submission_hours from private.weekly_count_settings where organisation_id=p_organisation_id),24),'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',i.name,'code',i.code,'unit',u.code,'included',coalesce(q.included,false),'quantity',private.pp_stock_balance(p_organisation_id,p_site_id,i.id)::text) order by i.name) from public.items i join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id join public.stock_locations s on s.organisation_id=i.organisation_id and s.id=p_site_id left join lateral(select included from private.weekly_count_scope where organisation_id=i.organisation_id and site_id=p_site_id and item_id=i.id and effective_from<=today+1 order by effective_from desc limit 1)q on true where i.organisation_id=p_organisation_id and i.is_active and i.stock_tracked and i.weekly_count_required and(i.location_id is null or s.outlet_id is null or i.location_id=s.outlet_id)),'[]'::jsonb));
end $$;
create function public.save_weekly_count_scope(p_organisation_id uuid,p_site_id uuid,p_item_ids uuid[],p_submission_hours integer,p_evidence text) returns void language plpgsql security definer set search_path='' as $$declare candidate record;day date;begin
 if not private.pp_stock_manager(p_organisation_id) or not private.pp_inventory_report_site(p_organisation_id,p_site_id) then raise exception 'Stock setup access required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if p_evidence is distinct from(public.weekly_count_scope(p_organisation_id,p_site_id)->>'evidence') then raise exception 'Count scope changed. Refresh before saving.' using errcode='22023';end if;
 if p_item_ids is null or cardinality(p_item_ids)>1000 or array_position(p_item_ids,null) is not null or p_submission_hours is null or p_submission_hours not between 1 and 168 then raise exception 'Choose count materials and a submission window from 1 to 168 hours.' using errcode='22023';end if;
 if exists(select 1 from unnest(p_item_ids)x where not exists(select 1 from public.items i join public.stock_locations s on s.organisation_id=i.organisation_id and s.id=p_site_id where i.organisation_id=p_organisation_id and i.id=x and i.is_active and i.stock_tracked and i.weekly_count_required and i.base_uom_id is not null and(i.location_id is null or s.outlet_id is null or i.location_id=s.outlet_id))) then raise exception 'Choose weekly-count materials within the centre scope.' using errcode='22023';end if;
 select(now() at time zone time_zone)::date+1 into day from public.organisations where id=p_organisation_id;
 for candidate in select id from public.items where organisation_id=p_organisation_id and weekly_count_required and is_active and stock_tracked and base_uom_id is not null loop
  if not(candidate.id=any(p_item_ids)) and private.pp_stock_balance(p_organisation_id,p_site_id,candidate.id)<>0 then raise exception 'A weekly-count material with stock at this centre must remain included.' using errcode='22023';end if;
  insert into private.weekly_count_scope values(p_organisation_id,p_site_id,candidate.id,day,true,candidate.id=any(p_item_ids),auth.uid()) on conflict(organisation_id,site_id,item_id,effective_from) do update set included=excluded.included;
 end loop;
 insert into private.weekly_count_settings values(p_organisation_id,p_submission_hours) on conflict(organisation_id) do update set submission_hours=excluded.submission_hours;
 for candidate in select id from public.stock_locations where organisation_id=p_organisation_id loop perform private.pp_weekly_programme(p_organisation_id,candidate.id,day);end loop;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'WEEKLY_COUNT_SCOPE',auth.uid(),p_site_id,jsonb_build_object('effective_from',day,'included',p_item_ids,'submission_hours',p_submission_hours));
end $$;
create function public.weekly_count_history(p_organisation_id uuid,p_count_id uuid,p_revision integer default null) returns jsonb language plpgsql stable security definer set search_path='' as $$declare c private.weekly_counts;snapshot jsonb;begin
 select * into c from private.weekly_counts where organisation_id=p_organisation_id and id=p_count_id;
 if c.id is null or not private.pp_inventory_report_site(p_organisation_id,c.site_id) then raise exception 'Count history access required.' using errcode='42501';end if;
 if p_revision is null then return coalesce((select jsonb_agg(jsonb_build_object('revision',revision,'changed_at',changed_at,'state',h.data->'report'->>'state','actor',changed_by) order by revision desc) from private.weekly_count_history h where count_id=c.id),'[]'::jsonb);end if;
 select h.data into snapshot from private.weekly_count_history h where count_id=c.id and revision=p_revision;
 if snapshot is null then raise exception 'Count revision unavailable.' using errcode='22023';end if;
 if not private.pp_reference_price_read(p_organisation_id) then snapshot:=jsonb_set(snapshot,'{lines}',coalesce((select jsonb_agg(value-'unit_cost'-'price_basis') from jsonb_array_elements(snapshot->'lines')),'[]'::jsonb));end if;return snapshot;
end $$;
create function public.weekly_counts_workspace(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;today date;first_day date;backlog integer;waiting integer;tasks jsonb;begin
 if not exists(select 1 from public.stock_locations where organisation_id=p_organisation_id and private.pp_inventory_report_site(p_organisation_id,id)) then return null;end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 result:=public.weekly_counts_report(p_organisation_id,null,today-6,today+7,1);
 select coalesce(min(effective_from),today) into first_day from private.weekly_count_programmes where organisation_id=p_organisation_id;
 with rows as materialized(select value from private.pp_weekly_rows(p_organisation_id,first_day,today+7,null)value),attention as(select value from rows where(value->>'overdue')::boolean or value->>'state' in('SUBMITTED','APPROVED','DRAFT','NOT_STARTED','UPCOMING') order by(value->>'overdue')::boolean desc,value->>'day',value->>'centre' limit 8)
 select (select count(*) from rows where(value->>'overdue')::boolean),(select count(*) from rows where value->>'state' in('SUBMITTED','APPROVED')),coalesce((select jsonb_agg(value) from attention),'[]'::jsonb) into backlog,waiting,tasks;
 return jsonb_build_object('summary',result->'summary','calendar_gaps',result->'calendar_gaps','backlog',backlog,'review_waiting',waiting,'rows',tasks);end $$;
do $$declare f record;begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname in('pp_weekly_programme','pp_count_scope_seed','pp_track_count_centre','pp_track_count_calendar','pp_track_count_material','pp_track_count_ledger','pp_track_zero_count_scope','pp_weekly_items','pp_weekly_write','pp_weekly_rows','pp_archive_weekly_count') loop execute 'revoke all on function '||f.signature||' from public,anon,authenticated';end loop;
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in('weekly_counts_report','weekly_count_detail','start_weekly_count','save_weekly_count','weekly_count_action','weekly_count_scope','save_weekly_count_scope','weekly_count_history','weekly_counts_workspace') loop execute 'revoke all on function '||f.signature||' from public,anon';execute 'grant execute on function '||f.signature||' to authenticated';end loop;
end $$;
notify pgrst,'reload schema';
commit;
