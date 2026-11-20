-- Full-period quantity reconciliation with clearly identified reference-value estimates.
begin;
create function private.pp_inventory_report_site(org uuid,site uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.pp_stock_read(org) and private.pp_stock_site(org,site,'read') and exists(select 1 from public.organisation_memberships m join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id where m.organisation_id=org and m.user_id=auth.uid() and m.status='active' and r.role_code in('restaurant_admin','ceo','finance','inventory_manager','inventory','operations','stock_department','kitchen_manager','bar_lead','stock_receiver','stock_dispatcher'));
$$;
create index if not exists stock_ledger_statement on public.stock_ledger(organisation_id,location_id,occurred_on,item_id,id);
create function public.inventory_movement_statement(p_organisation_id uuid,p_site_id uuid,p_from date,p_to date,p_item_id uuid default null,p_page integer default 1,p_export boolean default false,p_category text default '') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;financial boolean;today date;begin
 if not private.pp_inventory_report_site(p_organisation_id,p_site_id) then raise exception 'Stock statement access required at this centre.' using errcode='42501';end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 if p_from is null or p_to is null or p_from>p_to or p_to>today or p_to-p_from>366 or p_page is null or p_page not between 1 and 100000 or p_export is null or p_category is null or length(p_category)>60 then raise exception 'Choose a valid statement period of up to 367 days.' using errcode='22023';end if;
 financial:=private.pp_reference_price_read(p_organisation_id);
 with entries as materialized(select e.*,d.kind,d.reference from public.stock_ledger e join public.stock_documents d on d.organisation_id=e.organisation_id and d.id=e.document_id where e.organisation_id=p_organisation_id and e.location_id=p_site_id and e.occurred_on<=p_to and(p_item_id is null or e.item_id=p_item_id) and(p_category='' or exists(select 1 from public.items i where i.organisation_id=e.organisation_id and i.id=e.item_id and exists(select 1 from public.item_categories c where c.organisation_id=i.organisation_id and c.id=i.category_id and c.name=p_category)))),
 totals as materialized(select item_id,
 coalesce(sum(quantity) filter(where occurred_on<p_from),0) opening,
 coalesce(sum(quantity) filter(where occurred_on>=p_from and quantity>0 and kind<>'COUNT'),0) added,
 coalesce(-sum(quantity) filter(where occurred_on>=p_from and quantity<0 and kind<>'COUNT'),0) removed,
 coalesce(sum(quantity) filter(where occurred_on>=p_from and kind='COUNT'),0) adjusted,
 sum(quantity) closing,
 jsonb_build_object('opening_entries',coalesce(sum(quantity) filter(where occurred_on>=p_from and kind='OPENING'),0)::text,
 'receipts',coalesce(sum(quantity) filter(where occurred_on>=p_from and kind in('GRN','DIRECT_RECEIPT')),0)::text,
 'transfers_in',coalesce(sum(quantity) filter(where occurred_on>=p_from and kind in('TRANSFER','ISSUE') and quantity>0),0)::text,
 'transfers_out',coalesce(-sum(quantity) filter(where occurred_on>=p_from and kind in('TRANSFER','ISSUE') and quantity<0),0)::text,
 'production_output',coalesce(sum(quantity) filter(where occurred_on>=p_from and kind='PRODUCTION' and quantity>0),0)::text,
 'production_input',coalesce(-sum(quantity) filter(where occurred_on>=p_from and kind='PRODUCTION' and quantity<0),0)::text,
 'consumption',coalesce(-sum(quantity) filter(where occurred_on>=p_from and kind='CONSUMPTION' and quantity<0),0)::text,
 'waste',coalesce(-sum(quantity) filter(where occurred_on>=p_from and kind='WASTE' and quantity<0),0)::text) breakdown
 from entries group by item_id),
 priced as materialized(select t.*,i.name,i.code,u.code unit,case when financial then private.pp_effective_material_cost(p_organisation_id,i.id,p_to) else null end cost from totals t join public.items i on i.organisation_id=p_organisation_id and i.id=t.item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id),
 rows as materialized(select item_id,name,code,unit,opening::text,added::text,removed::text,adjusted::text,closing::text,breakdown,cost,
 case when financial and closing=0 then 0::numeric when financial and cost->>'unit_cost' is not null then closing*(cost->>'unit_cost')::numeric end estimated_value from priced),
 paged as(select * from rows order by name,item_id limit(case when p_export then 5001 when p_item_id is not null then 1 else 25 end) offset(case when p_export or p_item_id is not null then 0 else(p_page-1)*25 end)),
 detail as materialized(select id,document_id,reference,kind,occurred_on,created_at,quantity::text,((select coalesce(sum(quantity),0) from entries where occurred_on<p_from)+sum(quantity) over(order by occurred_on,id))::text running_balance from entries where occurred_on>=p_from and p_item_id is not null),
 detail_page as(select * from detail order by occurred_on,id limit(case when p_export then 5001 else 25 end) offset(case when p_export then 0 else(p_page-1)*25 end))
 select jsonb_build_object('centre',(select name from public.stock_locations where id=p_site_id),'restaurant',(select name from public.organisations where id=p_organisation_id),'currency',(select currency_code from public.organisations where id=p_organisation_id),
 'from',p_from,'through',p_to,'financial',financial,'generated_at',statement_timestamp(),'total',(select count(*) from rows),'detail_total',(select count(*) from detail),
 'known_estimated_value',case when financial then(select sum(estimated_value)::text from rows) end,'unpriced',case when financial then(select count(*) from rows where closing::numeric<>0 and estimated_value is null) end,
 'rows',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('estimated_value',p.estimated_value::text) order by name,item_id) from paged p),'[]'::jsonb),
 'entries',coalesce((select jsonb_agg(to_jsonb(p) order by occurred_on,id) from detail_page p),'[]'::jsonb)) into result;
 if p_export and((result->>'total')::integer>5000 or(result->>'detail_total')::integer>5000) then raise exception 'Narrow the export to at most 5,000 materials and movement entries.' using errcode='22023';end if;
 return result;
end $$;
create function public.inventory_report_options(p_organisation_id uuid,p_site_id uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.pp_stock_read(p_organisation_id) or(p_site_id is not null and not private.pp_inventory_report_site(p_organisation_id,p_site_id)) then raise exception 'Inventory report access required.' using errcode='42501';end if;
 return jsonb_build_object('centres',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.stock_locations where organisation_id=p_organisation_id and private.pp_inventory_report_site(p_organisation_id,id)),'[]'::jsonb),'items',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'code',code,'category',(select name from public.item_categories c where c.organisation_id=i.organisation_id and c.id=i.category_id)) order by name) from public.items i where i.organisation_id=p_organisation_id and exists(select 1 from public.stock_ledger e where e.organisation_id=i.organisation_id and e.item_id=i.id and e.location_id=p_site_id)),'[]'::jsonb));end $$;
revoke all on function public.inventory_report_options(uuid,uuid) from public,anon;
grant execute on function public.inventory_report_options(uuid,uuid) to authenticated;
revoke all on function public.inventory_movement_statement(uuid,uuid,date,date,uuid,integer,boolean,text) from public,anon;
revoke all on function private.pp_inventory_report_site(uuid,uuid) from public,anon,authenticated;
grant execute on function public.inventory_movement_statement(uuid,uuid,date,date,uuid,integer,boolean,text) to authenticated;
notify pgrst,'reload schema';
commit;
