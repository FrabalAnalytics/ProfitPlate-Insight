-- Operations oversight is separate from stock transactions and Finance administration.
-- Apply after 054. Existing role IDs, assignments and transaction histories are preserved.
begin;
update public.roles set name='Operations Manager' where code='operations';
create function private.pp_operations(org uuid,outlet uuid default null) returns boolean language sql stable security definer set search_path='' as $$
 select private.pp_stock_role(org,'operations',outlet);
$$;
create function private.pp_operations_any(org uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisation_memberships m join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id where m.organisation_id=org and m.user_id=auth.uid() and m.status='active' and r.role_code='operations');
$$;
create function private.pp_operations_site(org uuid,site uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.stock_locations s where s.organisation_id=org and s.id=site and private.pp_operations(org,s.outlet_id) and private.pp_stock_assignment(org,s.id,'read'));
$$;
-- Read-only business financial visibility. These helpers never grant posting or configuration.
create or replace function private.pp_reference_price_read(target_org uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisation_memberships m join public.membership_roles r
 on r.organisation_id=m.organisation_id and r.membership_id=m.id
 where m.organisation_id=target_org and m.user_id=(select auth.uid()) and m.status='active'
 and r.location_id is null and r.role_code in ('ceo','finance','procurement','restaurant_admin','operations'));
$$;
create or replace function private.pp_sales_read(target_org uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisation_memberships m join public.membership_roles r
 on r.organisation_id=m.organisation_id and r.membership_id=m.id
 where m.organisation_id=target_org and m.user_id=(select auth.uid()) and m.status='active'
 and r.location_id is null and r.role_code in ('restaurant_admin','ceo','finance','operations'));
$$;
-- Centre-specific Operations assignments narrow read access too; never infer transaction powers.
alter function private.pp_stock_site(uuid,uuid,text) rename to pp_stock_site_before_operations;
create function private.pp_stock_site(org uuid,site uuid,mode text) returns boolean language sql stable security definer set search_path='' as $$
 select (mode in('dispatch','receive') and private.pp_operations_site(org,site) and exists(select 1 from public.stock_member_access a join public.organisation_memberships m on m.organisation_id=a.organisation_id and m.id=a.membership_id where a.organisation_id=org and m.user_id=auth.uid() and m.status='active' and a.mode='ASSIGNED') and private.pp_stock_assignment(org,site,mode)) or case when mode='read' then private.pp_stock_site_before_operations(org,site,mode) or private.pp_operations_site(org,site)
 else private.pp_stock_site_before_operations(org,site,mode) and (
 not private.pp_operations_any(org) or mode not in('request','approve') or
 exists(select 1 from public.stock_member_access a join public.organisation_memberships m on m.organisation_id=a.organisation_id and m.id=a.membership_id where a.organisation_id=org and m.user_id=auth.uid() and m.status='active' and a.mode='ASSIGNED') or
 private.pp_stock_manager(org) or exists(select 1 from public.stock_locations s where s.organisation_id=org and s.id=site and(private.pp_stock_role(org,'inventory',s.outlet_id) or private.pp_stock_process(org,site,'stock_department',mode)))) end;
$$;
alter function private.pp_waste_site(uuid,uuid) rename to pp_waste_site_before_operations;
create function private.pp_waste_site(org uuid,site uuid) returns boolean language sql stable security definer set search_path='' as $$select private.pp_waste_site_before_operations(org,site) or private.pp_operations_site(org,site);$$;
alter function private.pp_stock_value_site(uuid,uuid) rename to pp_stock_value_site_before_operations;
create function private.pp_stock_value_site(org uuid,site uuid) returns boolean language sql stable security definer set search_path='' as $$select private.pp_stock_value_site_before_operations(org,site) or private.pp_operations_site(org,site);$$;
-- A scoped manager can compare their outlet's menus without obtaining all invoice data.
create function private.pp_operations_menu_scope(org uuid,outlet uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.pp_reference_price_read(org) or (outlet is not null and private.pp_operations(org,outlet));
$$;

create or replace function public.recipe_reference_cost_estimate(p_organisation_id uuid,p_version_id uuid,p_as_of date,p_output_quantity numeric) returns jsonb
language plpgsql stable security definer set search_path='' as $$begin
 if not (private.pp_reference_price_read(p_organisation_id) or private.pp_operations_any(p_organisation_id)) then raise exception 'Financial estimate access denied.' using errcode='42501';end if;
 return private.pp_recipe_cost(p_organisation_id,p_version_id,p_as_of,p_output_quantity,array[]::uuid[]);
end $$;

create or replace function public.menu_food_margin_estimate(p_organisation_id uuid,p_version_id uuid,p_location_id uuid,p_channel text,p_as_of date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare version_row public.menu_item_versions%rowtype; root public.menu_items%rowtype; price_row public.menu_price_versions%rowtype;
 currency text; recipe_estimate jsonb; price_issue text; net numeric; tax numeric; customer_total numeric; cost numeric; margin numeric;
begin
 if not private.pp_operations_menu_scope(p_organisation_id,p_location_id) then raise exception 'Menu financial access denied.' using errcode='42501'; end if;
 select * into version_row from public.menu_item_versions where organisation_id=p_organisation_id and id=p_version_id;
 if not found then raise exception 'Menu version unavailable.' using errcode='42501'; end if;
 select * into root from public.menu_items where organisation_id=p_organisation_id and id=version_row.menu_item_id;
 if not root.is_active then raise exception 'Reactivate the menu item to preview its current food margin.' using errcode='22023'; end if;
 select currency_code into currency from public.organisations where id=p_organisation_id;
 if p_as_of is null or p_as_of<version_row.effective_from or p_as_of>(select (now() at time zone time_zone)::date from public.organisations where id=p_organisation_id)
  then raise exception 'Choose a business date on or after this menu version starts, and not in the future.' using errcode='22023'; end if;
 if p_channel is null or not private.pp_sales_channel_exists(p_organisation_id,p_channel,true) then raise exception 'Choose a valid sales channel.' using errcode='22023'; end if;
 perform 1 from public.locations where organisation_id=p_organisation_id and id=p_location_id and is_active and brand_id=root.brand_id and(root.location_id is null or id=root.location_id);
 if not found then raise exception 'Choose an active location belonging to the menu brand.' using errcode='22023'; end if;
 recipe_estimate:=public.recipe_reference_cost_estimate(p_organisation_id,version_row.recipe_version_id,p_as_of,version_row.recipe_quantity);
 select * into price_row from public.menu_price_versions where organisation_id=p_organisation_id and menu_item_id=root.id
  and location_id=p_location_id and channel_code=p_channel and effective_from<=p_as_of order by effective_from desc,version desc limit 1;
 if not found then price_issue:='MISSING_SELLING_PRICE';
 elsif price_row.currency_code<>currency then price_issue:='PRICE_CURRENCY_MISMATCH';
 elsif price_row.effective_to is not null and p_as_of>price_row.effective_to then price_issue:='EXPIRED_SELLING_PRICE';
 else
  net:=round(case when price_row.tax_setting='INCLUSIVE' then price_row.price/(1+price_row.tax_percent/100) else price_row.price end,12);
  customer_total:=round(case when price_row.tax_setting='EXCLUSIVE' then price_row.price*(1+price_row.tax_percent/100) else price_row.price end,12);
  tax:=customer_total-net;
  if net<=0 then raise exception 'The net selling amount exceeds supported precision.' using errcode='22023'; end if;
 end if;
 cost:=(recipe_estimate->>'target_cost')::numeric;
 if price_issue is null and cost is not null then margin:=net-cost; end if;
 return jsonb_build_object('cost_state',case when margin is null then 'MISSING' else 'ESTIMATED' end,
  'method','MENU_REFERENCE_MARGIN_V1','as_of',p_as_of,'currency_code',currency,'recipe_estimate',recipe_estimate,
  'price_issue',price_issue,'price',case when price_row.id is null then null else jsonb_build_object('id',price_row.id,'version',price_row.version,
   'amount',price_row.price::text,'tax_setting',price_row.tax_setting,'tax_percent',price_row.tax_percent::text,'effective_from',price_row.effective_from,'effective_to',price_row.effective_to) end,
  'net_revenue',net::text,'tax_amount',tax::text,'customer_total',customer_total::text,'estimated_food_cost',cost::text,
  'estimated_food_margin',margin::text,'food_cost_percent',case when margin is not null then round(cost/net*100,6)::text else null end,
  'food_margin_percent',case when margin is not null then round(margin/net*100,6)::text else null end);
end; $$;

create or replace function public.menu_margin_for_scope(p_organisation_id uuid,p_version_id uuid,p_location_id uuid,p_channel text,p_as_of date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare chosen text; signatures integer;root uuid;result jsonb;begin
 if not private.pp_operations_menu_scope(p_organisation_id,p_location_id) then raise exception 'Menu financial access denied.' using errcode='42501';end if;
 if not private.pp_sales_channel_exists(p_organisation_id,p_channel,true) then raise exception 'Choose a valid sales channel.' using errcode='22023';end if;
 select menu_item_id into root from public.menu_item_versions where organisation_id=p_organisation_id and id=p_version_id;
 -- An explicit channel override wins; otherwise use the standard price.
 select channel_code into chosen from public.menu_price_versions where organisation_id=p_organisation_id and menu_item_id=root and location_id=p_location_id and channel_code=p_channel and effective_from<=p_as_of order by effective_from desc,version desc limit 1;
 if chosen is null and p_channel<>'STANDARD' then
  select channel_code into chosen from public.menu_price_versions where organisation_id=p_organisation_id and menu_item_id=root and location_id=p_location_id and channel_code='STANDARD' and effective_from<=p_as_of order by effective_from desc,version desc limit 1;
 end if;
 -- Legacy records: show the sole consistent usable price, never average conflicting prices.
 if chosen is null and p_channel='STANDARD' then
  with latest as(select distinct on(p.channel_code) p.* from public.menu_price_versions p join public.restaurant_sales_channels c on c.organisation_id=p.organisation_id and c.code=p.channel_code and c.is_active where p.organisation_id=p_organisation_id and p.menu_item_id=root and p.location_id=p_location_id and p.effective_from<=p_as_of order by p.channel_code,p.effective_from desc,p.version desc)
  select count(distinct(price,tax_setting,tax_percent)),min(channel_code) into signatures,chosen from latest where effective_to is null or effective_to>=p_as_of;
  if signatures>1 then chosen:=null;end if;
 end if;
 result:=public.menu_food_margin_estimate(p_organisation_id,p_version_id,p_location_id,coalesce(chosen,p_channel),p_as_of);
 if coalesce(signatures,0)>1 then result:=result||jsonb_build_object('price_issue','CHANNEL_PRICES_DIFFER','cost_state','MISSING');end if;
 return result||jsonb_build_object('price_channel',chosen,'price_basis',case when coalesce(signatures,0)>1 then 'CHOOSE_CHANNEL' when chosen='STANDARD' then 'STANDARD' when p_channel='STANDARD' and chosen is not null then 'LEGACY' else 'CHANNEL' end);
end $$;

create or replace function public.selling_menu_profitability(p_organisation_id uuid,p_location_id uuid,p_channel text,p_as_of date,p_search text,p_page integer,p_status text default 'ALL',p_major text default 'ALL',p_subcategory text default '')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare outlet public.locations; currency text; business_day date; result jsonb; eligible_count integer;
begin
 if not private.pp_operations_menu_scope(p_organisation_id,p_location_id) then
  raise exception 'Menu financial access denied.' using errcode='42501'; end if;
 select * into outlet from public.locations where organisation_id=p_organisation_id and id=p_location_id and is_active;
 if not found then raise exception 'Choose an active outlet in this business.' using errcode='22023'; end if;
 select currency_code,(now() at time zone time_zone)::date into currency,business_day
 from public.organisations where id=p_organisation_id;
 if p_as_of is null or p_as_of>business_day or p_channel is null or not private.pp_sales_channel_exists(p_organisation_id,p_channel,true)
  or p_page is null or p_page not between 1 and 100000 or p_search is null or length(p_search)>80 then
  raise exception 'Choose a valid date, channel, menu search and page. Future dates are unavailable.' using errcode='22023'; end if;
 if p_status is null or p_status not in ('ALL','AT_RISK','WITHIN_TARGET','INCOMPLETE','TARGET_NOT_SET') then raise exception 'Choose a valid menu status.' using errcode='22023';end if;
 if p_major is null or p_major not in('ALL','FOOD','DRINK','UNCLASSIFIED') or p_subcategory is null or length(p_subcategory)>60 then raise exception 'Choose a valid category.' using errcode='22023';end if;
 select count(*) into eligible_count from public.menu_items m left join lateral(select v.name from public.menu_item_versions v where v.organisation_id=m.organisation_id and v.menu_item_id=m.id and v.effective_from<=p_as_of order by v.effective_from desc,v.version desc limit 1)v on true
 where m.organisation_id=p_organisation_id and m.is_active and m.brand_id=outlet.brand_id and(m.location_id is null or m.location_id=p_location_id)
 and(p_major='ALL' or m.primary_category=p_major or(p_major='UNCLASSIFIED' and coalesce(m.primary_category,'') not in('FOOD','DRINK'))) and(p_subcategory='' or lower(m.subcategory)=lower(p_subcategory)) and(trim(p_search)='' or position(lower(trim(p_search)) in lower(coalesce(v.name,m.name)||' '||m.code))>0);
 if eligible_count>5000 then
  raise exception 'Narrow the menu search or category to compare up to 5,000 selling items.' using errcode='22023';end if;
 with eligible as materialized (
  select m.id,m.code,p_channel channel_code,m.primary_category,m.subcategory,private.pp_cost_target(p_organisation_id,p_location_id,m.primary_category) target,coalesce(v.name,m.name) as name,v.id as version_id,v.version,v.recipe_quantity,v.effective_from
  from public.menu_items m
  left join lateral (
   select id,name,version,recipe_quantity,effective_from from public.menu_item_versions
   where organisation_id=p_organisation_id and menu_item_id=m.id and effective_from<=p_as_of
   order by effective_from desc,version desc limit 1
  ) v on true
  where m.organisation_id=p_organisation_id and m.is_active and m.brand_id=outlet.brand_id and(m.location_id is null or m.location_id=p_location_id)
  and(p_major='ALL' or m.primary_category=p_major or(p_major='UNCLASSIFIED' and coalesce(m.primary_category,'') not in('FOOD','DRINK'))) and(p_subcategory='' or lower(m.subcategory)=lower(p_subcategory)) and (trim(p_search)='' or position(lower(trim(p_search)) in lower(coalesce(v.name,m.name)||' '||m.code))>0)
 ), estimates as materialized (
  select e.*,case when version_id is null then null else public.menu_margin_for_scope(p_organisation_id,version_id,p_location_id,e.channel_code,p_as_of) end estimate from eligible e
 ), scored as materialized (
  select e.*,case
   when estimate is null or estimate->>'cost_state'<>'ESTIMATED' or estimate->>'food_cost_percent' is null then 'INCOMPLETE'
   when (estimate->>'estimated_food_margin')::numeric<0 then 'LOSS'
   when target is null then 'TARGET_NOT_SET'
   when (estimate->>'food_cost_percent')::numeric>target then 'ABOVE_TARGET'
   else 'WITHIN_TARGET' end target_state,
   case when target is not null then (estimate->>'food_cost_percent')::numeric-target end target_gap_pp
  from estimates e
 ), matching as materialized (
  select * from scored where p_status='ALL' or(p_status='AT_RISK' and target_state in ('LOSS','ABOVE_TARGET')) or target_state=p_status
 ), paged as (
  select * from matching order by case target_state when 'LOSS' then 0 when 'ABOVE_TARGET' then 1 when 'INCOMPLETE' then 2 when 'TARGET_NOT_SET' then 3 else 4 end,
   target_gap_pp desc nulls last,name,id,channel_code limit 25 offset(p_page-1)*25
 )
 select jsonb_build_object('total',(select count(*) from matching),'currency_code',currency,
  'unassigned_menu_count',(select count(*) from public.menu_items where organisation_id=p_organisation_id and is_active and brand_id is null),
  'summary',(select jsonb_build_object('total',count(*),'at_risk',count(*) filter(where target_state in ('LOSS','ABOVE_TARGET')),
   'within_target',count(*) filter(where target_state='WITHIN_TARGET'),'incomplete',count(*) filter(where target_state='INCOMPLETE'),
   'target_not_set',count(*) filter(where target_state='TARGET_NOT_SET')) from scored),
  'rows',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('target',p.target::text,'target_gap_pp',p.target_gap_pp::text,'recipe_quantity',p.recipe_quantity::text) order by case target_state when 'LOSS' then 0 when 'ABOVE_TARGET' then 1 when 'INCOMPLETE' then 2 when 'TARGET_NOT_SET' then 3 else 4 end,
   target_gap_pp desc nulls last,name,id,channel_code) from paged p),'[]'::jsonb)) into result;
 return result;
end; $$;

create or replace function public.weekly_count_detail(p_organisation_id uuid,p_count_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare c private.weekly_counts;financial boolean;begin
 select * into c from private.weekly_counts where organisation_id=p_organisation_id and id=p_count_id;
 if c.id is null or not private.pp_inventory_report_site(p_organisation_id,c.site_id) then raise exception 'This weekly count is outside your access.' using errcode='42501';end if;
 financial:=private.pp_reference_price_read(p_organisation_id);
 return(to_jsonb(c)-'ledger_watermark')||jsonb_build_object('centre',(select name from public.stock_locations where id=c.site_id),'financial',financial,'currency',(select currency_code from public.organisations where id=p_organisation_id),'can_record',private.pp_weekly_write(p_organisation_id,c.site_id),'can_review',(private.pp_stock_manager(p_organisation_id) or (private.pp_stock_role(p_organisation_id,'finance',(select outlet_id from public.stock_locations where id=c.site_id)) or private.pp_operations_site(p_organisation_id,c.site_id))) and c.submitted_by is distinct from auth.uid(),'can_post',private.pp_stock_site(p_organisation_id,c.site_id,'inventory'),
 'stale',exists(select 1 from public.stock_ledger where organisation_id=p_organisation_id and location_id=c.site_id and id>c.ledger_watermark and occurred_on<c.count_date),
 'lines',coalesce((select jsonb_agg(jsonb_build_object('item_id',item_id,'name',name,'code',code,'unit',unit,'book',book::text,'physical',physical::text,'variance',(physical-book)::text,'variance_percent',case when book<>0 then(100*(physical-book)/abs(book))::text end,'note',note,'unit_cost',case when financial then unit_cost::text end,'estimated_variance_value',case when financial then((physical-book)*unit_cost)::text end,'price_basis',case when financial then price_basis end) order by name,item_id) from private.weekly_count_lines where count_id=c.id),'[]'::jsonb));
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

create function public.operations_access(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.pp_operations_any(p_organisation_id) then raise exception 'Operations Manager access required.' using errcode='42501';end if;
 return jsonb_build_object('business_wide',private.pp_operations(p_organisation_id),'outlets',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'name',l.name) order by l.name,l.id) from public.locations l where l.organisation_id=p_organisation_id and l.is_active and private.pp_operations(p_organisation_id,l.id)),'[]'::jsonb));
end $$;
create function public.operations_workspace(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;today date;begin
 if not private.pp_operations_any(p_organisation_id) then raise exception 'Operations Manager access required.' using errcode='42501';end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 with docs as materialized(select d.*,s.name source_name,t.name destination_name from public.stock_documents d left join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id left join public.stock_locations t on t.organisation_id=d.organisation_id and t.id=d.destination_id where d.organisation_id=p_organisation_id and (private.pp_operations_site(p_organisation_id,d.source_id) or private.pp_operations_site(p_organisation_id,d.destination_id))),
 tasks as materialized(
 select d.id,d.reference,'Material requests awaiting processing' task,d.state,d.document_date date,coalesce(d.approved_at,d.created_at) since,concat_ws(' / ',d.source_name,d.destination_name) centre,'/workspace/inventory' path,jsonb_build_object('view','movements','document',d.id) params from docs d where d.kind in('TRANSFER','ISSUE','RETURN') and d.state in('REQUESTED','APPROVED')
 union all select d.id,d.reference,'Transfers awaiting confirmation',d.state,d.document_date,d.dispatched_at,concat_ws(' / ',d.source_name,d.destination_name),'/workspace/inventory',jsonb_build_object('view','movements','document',d.id) from docs d where d.state in('DISPATCHED','PARTIAL','REJECTED') and d.resolved_at is null
 union all select d.id,d.reference,'Processing outside yield tolerance',d.state,d.document_date,d.completed_at,d.source_name,'/workspace/inventory/processing',jsonb_build_object('batch',d.id,'site',d.source_id,'from',d.document_date,'to',d.document_date) from docs d where d.kind='PRODUCTION' and d.state='POSTED' and d.document_date>=today-6 and coalesce((d.output->>'outside_tolerance')::boolean,false)
 union all select o.id,o.reference,'Outstanding purchase orders',o.status,o.document_date,coalesce(o.issued_at,o.created_at),o.payload->'header'->>'location_name','/workspace/records',jsonb_build_object('type','PO','q',o.reference,'from',o.document_date,'to',today) from public.purchase_orders o where o.organisation_id=p_organisation_id and o.status='ISSUED' and private.pp_operations(p_organisation_id,o.location_id) and exists(select 1 from public.purchase_order_lines l where l.organisation_id=o.organisation_id and l.order_id=o.id and l.quantity>coalesce((select sum(r.accepted) from public.goods_receipt_lines r where r.organisation_id=o.organisation_id and r.order_line_id=l.id and not private.pp_receipt_voided(o.organisation_id,r.receipt_id)),0))
 ), groups as(select task,count(*) count,count(*) filter(where since<statement_timestamp()-interval '24 hours') overdue from tasks group by task),paged as(select * from tasks order by since nulls last,id limit 12)
 select jsonb_build_object('today',today,'refreshed_at',statement_timestamp(),'queues',coalesce((select jsonb_agg(to_jsonb(g) order by count desc,task) from groups g),'[]'::jsonb),'rows',coalesce((select jsonb_agg(to_jsonb(p) order by since nulls last,id) from paged p),'[]'::jsonb)) into result;return result;
end $$;

alter function private.pp_order_read(uuid,uuid) rename to pp_order_read_before_operations;
create function private.pp_order_read(target_org uuid,target_order uuid) returns boolean language sql stable security definer set search_path='' as $$select private.pp_order_read_before_operations(target_org,target_order) or exists(select 1 from public.purchase_orders o where o.organisation_id=target_org and o.id=target_order and private.pp_operations(target_org,o.location_id));$$;
alter function private.pp_operational_types(uuid) rename to pp_operational_types_before_operations;
create function private.pp_operational_types(org uuid) returns text[] language sql stable security definer set search_path='' as $$select case when private.pp_operations_any(org) then array(select distinct t from unnest(private.pp_operational_types_before_operations(org)||array['PO','GRN'])t order by t) else private.pp_operational_types_before_operations(org) end;$$;
-- Retain the centre-owned waste restrictions installed after the original report function.
do $$declare definition text;updated text;begin
 definition:=pg_get_functiondef('public.operational_report_options(uuid,text)'::regprocedure);
 updated:=replace(definition,'private.pp_inventory_access(p_organisation_id,l.id)','(private.pp_inventory_access(p_organisation_id,l.id) or private.pp_operations(p_organisation_id,l.id))');
 if updated=definition then raise exception 'Expected purchasing scope guard missing.';end if;
 execute updated;
end $$;

create or replace function public.menu_access(p_organisation_id uuid) returns jsonb language sql stable security definer set search_path='' as $$select jsonb_build_object('read',private.pp_reference_price_read(p_organisation_id) or private.pp_operations_any(p_organisation_id),'write',private.pp_menu_write(p_organisation_id),'scoped_operations',private.pp_operations_any(p_organisation_id) and not private.pp_reference_price_read(p_organisation_id));$$;
revoke all on function private.pp_order_read_before_operations(uuid,uuid),private.pp_order_read(uuid,uuid),private.pp_operational_types_before_operations(uuid),private.pp_operational_types(uuid) from public,anon,authenticated;

alter function public.workspace_navigation_access(uuid) rename to pp_workspace_navigation_before_operations;
alter function public.pp_workspace_navigation_before_operations(uuid) set schema private;
revoke all on function private.pp_workspace_navigation_before_operations(uuid) from public,anon,authenticated;
create function public.workspace_navigation_access(p_organisation_id uuid) returns jsonb language sql stable security definer set search_path='' as $$select private.pp_workspace_navigation_before_operations(p_organisation_id)||jsonb_build_object('menus',private.pp_reference_price_read(p_organisation_id) or private.pp_operations_any(p_organisation_id));$$;
revoke all on function public.workspace_navigation_access(uuid) from public,anon;
grant execute on function public.workspace_navigation_access(uuid) to authenticated;
create or replace function public.save_stock_member_access(p_organisation_id uuid,p_membership_id uuid,p_revision integer,p_mode text,p_assignments jsonb) returns integer
language plpgsql security definer set search_path='' as $$
declare version integer; entry jsonb; site public.stock_locations; seen uuid[]:='{}'; prior jsonb; roles text[];
begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'Inventory Manager or business-wide Restaurant Administrator access is required.' using errcode='42501'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if not exists(select 1 from public.organisation_memberships where organisation_id=p_organisation_id and id=p_membership_id and status='active') then raise exception 'Choose an active member in this business.' using errcode='42501'; end if;
 select array_agg(role_code) into roles from public.membership_roles where organisation_id=p_organisation_id and membership_id=p_membership_id and role_code in ('inventory','operations','stock_department','kitchen_manager','bar_lead','stock_receiver','stock_dispatcher');
 if roles is null then raise exception 'Choose a department or stock-process member.' using errcode='42501'; end if;
 if p_mode is null or p_mode not in ('OUTLET','ASSIGNED') or jsonb_typeof(p_assignments) is distinct from 'array' or jsonb_array_length(p_assignments)>100 or octet_length(p_assignments::text)>32768 or (p_mode='OUTLET' and jsonb_array_length(p_assignments)>0) then raise exception 'Choose up to 100 explicit stock locations.' using errcode='22023'; end if;
 if p_mode='OUTLET' and not (roles&&array['inventory','operations']) then raise exception 'Department and delegated process roles require selected stock locations.' using errcode='22023'; end if;
 select a.revision,to_jsonb(a) into version,prior from public.stock_member_access a where a.organisation_id=p_organisation_id and a.membership_id=p_membership_id;
 version:=coalesce(version,0);if version is distinct from p_revision then raise exception 'Department access changed. Refresh and review the latest assignments before saving.' using errcode='22023'; end if;
 prior:=coalesce(prior,'{}')||jsonb_build_object('assignments',coalesce((select jsonb_agg(to_jsonb(g)) from public.stock_member_locations g where g.organisation_id=p_organisation_id and g.membership_id=p_membership_id),'[]'));
 for entry in select value from jsonb_array_elements(p_assignments) loop
  if jsonb_typeof(entry) is distinct from 'object' or jsonb_typeof(entry->'can_request') is distinct from 'boolean' or jsonb_typeof(entry->'can_handle') is distinct from 'boolean' or jsonb_typeof(entry->'can_approve') is distinct from 'boolean' or (entry?'can_dispatch' and jsonb_typeof(entry->'can_dispatch') is distinct from 'boolean') or (entry?'can_receive' and jsonb_typeof(entry->'can_receive') is distinct from 'boolean') or (entry?'can_record_waste' and jsonb_typeof(entry->'can_record_waste') is distinct from 'boolean') or (entry?'can_review_waste' and jsonb_typeof(entry->'can_review_waste') is distinct from 'boolean') then raise exception 'Choose explicit stock-process permissions.' using errcode='22023'; end if;
  begin select * into site from public.stock_locations where organisation_id=p_organisation_id and id=(entry->>'location_id')::uuid and is_active;exception when invalid_text_representation then raise exception 'Choose a valid stock location.' using errcode='22023';end;
  if site.id is null or site.id=any(seen) then raise exception 'Choose distinct active stock locations in this business.' using errcode='22023'; end if;
  select array_agg(role_code) into roles from public.membership_roles where organisation_id=p_organisation_id and membership_id=p_membership_id and role_code in ('inventory','operations','stock_department','kitchen_manager','bar_lead','stock_receiver','stock_dispatcher') and (location_id is null or (site.outlet_id is not null and location_id=site.outlet_id));
  if roles is null then raise exception 'Stock assignments cannot exceed the current role/outlet scope.' using errcode='22023'; end if;
  if (entry->>'can_request')::boolean and not (roles&&array['inventory','operations','stock_department','kitchen_manager','bar_lead']) then raise exception 'This process role cannot initiate requisitions.' using errcode='22023';end if;
  if (entry->>'can_handle')::boolean and not ('inventory'=any(roles)) then raise exception 'Department/process roles cannot post arbitrary stock adjustments; the Inventory Manager handles posting.' using errcode='22023';end if;
  if (entry->>'can_approve')::boolean and not (roles&&array['inventory','operations']) then raise exception 'Approval authority belongs to the Inventory Manager or the configured source approver.' using errcode='22023';end if;
  if coalesce((entry->>'can_dispatch')::boolean,(entry->>'can_handle')::boolean) and not (roles&&array['inventory','operations','stock_dispatcher']) then raise exception 'Dispatch permission requires a dispatcher process role.' using errcode='22023';end if;
  if coalesce((entry->>'can_receive')::boolean,(entry->>'can_handle')::boolean) and not (roles&&array['inventory','operations','stock_department','kitchen_manager','bar_lead','stock_receiver']) then raise exception 'Receiving permission requires a department or receiver role.' using errcode='22023';end if;
  if coalesce((entry->>'can_review_waste')::boolean,false) and not(roles&&array['inventory','operations','stock_department','kitchen_manager','bar_lead']) then raise exception 'Waste review requires a department or operational stock role at this centre.' using errcode='22023';end if;
  if coalesce((entry->>'can_record_waste')::boolean,(entry->>'can_request')::boolean) and not(roles&&array['inventory','operations','stock_department','kitchen_manager','bar_lead']) then raise exception 'Waste recording requires an operational role at this centre.' using errcode='22023';end if;
  seen:=array_append(seen,site.id);
 end loop;
 insert into public.stock_member_access(organisation_id,membership_id,mode,revision,updated_by) values(p_organisation_id,p_membership_id,p_mode,version+1,auth.uid()) on conflict(organisation_id,membership_id) do update set mode=excluded.mode,revision=excluded.revision,updated_by=excluded.updated_by,updated_at=clock_timestamp();
 delete from public.stock_member_locations where organisation_id=p_organisation_id and membership_id=p_membership_id;
 insert into public.stock_member_locations(organisation_id,membership_id,location_id,can_request,can_handle,can_approve,can_dispatch,can_receive,can_review_waste,can_record_waste)
 select p_organisation_id,p_membership_id,(g->>'location_id')::uuid,(g->>'can_request')::boolean,(g->>'can_handle')::boolean,(g->>'can_approve')::boolean,coalesce((g->>'can_dispatch')::boolean,(g->>'can_handle')::boolean),coalesce((g->>'can_receive')::boolean,(g->>'can_handle')::boolean),coalesce((g->>'can_review_waste')::boolean,false),coalesce((g->>'can_record_waste')::boolean,(g->>'can_request')::boolean) from jsonb_array_elements(p_assignments) g;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_DEPARTMENT_ACCESS_CHANGED',auth.uid(),p_membership_id,jsonb_build_object('previous',prior,'mode',p_mode,'assignments',p_assignments,'revision',version+1));return version+1;
end $$;

create function public.operations_price_warnings(p_organisation_id uuid,p_outlet_id uuid,p_from date,p_to date) returns jsonb language plpgsql stable security definer set search_path='' as $$declare today date;begin
 if p_outlet_id is null or not private.pp_operations(p_organisation_id,p_outlet_id) or not exists(select 1 from public.locations where organisation_id=p_organisation_id and id=p_outlet_id) then raise exception 'Operations access required at this outlet.' using errcode='42501';end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 if p_from is null or p_to is null or p_from>p_to or p_to>today or p_to-p_from>366 then raise exception 'Choose dates within 367 days, not in the future.' using errcode='22023';end if;
 return private.pp_executive_po_exposure(p_organisation_id,p_from,p_to,p_outlet_id);
end $$;
revoke all on function public.operations_price_warnings(uuid,uuid,date,date) from public,anon;
grant execute on function public.operations_price_warnings(uuid,uuid,date,date) to authenticated;

-- Planning and costed operational analysis remain read-only and centre-scoped.
create or replace function private.pp_material_plan_access(org uuid,site uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.pp_stock_read(org) and exists(select 1 from public.stock_locations s where s.organisation_id=org and s.id=site and s.is_active and(private.pp_stock_manager(org) or private.pp_stock_site(org,site,'request') or private.pp_operations_site(org,site)));
$$;
do $$declare signature text;definition text;updated text;begin
 foreach signature in array array['public.inventory_movement_statement(uuid,uuid,date,date,uuid,integer,boolean,text)','public.waste_analysis(uuid,uuid,date,date)','public.weekly_count_detail(uuid,uuid)'] loop
  definition:=pg_get_functiondef(signature::regprocedure);
  updated:=replace(definition,'financial:=private.pp_reference_price_read(p_organisation_id);','financial:=(private.pp_reference_price_read(p_organisation_id) or private.pp_operations_any(p_organisation_id));');
  if updated=definition then raise exception 'Expected operational cost guard missing: %',signature;end if;
  execute updated;
 end loop;
end $$;
-- Restore explicit grants after wrapping helpers. Internal functions remain inaccessible.
revoke all on function private.pp_operations(uuid,uuid),private.pp_operations_any(uuid),private.pp_operations_site(uuid,uuid),private.pp_operations_menu_scope(uuid,uuid),private.pp_stock_site_before_operations(uuid,uuid,text),private.pp_waste_site_before_operations(uuid,uuid),private.pp_stock_value_site_before_operations(uuid,uuid),private.pp_stock_site(uuid,uuid,text),private.pp_waste_site(uuid,uuid),private.pp_stock_value_site(uuid,uuid) from public,anon,authenticated;
revoke all on function private.pp_sales_read(uuid),private.pp_reference_price_read(uuid) from public,anon;
grant execute on function private.pp_sales_read(uuid),private.pp_reference_price_read(uuid) to authenticated;
revoke all on function public.operations_access(uuid),public.operations_workspace(uuid) from public,anon;
grant execute on function public.operations_access(uuid),public.operations_workspace(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
