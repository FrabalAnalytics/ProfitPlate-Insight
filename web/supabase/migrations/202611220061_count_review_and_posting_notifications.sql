-- Distinguish count review from approved adjustments awaiting stock posting.
begin;

create or replace function public.weekly_counts_workspace(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;today date;first_day date;backlog integer;waiting integer;posting integer;tasks jsonb;begin
 if not exists(select 1 from public.stock_locations where organisation_id=p_organisation_id and private.pp_inventory_report_site(p_organisation_id,id)) then return null;end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 result:=public.weekly_counts_report(p_organisation_id,null,today-6,today+7,1);
 select coalesce(min(effective_from),today) into first_day from private.weekly_count_programmes where organisation_id=p_organisation_id;
 with rows as materialized(select value from private.pp_weekly_rows(p_organisation_id,first_day,today+7,null)value),attention as(select value from rows where(value->>'overdue')::boolean or value->>'state' in('SUBMITTED','APPROVED','DRAFT','NOT_STARTED','UPCOMING') order by(value->>'overdue')::boolean desc,value->>'day',value->>'centre' limit 8)
 select (select count(*) from rows where(value->>'overdue')::boolean),(select count(*) from rows where value->>'state'='SUBMITTED'),(select count(*) from rows where value->>'state'='APPROVED'),coalesce((select jsonb_agg(value) from attention),'[]'::jsonb) into backlog,waiting,posting,tasks;
 return jsonb_build_object('summary',result->'summary','calendar_gaps',result->'calendar_gaps','backlog',backlog,'review_waiting',waiting,'posting_waiting',posting,'rows',tasks);end $$;

create or replace function public.monthly_counts_workspace(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare today date;first_day date;last_day date;result jsonb;backlog integer;waiting integer;posting integer;tasks jsonb;begin
 if not exists(select 1 from public.stock_locations where organisation_id=p_organisation_id and private.pp_inventory_report_site(p_organisation_id,id)) then return null;end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 last_day:=(date_trunc('month',today)+interval '1 month - 1 day')::date;
 select coalesce(min(effective_from),today) into first_day from private.monthly_count_programmes where organisation_id=p_organisation_id;
 result:=public.monthly_counts_report(p_organisation_id,null,date_trunc('month',today)::date,last_day,1);
 with rows as materialized(select value from private.pp_monthly_rows(p_organisation_id,first_day,greatest(last_day,today+7),null)value),attention as(select value from rows where(value->>'overdue')::boolean or value->>'state' in('SUBMITTED','APPROVED','DRAFT','NOT_STARTED','UPCOMING') order by(value->>'overdue')::boolean desc,value->>'day',value->>'centre' limit 8)
 select(select count(*) from rows where(value->>'overdue')::boolean),(select count(*) from rows where value->>'state'='SUBMITTED'),(select count(*) from rows where value->>'state'='APPROVED'),coalesce((select jsonb_agg(value) from attention),'[]'::jsonb) into backlog,waiting,posting,tasks;
 return jsonb_build_object('summary',result->'summary','calendar_gaps',0,'backlog',backlog,'review_waiting',waiting,'posting_waiting',posting,'rows',tasks);
end $$;


create index pending_count_actions on private.weekly_counts(organisation_id,state,site_id) where state in('SUBMITTED','APPROVED');
create function public.count_action_queue(p_organisation_id uuid,p_frequency text,p_state text,p_site_id uuid default null,p_page integer default 1) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;begin
 if not private.pp_stock_read(p_organisation_id) or(p_site_id is not null and not private.pp_inventory_report_site(p_organisation_id,p_site_id)) then raise exception 'Stock-count access required at this centre.' using errcode='42501';end if;
 if p_frequency is null or p_frequency not in('WEEKLY','MONTHLY') or p_state is null or p_state not in('SUBMITTED','APPROVED') or p_page is null or p_page not between 1 and 100000 then raise exception 'Choose the count frequency and a pending review or posting queue.' using errcode='22023';end if;
 with counts as materialized(
  select c.*,s.name centre,(select count(*) from private.weekly_count_lines where count_id=c.id) expected,(select count(*) from private.weekly_count_lines where count_id=c.id and physical is not null) entered
  from private.weekly_counts c join public.stock_locations s on s.organisation_id=c.organisation_id and s.id=c.site_id
  where c.organisation_id=p_organisation_id and c.state=p_state and(p_site_id is null or c.site_id=p_site_id) and private.pp_inventory_report_site(p_organisation_id,c.site_id)
  and case when p_frequency='MONTHLY' then c.monthly_date is not null else exists(select 1 from private.pp_weekly_rows(p_organisation_id,c.count_date,c.count_date,c.site_id)r where r->>'count_id'=c.id::text) end
 ),paged as(select * from counts order by cutoff,centre,id limit 25 offset(p_page-1)*25)
 select jsonb_build_object('centres',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.stock_locations where organisation_id=p_organisation_id and private.pp_inventory_report_site(p_organisation_id,id)),'[]'::jsonb),'manage',private.pp_stock_manager(p_organisation_id),'calendar_gaps',0,'total',(select count(*) from counts),
 'summary',jsonb_build_object('expected',(select count(*) from counts),'submitted',(select count(*) from counts),'overdue',0,'late',(select count(*) from counts where submitted_at>deadline),'reviewed',0),
 'rows',coalesce((select jsonb_agg(jsonb_build_object('site_id',site_id,'centre',centre,'day',case when p_frequency='MONTHLY' then monthly_date else count_date end,'count_id',id,'state',state,'expected',expected,'entered',entered,'cutoff',cutoff,'deadline',deadline,'time_zone',time_zone,'owner',owner_name,'submitter',submitter_name,'submitted_at',submitted_at,'late',submitted_at>deadline,'overdue',false,'revision',revision,'can_record',private.pp_weekly_write(p_organisation_id,site_id)) order by cutoff,centre,id) from paged),'[]'::jsonb)) into result;
 return result;
end $$;
revoke all on function public.count_action_queue(uuid,text,text,uuid,integer) from public,anon;
grant execute on function public.count_action_queue(uuid,text,text,uuid,integer) to authenticated;
notify pgrst,'reload schema';
commit;
