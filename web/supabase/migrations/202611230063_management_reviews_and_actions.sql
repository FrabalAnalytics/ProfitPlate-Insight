-- Additive management reviews and follow-up. Existing stock/financial posting APIs are unchanged.
begin;
create function private.pp_review_member(org uuid) returns uuid language sql stable security definer set search_path='' as $$
 select m.id from public.organisation_memberships m join public.organisations o on o.id=m.organisation_id and o.access_state='ACTIVE'
 where m.organisation_id=org and m.user_id=auth.uid() and m.status='active' and exists(select 1 from public.membership_roles r where r.organisation_id=org and r.membership_id=m.id and r.role_code in('ceo','finance','restaurant_admin','operations','inventory_manager','inventory','procurement','kitchen_manager','bar_lead','stock_department'));
$$;
create function public.management_review_access(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare member uuid;begin
 member:=private.pp_review_member(p_organisation_id);if member is null then raise exception 'Management review access required.' using errcode='42501';end if;
 return jsonb_build_object('member',member,'financial',private.pp_sales_read(p_organisation_id),'reference_financial',private.pp_reference_price_read(p_organisation_id),'menu',private.pp_sales_read(p_organisation_id) or private.pp_operations_any(p_organisation_id),'purchasing',public.purchase_order_access(p_organisation_id,null)->'read','manage',exists(select 1 from public.membership_roles where organisation_id=p_organisation_id and membership_id=member and role_code in('ceo','finance','restaurant_admin','operations','inventory_manager','procurement','kitchen_manager','bar_lead')),
 'outlets',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'name',l.name) order by l.name,l.id) from public.locations l where l.organisation_id=p_organisation_id and (private.pp_sales_read(p_organisation_id) or private.pp_operations(p_organisation_id,l.id) or private.pp_stock_role(p_organisation_id,'procurement',l.id) or exists(select 1 from public.stock_locations s where s.organisation_id=l.organisation_id and s.outlet_id=l.id and private.pp_inventory_report_site(p_organisation_id,s.id)))),'[]'::jsonb),
 'centres',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'outlet_id',s.outlet_id,'waste',private.pp_waste_site(p_organisation_id,s.id)) order by s.name,s.id) from public.stock_locations s where s.organisation_id=p_organisation_id and private.pp_inventory_report_site(p_organisation_id,s.id)),'[]'::jsonb));
end $$;

create function private.pp_review_period(org uuid,kind text,anchor date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare today date;tz text;week integer;a date;f date;t date;pf date;pt date;begin
 select (now() at time zone time_zone)::date,time_zone,coalesce(reporting_week_start,1) into today,tz,week from public.organisations where id=org;
 if kind is null or kind not in('DAILY','WEEKLY','MONTHLY') then raise exception 'Choose Daily, Weekly or Monthly.' using errcode='22023';end if;
 a:=coalesce(anchor,case kind when 'DAILY' then today-1 when 'WEEKLY' then today-((extract(dow from today)::integer-week+7)%7)-1 else date_trunc('month',today)::date-1 end);
 if a>today or a<date '2000-01-01' then raise exception 'Choose a business date from 2000 through today.' using errcode='22023';end if;
 if kind='DAILY' then f:=a;t:=a;pf:=a-1;pt:=a-1;
 elsif kind='WEEKLY' then f:=a-((extract(dow from a)::integer-week+7)%7);t:=least(f+6,today);pf:=f-7;pt:=pf+(t-f);
 else f:=date_trunc('month',a)::date;t:=least((f+interval '1 month - 1 day')::date,today);pf:=(f-interval '1 month')::date;pt:=least(f-1,pf+(t-f));end if;
 return jsonb_build_object('period',kind,'anchor',a,'from',f,'to',t,'previous_from',pf,'previous_to',pt,'today',today,'time_zone',tz,'complete',t<today,'days',t-f+1,'previous_days',pt-pf+1,'generated_at',clock_timestamp());
end $$;

create function private.pp_review_operating(org uuid,f date,t date,outlet uuid,site uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;money boolean:=private.pp_reference_price_read(org);begin
 with centres as materialized(select s.* from public.stock_locations s where s.organisation_id=org and private.pp_inventory_report_site(org,s.id) and(site is null or s.id=site) and(outlet is null or s.outlet_id=outlet)),
 waste_scope as materialized(select id from centres where private.pp_waste_site(org,id)),
 compliance as materialized(select r.* from private.pp_waste_daily_rows(org,f,t,null) r join waste_scope s on s.id=r.site_id),
 losses as materialized(select d.id,d.document_date,s.name centre,i.name material,u.code unit,v.quantity,v.estimated_value,case when v.source='PROCESSING' then 'PROCESSING' else coalesce(d.waste_reason_code,'UNCLASSIFIED') end reason from private.waste_value_snapshots v join public.stock_documents d on d.organisation_id=v.organisation_id and d.id=v.document_id and d.state='POSTED' join waste_scope ws on ws.id=d.source_id join centres s on s.id=ws.id join public.items i on i.organisation_id=v.organisation_id and i.id=v.item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id where v.organisation_id=org and d.document_date between f and t and private.pp_stock_doc_read(org,d.id)),
 counts as materialized(select 'WEEKLY' frequency,value from private.pp_weekly_rows(org,f,t,null)value where exists(select 1 from centres where id::text=value->>'site_id') union all select 'MONTHLY',value from private.pp_monthly_rows(org,f,t,null)value where exists(select 1 from centres where id::text=value->>'site_id')),
 batches as materialized(select b.*,d.reference,d.document_date,d.source_id,s.name centre,v.name process,u.code unit,st.output_item_id from public.processing_batches b join public.stock_documents d on d.organisation_id=b.organisation_id and d.id=b.document_id and d.state='POSTED' join centres s on s.id=d.source_id join public.processing_standards st on st.organisation_id=b.organisation_id and st.id=b.standard_id join public.recipe_versions v on v.organisation_id=st.organisation_id and v.id=st.recipe_version_id join public.items i on i.organisation_id=st.organisation_id and i.id=st.output_item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id where b.organisation_id=org and d.document_date between f and t and private.pp_stock_doc_read(org,d.id)),
 variances as materialized(select l.*,c.site_id from private.weekly_count_lines l join private.weekly_counts c on c.id=l.count_id join centres s on s.id=c.site_id where c.organisation_id=org and coalesce(c.monthly_date,c.count_date) between f and t and c.state in('SUBMITTED','APPROVED','POSTED','REVIEWED') and l.physical is not null),
 orders as materialized(select p.id,p.document_date,p.status,p.reference,l.name outlet from public.purchase_orders p join public.locations l on l.organisation_id=p.organisation_id and l.id=p.location_id where p.organisation_id=org and p.document_date between f and t and private.pp_order_read(org,p.id) and(outlet is null or p.location_id=outlet) and site is null),
 days as(select x::date as day from generate_series(f,t,interval '1 day') x)
 select jsonb_build_object(
 'waste',jsonb_build_object('centres',(select count(*) from waste_scope),'entries',(select count(*) from losses),'known_value',case when money then(select sum(estimated_value)::text from losses) end,'unpriced',case when money then(select count(*) from losses where estimated_value is null) end,
 'coverage',(select jsonb_build_object('expected',count(*) filter(where expected),'complete',count(*) filter(where state like 'COMPLETE_%'),'due',count(*) filter(where expected and deadline<=clock_timestamp()),'on_time',count(*) filter(where on_time=true and deadline<=clock_timestamp()),'overdue',count(*) filter(where state='OVERDUE')) from compliance),
 'daily',coalesce((select jsonb_agg(jsonb_build_object('day',day,'entries',(select count(*) from losses where document_date=d.day),'value',case when money then(select sum(estimated_value)::text from losses where document_date=d.day) end,'expected',(select count(*) from compliance c where c.day=d.day and expected),'complete',(select count(*) from compliance c where c.day=d.day and state like 'COMPLETE_%')) order by day) from days d),'[]'::jsonb),
 'reasons',coalesce((select jsonb_agg(to_jsonb(x)) from(select reason,count(*) entries,case when money then sum(estimated_value)::text end value from losses group by reason order by count(*) desc,reason limit 8)x),'[]'::jsonb),
 'materials',coalesce((select jsonb_agg(to_jsonb(x)) from(select material,unit,sum(quantity)::text quantity,count(*) entries,case when money then sum(estimated_value)::text end value from losses group by material,unit order by count(*) desc,material limit 8)x),'[]'::jsonb)),
 'counts',jsonb_build_object('weekly',(select jsonb_build_object('expected',count(*) filter(where(value->>'cutoff')::timestamptz<=clock_timestamp()),'submitted',count(*) filter(where(value->>'cutoff')::timestamptz<=clock_timestamp() and value->>'state' in('SUBMITTED','APPROVED','POSTED','REVIEWED')),'overdue',count(*) filter(where(value->>'overdue')::boolean),'review',count(*) filter(where value->>'state'='SUBMITTED'),'posting',count(*) filter(where value->>'state'='APPROVED')) from counts where frequency='WEEKLY'),
 'monthly',(select jsonb_build_object('expected',count(*) filter(where(value->>'cutoff')::timestamptz<=clock_timestamp()),'submitted',count(*) filter(where(value->>'cutoff')::timestamptz<=clock_timestamp() and value->>'state' in('SUBMITTED','APPROVED','POSTED','REVIEWED')),'overdue',count(*) filter(where(value->>'overdue')::boolean),'review',count(*) filter(where value->>'state'='SUBMITTED'),'posting',count(*) filter(where value->>'state'='APPROVED')) from counts where frequency='MONTHLY'),
 'differences',jsonb_build_object('lines',(select count(*) from variances where physical<>book),'shortage_value',case when money then(select sum((book-physical)*unit_cost)::text from variances where physical<book) end,'surplus_value',case when money then(select sum((physical-book)*unit_cost)::text from variances where physical>book) end,'unpriced',(select count(*) from variances where physical<>book and unit_cost is null)),
 'rows',coalesce((select jsonb_agg(jsonb_build_object('frequency',frequency,'count',value) order by value->>'day' desc) from(select * from counts order by value->>'day' desc limit 12)x),'[]'::jsonb)),
 'production',jsonb_build_object('batches',(select count(*) from batches),'exceptions',(select count(*) from batches where outside_tolerance),
 'processes',coalesce((select jsonb_agg(to_jsonb(x)) from(select process,unit,output_item_id,count(*) batches,count(*) filter(where outside_tolerance) exceptions,sum(expected_output)::text expected,sum(actual_output)::text actual,round(100*sum(actual_output)/nullif(sum(expected_output),0),6)::text achievement from batches group by process,unit,output_item_id order by count(*) filter(where outside_tolerance) desc,process limit 10)x),'[]'::jsonb),
 'rows',coalesce((select jsonb_agg(to_jsonb(x)) from(select document_id,reference,document_date,centre,process,unit,expected_output::text expected,actual_output::text actual,variance_percent::text variance,responsible_name,variance_reason from batches order by abs(variance_percent) desc,document_date desc limit 8)x),'[]'::jsonb)),
 'purchasing',jsonb_build_object('orders',(select count(*) from orders),'issued',(select count(*) from orders where status='ISSUED'),'grns',(select count(*) from public.goods_receipts g join public.purchase_orders p on p.organisation_id=g.organisation_id and p.id=g.order_id where g.organisation_id=org and g.received_on between f and t and not private.pp_receipt_voided(org,g.id) and private.pp_order_read(org,p.id) and(outlet is null or p.location_id=outlet) and site is null)),
 'movement_documents',(select count(*) from public.stock_documents d where d.organisation_id=org and d.document_date between f and t and d.state='POSTED' and exists(select 1 from centres s where s.id=d.source_id or s.id=d.destination_id) and private.pp_stock_doc_read(org,d.id))) into result;
 return result;
end $$;

create function public.management_review_pack(p_organisation_id uuid,p_period text default 'DAILY',p_anchor date default null,p_outlet_id uuid default null,p_site_id uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare access jsonb;context jsonb;f date;t date;pf date;pt date;brief jsonb;prior_finance jsonb;overview jsonb;costs jsonb;stock jsonb;current_ops jsonb;previous_ops jsonb;warnings jsonb:='[]';live jsonb;menus jsonb:='[]';o jsonb;m jsonb;begin
 access:=public.management_review_access(p_organisation_id);
 if p_outlet_id is not null and not exists(select 1 from jsonb_array_elements(access->'outlets')x where x->>'id'=p_outlet_id::text) then raise exception 'Choose a permitted outlet.' using errcode='42501';end if;
 if p_site_id is not null and not exists(select 1 from jsonb_array_elements(access->'centres')x where x->>'id'=p_site_id::text and(p_outlet_id is null or x->>'outlet_id'=p_outlet_id::text)) then raise exception 'Choose a permitted centre within this outlet.' using errcode='42501';end if;
 context:=private.pp_review_period(p_organisation_id,p_period,p_anchor)||jsonb_build_object('outlet_id',p_outlet_id,'site_id',p_site_id);
 f:=(context->>'from')::date;t:=(context->>'to')::date;pf:=(context->>'previous_from')::date;pt:=(context->>'previous_to')::date;
 current_ops:=private.pp_review_operating(p_organisation_id,f,t,p_outlet_id,p_site_id);previous_ops:=private.pp_review_operating(p_organisation_id,pf,pt,p_outlet_id,p_site_id);
 if (access->>'financial')::boolean and p_site_id is null then
  begin brief:=public.executive_profitability_briefing(p_organisation_id,f,t,p_outlet_id);exception when sqlstate '22023' then warnings:=warnings||jsonb_build_array('Financial summary exceeds its supported selection or has incomplete inputs. Use the financial reports to narrow or review the source data.');end;
  begin prior_finance:=public.sales_period_summary(p_organisation_id,pf,pt,p_outlet_id);overview:=public.executive_overview(p_organisation_id,f,t,p_outlet_id);exception when sqlstate '22023' then warnings:=warnings||jsonb_build_array('Sales trend or comparison is unavailable for this selection. Recorded-day coverage may differ between periods.');end;
  begin costs:=public.expense_period_report(p_organisation_id,f,t,p_outlet_id,1);exception when sqlstate '22023' then warnings:=warnings||jsonb_build_array('Expense summary could not be generated for this selection. Review expense coverage.');end;
 end if;
 if jsonb_array_length(access->'centres')>0 then
  begin stock:=public.current_stock_value(p_organisation_id,p_site_id,p_outlet_id,1,false);exception when sqlstate '42501' then stock:=null;end;
 end if;
 for o in select value from jsonb_array_elements(access->'outlets') where (p_outlet_id is null or value->>'id'=p_outlet_id::text) and p_site_id is null loop
  if exists(select 1 from public.locations where organisation_id=p_organisation_id and id=(o->>'id')::uuid and is_active) and ((access->>'financial')::boolean or private.pp_operations_any(p_organisation_id)) and private.pp_operations_menu_scope(p_organisation_id,(o->>'id')::uuid) then
   begin m:=public.selling_menu_profitability(p_organisation_id,(o->>'id')::uuid,'STANDARD',t,'',1,'ALL','ALL','');menus:=menus||jsonb_build_array(jsonb_build_object('id',o->>'id','outlet',o->>'name','summary',m->'summary'));
   exception when sqlstate '22023' then warnings:=warnings||jsonb_build_array('Some menu comparisons are unavailable. Review the outlet menu setup or narrow the selection.');end;
  end if;
 end loop;
 select jsonb_build_object('open_transfers',(select count(*) from public.stock_documents d where d.organisation_id=p_organisation_id and d.kind in('TRANSFER','ISSUE') and d.state in('REQUESTED','APPROVED','DISPATCHED','PARTIAL','REJECTED') and private.pp_stock_doc_read(p_organisation_id,d.id) and exists(select 1 from public.stock_locations s where s.organisation_id=d.organisation_id and private.pp_inventory_report_site(p_organisation_id,s.id) and(s.id=d.source_id or s.id=d.destination_id) and(p_site_id is null or s.id=p_site_id) and(p_outlet_id is null or s.outlet_id=p_outlet_id))),
 'last_sale_date',case when (access->>'financial')::boolean and p_site_id is null then(select max(sale_date) from public.sales_headers where organisation_id=p_organisation_id and(p_outlet_id is null or location_id=p_outlet_id)) end,
 'pending_consumption',case when (access->>'financial')::boolean and p_site_id is null then(select count(*) from private.sales_stock_jobs j join public.sales_lines l on l.organisation_id=j.organisation_id and l.id=j.sale_line_id join public.sales_headers h on h.organisation_id=l.organisation_id and h.id=l.sale_id where j.organisation_id=p_organisation_id and j.state='PENDING' and h.sale_date<=t and(p_outlet_id is null or h.location_id=p_outlet_id)) end) into live;
 -- Financial access does not widen centre-level operational visibility. Never embed
 -- the briefing's separate waste, production or movement sections in this payload.
 if brief is not null then brief:=jsonb_build_object('summary',brief->'summary','food_cost_percent',brief->'food_cost_percent','prior_from',brief->'prior_from','prior_to',brief->'prior_to','prices',brief->'prices','po_exposure',brief->'po_exposure');end if;
 return jsonb_build_object('context',context,'access',access,'financial',brief,'financial_previous',prior_finance,'overview',overview,'expenses',costs,'stock_now',stock,'current',current_ops,'previous',previous_ops,'live',live,'menus',menus,'warnings',warnings,'currency',(select currency_code from public.organisations where id=p_organisation_id));
end $$;

-- Named follow-up records are private; every read and mutation rechecks current role/centre access.
create table private.management_actions(
 id uuid primary key default gen_random_uuid(),organisation_id uuid not null references public.organisations(id),
 topic text not null check(topic in('WASTE','COUNT','PRODUCTION','STOCK','PURCHASING','MENU','DATA')),
 site_id uuid,outlet_id uuid,title text not null check(length(trim(title)) between 1 and 160),description text not null default '' check(length(description)<=2000),
 assignee_id uuid not null,due_date date not null,priority text not null default 'NORMAL' check(priority in('NORMAL','HIGH')),
 state text not null default 'OPEN' check(state in('OPEN','IN_PROGRESS','RESOLVED','CLOSED','CANCELLED')),revision integer not null default 0,
 created_by uuid not null,created_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp(),
 foreign key(organisation_id,site_id) references public.stock_locations(organisation_id,id),foreign key(organisation_id,outlet_id) references public.locations(organisation_id,id),foreign key(organisation_id,assignee_id) references public.organisation_memberships(organisation_id,id),
 check(site_id is not null or outlet_id is not null));
create table private.management_action_events(id bigint generated always as identity primary key,action_id uuid not null references private.management_actions(id),revision integer not null,actor_id uuid not null,note text not null check(length(note) between 1 and 2000),data jsonb not null,created_at timestamptz not null default clock_timestamp(),unique(action_id,revision));
create table private.management_action_requests(organisation_id uuid not null,request_id uuid not null,actor_id uuid not null,digest text not null,action_id uuid not null references private.management_actions(id),primary key(organisation_id,request_id));
create index management_action_queue on private.management_actions(organisation_id,state,due_date,id);
create trigger restaurant_active_write before insert or update or delete on private.management_actions for each row execute function private.pp_require_active_restaurant();
revoke all on private.management_actions,private.management_action_events,private.management_action_requests from public,anon,authenticated;

create function private.pp_review_action_scope(org uuid,site uuid,outlet uuid,topic text) returns boolean language sql stable security definer set search_path='' as $$
 select private.pp_review_member(org) is not null and case when site is not null then exists(select 1 from public.stock_locations s where s.organisation_id=org and s.id=site and s.outlet_id is not distinct from outlet and case when topic='WASTE' then private.pp_waste_site(org,site) when topic in('COUNT','PRODUCTION','STOCK','DATA') then private.pp_inventory_report_site(org,site) else false end)
 else outlet is not null and exists(select 1 from public.locations l where l.organisation_id=org and l.id=outlet) and case when topic in('MENU','DATA') then private.pp_sales_read(org) or private.pp_operations(org,outlet) when topic='PURCHASING' then private.pp_sales_read(org) or private.pp_operations(org,outlet) or private.pp_stock_role(org,'procurement',outlet) else false end end;
$$;
create function private.pp_review_assignee(org uuid,member uuid,site uuid,outlet uuid,topic text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisation_memberships m join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id where m.organisation_id=org and m.id=member and m.status='active' and
 ((r.location_id is null and r.role_code in('ceo','finance','restaurant_admin')) or
 ((r.location_id is null or r.location_id=outlet) and case when site is null then r.role_code='operations' or(topic in('PURCHASING','DATA') and r.role_code='procurement')
 else (r.role_code in('operations','inventory','stock_department','kitchen_manager','bar_lead') and(not exists(select 1 from public.stock_member_access a where a.organisation_id=org and a.membership_id=member and a.mode='ASSIGNED') or exists(select 1 from public.stock_member_locations a where a.organisation_id=org and a.membership_id=member and a.location_id=site))) or(r.role_code='inventory_manager' and(topic<>'WASTE' or exists(select 1 from public.stock_locations s where s.organisation_id=org and s.id=site and s.responsible_membership_id=member))) end)));
$$;
create function private.pp_review_manage(org uuid,site uuid,outlet uuid,topic text) returns boolean language sql stable security definer set search_path='' as $$
 select private.pp_review_action_scope(org,site,outlet,topic) and exists(select 1 from public.organisation_memberships m join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id where m.organisation_id=org and m.user_id=auth.uid() and m.status='active' and(r.location_id is null or r.location_id=outlet) and r.role_code in('ceo','finance','restaurant_admin','operations','inventory_manager','procurement','kitchen_manager','bar_lead'));
$$;
create function public.management_action_options(p_organisation_id uuid,p_site_id uuid,p_outlet_id uuid,p_topic text) returns jsonb language plpgsql stable security definer set search_path='' as $$declare access jsonb;begin
 access:=public.management_review_access(p_organisation_id);
 if not private.pp_review_action_scope(p_organisation_id,p_site_id,p_outlet_id,p_topic) then raise exception 'Choose a topic and scope available to your role.' using errcode='42501';end if;
 return jsonb_build_object('manage',private.pp_review_manage(p_organisation_id,p_site_id,p_outlet_id,p_topic),'members',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'name',private.pp_member_label(m.organisation_id,m.id)) order by private.pp_member_label(m.organisation_id,m.id),m.id) from public.organisation_memberships m where m.organisation_id=p_organisation_id and private.pp_review_assignee(m.organisation_id,m.id,p_site_id,p_outlet_id,p_topic) and(private.pp_review_manage(p_organisation_id,p_site_id,p_outlet_id,p_topic) or m.id::text=access->>'member')),'[]'::jsonb));
end $$;
create function public.save_management_action(p_organisation_id uuid,p_id uuid,p_revision integer,p_request_id uuid,p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare access jsonb;old private.management_actions;r private.management_action_requests;doc private.management_actions;digest text:=md5(jsonb_build_array(p_id,p_revision,p_data)::text);site uuid;outlet uuid;assignee uuid;topic text;next_state text;note text;manager boolean;today date;begin
 access:=public.management_review_access(p_organisation_id);manager:=(access->>'manage')::boolean;
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into r from private.management_action_requests where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then if r.actor_id<>auth.uid() or r.digest<>digest then raise exception 'This request was already used. Refresh and review.' using errcode='22023';end if;if not exists(select 1 from private.management_actions a where a.id=r.action_id and private.pp_review_action_scope(p_organisation_id,a.site_id,a.outlet_id,a.topic)) then raise exception 'This follow-up is outside your current access.' using errcode='42501';end if;return r.action_id;end if;
 if p_request_id is null or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>16000 then raise exception 'Enter valid follow-up details.' using errcode='22023';end if;
 site:=nullif(p_data->>'site_id','')::uuid;outlet:=nullif(p_data->>'outlet_id','')::uuid;assignee:=nullif(p_data->>'assignee_id','')::uuid;topic:=p_data->>'topic';next_state:=coalesce(p_data->>'state','OPEN');note:=trim(coalesce(p_data->>'note',''));
 manager:=private.pp_review_manage(p_organisation_id,site,outlet,topic);
 if topic not in('WASTE','COUNT','PRODUCTION','STOCK','PURCHASING','MENU','DATA') or topic is null or not private.pp_review_action_scope(p_organisation_id,site,outlet,topic) then raise exception 'This follow-up scope is outside your access.' using errcode='42501';end if;
 if not private.pp_review_assignee(p_organisation_id,assignee,site,outlet,topic) then raise exception 'Choose an active colleague with access to this scope.' using errcode='22023';end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 if length(trim(coalesce(p_data->>'title',''))) not between 1 and 160 or length(coalesce(p_data->>'description',''))>2000 or length(note) not between 1 and 2000 or next_state not in('OPEN','IN_PROGRESS','RESOLVED','CLOSED','CANCELLED') or coalesce(p_data->>'priority','NORMAL') not in('NORMAL','HIGH') or nullif(p_data->>'due_date','') is null or (p_data->>'due_date')::date not between date '2000-01-01' and today+366 then raise exception 'Check the title, due date, priority and update note.' using errcode='22023';end if;
 if p_id is null then
  if p_revision is distinct from 0 or next_state<>'OPEN' or(not manager and assignee::text<>access->>'member') then raise exception 'Create an open follow-up within your assignment rights.' using errcode='42501';end if;
  insert into private.management_actions(organisation_id,topic,site_id,outlet_id,title,description,assignee_id,due_date,priority,created_by) values(p_organisation_id,topic,site,outlet,trim(p_data->>'title'),trim(coalesce(p_data->>'description','')),assignee,(p_data->>'due_date')::date,coalesce(p_data->>'priority','NORMAL'),auth.uid()) returning * into doc;
 else
  select * into old from private.management_actions where organisation_id=p_organisation_id and id=p_id for update;
  if old.id is null or not private.pp_review_action_scope(p_organisation_id,old.site_id,old.outlet_id,old.topic) then raise exception 'This follow-up is unavailable.' using errcode='42501';end if;
  if old.revision is distinct from p_revision then raise exception 'This follow-up changed. Refresh before saving.' using errcode='22023';end if;
  if (site,outlet,topic) is distinct from(old.site_id,old.outlet_id,old.topic) then raise exception 'The follow-up topic and scope cannot change. Create another follow-up if needed.' using errcode='22023';end if;
  if not manager and (old.assignee_id::text<>access->>'member' or next_state not in('OPEN','IN_PROGRESS','RESOLVED') or (assignee,p_data->>'title',coalesce(p_data->>'description',''),(p_data->>'due_date')::date,coalesce(p_data->>'priority','NORMAL')) is distinct from(old.assignee_id,old.title,old.description,old.due_date,old.priority)) then raise exception 'Only the assigned colleague can update progress; a manager changes assignments or closes follow-up.' using errcode='42501';end if;
  if old.state in('CLOSED','CANCELLED') and (not manager or next_state<>'OPEN') then raise exception 'A manager must reopen this follow-up before other changes.' using errcode='22023';end if;
  update private.management_actions set title=trim(p_data->>'title'),description=trim(coalesce(p_data->>'description','')),assignee_id=assignee,due_date=(p_data->>'due_date')::date,priority=coalesce(p_data->>'priority','NORMAL'),state=next_state,revision=revision+1,updated_at=clock_timestamp() where id=old.id returning * into doc;
 end if;
 insert into private.management_action_events(action_id,revision,actor_id,note,data) values(doc.id,doc.revision,auth.uid(),note,to_jsonb(doc));
 insert into private.management_action_requests values(p_organisation_id,p_request_id,auth.uid(),digest,doc.id);
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'MANAGEMENT_FOLLOW_UP',auth.uid(),doc.id,jsonb_build_object('state',doc.state,'revision',doc.revision,'assignee',doc.assignee_id));return doc.id;
end $$;
create function public.management_actions(p_organisation_id uuid,p_state text default 'ACTIVE',p_page integer default 1,p_id uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare access jsonb;result jsonb;today date;begin
 access:=public.management_review_access(p_organisation_id);
 if p_state is null or p_state not in('ACTIVE','ALL','OVERDUE','OPEN','IN_PROGRESS','RESOLVED','CLOSED','CANCELLED') or p_page is null or p_page not between 1 and 100000 then raise exception 'Choose a valid action filter and page.' using errcode='22023';end if;
 select(now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 if p_id is not null and not exists(select 1 from private.management_actions a where a.organisation_id=p_organisation_id and a.id=p_id and private.pp_review_action_scope(a.organisation_id,a.site_id,a.outlet_id,a.topic)) then raise exception 'This follow-up is unavailable.' using errcode='42501';end if;
 with readable as materialized(select a.*,private.pp_member_label(a.organisation_id,a.assignee_id) assignee,s.name centre,l.name outlet,private.pp_review_manage(a.organisation_id,a.site_id,a.outlet_id,a.topic) can_manage,a.assignee_id::text=access->>'member' can_progress,a.due_date<today and a.state in('OPEN','IN_PROGRESS','RESOLVED') overdue from private.management_actions a left join public.stock_locations s on s.organisation_id=a.organisation_id and s.id=a.site_id left join public.locations l on l.organisation_id=a.organisation_id and l.id=a.outlet_id where a.organisation_id=p_organisation_id and private.pp_review_action_scope(a.organisation_id,a.site_id,a.outlet_id,a.topic)),
 filtered as(select * from readable where (p_id is null or id=p_id) and(p_id is not null or p_state='ALL' or(p_state='ACTIVE' and state not in('CLOSED','CANCELLED')) or(p_state='OVERDUE' and overdue) or state=p_state)),
 paged as(select * from filtered order by overdue desc,case priority when 'HIGH' then 0 else 1 end,due_date,id limit 20 offset(p_page-1)*20)
 select jsonb_build_object('access',access,'today',today,'total',(select count(*) from filtered),'summary',(select jsonb_build_object('open',count(*) filter(where state in('OPEN','IN_PROGRESS')),'overdue',count(*) filter(where overdue),'resolved',count(*) filter(where state='RESOLVED'),'closed',count(*) filter(where state='CLOSED')) from readable),'rows',coalesce((select jsonb_agg(to_jsonb(x)) from paged x),'[]'::jsonb),
 'events',case when p_id is not null then coalesce((select jsonb_agg(jsonb_build_object('revision',revision,'note',note,'state',data->>'state','due_date',data->>'due_date','assignee',private.pp_member_label(p_organisation_id,(data->>'assignee_id')::uuid),'at',created_at,'actor',coalesce((select private.pp_member_label(p_organisation_id,m.id) from public.organisation_memberships m where m.organisation_id=p_organisation_id and m.user_id=e.actor_id),'Former colleague')) order by revision desc) from private.management_action_events e where action_id=p_id),'[]'::jsonb) else '[]'::jsonb end) into result;return result;
end $$;

create table private.management_review_snapshots(id uuid primary key default gen_random_uuid(),organisation_id uuid not null references public.organisations(id),actor_id uuid not null references auth.users(id),request_id uuid not null,digest text not null,payload jsonb not null,created_at timestamptz not null default clock_timestamp(),unique(organisation_id,request_id));
revoke all on private.management_review_snapshots from public,anon,authenticated;
create trigger restaurant_active_write before insert or update or delete on private.management_review_snapshots for each row execute function private.pp_require_active_restaurant();
create function private.pp_review_snapshot_allowed(org uuid,payload jsonb) returns boolean language plpgsql stable security definer set search_path='' as $$declare a jsonb;begin
 a:=public.management_review_access(org);
 return (not(payload->'access'->>'financial')::boolean or(a->>'financial')::boolean)
 and (not(payload->'access'->>'purchasing')::boolean or(a->>'purchasing')::boolean)
 and (not(payload->'access'->>'menu')::boolean or(a->>'menu')::boolean)
 and (not(payload->'access'->>'reference_financial')::boolean or(a->>'reference_financial')::boolean)
 and not exists(select 1 from jsonb_array_elements(coalesce(payload->'stock_now'->'centres','[]'::jsonb)) s where not private.pp_stock_value_site(org,(s->>'id')::uuid))
 and not exists(select 1 from jsonb_array_elements(payload->'access'->'centres') old where not exists(select 1 from jsonb_array_elements(a->'centres') cur where cur->>'id'=old->>'id' and(not(old->>'waste')::boolean or(cur->>'waste')::boolean)))
 and not exists(select 1 from jsonb_array_elements(payload->'access'->'outlets') old where not exists(select 1 from jsonb_array_elements(a->'outlets') cur where cur->>'id'=old->>'id'));
end $$;
create function public.save_management_review(p_organisation_id uuid,p_period text,p_anchor date,p_outlet_id uuid,p_site_id uuid,p_request_id uuid) returns uuid language plpgsql security definer set search_path='' as $$declare prior private.management_review_snapshots;payload jsonb;result uuid;digest text:=md5(jsonb_build_array(p_period,p_anchor,p_outlet_id,p_site_id)::text);begin
 perform public.management_review_access(p_organisation_id);perform 1 from public.organisations where id=p_organisation_id for update;
 if p_request_id is null then raise exception 'Refresh before saving the review.' using errcode='22023';end if;
 select * into prior from private.management_review_snapshots where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then if prior.actor_id<>auth.uid() or prior.digest<>digest or not private.pp_review_snapshot_allowed(p_organisation_id,prior.payload) then raise exception 'This save request was already used. Refresh the review.' using errcode='22023';end if;return prior.id;end if;
 payload:=public.management_review_pack(p_organisation_id,p_period,p_anchor,p_outlet_id,p_site_id);
 if octet_length(payload::text)>2097152 then raise exception 'Narrow the review scope before saving.' using errcode='22023';end if;
 insert into private.management_review_snapshots(organisation_id,actor_id,request_id,digest,payload) values(p_organisation_id,auth.uid(),p_request_id,digest,payload) returning id into result;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'MANAGEMENT_REVIEW_SAVED',auth.uid(),result,jsonb_build_object('period',p_period,'context',payload->'context'));return result;
end $$;
create function public.management_review_history(p_organisation_id uuid,p_id uuid default null,p_page integer default 1) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;begin
 perform public.management_review_access(p_organisation_id);
 if p_page is null or p_page not between 1 and 100000 then raise exception 'Choose a valid history page.' using errcode='22023';end if;
 if p_id is not null then select payload into result from private.management_review_snapshots where organisation_id=p_organisation_id and actor_id=auth.uid() and id=p_id and private.pp_review_snapshot_allowed(p_organisation_id,payload);if result is null then raise exception 'This saved review is unavailable under your current access.' using errcode='42501';end if;return jsonb_build_object('payload',result);end if;
 with readable as materialized(select * from private.management_review_snapshots where organisation_id=p_organisation_id and actor_id=auth.uid() and private.pp_review_snapshot_allowed(p_organisation_id,payload)) select jsonb_build_object('total',(select count(*) from readable),'rows',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,created_at,payload->'context' context from readable order by created_at desc,id limit 20 offset(p_page-1)*20)x),'[]'::jsonb)) into result;return result;
end $$;

revoke all on function private.pp_review_member(uuid),private.pp_review_period(uuid,text,date),private.pp_review_operating(uuid,date,date,uuid,uuid),private.pp_review_action_scope(uuid,uuid,uuid,text),private.pp_review_assignee(uuid,uuid,uuid,uuid,text),private.pp_review_manage(uuid,uuid,uuid,text) from public,anon,authenticated;
revoke all on function private.pp_review_snapshot_allowed(uuid,jsonb) from public,anon,authenticated;
revoke all on function public.management_review_access(uuid),public.management_review_pack(uuid,text,date,uuid,uuid),public.management_action_options(uuid,uuid,uuid,text),public.save_management_action(uuid,uuid,integer,uuid,jsonb),public.management_actions(uuid,text,integer,uuid) from public,anon;
grant execute on function public.management_review_access(uuid),public.management_review_pack(uuid,text,date,uuid,uuid),public.management_action_options(uuid,uuid,uuid,text),public.save_management_action(uuid,uuid,integer,uuid,jsonb),public.management_actions(uuid,text,integer,uuid) to authenticated;
revoke all on function public.save_management_review(uuid,text,date,uuid,uuid,uuid),public.management_review_history(uuid,uuid,integer) from public,anon;
grant execute on function public.save_management_review(uuid,text,date,uuid,uuid,uuid),public.management_review_history(uuid,uuid,integer) to authenticated;
notify pgrst,'reload schema';
commit;
