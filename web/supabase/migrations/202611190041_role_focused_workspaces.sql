-- Role-focused setup access and complete, centre-filterable waste history.
begin;
alter function public.setup_workspace(uuid) rename to pp_setup_workspace_before_role_focus;
alter function public.pp_setup_workspace_before_role_focus(uuid) set schema private;
revoke all on function private.pp_setup_workspace_before_role_focus(uuid) from public,anon,authenticated;
create function public.setup_workspace(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not(private.pp_team_manage(p_organisation_id) or private.pp_stock_manager(p_organisation_id)) then raise exception 'Business or stock setup administration access required.' using errcode='42501';end if;
 return private.pp_setup_workspace_before_role_focus(p_organisation_id);
end $$;
revoke all on function public.setup_workspace(uuid) from public,anon;
grant execute on function public.setup_workspace(uuid) to authenticated;

create function public.centre_waste_report(p_organisation_id uuid,p_site_id uuid,p_from date,p_to date,p_kind text default 'WASTE',p_page integer default 1,p_state text default 'ALL',p_export boolean default false) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Waste report access required.' using errcode='42501';end if;
 if p_site_id is not null and not private.pp_waste_site(p_organisation_id,p_site_id) then raise exception 'Waste report is outside your permitted centres.' using errcode='42501';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>366 or p_kind is null or p_kind not in ('WASTE','LOSSES','PROCESSING') or p_page is null or p_page not between 1 and 100000 or p_state is null or p_state not in ('ALL','REQUESTED','APPROVED','POSTED','CANCELLED','REJECTED') or p_export is null then raise exception 'Choose valid dates within 367 days, source and status.' using errcode='22023';end if;
 with rows as materialized(
 select d.id,d.reference,d.document_date,d.state,s.id site_id,s.name site,i.id item_id,i.name material,u.code unit,w.quantity::text quantity,w.reason,true included_in_production,coalesce(nullif(m.display_name,''),a.email) submitter_name,a.email recorded_by
 from public.processing_waste w join public.stock_documents d on d.organisation_id=w.organisation_id and d.id=w.document_id join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id join public.items i on i.organisation_id=w.organisation_id and i.id=w.item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id left join auth.users a on a.id=d.created_by left join public.organisation_memberships m on m.organisation_id=d.organisation_id and m.user_id=d.created_by
 where p_kind in ('WASTE','PROCESSING') and d.organisation_id=p_organisation_id and d.document_date between p_from and p_to and(p_state='ALL' or d.state=p_state) and(p_site_id is null or d.source_id=p_site_id) and private.pp_stock_doc_read(p_organisation_id,d.id) and private.pp_waste_site(p_organisation_id,d.source_id)
 union all
 select d.id,d.reference,d.document_date,d.state,s.id,s.name,i.id,i.name,u.code,l->>'quantity',d.note,false,d.submitter_name,a.email
 from public.stock_documents d cross join lateral jsonb_array_elements(d.lines) l join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id join public.items i on i.organisation_id=d.organisation_id and i.id=(l->>'item_id')::uuid join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id left join auth.users a on a.id=d.created_by
 where p_kind in ('WASTE','LOSSES') and d.organisation_id=p_organisation_id and d.kind='WASTE' and d.document_date between p_from and p_to and(p_state='ALL' or d.state=p_state) and(p_site_id is null or d.source_id=p_site_id) and private.pp_stock_doc_read(p_organisation_id,d.id) and private.pp_waste_site(p_organisation_id,d.source_id)
 ),paged as(select * from rows order by document_date desc,id,item_id limit(case when p_export then 5001 else 10 end) offset(case when p_export then 0 else(p_page-1)*10 end))
 select jsonb_build_object('total',(select count(*) from rows),'processing_entries',(select count(*) from rows where included_in_production),'standalone_entries',(select count(*) from rows where not included_in_production),'posted_entries',(select count(*) from rows where state='POSTED'),'export',p_export,'generated_at',statement_timestamp(),'rows',coalesce((select jsonb_agg(to_jsonb(p) order by document_date desc,id,item_id) from paged p),'[]'::jsonb)) into result;
 if p_export and(result->>'total')::integer>5000 then raise exception 'This export exceeds 5,000 material entries. Narrow the dates or centre. No partial file was generated.' using errcode='22023';end if;
 return result;
end $$;
revoke all on function public.centre_waste_report(uuid,uuid,date,date,text,integer,text,boolean) from public,anon;
grant execute on function public.centre_waste_report(uuid,uuid,date,date,text,integer,text,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
