-- Daily centre accountability is separate from physical stock posting.
begin;
create table private.waste_schedules(
 organisation_id uuid not null,site_id uuid not null,effective_from date not null,revision integer not null,
 operating_days integer[] not null check(cardinality(operating_days) between 1 and 7 and operating_days<@array[0,1,2,3,4,5,6]),
 cutoff time not null,day_offset integer not null check(day_offset in(0,1)),time_zone text not null,
 required boolean not null,owner_id uuid,owner_name text,created_at timestamptz not null default clock_timestamp(),
 primary key(organisation_id,site_id,effective_from),foreign key(organisation_id,site_id) references public.stock_locations(organisation_id,id)
);
create table private.waste_daily_reports(
 id uuid primary key,organisation_id uuid not null,site_id uuid not null,day date not null,
 status text not null check(status in('CONFIRMED','REOPENED','CLOSED')),outcome text check(outcome in('WASTE','NO_WASTE')),
 revision integer not null,submitter_name text not null,actor_id uuid not null references auth.users(id),confirmed_at timestamptz not null,
 deadline timestamptz not null,owner_name text,reason text not null default '',
 unique(organisation_id,site_id,day),foreign key(organisation_id,site_id) references public.stock_locations(organisation_id,id)
);
create table private.waste_confirmation_requests(
 organisation_id uuid not null,request_id uuid not null,actor_id uuid not null,input_hash text not null,result_id uuid not null,
 primary key(organisation_id,request_id)
);
create table private.waste_value_snapshots(
 organisation_id uuid not null,document_id uuid not null,item_id uuid not null,source text not null check(source in('WASTE','PROCESSING')),
 quantity numeric not null,unit_cost numeric,estimated_value numeric,price_source jsonb,cost_basis text not null,
 primary key(organisation_id,document_id,item_id,source),foreign key(organisation_id,document_id) references public.stock_documents(organisation_id,id)
);
revoke all on private.waste_schedules,private.waste_daily_reports,private.waste_confirmation_requests,private.waste_value_snapshots from public,anon,authenticated;
create function private.pp_waste_schedule_manage(org uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.pp_team_manage(org) or private.pp_stock_role(org,'ceo',null);
$$;
-- Historical daily attestation keeps the existing waste role/scope checks, but does not
-- require the centre to remain active. Physical recording still requires an active centre.
do $$declare d text;n text;begin
 d:=pg_get_functiondef('private.pp_can_record_waste(uuid,uuid)'::regprocedure);
 n:=replace(d,' and exists(select 1 from public.stock_locations s where s.organisation_id=org and s.id=site and s.is_active)','');
 if n=d then raise exception 'Expected waste recording active-centre guard missing';end if;
 n:=replace(n,'private.pp_can_record_waste','private.pp_can_confirm_waste');execute n;
end $$;
create function private.pp_track_waste_schedule() returns trigger language plpgsql security definer set search_path='' as $$
declare day date;zone text;prior private.waste_schedules;applicable private.waste_schedules;begin
 select time_zone,(now() at time zone time_zone)::date into zone,day from public.organisations where id=new.organisation_id;
 select * into prior from private.waste_schedules where organisation_id=new.organisation_id and site_id=new.id order by effective_from desc limit 1;
 if tg_op='INSERT' or prior.site_id is null then
  insert into private.waste_schedules values(new.organisation_id,new.id,day,0,array[0,1,2,3,4,5,6],'23:59',0,zone,new.is_active,new.responsible_membership_id,private.pp_member_label(new.organisation_id,new.responsible_membership_id),clock_timestamp());
 elsif new.is_active is distinct from old.is_active or new.responsible_membership_id is distinct from old.responsible_membership_id then
  if prior.effective_from=day and new.is_active=old.is_active and not exists(select 1 from private.waste_daily_reports where organisation_id=new.organisation_id and site_id=new.id) and not exists(select 1 from public.stock_documents where organisation_id=new.organisation_id and(source_id=new.id or destination_id=new.id)) then
   update private.waste_schedules set owner_id=new.responsible_membership_id,owner_name=private.pp_member_label(new.organisation_id,new.responsible_membership_id),required=new.is_active where organisation_id=new.organisation_id and site_id=new.id and effective_from=day;
  else
   select * into applicable from private.waste_schedules where organisation_id=new.organisation_id and site_id=new.id and effective_from<=day+1 order by effective_from desc limit 1;
   insert into private.waste_schedules values(new.organisation_id,new.id,day+1,prior.revision+1,applicable.operating_days,applicable.cutoff,applicable.day_offset,applicable.time_zone,new.is_active,new.responsible_membership_id,private.pp_member_label(new.organisation_id,new.responsible_membership_id),clock_timestamp())
   on conflict(organisation_id,site_id,effective_from) do update set required=excluded.required,owner_id=excluded.owner_id,owner_name=excluded.owner_name,revision=excluded.revision;
   update private.waste_schedules set owner_id=new.responsible_membership_id,owner_name=private.pp_member_label(new.organisation_id,new.responsible_membership_id),required=new.is_active,revision=prior.revision+1 where organisation_id=new.organisation_id and site_id=new.id and effective_from>day+1;
   insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(new.organisation_id,'WASTE_CENTRE_SCHEDULE_UPDATED',auth.uid(),new.id,jsonb_build_object('prior',to_jsonb(prior),'effective_from',day+1,'responsible',new.responsible_membership_id,'active',new.is_active));
  end if;
 end if;return new;
end $$;
create function public.waste_reporting_setup(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Waste access required.' using errcode='42501';end if;
 return jsonb_build_object('manage',private.pp_waste_schedule_manage(p_organisation_id),'centres',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'active',s.is_active,'owner',private.pp_member_label(s.organisation_id,s.responsible_membership_id),'schedule',to_jsonb(p)) order by s.name,s.id) from public.stock_locations s join lateral(select * from private.waste_schedules where organisation_id=s.organisation_id and site_id=s.id order by effective_from desc limit 1)p on true where s.organisation_id=p_organisation_id and private.pp_waste_site(p_organisation_id,s.id)),'[]'::jsonb));
end $$;
create function public.save_waste_reporting_schedule(p_organisation_id uuid,p_site_id uuid,p_revision integer,p_effective_from date,p_days integer[],p_cutoff time,p_day_offset integer) returns void language plpgsql security definer set search_path='' as $$
declare prior private.waste_schedules;today date;zone text;s public.stock_locations;superseded jsonb;begin
 if not private.pp_waste_schedule_manage(p_organisation_id) or not private.pp_waste_site(p_organisation_id,p_site_id) then raise exception 'Restaurant administrator or CEO access is required.' using errcode='42501';end if;
 select time_zone,(now() at time zone time_zone)::date into zone,today from public.organisations where id=p_organisation_id for update;
 select * into s from public.stock_locations where organisation_id=p_organisation_id and id=p_site_id;
 select * into prior from private.waste_schedules where organisation_id=p_organisation_id and site_id=p_site_id order by effective_from desc limit 1;
 if prior.revision is distinct from p_revision then raise exception 'The schedule changed. Refresh before saving.' using errcode='22023';end if;
 if p_effective_from is null or p_effective_from<today+1 or p_days is null or cardinality(p_days) not between 1 and 7 or not p_days<@array[0,1,2,3,4,5,6] or cardinality(p_days)<>(select count(distinct v) from unnest(p_days) v) or array_position(p_days,null) is not null or p_cutoff is null or p_cutoff='24:00'::time or p_day_offset is null or p_day_offset not in(0,1) then raise exception 'Choose operating days, a local deadline and an effective date from tomorrow. Past obligations cannot be removed.' using errcode='22023';end if;
 select jsonb_agg(to_jsonb(v)) into superseded from private.waste_schedules v where organisation_id=p_organisation_id and site_id=p_site_id and effective_from>=p_effective_from;
 delete from private.waste_schedules where organisation_id=p_organisation_id and site_id=p_site_id and effective_from>=p_effective_from and effective_from>today;
 insert into private.waste_schedules values(p_organisation_id,p_site_id,p_effective_from,prior.revision+1,p_days,p_cutoff,p_day_offset,zone,s.is_active,s.responsible_membership_id,private.pp_member_label(p_organisation_id,s.responsible_membership_id),clock_timestamp()) on conflict(organisation_id,site_id,effective_from) do update set revision=excluded.revision,operating_days=excluded.operating_days,cutoff=excluded.cutoff,day_offset=excluded.day_offset,time_zone=excluded.time_zone,required=excluded.required,owner_id=excluded.owner_id,owner_name=excluded.owner_name;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'WASTE_SCHEDULE_CHANGED',auth.uid(),p_site_id,jsonb_build_object('prior',to_jsonb(prior),'superseded_future_plans',superseded,'effective_from',p_effective_from,'days',p_days,'cutoff',p_cutoff,'day_offset',p_day_offset,'time_zone',zone));
end $$;
create function public.waste_day_history(p_organisation_id uuid,p_site_id uuid,p_day date) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.pp_stock_read(p_organisation_id) or not private.pp_waste_site(p_organisation_id,p_site_id) then raise exception 'Waste history access required.' using errcode='42501';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('event',a.event_type,'at',a.created_at,'actor',coalesce(nullif(m.display_name,''),u.email),'details',a.details) order by a.created_at desc,a.id) from public.audit_events a left join auth.users u on u.id=a.actor_id left join public.organisation_memberships m on m.organisation_id=a.organisation_id and m.user_id=a.actor_id where a.organisation_id=p_organisation_id and a.entity_id=md5(p_organisation_id::text||p_site_id::text||p_day::text)::uuid and a.event_type in('WASTE_DAY_CONFIRMED','WASTE_DAY_REOPENED')),'[]'::jsonb);
end $$;
create function public.waste_compliance_workspace(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare start_day date;today date;result jsonb;begin
 if not private.pp_stock_read(p_organisation_id) then return null;end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 select min(effective_from) into start_day from private.waste_schedules where organisation_id=p_organisation_id;
 if start_day is null then return null;end if;
 with rows as materialized(select * from private.pp_waste_daily_rows(p_organisation_id,start_day,today)),tasks as(select * from rows where expected and(state not like 'COMPLETE_%') order by case state when 'OVERDUE' then 0 else 1 end,day,centre limit 5)
 select jsonb_build_object('today',today,'from',start_day,'expected_today',count(*) filter(where day=today and expected),'complete_today',count(*) filter(where day=today and state like 'COMPLETE_%'),'overdue',count(*) filter(where state='OVERDUE'),'missing_owners',count(distinct site_id) filter(where owner_missing and day=today and expected),'open',count(*) filter(where expected and state not like 'COMPLETE_%'),'today_rows',coalesce((select jsonb_agg(to_jsonb(t)) from(select * from rows where day=today and expected order by centre,site_id limit 10)t),'[]'::jsonb),'tasks',coalesce((select jsonb_agg(to_jsonb(t)) from tasks t),'[]'::jsonb)) into result from rows;
 return result;
end $$;
-- Existing centres start today, never retroactively overdue at rollout.
insert into private.waste_schedules select s.organisation_id,s.id,(now() at time zone o.time_zone)::date,0,array[0,1,2,3,4,5,6],'23:59',0,o.time_zone,s.is_active,s.responsible_membership_id,private.pp_member_label(s.organisation_id,s.responsible_membership_id),clock_timestamp() from public.stock_locations s join public.organisations o on o.id=s.organisation_id;
create trigger waste_centre_schedule after insert or update of is_active,responsible_membership_id on public.stock_locations for each row execute function private.pp_track_waste_schedule();
alter table public.stock_documents add column waste_reason_code text check(waste_reason_code in('SPOILAGE','EXPIRY','DAMAGE','BAD_PRODUCTION','OTHER'));
create function private.pp_snapshot_waste(org uuid,doc uuid,reconstructed boolean default false) returns void language plpgsql security definer set search_path='' as $$
declare d public.stock_documents;r record;price jsonb;amount numeric;begin
 select * into d from public.stock_documents where organisation_id=org and id=doc and state='POSTED';if not found then return;end if;
 for r in
  select (l->>'item_id')::uuid item_id,sum((l->>'quantity')::numeric) quantity,'WASTE'::text source from jsonb_array_elements(d.lines) l where d.kind='WASTE' group by l->>'item_id'
  union all select w.item_id,w.quantity,'PROCESSING' from public.processing_waste w where w.organisation_id=org and w.document_id=doc
 loop
  if exists(select 1 from private.waste_value_snapshots where organisation_id=org and document_id=doc and item_id=r.item_id and source=r.source) then continue;end if;
  price:=null;amount:=null;
  begin
   if r.source='PROCESSING' then select a->'source' into price from private.processing_batch_costs c cross join lateral jsonb_array_elements(c.value->'lines') a where c.organisation_id=org and c.document_id=doc and a->>'item_id'=r.item_id::text limit 1;end if;
   if price is null then price:=private.pp_effective_material_cost(org,r.item_id,d.document_date,array[]::uuid[]);end if;
   if price->>'unit_cost' is not null then amount:=round(r.quantity*(price->>'unit_cost')::numeric,12);end if;
  exception when others then price:=jsonb_build_object('missing_reason','COST_UNAVAILABLE');amount:=null;end;
  insert into private.waste_value_snapshots values(org,doc,r.item_id,r.source,r.quantity,(price->>'unit_cost')::numeric,amount,price,case when reconstructed then 'RECONSTRUCTED_AT_ROLLOUT' else 'POSTING_ESTIMATE' end) on conflict do nothing;
 end loop;
end $$;
create function private.pp_reopen_waste_day(org uuid,site uuid,p_day date,doc uuid) returns void language plpgsql security definer set search_path='' as $$
declare prior private.waste_daily_reports;begin
 select * into prior from private.waste_daily_reports where organisation_id=org and site_id=site and waste_daily_reports.day=p_day for update;
 if found and prior.status in('CONFIRMED','CLOSED') then
  update private.waste_daily_reports set status='REOPENED',revision=revision+1 where id=prior.id;
  insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(org,'WASTE_DAY_REOPENED',auth.uid(),prior.id,jsonb_build_object('prior',to_jsonb(prior),'document',doc));
 end if;
end $$;
create function private.pp_waste_document_changed() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.kind='WASTE' or exists(select 1 from public.processing_waste where organisation_id=new.organisation_id and document_id=new.id) then
  if tg_op='INSERT' or new.state is distinct from old.state then
   perform private.pp_reopen_waste_day(new.organisation_id,new.source_id,new.document_date,new.id);
   if new.state='POSTED' then perform private.pp_snapshot_waste(new.organisation_id,new.id);end if;
  end if;
 end if;return new;
end $$;
create trigger waste_daily_document after insert or update of state on public.stock_documents for each row execute function private.pp_waste_document_changed();
create function private.pp_processing_loss_changed() returns trigger language plpgsql security definer set search_path='' as $$declare d public.stock_documents;begin
 select * into d from public.stock_documents where organisation_id=new.organisation_id and id=new.document_id;
 perform private.pp_reopen_waste_day(d.organisation_id,d.source_id,d.document_date,d.id);
 if d.state='POSTED' then perform private.pp_snapshot_waste(d.organisation_id,d.id);end if;return new;
end $$;
create trigger processing_daily_loss after insert on public.processing_waste for each row execute function private.pp_processing_loss_changed();
do $$declare r record;begin for r in select distinct d.organisation_id,d.id from public.stock_documents d where d.state='POSTED' and(d.kind='WASTE' or exists(select 1 from public.processing_waste w where w.organisation_id=d.organisation_id and w.document_id=d.id)) loop perform private.pp_snapshot_waste(r.organisation_id,r.id,true);end loop;end $$;
alter function public.request_stock_document(uuid,uuid,jsonb,jsonb) rename to pp_request_before_daily_waste;
alter function public.pp_request_before_daily_waste(uuid,uuid,jsonb,jsonb) set schema private;
revoke all on function private.pp_request_before_daily_waste(uuid,uuid,jsonb,jsonb) from public,anon,authenticated;
create function public.request_stock_document(p_organisation_id uuid,p_request_id uuid,p_document jsonb,p_lines jsonb) returns uuid language plpgsql security definer set search_path='' as $$declare doc uuid;begin
 if p_document->>'kind'='WASTE' and p_document?'waste_reason_code' and coalesce(p_document->>'waste_reason_code','') not in('SPOILAGE','EXPIRY','DAMAGE','BAD_PRODUCTION','OTHER') then raise exception 'Choose a valid waste reason.' using errcode='22023';end if;
 doc:=private.pp_request_before_daily_waste(p_organisation_id,p_request_id,p_document,p_lines);
 if p_document->>'kind'='WASTE' then update public.stock_documents set waste_reason_code=p_document->>'waste_reason_code' where organisation_id=p_organisation_id and id=doc;end if;return doc;
end $$;
revoke all on function public.request_stock_document(uuid,uuid,jsonb,jsonb) from public,anon;
grant execute on function public.request_stock_document(uuid,uuid,jsonb,jsonb) to authenticated;
-- One source of truth for posted and unposted loss documents, including trim once.
create function private.pp_waste_day_evidence(org uuid,site uuid,day date) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('posted',count(*) filter(where state='POSTED'),'pending',count(*) filter(where state in('REQUESTED','APPROVED')),'hash',md5(coalesce(string_agg(id::text||state||lines::text,',' order by id),'')))
 from public.stock_documents d where d.organisation_id=org and d.source_id=site and d.document_date=day and d.state in('REQUESTED','APPROVED','POSTED') and(d.kind='WASTE' or exists(select 1 from public.processing_waste w where w.organisation_id=d.organisation_id and w.document_id=d.id));
$$;
create function private.pp_waste_daily_rows(org uuid,day_from date,day_to date,site uuid default null) returns table(
 site_id uuid,centre text,outlet_id uuid,day date,deadline timestamptz,time_zone text,owner_name text,owner_missing boolean,
 state text,expected boolean,posted integer,pending integer,revision integer,evidence text,submitter_name text,confirmed_account text,confirmed_at timestamptz,on_time boolean,closure_late boolean,reason text,can_confirm boolean,record_id uuid)
language sql stable security definer set search_path='' as $$
 with dates as(select generate_series(day_from,day_to,interval '1 day')::date as day),base as(
  select s.*,dt.day,p.cutoff,p.day_offset,p.time_zone,p.owner_id,p.owner_name policy_owner,
   (dt.day+p.day_offset+p.cutoff) at time zone p.time_zone deadline,p.required and extract(dow from dt.day)::integer=any(p.operating_days) scheduled,
   e.value evidence_data,d.id daily_id,d.status,d.outcome,d.revision,d.submitter_name,d.confirmed_at,d.owner_name saved_owner,d.reason,ua.email confirmed_account
  from public.stock_locations s cross join dates dt
  join lateral(select * from private.waste_schedules p where p.organisation_id=s.organisation_id and p.site_id=s.id and p.effective_from<=dt.day order by p.effective_from desc limit 1)p on true
  cross join lateral(select private.pp_waste_day_evidence(org,s.id,dt.day) value)e
  left join private.waste_daily_reports d on d.organisation_id=s.organisation_id and d.site_id=s.id and d.day=dt.day
  left join auth.users ua on ua.id=d.actor_id
  where s.organisation_id=org and(site is null or s.id=site) and private.pp_waste_site(org,s.id)
 ),status as(
  select b.*,case when b.status='CLOSED' and (evidence_data->>'posted')::integer=0 and(evidence_data->>'pending')::integer=0 then 'CLOSED'
   when b.status is null and not scheduled and(evidence_data->>'posted')::integer=0 and(evidence_data->>'pending')::integer=0 then 'CLOSED'
   when b.status='CONFIRMED' then case when outcome='NO_WASTE' then 'COMPLETE_NO_WASTE' else 'COMPLETE_WASTE' end
   when clock_timestamp()>b.deadline then 'OVERDUE'
   when b.status='REOPENED' or(evidence_data->>'posted')::integer>0 or(evidence_data->>'pending')::integer>0 then 'IN_PROGRESS' else 'PENDING' end computed_state
  from base b
 )
 select b.id,b.name,b.outlet_id,b.day,b.deadline,b.time_zone,coalesce(b.saved_owner,b.policy_owner),
  case when b.status in('CONFIRMED','CLOSED') and b.saved_owner is not null then false else b.responsible_membership_id is null or not exists(select 1 from public.organisation_memberships m where m.organisation_id=org and m.id=b.responsible_membership_id and m.status='active') end,
  computed_state,computed_state<>'CLOSED',(evidence_data->>'posted')::integer,(evidence_data->>'pending')::integer,coalesce(b.revision,0),evidence_data->>'hash',b.submitter_name,b.confirmed_account,b.confirmed_at,
  case when b.status='CONFIRMED' then b.confirmed_at<=b.deadline end,case when b.status='CLOSED' then b.confirmed_at>b.deadline else false end,coalesce(b.reason,''),private.pp_can_confirm_waste(org,b.id),
  coalesce(b.daily_id,md5(org::text||b.id::text||b.day::text)::uuid)
 from status b;
$$;
create function public.waste_daily_report(p_organisation_id uuid,p_site_id uuid,p_from date,p_to date,p_state text default 'ALL',p_page integer default 1,p_export boolean default false) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;today date;begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Waste report access required.' using errcode='42501';end if;
 if p_site_id is not null and not private.pp_waste_site(p_organisation_id,p_site_id) then raise exception 'This centre is outside your waste access.' using errcode='42501';end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 if p_from is null or p_to is null or p_from>p_to or p_to>today or p_to-p_from>366 or p_state is null or p_state not in('ALL','OVERDUE','PENDING','IN_PROGRESS','COMPLETE_WASTE','COMPLETE_NO_WASTE','CLOSED','LATE') or p_page is null or p_page not between 1 and 100000 or p_export is null then raise exception 'Choose valid dates within 367 days and a reporting status.' using errcode='22023';end if;
 with rows as materialized(select * from private.pp_waste_daily_rows(p_organisation_id,p_from,p_to,p_site_id)),matching as materialized(select * from rows where p_state='ALL' or state=p_state or(p_state='LATE' and on_time=false)),paged as(select * from matching order by case state when 'OVERDUE' then 0 when 'IN_PROGRESS' then 1 when 'PENDING' then 2 else 3 end,day desc,centre,site_id limit(case when p_export then 5001 else 25 end) offset(case when p_export then 0 else(p_page-1)*25 end))
 select jsonb_build_object('total',(select count(*) from matching),'summary',(select jsonb_build_object('expected',count(*) filter(where expected),'complete',count(*) filter(where state like 'COMPLETE_%'),'on_time',count(*) filter(where on_time=true),'late',count(*) filter(where on_time=false),'late_closures',count(*) filter(where closure_late),'overdue',count(*) filter(where state='OVERDUE'),'no_waste',count(*) filter(where state='COMPLETE_NO_WASTE'),'closed',count(*) filter(where state='CLOSED'),'owner_missing',count(*) filter(where owner_missing and expected),'due_expected',count(*) filter(where expected and deadline<=clock_timestamp()),'on_time_due',count(*) filter(where on_time=true and deadline<=clock_timestamp())) from rows),'rows',coalesce((select jsonb_agg(to_jsonb(p) order by case state when 'OVERDUE' then 0 when 'IN_PROGRESS' then 1 when 'PENDING' then 2 else 3 end,day desc,centre,site_id) from paged p),'[]'::jsonb)) into result;
 if p_export and(result->>'total')::integer>5000 then raise exception 'Narrow the report to export at most 5,000 centre-days.' using errcode='22023';end if;
 return result;
end $$;
create function public.confirm_waste_day(p_organisation_id uuid,p_site_id uuid,p_day date,p_outcome text,p_submitter text,p_revision integer,p_evidence text,p_request_id uuid,p_reason text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare r record;old private.waste_confirmation_requests;prior private.waste_daily_reports;today date;digest text:=md5(jsonb_build_array(p_site_id,p_day,p_outcome,p_submitter,p_revision,p_evidence,p_reason)::text);begin
 if not private.pp_can_confirm_waste(p_organisation_id,p_site_id) and not(p_outcome in('CLOSED','REOPEN') and private.pp_waste_schedule_manage(p_organisation_id) and private.pp_waste_site(p_organisation_id,p_site_id)) then raise exception 'You cannot confirm this centre waste report.' using errcode='42501';end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 if p_day is null or p_day>today or p_request_id is null or p_outcome is null or p_outcome not in('WASTE','NO_WASTE','CLOSED','REOPEN') or p_submitter is null or length(trim(p_submitter)) not between 1 and 120 or p_submitter~'[[:cntrl:]]' or p_reason is null or length(p_reason)>500 then raise exception 'Choose a reporting date and enter the submitter name.' using errcode='22023';end if;
 if p_outcome='CLOSED' and(not private.pp_waste_schedule_manage(p_organisation_id) or length(trim(p_reason))<3) then raise exception 'An administrator or CEO must give the reason this centre was closed.' using errcode='22023';end if;
 perform 1 from public.organisations o where o.id=p_organisation_id for update;
 select * into old from private.waste_confirmation_requests where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then if old.actor_id<>auth.uid() or old.input_hash<>digest then raise exception 'Refresh before confirming changed details.' using errcode='22023';end if;return(select to_jsonb(d) from private.waste_daily_reports d where d.id=old.result_id);end if;
 select * into r from private.pp_waste_daily_rows(p_organisation_id,p_day,p_day,p_site_id);
 if not found or r.revision is distinct from p_revision or r.evidence is distinct from p_evidence then raise exception 'This report changed. Refresh and review the entries again.' using errcode='22023';end if;
 if p_outcome='REOPEN' and length(trim(p_reason))<3 then raise exception 'Explain why the report is being reopened.' using errcode='22023';end if;
 if r.state like 'COMPLETE_%' and p_outcome<>'REOPEN' then raise exception 'This day is already confirmed. Reopen it with a reason before changing the declaration.' using errcode='22023';end if;
 if r.state='CLOSED' and p_outcome<>'REOPEN' then raise exception 'This centre is not scheduled to report on this day.' using errcode='22023';end if;
 if p_outcome<>'REOPEN' and r.pending>0 then raise exception 'Complete or cancel the unposted waste/processing losses before confirming the day.' using errcode='22023';end if;
 if p_outcome in('NO_WASTE','CLOSED') and r.posted>0 then raise exception 'Recorded waste exists. Confirm the waste report instead.' using errcode='22023';end if;
 if p_outcome='WASTE' and r.posted=0 then raise exception 'Record the waste first, or explicitly confirm no waste.' using errcode='22023';end if;
 if p_outcome not in('CLOSED','REOPEN') and r.owner_missing then raise exception 'Assign an active responsible owner for this centre before confirming its report.' using errcode='22023';end if;
 select * into prior from private.waste_daily_reports where id=r.record_id;
 insert into private.waste_daily_reports values(r.record_id,p_organisation_id,p_site_id,p_day,case when p_outcome='CLOSED' then 'CLOSED' when p_outcome='REOPEN' then 'REOPENED' else 'CONFIRMED' end,case when p_outcome in('WASTE','NO_WASTE') then p_outcome end,r.revision+1,trim(p_submitter),auth.uid(),clock_timestamp(),r.deadline,r.owner_name,trim(p_reason))
 on conflict(organisation_id,site_id,day) do update set status=excluded.status,outcome=excluded.outcome,revision=excluded.revision,submitter_name=excluded.submitter_name,actor_id=excluded.actor_id,confirmed_at=excluded.confirmed_at,deadline=excluded.deadline,owner_name=excluded.owner_name,reason=excluded.reason;
 insert into private.waste_confirmation_requests values(p_organisation_id,p_request_id,auth.uid(),digest,r.record_id);
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,case when p_outcome='REOPEN' then 'WASTE_DAY_REOPENED' else 'WASTE_DAY_CONFIRMED' end,auth.uid(),r.record_id,jsonb_build_object('prior',case when prior.id is not null then to_jsonb(prior) end,'centre',p_site_id,'day',p_day,'outcome',p_outcome,'submitter',trim(p_submitter),'reason',trim(p_reason),'deadline',r.deadline));
 return(select to_jsonb(d) from private.waste_daily_reports d where d.id=r.record_id);
end $$;

create index waste_day_documents on public.stock_documents(organisation_id,source_id,document_date);
create index waste_day_audit on public.audit_events(organisation_id,entity_id,created_at) where event_type in('WASTE_DAY_CONFIRMED','WASTE_DAY_REOPENED');
create function public.waste_analysis(p_organisation_id uuid,p_site_id uuid,p_from date,p_to date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;today date;financial boolean;currency text;begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Waste analysis access required.' using errcode='42501';end if;
 if p_site_id is not null and not private.pp_waste_site(p_organisation_id,p_site_id) then raise exception 'This centre is outside your waste access.' using errcode='42501';end if;
 select(now() at time zone time_zone)::date,currency_code into today,currency from public.organisations where id=p_organisation_id;
 if p_from is null or p_to is null or p_from>p_to or p_to>today or p_to-p_from>366 then raise exception 'Choose an analysis period within 367 days, ending no later than today.' using errcode='22023';end if;
 financial:=private.pp_reference_price_read(p_organisation_id);
 with losses as materialized(
  select d.id,d.document_date,d.source_id,s.name centre,v.item_id,i.name material,u.code unit,v.quantity,v.estimated_value,v.cost_basis,
   case when v.source='PROCESSING' then 'PROCESSING' else coalesce(d.waste_reason_code,'UNCLASSIFIED') end reason
  from private.waste_value_snapshots v join public.stock_documents d on d.organisation_id=v.organisation_id and d.id=v.document_id and d.state='POSTED'
  join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id
  join public.items i on i.organisation_id=v.organisation_id and i.id=v.item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id
  where d.organisation_id=p_organisation_id and d.document_date between p_from and p_to and(p_site_id is null or d.source_id=p_site_id) and private.pp_waste_site(p_organisation_id,d.source_id) and private.pp_stock_doc_read(p_organisation_id,d.id)
 ),compliance as materialized(select * from private.pp_waste_daily_rows(p_organisation_id,p_from,p_to,p_site_id)),days as(
  select x::date as day from generate_series(p_from,p_to,interval '1 day') x
 ),daily as(
  select a.day,coalesce(l.entries,0) entries,coalesce(l.unpriced,0) unpriced,coalesce(c.expected,0) expected,coalesce(c.complete,0) complete,coalesce(c.on_time,0) on_time,
   case when financial then case when l.priced>0 then l.known_value::text when c.expected>0 and c.expected=c.complete and coalesce(l.entries,0)=0 then '0' end end known_value
  from days a left join(select document_date,count(*) entries,count(*) filter(where estimated_value is null) unpriced,count(*) filter(where estimated_value is not null) priced,sum(estimated_value) known_value from losses group by document_date)l on l.document_date=a.day
  left join(select day,count(*) filter(where expected) expected,count(*) filter(where state like 'COMPLETE_%') complete,count(*) filter(where on_time) on_time from compliance group by day)c on c.day=a.day
 ),materials as(
  select item_id,material,unit,sum(quantity)::text quantity,count(*) entries,
   case when financial then sum(estimated_value)::text end known_value,case when financial then count(*) filter(where estimated_value is null) end unpriced
  from losses group by item_id,material,unit order by case when financial then sum(estimated_value) end desc nulls last,count(*) desc,material,item_id limit 10
 ),reasons as(
  select reason,count(*) entries,case when financial then sum(estimated_value)::text end known_value,case when financial then count(*) filter(where estimated_value is null) end unpriced from losses group by reason order by count(*) desc,reason
 ),centres as(
  select source_id,centre,count(*) entries,case when financial then sum(estimated_value)::text end known_value,case when financial then count(*) filter(where estimated_value is null) end unpriced from losses group by source_id,centre order by count(*) desc,centre,source_id limit 20
 ),yields as(
  select st.id standard_id,v.name process,u.code unit,count(*) batches,count(*) filter(where b.outside_tolerance) outside_tolerance,
   round(sum(b.actual_output)/nullif(sum(b.expected_output),0)*100,6)::text output_achievement,
   count(*) filter(where b.input_weight_kg is not null and b.usable_weight_kg is not null) measured_batches,
   case when count(*)=count(*) filter(where b.input_weight_kg is not null and b.usable_weight_kg is not null) then round(sum(b.usable_weight_kg)/nullif(sum(b.input_weight_kg),0)*100,6)::text end usable_yield
  from public.processing_batches b join public.stock_documents d on d.organisation_id=b.organisation_id and d.id=b.document_id and d.state='POSTED'
  join public.processing_standards st on st.organisation_id=b.organisation_id and st.id=b.standard_id join public.recipe_versions v on v.organisation_id=st.organisation_id and v.id=st.recipe_version_id
  join public.items i on i.organisation_id=st.organisation_id and i.id=st.output_item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id
  where b.organisation_id=p_organisation_id and d.document_date between p_from and p_to and(p_site_id is null or d.source_id=p_site_id) and private.pp_waste_site(p_organisation_id,d.source_id) and private.pp_stock_doc_read(p_organisation_id,d.id)
  group by st.id,v.name,u.code order by count(*) filter(where b.outside_tolerance) desc,v.name,st.id limit 10
 )
 select jsonb_build_object('from',p_from,'to',p_to,'financial',financial,'currency',currency,
  'entries',(select count(*) from losses),'known_value',case when financial then coalesce((select sum(estimated_value)::text from losses),case when not exists(select 1 from losses) and exists(select 1 from compliance where expected) and not exists(select 1 from compliance where expected and state not like 'COMPLETE_%') then '0' end) end,
  'unpriced',case when financial then(select count(*) from losses where estimated_value is null) end,
  'reconstructed',case when financial then(select count(*) from losses where cost_basis='RECONSTRUCTED_AT_ROLLOUT') end,
  'coverage',(select jsonb_build_object('expected',count(*) filter(where expected),'complete',count(*) filter(where state like 'COMPLETE_%'),'on_time',count(*) filter(where on_time),'closed',count(*) filter(where state='CLOSED'),'due_expected',count(*) filter(where expected and deadline<=clock_timestamp()),'on_time_due',count(*) filter(where on_time=true and deadline<=clock_timestamp())) from compliance),
  'daily',coalesce((select jsonb_agg(to_jsonb(x) order by day) from daily x),'[]'::jsonb),
  'materials',coalesce((select jsonb_agg(to_jsonb(x)) from materials x),'[]'::jsonb),'reasons',coalesce((select jsonb_agg(to_jsonb(x)) from reasons x),'[]'::jsonb),'centres',coalesce((select jsonb_agg(to_jsonb(x)) from centres x),'[]'::jsonb),'yields',coalesce((select jsonb_agg(to_jsonb(x)) from yields x),'[]'::jsonb)) into result;
 return result;
end $$;
do $$declare r record;begin
 for r in select oid::regprocedure sig from pg_proc where pronamespace='private'::regnamespace and proname in('pp_can_confirm_waste','pp_waste_schedule_manage','pp_track_waste_schedule','pp_snapshot_waste','pp_reopen_waste_day','pp_waste_document_changed','pp_processing_loss_changed','pp_waste_day_evidence','pp_waste_daily_rows') loop execute format('revoke all on function %s from public,anon,authenticated',r.sig);end loop;
end $$;
revoke all on function public.waste_reporting_setup(uuid),public.save_waste_reporting_schedule(uuid,uuid,integer,date,integer[],time,integer),public.waste_day_history(uuid,uuid,date),public.waste_compliance_workspace(uuid),public.waste_daily_report(uuid,uuid,date,date,text,integer,boolean),public.confirm_waste_day(uuid,uuid,date,text,text,integer,text,uuid,text),public.waste_analysis(uuid,uuid,date,date) from public,anon;
grant execute on function public.waste_reporting_setup(uuid),public.save_waste_reporting_schedule(uuid,uuid,integer,date,integer[],time,integer),public.waste_day_history(uuid,uuid,date),public.waste_compliance_workspace(uuid),public.waste_daily_report(uuid,uuid,date,date,text,integer,boolean),public.confirm_waste_day(uuid,uuid,date,text,text,integer,text,uuid,text),public.waste_analysis(uuid,uuid,date,date) to authenticated;
notify pgrst,'reload schema';
commit;
