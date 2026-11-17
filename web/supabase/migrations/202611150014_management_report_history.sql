-- Apply ONCE after 013. Saved management estimates; no accounting approval/close.
begin;
create table public.management_report_snapshots (
 id uuid primary key default gen_random_uuid(),
 organisation_id uuid not null references public.organisations(id),
 request_id uuid not null,
 title text not null check(length(title) between 1 and 120),
 period_from date not null, period_to date not null,
 location_id uuid,
 format_version text not null check(format_version='MANAGEMENT_SNAPSHOT_V1'),
 payload jsonb not null,
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default statement_timestamp(),
 unique(organisation_id,id), unique(organisation_id,request_id),
 foreign key(organisation_id,location_id) references public.locations(organisation_id,id),
 check(period_to>=period_from and period_to-period_from<=92)
);
create index pp_management_history on public.management_report_snapshots(organisation_id,created_at desc,id desc);
alter table public.management_report_snapshots enable row level security;
revoke all on public.management_report_snapshots from public,anon,authenticated;

create function private.pp_report_immutable() returns trigger
language plpgsql set search_path='' as $$
begin raise exception 'Saved management reports cannot be changed or deleted.' using errcode='42501'; end; $$;
revoke all on function private.pp_report_immutable() from public,anon,authenticated;
create trigger pp_report_immutable before update or delete on public.management_report_snapshots
for each row execute function private.pp_report_immutable();

create function public.save_management_report(p_organisation_id uuid,p_from date,p_to date,p_location_id uuid,p_request_id uuid,p_title text)
returns uuid language plpgsql security definer set search_path='' as $$
declare prior public.management_report_snapshots; result uuid; report_context jsonb; overview jsonb; costs jsonb;
begin
 if not private.pp_sales_read(p_organisation_id) then raise exception 'Report access denied.' using errcode='42501'; end if;
 if p_request_id is null or p_title is null or length(trim(p_title)) not between 1 and 120 then
  raise exception 'Enter a report name of up to 120 characters.' using errcode='22023'; end if;
 -- Serialize retries before reading sources; never accept client financial data.
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into prior from public.management_report_snapshots where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then
  if prior.created_by<>auth.uid() or prior.period_from is distinct from p_from or prior.period_to is distinct from p_to
   or prior.location_id is distinct from p_location_id or prior.title<>trim(p_title) then
   raise exception 'This save request was already used for another report. Refresh and try again.' using errcode='22023'; end if;
  return prior.id;
 end if;
 -- Both STABLE source functions run in one SQL statement with one source view.
 -- Source validation includes roles, tenant/location, dates, currency and caps.
 select public.executive_overview(p_organisation_id,p_from,p_to,p_location_id),
        public.expense_period_report(p_organisation_id,p_from,p_to,p_location_id,1)
 into overview,costs;
 select jsonb_build_object('organisation',o.name,'organisationId',o.id,'from',p_from,'to',p_to,
  'location',case when p_location_id is null then 'All business locations + central costs' else
   (select l.name from public.locations l where l.organisation_id=o.id and l.id=p_location_id) end,
  'locationId',coalesce(p_location_id::text,''),'currency',o.currency_code,'timeZone',o.time_zone,'generatedAt',statement_timestamp())
 into report_context from public.organisations o where o.id=p_organisation_id;
 insert into public.management_report_snapshots(organisation_id,request_id,title,period_from,period_to,location_id,format_version,payload,created_by)
 values(p_organisation_id,p_request_id,trim(p_title),p_from,p_to,p_location_id,'MANAGEMENT_SNAPSHOT_V1',
  jsonb_build_object('context',report_context,'overview',overview,'costs',costs),auth.uid()) returning id into result;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details)
 values(p_organisation_id,'MANAGEMENT_REPORT_SAVED',auth.uid(),result,
  jsonb_build_object('from',p_from,'to',p_to,'location_id',p_location_id,'format_version','MANAGEMENT_SNAPSHOT_V1'));
 return result;
end; $$;

create function public.get_management_report(p_organisation_id uuid,p_report_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_sales_read(p_organisation_id) then raise exception 'Report access denied.' using errcode='42501'; end if;
 select jsonb_build_object('id',id,'title',title,'format_version',format_version,'created_at',created_at,'payload',payload)
 into result from public.management_report_snapshots where organisation_id=p_organisation_id and id=p_report_id;
 if result is null then raise exception 'Saved report unavailable.' using errcode='42501'; end if;
 return result;
end; $$;

create function public.list_management_reports(p_organisation_id uuid,p_page integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare reports jsonb; total integer;
begin
 if not private.pp_sales_read(p_organisation_id) then raise exception 'Report access denied.' using errcode='42501'; end if;
 if p_page is null or p_page not between 1 and 100000 then raise exception 'Choose a valid history page.' using errcode='22023'; end if;
 select count(*)::integer into total from public.management_report_snapshots where organisation_id=p_organisation_id;
 select coalesce(jsonb_agg(v order by created_at desc,id desc),'[]') into reports from (
  select id,created_at,jsonb_build_object('id',id,'title',title,'from',period_from,'to',period_to,
   'location',payload->'context'->>'location','currency',payload->'context'->>'currency','created_at',created_at) v
  from public.management_report_snapshots where organisation_id=p_organisation_id
  order by created_at desc,id desc limit 20 offset(p_page-1)*20
 ) s;
 return jsonb_build_object('total',total,'reports',reports);
end; $$;
revoke all on function public.save_management_report(uuid,date,date,uuid,uuid,text),public.get_management_report(uuid,uuid),public.list_management_reports(uuid,integer) from public,anon;
grant execute on function public.save_management_report(uuid,date,date,uuid,uuid,text),public.get_management_report(uuid,uuid),public.list_management_reports(uuid,integer) to authenticated;
notify pgrst,'reload schema';
commit;
