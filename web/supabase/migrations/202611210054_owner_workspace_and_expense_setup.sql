-- Current, scoped stock estimates and restaurant-owned expense categories.
begin;
create function private.pp_stock_value_site(org uuid,site uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.pp_inventory_report_site(org,site) and (
 private.pp_reference_price_read(org) or exists(
 select 1 from public.stock_locations s join public.organisation_memberships m on m.organisation_id=s.organisation_id and m.user_id=auth.uid() and m.status='active'
 where s.organisation_id=org and s.id=site and s.responsible_membership_id=m.id));
$$;
revoke all on function private.pp_stock_value_site(uuid,uuid) from public,anon,authenticated;
create function public.current_stock_value(p_organisation_id uuid,p_site_id uuid default null,p_outlet_id uuid default null,p_page integer default 1,p_export boolean default false) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;today date;begin
 if not private.pp_stock_read(p_organisation_id) or (p_site_id is not null and not private.pp_stock_value_site(p_organisation_id,p_site_id)) then raise exception 'Stock value access is required at this centre.' using errcode='42501';end if;
 if p_page is null or p_page not between 1 and 100000 or p_export is null or(p_outlet_id is not null and not exists(select 1 from public.stock_locations where organisation_id=p_organisation_id and outlet_id=p_outlet_id and private.pp_stock_value_site(p_organisation_id,id))) then raise exception 'Choose an available outlet and page.' using errcode='22023';end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 with sites as materialized(select s.id,s.name,s.outlet_id,s.is_active,private.pp_member_label(s.organisation_id,s.responsible_membership_id) owner,
 coalesce((select name from public.locations where organisation_id=s.organisation_id and id=s.outlet_id),'Central / shared') outlet
 from public.stock_locations s where s.organisation_id=p_organisation_id and private.pp_stock_value_site(p_organisation_id,s.id) and(p_site_id is null or s.id=p_site_id) and(p_outlet_id is null or s.outlet_id=p_outlet_id)),
 balances as materialized(select e.location_id site_id,e.item_id,sum(e.quantity) quantity from public.stock_ledger e join sites s on s.id=e.location_id where e.organisation_id=p_organisation_id group by e.location_id,e.item_id having sum(e.quantity)<>0),
 costs as materialized(select distinct b.item_id,private.pp_effective_material_cost(p_organisation_id,b.item_id,today) cost from(select distinct item_id from balances)b),
 valued as materialized(select b.*,i.code,i.name,u.code unit,c.cost,private.pp_stock_reserved(p_organisation_id,b.site_id,b.item_id) reserved,
 case when c.cost->>'unit_cost' is not null then b.quantity*(c.cost->>'unit_cost')::numeric end value
 from balances b join costs c on c.item_id=b.item_id join public.items i on i.organisation_id=p_organisation_id and i.id=b.item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id),
 centres as materialized(select s.*,count(v.item_id) materials,count(v.item_id) filter(where v.value is not null) priced,count(v.item_id) filter(where v.value is null) unpriced,coalesce(sum(v.value),0) known_value from sites s left join valued v on v.site_id=s.id group by s.id,s.name,s.outlet_id,s.is_active,s.owner,s.outlet),
 paged as(select * from valued where p_site_id is not null order by name,item_id limit(case when p_export then 5001 else 25 end) offset(case when p_export then 0 else(p_page-1)*25 end))
 select jsonb_build_object('as_of',statement_timestamp(),'business_date',today,'currency',(select currency_code from public.organisations where id=p_organisation_id),'financial',private.pp_reference_price_read(p_organisation_id),
 'known_value',coalesce((select sum(known_value)::text from centres),'0'),'unpriced',coalesce((select sum(unpriced) from centres),0),'materials',(select count(*) from valued),'centre_count',(select count(*) from sites),
 'centres',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'outlet_id',outlet_id,'outlet',outlet,'active',is_active,'owner',owner,'known_value',known_value::text,'materials',materials,'priced',priced,'unpriced',unpriced) order by known_value desc,name) from centres),'[]'),
 'rows',coalesce((select jsonb_agg(jsonb_build_object('item_id',item_id,'code',code,'name',name,'unit',unit,'quantity',quantity::text,'reserved',reserved::text,'available',(quantity-reserved)::text,'unit_cost',cost->>'unit_cost','basis',cost->>'basis','estimated_value',value::text) order by name,item_id) from paged),'[]')) into result;
 if p_export and(result->>'materials')::integer>5000 and p_site_id is not null then raise exception 'Narrow the export to fewer than 5,001 held materials.' using errcode='22023';end if;
 return result;
end $$;
revoke all on function public.current_stock_value(uuid,uuid,uuid,integer,boolean) from public,anon;
grant execute on function public.current_stock_value(uuid,uuid,uuid,integer,boolean) to authenticated;

-- Current menu exceptions include unsold items, rather than depending on sales imports.
create function public.owner_menu_attention(p_organisation_id uuid,p_outlet_id uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$declare site record;packet jsonb;day date;risk integer:=0;incomplete integer:=0;missing integer:=0;sites integer:=0;scopes jsonb:='[]';begin
 if not private.pp_sales_read(p_organisation_id) then raise exception 'Executive financial access required.' using errcode='42501';end if;
 select(now() at time zone time_zone)::date into day from public.organisations where id=p_organisation_id;
 if p_outlet_id is not null and not exists(select 1 from public.locations where organisation_id=p_organisation_id and id=p_outlet_id and is_active) then raise exception 'Choose an active outlet.' using errcode='22023';end if;
 for site in select id,name from public.locations where organisation_id=p_organisation_id and is_active and(p_outlet_id is null or id=p_outlet_id) loop
  packet:=public.selling_menu_profitability(p_organisation_id,site.id,'STANDARD',day,'',1,'ALL','ALL','');
  risk:=risk+coalesce((packet->'summary'->>'at_risk')::integer,0);incomplete:=incomplete+coalesce((packet->'summary'->>'incomplete')::integer,0);missing:=missing+coalesce((packet->'summary'->>'target_not_set')::integer,0);sites:=sites+1;scopes:=scopes||jsonb_build_array(jsonb_build_object('id',site.id,'name',site.name,'at_risk',packet->'summary'->'at_risk','incomplete',packet->'summary'->'incomplete','targets_missing',packet->'summary'->'target_not_set'));
 end loop;
 return jsonb_build_object('as_of',day,'at_risk',risk,'incomplete',incomplete,'targets_missing',missing,'outlets',sites,'scopes',scopes);
end $$;
revoke all on function public.owner_menu_attention(uuid,uuid) from public,anon;
grant execute on function public.owner_menu_attention(uuid,uuid) to authenticated;

create function private.pp_check_expense_categories(rows jsonb) returns void language plpgsql set search_path='' as $$begin
 if rows is null or jsonb_typeof(rows) is distinct from 'array' or jsonb_array_length(rows)>100 or octet_length(rows::text)>32768 then raise exception 'Use up to 100 expense categories.' using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(rows) r where jsonb_typeof(r) is distinct from 'object' or coalesce(r->>'code','')!~'^[A-Z0-9][A-Z0-9_-]{0,39}$' or length(trim(coalesce(r->>'name',''))) not between 1 and 90 or coalesce(r->>'kind','') not in('LABOUR','OPERATING') or jsonb_typeof(r->'is_active') is distinct from 'boolean' or(r->>'name')~'[[:cntrl:]]') then raise exception 'Check each category name, code, type and active status.' using errcode='22023';end if;
 if(select count(*)<>count(distinct value->>'code') from jsonb_array_elements(rows)) or(select count(*)<>count(distinct (value->>'kind',lower(trim(value->>'name')))) from jsonb_array_elements(rows)) then raise exception 'Use unique category codes and names within each expense type.' using errcode='22023';end if;
end $$;
revoke all on function private.pp_check_expense_categories(jsonb) from public,anon,authenticated;
create function public.expense_category_setup(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Restaurant administrator access required.' using errcode='42501';end if;
 return jsonb_build_object('categories',public.list_expense_categories(p_organisation_id),'evidence',(select md5(coalesce(jsonb_agg(to_jsonb(c) order by code)::text,'[]')) from public.management_expense_categories c where organisation_id=p_organisation_id));
end $$;
create function public.save_expense_categories(p_organisation_id uuid,p_evidence text,p_categories jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare r jsonb;begin
 perform 1 from public.organisations where id=p_organisation_id for update;
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Restaurant administrator access required.' using errcode='42501';end if;
 if p_evidence is distinct from(public.expense_category_setup(p_organisation_id)->>'evidence') then raise exception 'Categories changed. Refresh before saving.' using errcode='22023';end if;
 perform private.pp_check_expense_categories(p_categories);
 if exists(select 1 from jsonb_array_elements(p_categories) candidate join public.management_expense_categories c on c.organisation_id=p_organisation_id and c.code=candidate->>'code' where c.kind<>candidate->>'kind') then raise exception 'An existing category reporting type cannot change.' using errcode='22023';end if;
 if(select count(*) from(select code from public.management_expense_categories where organisation_id=p_organisation_id union select value->>'code' from jsonb_array_elements(p_categories))q)>100 then raise exception 'Use at most 100 expense categories, including inactive history.' using errcode='22023';end if;
 update public.management_expense_categories set is_active=false where organisation_id=p_organisation_id;
 for r in select value from jsonb_array_elements(p_categories) loop
  insert into public.management_expense_categories(organisation_id,code,name,kind,is_active,created_by) values(p_organisation_id,r->>'code',trim(r->>'name'),r->>'kind',(r->>'is_active')::boolean,auth.uid()) on conflict(organisation_id,code) do update set name=excluded.name,is_active=excluded.is_active;
 end loop;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'EXPENSE_CATEGORIES_UPDATED',auth.uid(),p_organisation_id,jsonb_build_object('categories',p_categories));
 return public.expense_category_setup(p_organisation_id);
end $$;
alter table public.restaurant_setup_drafts add column expense_categories jsonb not null default '[]';
create function public.save_setup_expense_categories(p_categories jsonb) returns void language plpgsql security definer set search_path='' as $$begin
 if auth.uid() is null then raise exception 'Sign in first.' using errcode='42501';end if;
 perform private.pp_check_expense_categories(p_categories);
 update public.restaurant_setup_drafts set expense_categories=p_categories where user_id=auth.uid() and completed_organisation_id is null;
 if not found and not exists(select 1 from public.restaurant_setup_drafts where user_id=auth.uid() and completed_organisation_id is not null) then raise exception 'Save business details first.' using errcode='22023';end if;
end $$;
create function public.complete_restaurant_setup_with_expenses() returns uuid language plpgsql security definer set search_path='' as $$declare draft public.restaurant_setup_drafts;org uuid;r jsonb;begin
 select * into draft from public.restaurant_setup_drafts where user_id=auth.uid() for update;
 if draft.user_id is null then raise exception 'Save setup details first.' using errcode='22023';end if;
 if draft.completed_organisation_id is not null then return draft.completed_organisation_id;end if;
 perform private.pp_check_expense_categories(draft.expense_categories);
 org:=public.complete_restaurant_setup_with_categories();
 -- Preserve seeded labour categories; replace optional operating defaults only when chosen.
 if jsonb_array_length(draft.expense_categories)>0 then
  update public.management_expense_categories set is_active=false where organisation_id=org and kind='OPERATING';
  for r in select value from jsonb_array_elements(draft.expense_categories) loop
   if exists(select 1 from public.management_expense_categories where organisation_id=org and code=r->>'code' and kind<>r->>'kind') then raise exception 'Category code conflicts with an existing expense type.' using errcode='22023';end if;
   insert into public.management_expense_categories(organisation_id,code,name,kind,is_active,created_by) values(org,r->>'code',trim(r->>'name'),r->>'kind',(r->>'is_active')::boolean,auth.uid()) on conflict(organisation_id,code) do update set name=excluded.name,is_active=excluded.is_active;
  end loop;
 end if;
 return org;
end $$;
do $$declare f record;begin for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in('expense_category_setup','save_expense_categories','save_setup_expense_categories','complete_restaurant_setup_with_expenses') loop execute 'revoke all on function '||f.signature||' from public,anon';execute 'grant execute on function '||f.signature||' to authenticated';end loop;end $$;
notify pgrst,'reload schema';
commit;
