-- Mandatory prospective monthly counts share the proven physical-count review/posting engine.
begin;
alter table public.organisations add column monthly_count_day integer not null default 0 check(monthly_count_day between 0 and 31),add column monthly_count_cutoff time not null default '23:59',add column monthly_submission_hours integer not null default 24 check(monthly_submission_hours between 1 and 168);
alter table private.weekly_counts add column monthly_date date,add column no_stock_confirmed boolean not null default false,add constraint monthly_date_matches_sheet check(monthly_date is null or monthly_date=count_date);
alter table private.weekly_counts drop constraint weekly_counts_organisation_id_site_id_count_date_key;
alter table private.weekly_counts add unique(organisation_id,site_id,cutoff);
create unique index monthly_sheet_per_centre_date on private.weekly_counts(organisation_id,site_id,(monthly_date - (extract(day from monthly_date)::integer - 1))) where monthly_date is not null;
create table private.monthly_count_programmes(organisation_id uuid not null,site_id uuid not null,effective_from date not null,active boolean not null,count_day integer not null,count_cutoff time not null,time_zone text not null,submission_hours integer not null,owner_name text,primary key(organisation_id,site_id,effective_from),foreign key(organisation_id,site_id) references public.stock_locations(organisation_id,id));
revoke all on private.monthly_count_programmes from public,anon,authenticated;

create function private.pp_monthly_programme(org uuid,site uuid,day date) returns void language plpgsql security definer set search_path='' as $$begin
 insert into private.monthly_count_programmes select o.id,s.id,day,s.is_active and o.access_state='ACTIVE',o.monthly_count_day,o.monthly_count_cutoff,o.time_zone,o.monthly_submission_hours,private.pp_member_label(o.id,s.responsible_membership_id) from public.organisations o join public.stock_locations s on s.organisation_id=o.id where o.id=org and s.id=site
 on conflict(organisation_id,site_id,effective_from) do update set active=excluded.active,count_day=excluded.count_day,count_cutoff=excluded.count_cutoff,time_zone=excluded.time_zone,submission_hours=excluded.submission_hours,owner_name=excluded.owner_name;
end $$;
do $$declare s record;begin
 for s in select l.id,l.organisation_id,o.time_zone,o.monthly_count_cutoff from public.stock_locations l join public.organisations o on o.id=l.organisation_id loop
 perform private.pp_monthly_programme(s.organisation_id,s.id,(now() at time zone s.time_zone)::date+case when(now() at time zone s.time_zone)::time>=s.monthly_count_cutoff then 1 else 0 end);
 end loop;
end $$;
-- Programme history can be recorded during Founder suspension; public APIs remain membership-gated.
create function private.pp_track_monthly_centre() returns trigger language plpgsql security definer set search_path='' as $$declare day date;begin
 if tg_op='UPDATE' and(old.is_active,old.responsible_membership_id) is not distinct from(new.is_active,new.responsible_membership_id) then return new;end if;
 select(now() at time zone time_zone)::date+case when tg_op='UPDATE' or(now() at time zone time_zone)::time>=monthly_count_cutoff then 1 else 0 end into day from public.organisations where id=new.organisation_id;
 perform private.pp_monthly_programme(new.organisation_id,new.id,day);return new;
end $$;
create trigger track_monthly_centre after insert or update on public.stock_locations for each row execute function private.pp_track_monthly_centre();
create function private.pp_track_monthly_calendar() returns trigger language plpgsql security definer set search_path='' as $$declare s record;begin
 if(old.monthly_count_day,old.monthly_count_cutoff,old.monthly_submission_hours,old.time_zone,old.access_state) is not distinct from(new.monthly_count_day,new.monthly_count_cutoff,new.monthly_submission_hours,new.time_zone,new.access_state) then return new;end if;
 for s in select id from public.stock_locations where organisation_id=new.id loop perform private.pp_monthly_programme(new.id,s.id,case when old.access_state is distinct from new.access_state then(now() at time zone new.time_zone)::date+1 else(date_trunc('month',now() at time zone new.time_zone)+interval '1 month')::date end);end loop;return new;
end $$;
create trigger track_monthly_calendar after update on public.organisations for each row execute function private.pp_track_monthly_calendar();

create function public.monthly_count_calendar(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare o public.organisations;begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'Stock setup access required.' using errcode='42501';end if;
 select * into o from public.organisations where id=p_organisation_id;
 return jsonb_build_object('day',o.monthly_count_day,'cutoff',o.monthly_count_cutoff,'hours',o.monthly_submission_hours,'timezone',o.time_zone,'can_edit',private.pp_stock_role(p_organisation_id,'restaurant_admin',null),'evidence',md5(jsonb_build_array(o.monthly_count_day,o.monthly_count_cutoff,o.monthly_submission_hours,o.time_zone)::text));
end $$;
create function public.save_monthly_count_calendar(p_organisation_id uuid,p_day integer,p_cutoff time,p_hours integer,p_evidence text) returns void language plpgsql security definer set search_path='' as $$begin
 if not private.pp_stock_role(p_organisation_id,'restaurant_admin',null) then raise exception 'Restaurant administrator access required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if p_day is null or p_day not between 0 and 31 or p_cutoff is null or p_hours is null or p_hours not between 1 and 168 or p_evidence is distinct from(public.monthly_count_calendar(p_organisation_id)->>'evidence') then raise exception 'Refresh and choose a valid monthly schedule and submission window.' using errcode='22023';end if;
 update public.organisations set monthly_count_day=p_day,monthly_count_cutoff=p_cutoff,monthly_submission_hours=p_hours where id=p_organisation_id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'MONTHLY_COUNT_CALENDAR',auth.uid(),p_organisation_id,jsonb_build_object('day',p_day,'cutoff',p_cutoff,'submission_hours',p_hours,'effective_from',(select(date_trunc('month',now() at time zone time_zone)+interval '1 month')::date from public.organisations where id=p_organisation_id)));
end $$;

create function private.pp_monthly_items(org uuid,site uuid,day date) returns table(item_id uuid) language sql stable security definer set search_path='' as $$
 select i.id from public.items i join public.stock_locations s on s.organisation_id=i.organisation_id and s.id=site where i.organisation_id=org and i.base_uom_id is not null and(i.location_id is null or s.outlet_id is null or i.location_id=s.outlet_id) and((i.is_active and i.stock_tracked) or exists(select 1 from public.stock_ledger e where e.organisation_id=org and e.location_id=site and e.item_id=i.id and e.occurred_on<=day group by e.item_id having sum(e.quantity)<>0));
$$;
create function private.pp_monthly_rows(org uuid,from_day date,to_day date,site uuid default null) returns setof jsonb language sql stable security definer set search_path='' as $$
 with dates as(select s.id site_id,s.name centre,d::date as day from public.stock_locations s cross join generate_series(from_day::timestamp,to_day::timestamp,'1 day')d where s.organisation_id=org and(site is null or s.id=site) and private.pp_inventory_report_site(org,s.id)),
 planned as(select d.*,p.time_zone,p.owner_name,c.id count_id,c.state,c.revision,c.submitted_at,c.submitter_name,c.stock_document_id,coalesce(c.cutoff,(d.day+p.count_cutoff) at time zone p.time_zone) cutoff_at,coalesce(c.deadline,((d.day+p.count_cutoff) at time zone p.time_zone)+make_interval(hours=>p.submission_hours)) due_at,
 case when c.id is null then(select count(*) from private.pp_monthly_items(org,d.site_id,d.day)) else(select count(*) from private.weekly_count_lines where count_id=c.id) end expected,(select count(*) from private.weekly_count_lines where count_id=c.id and physical is not null) entered,coalesce(c.owner_name,p.owner_name) owner
 from dates d left join lateral(select * from private.monthly_count_programmes where organisation_id=org and site_id=d.site_id and effective_from<=d.day order by effective_from desc limit 1)p on true left join private.weekly_counts c on c.organisation_id=org and c.site_id=d.site_id and c.monthly_date=d.day
 where c.id is not null or(p.active and extract(day from d.day)=case when p.count_day=0 then extract(day from(date_trunc('month',d.day)+interval '1 month - 1 day')) else least(p.count_day,extract(day from(date_trunc('month',d.day)+interval '1 month - 1 day'))) end))
 select jsonb_build_object('site_id',site_id,'centre',centre,'day',day,'count_id',count_id,'state',case when state is not null then state when cutoff_at>clock_timestamp() then 'UPCOMING' else 'NOT_STARTED' end,'expected',expected,'entered',entered,'cutoff',cutoff_at,'deadline',due_at,'time_zone',time_zone,'owner',owner,'submitter',submitter_name,'submitted_at',submitted_at,'late',submitted_at>due_at,'overdue',due_at<clock_timestamp() and coalesce(state,'DRAFT')='DRAFT','revision',revision,'can_record',private.pp_weekly_write(org,site_id)) from planned;
$$;
create function public.monthly_counts_report(p_organisation_id uuid,p_site_id uuid,p_from date,p_to date,p_page integer default 1) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;today date;financial boolean;begin
 if not private.pp_stock_read(p_organisation_id) or(p_site_id is not null and not private.pp_inventory_report_site(p_organisation_id,p_site_id)) then raise exception 'Monthly count report access required.' using errcode='42501';end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 if p_from is null or p_to is null or p_from>p_to or p_to>today+62 or p_to-p_from>366 or p_page is null or p_page not between 1 and 100000 then raise exception 'Choose a valid count period of up to 367 days.' using errcode='22023';end if;
 financial:=private.pp_reference_price_read(p_organisation_id);
 with rows as materialized(select value from private.pp_monthly_rows(p_organisation_id,p_from,p_to,p_site_id)value),paged as(select value from rows order by(value->>'overdue')::boolean desc,value->>'day' desc,value->>'centre' limit 25 offset(p_page-1)*25)
 select jsonb_build_object('centres',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.stock_locations where organisation_id=p_organisation_id and private.pp_inventory_report_site(p_organisation_id,id)),'[]'::jsonb),'manage',private.pp_stock_manager(p_organisation_id),'financial',financial,'calendar_gaps',0,'total',(select count(*) from rows),
 'summary',(select jsonb_build_object('expected',count(*) filter(where(value->>'cutoff')::timestamptz<=clock_timestamp()),'submitted',count(*) filter(where(value->>'cutoff')::timestamptz<=clock_timestamp() and value->>'state' in('SUBMITTED','APPROVED','POSTED','REVIEWED')),'overdue',count(*) filter(where(value->>'overdue')::boolean),'late',count(*) filter(where(value->>'late')::boolean),'reviewed',count(*) filter(where value->>'state' in('POSTED','REVIEWED'))) from rows),
 'rows',coalesce((select jsonb_agg(value) from paged),'[]'::jsonb)) into result;return result;
end $$;

create function public.start_monthly_count(p_organisation_id uuid,p_site_id uuid,p_day date) returns uuid language plpgsql security definer set search_path='' as $$declare r jsonb;c private.weekly_counts;result_id uuid;begin
 if not private.pp_weekly_write(p_organisation_id,p_site_id) then raise exception 'Stock count entry access required at this centre.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 select value into r from private.pp_monthly_rows(p_organisation_id,p_day,p_day,p_site_id)value;
 if r is null or(r->>'cutoff')::timestamptz>clock_timestamp() then raise exception 'Monthly count opens at its configured cutoff.' using errcode='22023';end if;
 if(r->>'expected')::integer>1000 then raise exception 'This centre exceeds the 1,000-material sheet limit. Review its material availability.' using errcode='22023';end if;
 -- One shared submission uses the earlier deadline; a monthly window cannot extend weekly duty.
 select jsonb_set(r,'{deadline}',to_jsonb(least((r->>'deadline')::timestamptz,((p_day+p.count_cutoff) at time zone p.time_zone)+make_interval(hours=>p.submission_hours)))) into r from (select * from private.weekly_count_programmes where organisation_id=p_organisation_id and site_id=p_site_id and effective_from<=p_day order by effective_from desc limit 1)p where p.active and p.count_day=extract(dow from p_day)::integer and((p_day+p.count_cutoff) at time zone p.time_zone)=(r->>'cutoff')::timestamptz and exists(select 1 from private.pp_weekly_items(p_organisation_id,p_site_id,p_day)) order by p.effective_from desc limit 1;
 if r is null then select value into r from private.pp_monthly_rows(p_organisation_id,p_day,p_day,p_site_id)value;end if;
 select * into c from private.weekly_counts where organisation_id=p_organisation_id and site_id=p_site_id and cutoff=(r->>'cutoff')::timestamptz;
 if c.id is not null and c.monthly_date is not null then return c.id;end if;
 if c.id is null then
  if exists(select 1 from private.weekly_counts where organisation_id=p_organisation_id and site_id=p_site_id and count_date<p_day and state in('DRAFT','SUBMITTED','APPROVED')) then raise exception 'Finish earlier count reviews at this centre before starting another.' using errcode='22023';end if;
  insert into private.weekly_counts(organisation_id,site_id,count_date,monthly_date,cutoff,deadline,time_zone,owner_name,created_by,ledger_watermark) values(p_organisation_id,p_site_id,p_day,p_day,(r->>'cutoff')::timestamptz,(r->>'deadline')::timestamptz,r->>'time_zone',r->>'owner',auth.uid(),coalesce((select max(id) from public.stock_ledger where organisation_id=p_organisation_id and location_id=p_site_id),0)) returning * into c;
  update private.weekly_counts set cutoff_warnings=coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'reference',d.reference)) from public.stock_documents d where d.organisation_id=p_organisation_id and(d.source_id=p_site_id or d.destination_id=p_site_id) and d.dispatched_at<=c.cutoff and(d.completed_at is null or d.completed_at>c.cutoff or(d.state in('PARTIAL','REJECTED') and(d.resolved_at is null or d.resolved_at>c.cutoff)))),'[]'::jsonb) where id=c.id;
 elsif c.state<>'DRAFT' and exists(select 1 from private.pp_monthly_items(p_organisation_id,p_site_id,p_day)m where not exists(select 1 from private.weekly_count_lines where count_id=c.id and item_id=m.item_id)) then raise exception 'The existing weekly submission lacks monthly materials. Reopen and complete its full sheet before sharing it.' using errcode='22023';
 else
  perform private.pp_archive_weekly_count(c.id);
  update private.weekly_counts set monthly_date=p_day,revision=revision+1,deadline=least(deadline,(r->>'deadline')::timestamptz) where id=c.id;
 end if;
 insert into private.weekly_count_lines(count_id,item_id,name,code,unit,book,unit_cost,price_basis)
 select c.id,i.id,i.name,i.code,u.code,coalesce((select sum(quantity) from public.stock_ledger where organisation_id=p_organisation_id and location_id=p_site_id and item_id=i.id and(occurred_on<p_day or(occurred_on=p_day and created_at<=c.cutoff))),0),(cost->>'unit_cost')::numeric,cost
 from private.pp_monthly_items(p_organisation_id,p_site_id,p_day)m join public.items i on i.organisation_id=p_organisation_id and i.id=m.item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id cross join lateral(select private.pp_effective_material_cost(p_organisation_id,i.id,p_day) cost)p on conflict(count_id,item_id) do nothing;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'MONTHLY_COUNT_STARTED',auth.uid(),c.id,jsonb_build_object('centre',p_site_id,'date',p_day,'cutoff',c.cutoff,'shared_weekly_sheet',c.monthly_date is null));return c.id;
end $$;
create function public.save_monthly_count(p_organisation_id uuid,p_count_id uuid,p_revision integer,p_request_id uuid,p_rows jsonb,p_submit boolean,p_submitter text,p_note text default '',p_no_stock boolean default false) returns uuid language plpgsql security definer set search_path='' as $$declare c private.weekly_counts;begin
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into c from private.weekly_counts where organisation_id=p_organisation_id and id=p_count_id and monthly_date is not null;
 if c.id is null or not private.pp_weekly_write(p_organisation_id,c.site_id) then raise exception 'Monthly count entry access required.' using errcode='42501';end if;
 if exists(select 1 from private.weekly_count_requests where organisation_id=p_organisation_id and request_id=p_request_id) then
  if c.no_stock_confirmed is distinct from coalesce(p_no_stock,false) then raise exception 'Refresh before changing a saved declaration.' using errcode='22023';end if;
 else
  if c.state<>'DRAFT' or c.revision is distinct from p_revision then raise exception 'This count changed. Refresh before saving.' using errcode='22023';end if;
  perform private.pp_archive_weekly_count(c.id);
  update private.weekly_counts set no_stock_confirmed=coalesce(p_no_stock,false) where id=c.id;
 end if;
 return public.save_weekly_count(p_organisation_id,p_count_id,p_revision,p_request_id,p_rows,p_submit,p_submitter,p_note);
end $$;
create function public.monthly_count_detail(p_organisation_id uuid,p_count_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not exists(select 1 from private.weekly_counts where organisation_id=p_organisation_id and id=p_count_id and monthly_date is not null) then raise exception 'Monthly count unavailable.' using errcode='42501';end if;
 return public.weekly_count_detail(p_organisation_id,p_count_id);
end $$;
create function public.monthly_counts_workspace(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare today date;first_day date;last_day date;result jsonb;backlog integer;waiting integer;tasks jsonb;begin
 if not exists(select 1 from public.stock_locations where organisation_id=p_organisation_id and private.pp_inventory_report_site(p_organisation_id,id)) then return null;end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 last_day:=(date_trunc('month',today)+interval '1 month - 1 day')::date;
 select coalesce(min(effective_from),today) into first_day from private.monthly_count_programmes where organisation_id=p_organisation_id;
 result:=public.monthly_counts_report(p_organisation_id,null,date_trunc('month',today)::date,last_day,1);
 with rows as materialized(select value from private.pp_monthly_rows(p_organisation_id,first_day,last_day,null)value),attention as(select value from rows where(value->>'overdue')::boolean or value->>'state' in('SUBMITTED','APPROVED','DRAFT','NOT_STARTED','UPCOMING') order by(value->>'overdue')::boolean desc,value->>'day',value->>'centre' limit 8)
 select(select count(*) from rows where(value->>'overdue')::boolean),(select count(*) from rows where value->>'state' in('SUBMITTED','APPROVED')),coalesce((select jsonb_agg(value) from attention),'[]'::jsonb) into backlog,waiting,tasks;
 return jsonb_build_object('summary',result->'summary','calendar_gaps',0,'backlog',backlog,'review_waiting',waiting,'rows',tasks);
end $$;

create function public.monthly_count_analysis(p_organisation_id uuid,p_site_id uuid,p_from date,p_to date,p_page integer default 1) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;financial boolean;today date;begin
 if not private.pp_stock_read(p_organisation_id) or(p_site_id is not null and not private.pp_inventory_report_site(p_organisation_id,p_site_id)) then raise exception 'Monthly count analysis access required.' using errcode='42501';end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 if p_from is null or p_to is null or p_from>p_to or p_to>today+62 or p_to-p_from>366 or p_page is null or p_page not between 1 and 100000 then raise exception 'Choose a valid monthly analysis period.' using errcode='22023';end if;
 financial:=private.pp_reference_price_read(p_organisation_id) or private.pp_operations_any(p_organisation_id);
 with sheets as materialized(select * from private.weekly_counts c where c.organisation_id=p_organisation_id and c.monthly_date between p_from and p_to and(p_site_id is null or c.site_id=p_site_id) and private.pp_inventory_report_site(p_organisation_id,c.site_id) and c.state in('SUBMITTED','APPROVED','POSTED','REVIEWED')),
 lines as materialized(select l.*,c.monthly_date from sheets c join private.weekly_count_lines l on l.count_id=c.id),
 latest as(select distinct on(site_id) id from sheets order by site_id,cutoff desc),
 materials as(select item_id,min(name) name,min(code) code,min(unit) unit,count(*) filter(where physical<>book) occurrences,count(distinct date_trunc('month',monthly_date)) filter(where physical<>book) months_affected,sum(greatest(book-physical,0)) shortage,sum(greatest(physical-book,0)) surplus,sum((physical-book)*unit_cost) estimated_variance,count(*) filter(where unit_cost is null and physical<>book) unpriced from lines group by item_id having bool_or(physical<>book)),
 paged as(select * from materials order by occurrences desc,name,item_id limit 25 offset(p_page-1)*25),
 trend as(select date_trunc('month',monthly_date)::date month_start,sum(book*unit_cost) book_value,sum(physical*unit_cost) physical_value,sum(greatest(book-physical,0)*unit_cost) shortage,sum(greatest(physical-book,0)*unit_cost) surplus,count(distinct count_id) sheets,count(*) filter(where unit_cost is null and(book<>0 or physical<>0)) unpriced from lines group by 1)
 select jsonb_build_object('financial',financial,'currency',(select currency_code from public.organisations where id=p_organisation_id),'total',(select count(*) from materials),'sheets',(select count(*) from sheets),
 'summary',(select jsonb_build_object('book_value',case when financial then(select coalesce(sum(l.book*l.unit_cost),0)::text from lines l join latest z on z.id=l.count_id) end,'physical_value',case when financial then(select coalesce(sum(l.physical*l.unit_cost),0)::text from lines l join latest z on z.id=l.count_id) end,'shortage_value',case when financial then coalesce(sum(greatest(book-physical,0)*unit_cost),0)::text end,'surplus_value',case when financial then coalesce(sum(greatest(physical-book,0)*unit_cost),0)::text end,'unpriced',case when financial then count(*) filter(where unit_cost is null and(book<>0 or physical<>0)) end,'variance_lines',count(*) filter(where physical<>book)) from lines),
 'trend',coalesce((select jsonb_agg(jsonb_build_object('month',month_start,'sheets',sheets,'book_value',case when financial then book_value::text end,'physical_value',case when financial then physical_value::text end,'shortage',case when financial then shortage::text end,'surplus',case when financial then surplus::text end,'unpriced',case when financial then unpriced end) order by month_start) from trend),'[]'::jsonb),
 'rows',coalesce((select jsonb_agg(jsonb_build_object('item_id',item_id,'name',name,'code',code,'unit',unit,'occurrences',occurrences,'months_affected',months_affected,'shortage',shortage::text,'surplus',surplus::text,'estimated_variance',case when financial then estimated_variance::text end,'unpriced',case when financial then unpriced end)) from paged),'[]'::jsonb)) into result;return result;
end $$;

-- Existing weekly functions below retain their permissions, revision checks and posting safeguards.
create or replace function private.pp_weekly_rows(org uuid,from_day date,to_day date,site uuid default null) returns setof jsonb language sql stable security definer set search_path='' as $$
 with dates as(select s.id site_id,s.name centre,d::date as day from public.stock_locations s cross join generate_series(from_day::timestamp,to_day::timestamp,'1 day')d where s.organisation_id=org and(site is null or s.id=site) and private.pp_inventory_report_site(org,s.id)),
 planned as(select d.site_id,d.centre,d.day,p.time_zone,c.id count_id,c.state,c.revision,c.submitted_at,c.submitter_name,c.stock_document_id,coalesce(c.cutoff,(d.day+p.count_cutoff) at time zone p.time_zone) cutoff_at,coalesce(c.deadline,((d.day+p.count_cutoff) at time zone p.time_zone)+make_interval(hours=>p.submission_hours)) due_at,
 case when c.id is null then(select count(*) from private.pp_weekly_items(org,d.site_id,d.day)) else(select count(*) from private.weekly_count_lines where count_id=c.id) end expected,
 (select count(*) from private.weekly_count_lines where count_id=c.id and physical is not null) entered,
 coalesce(c.owner_name,p.owner_name) owner
 from dates d left join lateral(select * from private.weekly_count_programmes where organisation_id=org and site_id=d.site_id and effective_from<=d.day order by effective_from desc limit 1)p on true left join private.weekly_counts c on c.organisation_id=org and c.site_id=d.site_id and c.count_date=d.day and p.count_day=extract(dow from d.day)::integer and c.cutoff=(d.day+p.count_cutoff) at time zone p.time_zone
 where (c.id is not null and c.monthly_date is null) or(p.active and p.count_day=extract(dow from d.day)::integer and p.count_cutoff is not null and exists(select 1 from private.pp_weekly_items(org,d.site_id,d.day))))
 select jsonb_build_object('site_id',site_id,'centre',centre,'day',day,'count_id',count_id,'state',case when state is not null then state when cutoff_at>clock_timestamp() then 'UPCOMING' else 'NOT_STARTED' end,'expected',expected,'entered',entered,'cutoff',cutoff_at,'deadline',due_at,'time_zone',time_zone,'owner',owner,'submitter',submitter_name,'submitted_at',submitted_at,'late',submitted_at>due_at,'overdue',due_at<clock_timestamp() and coalesce(state,'DRAFT')='DRAFT','revision',revision,'can_record',private.pp_weekly_write(org,site_id)) from planned where expected>0;
$$;

create or replace function public.start_weekly_count(p_organisation_id uuid,p_site_id uuid,p_day date) returns uuid language plpgsql security definer set search_path='' as $$declare r jsonb;result_id uuid;watermark bigint;line record;begin
 if not private.pp_weekly_write(p_organisation_id,p_site_id) then raise exception 'Stock count entry access required at this centre.' using errcode='42501';end if;
 perform 1 from public.organisations where organisations.id=p_organisation_id for update;
 select value into r from private.pp_weekly_rows(p_organisation_id,p_day,p_day,p_site_id)value;
 if r is null or(r->>'cutoff')::timestamptz>clock_timestamp() then raise exception 'Start the count at or after its scheduled cutoff. Check the reporting calendar and centre count scope.' using errcode='22023';end if;
 if exists(select 1 from private.pp_monthly_rows(p_organisation_id,p_day,p_day,p_site_id)m where (m->>'cutoff')::timestamptz=(r->>'cutoff')::timestamptz) then return public.start_monthly_count(p_organisation_id,p_site_id,p_day);end if;
 select c.id into result_id from private.weekly_counts c where organisation_id=p_organisation_id and site_id=p_site_id and cutoff=(r->>'cutoff')::timestamptz;if result_id is not null then return result_id;end if;
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

create or replace function public.save_weekly_count(p_organisation_id uuid,p_count_id uuid,p_revision integer,p_request_id uuid,p_rows jsonb,p_submit boolean,p_submitter text,p_note text default '') returns uuid language plpgsql security definer set search_path='' as $$
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
  if c.monthly_date is not null and not exists(select 1 from private.weekly_count_lines where count_id=c.id) and not c.no_stock_confirmed then raise exception 'Confirm that this centre holds no stock before submitting an empty count.' using errcode='22023';end if;
  if p_submitter is null or length(trim(p_submitter)) not between 1 and 120 or p_submitter~'[[:cntrl:]]' then raise exception 'Enter the submitter name.' using errcode='22023';end if;
  if exists(select 1 from private.weekly_count_lines where count_id=c.id and physical is null) then raise exception 'Count every expected material. Enter an explicit zero where none is held; blanks are incomplete.' using errcode='22023';end if;
  if length(trim(coalesce(p_note,'')))<3 and exists(select 1 from private.weekly_count_lines where count_id=c.id and physical<>book and length(trim(note))<3) then raise exception 'Explain the variance, or state that it is under investigation.' using errcode='22023';end if;
 end if;
 update private.weekly_counts set revision=revision+1,state=case when p_submit then 'SUBMITTED' else 'DRAFT' end,submitter_name=case when p_submit then trim(p_submitter) else submitter_name end,submitted_by=case when p_submit then auth.uid() else submitted_by end,submitted_at=case when p_submit then clock_timestamp() else submitted_at end,submission_note=trim(coalesce(p_note,'')) where id=c.id;
 insert into private.weekly_count_requests values(p_organisation_id,p_request_id,auth.uid(),digest,c.id);
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,case when c.monthly_date is not null then case when p_submit then 'MONTHLY_COUNT_SUBMITTED' else 'MONTHLY_COUNT_DRAFT' end else case when p_submit then 'WEEKLY_COUNT_SUBMITTED' else 'WEEKLY_COUNT_DRAFT' end end,auth.uid(),c.id,jsonb_build_object('centre',c.site_id,'revision',c.revision+1,'stock_changed',false));return c.id;
end $$;

create or replace function public.weekly_count_action(p_organisation_id uuid,p_count_id uuid,p_revision integer,p_request_id uuid,p_action text,p_reason text default '') returns uuid language plpgsql security definer set search_path='' as $$
declare c private.weekly_counts;old private.weekly_count_requests;reviewer boolean;line record;doc uuid;today date;digest text:=md5(jsonb_build_array(p_count_id,p_revision,p_action,p_reason)::text);begin
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into c from private.weekly_counts where organisation_id=p_organisation_id and id=p_count_id;
 if c.id is null or not private.pp_inventory_report_site(p_organisation_id,c.site_id) then raise exception 'Weekly count access required.' using errcode='42501';end if;
 reviewer:=private.pp_stock_manager(p_organisation_id) or (private.pp_stock_role(p_organisation_id,'finance',(select outlet_id from public.stock_locations where id=c.site_id)) or private.pp_operations_site(p_organisation_id,c.site_id));
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


do $$declare f record;begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname in('pp_monthly_programme','pp_track_monthly_centre','pp_track_monthly_calendar','pp_monthly_items','pp_monthly_rows') loop execute 'revoke all on function '||f.signature||' from public,anon,authenticated';end loop;
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in('monthly_count_calendar','save_monthly_count_calendar','monthly_counts_report','start_monthly_count','save_monthly_count','monthly_count_detail','monthly_counts_workspace','monthly_count_analysis') loop execute 'revoke all on function '||f.signature||' from public,anon';execute 'grant execute on function '||f.signature||' to authenticated';end loop;
end $$;
notify pgrst,'reload schema';
commit;
