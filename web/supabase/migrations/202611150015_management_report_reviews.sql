-- Apply ONCE after 014. Management review only; no accounting close/valuation change.
begin;
create function private.pp_report_approve(target_org uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisation_memberships m join public.membership_roles r
 on r.organisation_id=m.organisation_id and r.membership_id=m.id
 where m.organisation_id=target_org and m.user_id=(select auth.uid()) and m.status='active'
 and r.location_id is null and r.role_code in ('ceo','restaurant_admin'));
$$;
revoke all on function private.pp_report_approve(uuid) from public,anon,authenticated;

create table public.management_report_review_events (
 id uuid primary key default gen_random_uuid(), organisation_id uuid not null,
 report_id uuid not null, request_id uuid not null, revision integer not null check(revision>0),
 action text not null check(action in ('SUBMIT','COMMENT','APPROVE','REQUEST_CHANGES','WITHDRAW_APPROVAL')),
 status text not null check(status in ('SAVED','IN_REVIEW','CHANGES_REQUESTED','APPROVED')),
 note text not null check(length(note)<=2000), acknowledged boolean not null,
 actor_id uuid not null references auth.users(id), actor_label text not null,
 created_at timestamptz not null default statement_timestamp(),
 unique(organisation_id,id),unique(organisation_id,request_id),unique(organisation_id,report_id,revision),
 foreign key(organisation_id,report_id) references public.management_report_snapshots(organisation_id,id)
);
create index pp_report_review_order on public.management_report_review_events(organisation_id,report_id,revision desc);
alter table public.management_report_review_events enable row level security;
revoke all on public.management_report_review_events from public,anon,authenticated;
create trigger pp_report_review_immutable before update or delete on public.management_report_review_events
for each row execute function private.pp_report_immutable();

create function public.review_management_report(p_organisation_id uuid,p_report_id uuid,p_request_id uuid,
 p_expected_revision integer,p_action text,p_note text,p_acknowledged boolean)
returns uuid language plpgsql security definer set search_path='' as $$
declare previous public.management_report_review_events; retry public.management_report_review_events;
 current_revision integer:=0; current_status text:='SAVED'; next_status text; result uuid;
begin
 if not private.pp_sales_read(p_organisation_id) then raise exception 'Report access denied.' using errcode='42501'; end if;
 if p_action in ('APPROVE','REQUEST_CHANGES','WITHDRAW_APPROVAL') and not private.pp_report_approve(p_organisation_id)
 then raise exception 'Only an organisation-wide CEO or Restaurant Administrator can make review decisions.' using errcode='42501'; end if;
 if p_request_id is null or p_expected_revision is null or p_expected_revision<0 or p_note is null or length(trim(p_note))>2000
  or p_acknowledged is null or p_action is null or p_action not in ('SUBMIT','COMMENT','APPROVE','REQUEST_CHANGES','WITHDRAW_APPROVAL')
 then raise exception 'Choose a valid review action and enter a note of up to 2,000 characters.' using errcode='22023'; end if;
 -- Lock the immutable parent to serialize concurrent review decisions and retries.
 perform 1 from public.management_report_snapshots where organisation_id=p_organisation_id and id=p_report_id for update;
 if not found then raise exception 'Saved report unavailable.' using errcode='42501'; end if;
 select * into retry from public.management_report_review_events where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then
  if retry.report_id<>p_report_id or retry.actor_id<>auth.uid() or retry.action<>p_action or retry.note<>trim(p_note)
   or retry.acknowledged<>p_acknowledged or retry.revision<>p_expected_revision+1
  then raise exception 'This request was already used. Refresh the report before trying again.' using errcode='22023'; end if;
  return retry.id;
 end if;
 select * into previous from public.management_report_review_events where organisation_id=p_organisation_id and report_id=p_report_id order by revision desc limit 1;
 if found then current_revision:=previous.revision;current_status:=previous.status;end if;
 if current_revision<>p_expected_revision then raise exception 'This review changed since you opened it. Refresh the report before trying again.' using errcode='22023'; end if;
 if p_action in ('COMMENT','REQUEST_CHANGES','WITHDRAW_APPROVAL') and trim(p_note)='' then
  raise exception 'Enter a comment or the reason for your decision.' using errcode='22023'; end if;
 if p_action='SUBMIT' then
  if current_status not in ('SAVED','CHANGES_REQUESTED') then raise exception 'Only a saved report or a report with changes requested can be submitted.' using errcode='22023'; end if;
  if current_status='CHANGES_REQUESTED' and trim(p_note)='' then raise exception 'Explain how the review feedback has been addressed before resubmitting.' using errcode='22023'; end if;
  next_status:='IN_REVIEW';
 elsif p_action='COMMENT' then
  -- Comments before submission leave the report in its saved state.
  next_status:=current_status;
 elsif p_action='APPROVE' then
  if current_status<>'IN_REVIEW' then raise exception 'Submit this report for review before approving it.' using errcode='22023'; end if;
  if p_acknowledged is distinct from true then raise exception 'Confirm that you reviewed the saved figures, estimates and coverage warnings.' using errcode='22023'; end if;
  next_status:='APPROVED';
 elsif p_action='REQUEST_CHANGES' then
  if current_status<>'IN_REVIEW' then raise exception 'Changes can be requested only while a report is in review.' using errcode='22023'; end if;
  next_status:='CHANGES_REQUESTED';
 else
  if current_status<>'APPROVED' then raise exception 'Only an approved report has an approval to withdraw.' using errcode='22023'; end if;
  next_status:='CHANGES_REQUESTED';
 end if;
 insert into public.management_report_review_events(organisation_id,report_id,request_id,revision,action,status,note,acknowledged,actor_id,actor_label)
 values(p_organisation_id,p_report_id,p_request_id,current_revision+1,p_action,next_status,trim(p_note),p_acknowledged,auth.uid(),
  coalesce((select email from auth.users where id=auth.uid()),auth.uid()::text)) returning id into result;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details)
 values(p_organisation_id,'MANAGEMENT_REPORT_REVIEWED',auth.uid(),p_report_id,
  jsonb_build_object('review_event_id',result,'action',p_action,'status',next_status,'revision',current_revision+1));
 return result;
end; $$;
create function public.get_management_report_review(p_organisation_id uuid,p_report_id uuid,p_page integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare latest public.management_report_review_events; decision jsonb; events jsonb;
begin
 if not private.pp_sales_read(p_organisation_id) then raise exception 'Report access denied.' using errcode='42501'; end if;
 if not exists(select 1 from public.management_report_snapshots where organisation_id=p_organisation_id and id=p_report_id)
 then raise exception 'Saved report unavailable.' using errcode='42501'; end if;
 if p_page is null or p_page not between 1 and 100000 then raise exception 'Choose a valid review history page.' using errcode='22023'; end if;
 select * into latest from public.management_report_review_events where organisation_id=p_organisation_id and report_id=p_report_id order by revision desc limit 1;
 select jsonb_build_object('action',action,'actor',actor_label,'at',created_at,'note',note,'revision',revision)
 into decision from public.management_report_review_events where organisation_id=p_organisation_id and report_id=p_report_id and action<>'COMMENT' order by revision desc limit 1;
 select coalesce(jsonb_agg(v order by revision desc),'[]') into events from (
  select revision,jsonb_build_object('id',id,'revision',revision,'action',action,'status',status,'note',note,'actor',actor_label,'at',created_at) v
  from public.management_report_review_events where organisation_id=p_organisation_id and report_id=p_report_id
  order by revision desc limit 20 offset(p_page-1)*20
 ) s;
 return jsonb_build_object('status',coalesce(latest.status,'SAVED'),'revision',coalesce(latest.revision,0),
  'can_approve',private.pp_report_approve(p_organisation_id),'decision',decision,'events',events);
end; $$;

create or replace function public.list_management_reports(p_organisation_id uuid,p_page integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare reports jsonb; total integer;
begin
 if not private.pp_sales_read(p_organisation_id) then raise exception 'Report access denied.' using errcode='42501'; end if;
 if p_page is null or p_page not between 1 and 100000 then raise exception 'Choose a valid history page.' using errcode='22023'; end if;
 select count(*)::integer into total from public.management_report_snapshots where organisation_id=p_organisation_id;
 select coalesce(jsonb_agg(v order by created_at desc,id desc),'[]') into reports from (
  select s.id,s.created_at,jsonb_build_object('id',s.id,'title',s.title,'from',s.period_from,'to',s.period_to,
   'location',s.payload->'context'->>'location','currency',s.payload->'context'->>'currency','created_at',s.created_at,
   'review_status',coalesce((select e.status from public.management_report_review_events e where e.organisation_id=s.organisation_id and e.report_id=s.id order by e.revision desc limit 1),'SAVED')) v
  from public.management_report_snapshots s where s.organisation_id=p_organisation_id
  order by s.created_at desc,s.id desc limit 20 offset(p_page-1)*20
 ) s;
 return jsonb_build_object('total',total,'reports',reports);
end; $$;
revoke all on function public.review_management_report(uuid,uuid,uuid,integer,text,text,boolean),public.get_management_report_review(uuid,uuid,integer) from public,anon;
grant execute on function public.review_management_report(uuid,uuid,uuid,integer,text,text,boolean),public.get_management_report_review(uuid,uuid,integer) to authenticated;
notify pgrst,'reload schema';
commit;
