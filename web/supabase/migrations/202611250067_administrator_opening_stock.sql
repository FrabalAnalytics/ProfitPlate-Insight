-- Restaurant Administrators may verify and post initial stock without a second
-- approver. Existing permissions and first-posting safeguards still apply.
begin;
alter table public.stock_documents add column opening_recorded_directly boolean not null default false;
alter function public.stock_document_action(uuid,uuid,text,text,jsonb) rename to pp_stock_action_before_admin_openings;
alter function public.pp_stock_action_before_admin_openings(uuid,uuid,text,text,jsonb) set schema private;
revoke all on function private.pp_stock_action_before_admin_openings(uuid,uuid,text,text,jsonb) from public,anon,authenticated;
create function private.pp_post_admin_opening(org uuid,doc uuid,p_note text) returns uuid language plpgsql security definer set search_path='' as $$
declare d public.stock_documents;line jsonb;
begin
 if not private.pp_stock_role(org,'restaurant_admin',null) then raise exception 'Business-wide Restaurant Administrator access is required to record opening stock directly.' using errcode='42501';end if;
 perform 1 from public.organisations o where o.id=org and o.access_state='ACTIVE' for update;
 if not found then raise exception 'An active restaurant workspace is required.' using errcode='42501';end if;
 select * into d from public.stock_documents where organisation_id=org and id=doc for update;
 if d.id is null or not private.pp_stock_doc_read(org,doc) then raise exception 'Opening stock is outside your restaurant access.' using errcode='42501';end if;
 if d.kind<>'OPENING' then raise exception 'Direct administrator posting applies only to opening stock.' using errcode='22023';end if;
 if d.state='POSTED' and d.opening_recorded_directly then return d.id;end if;
 if d.state not in('REQUESTED','APPROVED') then raise exception 'This opening is no longer available for posting.' using errcode='22023';end if;
 if length(trim(coalesce(p_note,''))) not between 1 and 1000 then raise exception 'Enter the verified opening reference or reason.' using errcode='22023';end if;
 if not exists(select 1 from public.stock_locations where organisation_id=org and id=d.destination_id and is_active) then raise exception 'Choose an active stock centre.' using errcode='22023';end if;
 if d.document_date>(select(now() at time zone time_zone)::date from public.organisations where id=org) then raise exception 'Opening date cannot be in the future.' using errcode='22023';end if;
 perform private.pp_stock_lines(org,d.lines);
 if exists(select 1 from jsonb_array_elements(d.lines) l where (l->>'quantity')::numeric<=0) then raise exception 'Opening quantities must be positive. Confirm zero openings separately.' using errcode='22023';end if;
 if exists(select 1 from public.stock_ledger e join jsonb_array_elements(d.lines) l on l->>'item_id'=e.item_id::text where e.organisation_id=org and e.location_id=d.destination_id) then raise exception 'Opening balances must be the first posting for each material at this centre. Use a reviewed physical count for corrections.' using errcode='22023';end if;
 for line in select value from jsonb_array_elements(d.lines) loop
  perform private.pp_stock_entry(org,doc,d.destination_id,(line->>'item_id')::uuid,(line->>'quantity')::numeric,d.document_date);
 end loop;
 update public.stock_documents set state='POSTED',opening_recorded_directly=(d.state='REQUESTED' or d.opening_recorded_directly),completed_by=auth.uid(),completed_at=clock_timestamp(),decision_note=p_note where id=d.id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(org,'OPENING_VERIFIED_BY_ADMIN',auth.uid(),doc,jsonb_build_object('note',p_note,'requester',d.created_by,'centre',d.destination_id,'opening_date',d.document_date,'approval_required',false,'previous_state',d.state));
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(org,'STOCK_POST',auth.uid(),doc,jsonb_build_object('note',p_note,'administrator_opening',true));
 return d.id;
end $$;
revoke all on function private.pp_post_admin_opening(uuid,uuid,text) from public,anon,authenticated;
create function public.stock_document_action(p_organisation_id uuid,p_document_id uuid,p_action text,p_note text,p_received jsonb default null) returns uuid language plpgsql security definer set search_path='' as $$begin
 if p_action='POST' and private.pp_stock_role(p_organisation_id,'restaurant_admin',null) and exists(select 1 from public.stock_documents d where d.organisation_id=p_organisation_id and d.id=p_document_id and d.kind='OPENING' and(d.state in('REQUESTED','APPROVED') or d.opening_recorded_directly)) then return private.pp_post_admin_opening(p_organisation_id,p_document_id,p_note);end if;
 return private.pp_stock_action_before_admin_openings(p_organisation_id,p_document_id,p_action,p_note,p_received);
end $$;
revoke all on function public.stock_document_action(uuid,uuid,text,text,jsonb) from public,anon;
grant execute on function public.stock_document_action(uuid,uuid,text,text,jsonb) to authenticated;
create function public.record_admin_opening(p_organisation_id uuid,p_request_id uuid,p_document jsonb,p_lines jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare doc uuid:=gen_random_uuid();prior public.stock_documents;site uuid;day date;lines jsonb;digest text:=md5(jsonb_build_array(p_document,p_lines)::text);
begin
 if not private.pp_stock_role(p_organisation_id,'restaurant_admin',null) then raise exception 'Restaurant Administrator access is required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id and access_state='ACTIVE' for update;
 if not found then raise exception 'An active restaurant workspace is required.' using errcode='42501';end if;
 if p_document->>'kind' is distinct from 'OPENING' or p_request_id is null or octet_length(coalesce(p_document::text,''))>65536 then raise exception 'Choose a valid opening stock record.' using errcode='22023';end if;
 select * into prior from public.stock_documents where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then
  if prior.kind<>'OPENING' or prior.input_hash<>digest or prior.created_by<>auth.uid() then raise exception 'This entry was already used. Refresh before recording different quantities.' using errcode='22023';end if;
  return private.pp_post_admin_opening(p_organisation_id,prior.id,p_document->>'note');
 end if;
 begin site:=(p_document->>'destination_id')::uuid;day:=(p_document->>'date')::date;exception when others then raise exception 'Choose a valid centre and opening date.' using errcode='22023';end;
 if site is null or not exists(select 1 from public.stock_locations where organisation_id=p_organisation_id and id=site and is_active) then raise exception 'Choose an active centre in this restaurant.' using errcode='22023';end if;
 if day is null or day>(select(now() at time zone time_zone)::date from public.organisations where id=p_organisation_id) or length(trim(coalesce(p_document->>'note',''))) not between 1 and 1000 then raise exception 'Choose an opening date that is not in the future and enter its reference or reason.' using errcode='22023';end if;
 lines:=private.pp_stock_lines(p_organisation_id,p_lines);
 if exists(select 1 from jsonb_array_elements(lines) l where (l->>'quantity')::numeric<=0) then raise exception 'Opening quantities must be positive.' using errcode='22023';end if;
 insert into public.stock_documents(id,organisation_id,request_id,input_hash,reference,kind,destination_id,document_date,note,lines,created_by) values(doc,p_organisation_id,p_request_id,digest,'STK-'||upper(substr(replace(doc::text,'-',''),1,12)),'OPENING',site,day,trim(p_document->>'note'),lines,auth.uid());
 return private.pp_post_admin_opening(p_organisation_id,doc,p_document->>'note');
end $$;
create function public.record_imported_opening(p_organisation_id uuid,p_batch_id uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare b private.master_opening_batches;r record;lines jsonb;doc uuid;
begin
 if not private.pp_stock_role(p_organisation_id,'restaurant_admin',null) then raise exception 'Restaurant Administrator access is required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id and access_state='ACTIVE' for update;
 if not found then raise exception 'An active restaurant workspace is required.' using errcode='42501';end if;
 select * into b from private.master_opening_batches where organisation_id=p_organisation_id and id=p_batch_id for update;
 if b.id is null then raise exception 'Choose an imported opening in this restaurant.' using errcode='42501';end if;
 if b.completed then
  if b.document_id is null then return null;end if;
  return private.pp_post_admin_opening(p_organisation_id,b.document_id,'Physical opening quantities verified directly by the Restaurant Administrator.');
 end if;
 for r in select * from private.master_opening_items where organisation_id=p_organisation_id and batch_id=b.id and quantity=0 loop
  perform public.confirm_zero_opening(p_organisation_id,r.item_id,b.site_id,b.opening_date,'Zero opening verified by Restaurant Administrator from reviewed material import.');
 end loop;
 select jsonb_agg(jsonb_build_object('item_id',item_id,'quantity',quantity::text) order by item_id) into lines from private.master_opening_items where organisation_id=p_organisation_id and batch_id=b.id and quantity>0;
 if lines is not null then doc:=public.record_admin_opening(p_organisation_id,b.id,jsonb_build_object('kind','OPENING','destination_id',b.site_id,'date',b.opening_date,'note','Physical opening quantities verified directly by Restaurant Administrator from reviewed material import.'),lines);end if;
 update private.master_opening_batches set completed=true,document_id=doc where id=b.id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'IMPORTED_OPENING_RECORDED_BY_ADMIN',auth.uid(),b.id,jsonb_build_object('document',doc));return doc;
end $$;
revoke all on function public.record_admin_opening(uuid,uuid,jsonb,jsonb),public.record_imported_opening(uuid,uuid) from public,anon;
grant execute on function public.record_admin_opening(uuid,uuid,jsonb,jsonb),public.record_imported_opening(uuid,uuid) to authenticated;
alter function private.pp_stock_packet(uuid,uuid) rename to pp_stock_packet_before_admin_openings;
revoke all on function private.pp_stock_packet_before_admin_openings(uuid,uuid) from public,anon,authenticated;
create function private.pp_stock_packet(org uuid,doc uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare r jsonb;begin
 r:=private.pp_stock_packet_before_admin_openings(org,doc);
 if r is not null and r->>'kind'='OPENING' and r->>'state'='REQUESTED' and private.pp_stock_role(org,'restaurant_admin',null)  then
  r:=r||jsonb_build_object('admin_opening_entry',true,'actions',coalesce(r->'actions','{}')||jsonb_build_object('post',true));
 end if;return r;
end $$;
revoke all on function private.pp_stock_packet(uuid,uuid) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
