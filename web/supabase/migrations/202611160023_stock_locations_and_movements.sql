-- Quantity inventory only. No legacy stock migration, valuation or automatic sales depletion.
begin;
create table public.stock_locations (
 id uuid primary key default gen_random_uuid(), organisation_id uuid not null references public.organisations(id),
 code text not null check(code ~ '^[A-Z0-9][A-Z0-9_-]{0,39}$'), name text not null check(length(trim(name)) between 1 and 120),
 kind text not null check(kind in ('WAREHOUSE','STORE','KITCHEN','BAR','PRODUCTION')), outlet_id uuid,
 department text not null default '' check(length(department)<=80), is_active boolean not null default true,
 unique(organisation_id,id), unique(organisation_id,code),
 foreign key(organisation_id,outlet_id) references public.locations(organisation_id,id)
);
create table public.stock_routes (
 id uuid primary key default gen_random_uuid(), organisation_id uuid not null, source_id uuid not null, destination_id uuid not null,
 kind text not null check(kind in ('TRANSFER','ISSUE')), approval_role text not null check(approval_role in ('inventory','operations','restaurant_admin')),
 is_active boolean not null default true, check(source_id<>destination_id),
 unique(organisation_id,id), unique(organisation_id,source_id,destination_id,kind),
 foreign key(organisation_id,source_id) references public.stock_locations(organisation_id,id),
 foreign key(organisation_id,destination_id) references public.stock_locations(organisation_id,id)
);
create table public.stock_recipe_bindings (
 organisation_id uuid not null, recipe_version_id uuid not null, item_id uuid not null,
 primary key(organisation_id,recipe_version_id),
 foreign key(organisation_id,recipe_version_id) references public.recipe_versions(organisation_id,id),
 foreign key(organisation_id,item_id) references public.items(organisation_id,id)
);
create table public.stock_documents (
 id uuid primary key default gen_random_uuid(), organisation_id uuid not null references public.organisations(id),
 request_id uuid not null, input_hash text not null, reference text not null,
 kind text not null check(kind in ('OPENING','GRN','DIRECT_RECEIPT','TRANSFER','ISSUE','COUNT','WASTE','CONSUMPTION','PRODUCTION')),
 state text not null default 'REQUESTED' check(state in ('REQUESTED','APPROVED','DISPATCHED','RECEIVED','POSTED','CANCELLED')),
 source_id uuid, destination_id uuid, route_id uuid, receipt_id uuid, recipe_version_id uuid,
 document_date date not null, note text not null check(length(trim(note)) between 1 and 1000),
 lines jsonb not null, output jsonb, received_lines jsonb, count_fingerprint text,
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 approved_by uuid references auth.users(id), approved_at timestamptz, dispatched_by uuid references auth.users(id), dispatched_at timestamptz,
 completed_by uuid references auth.users(id), completed_at timestamptz, decision_note text,
 unique(organisation_id,id), unique(organisation_id,request_id), unique(organisation_id,reference),
 foreign key(organisation_id,source_id) references public.stock_locations(organisation_id,id),
 foreign key(organisation_id,destination_id) references public.stock_locations(organisation_id,id),
 foreign key(organisation_id,route_id) references public.stock_routes(organisation_id,id),
 foreign key(organisation_id,receipt_id) references public.goods_receipts(organisation_id,id),
 foreign key(organisation_id,recipe_version_id) references public.recipe_versions(organisation_id,id)
);
create unique index stock_grn_once on public.stock_documents(organisation_id,receipt_id) where receipt_id is not null and state<>'CANCELLED';
create unique index stock_direct_receipt_once on public.stock_documents(organisation_id,(output->>'supplier_id'),lower(output->>'delivery_reference')) where kind='DIRECT_RECEIPT' and state<>'CANCELLED';
create table public.stock_ledger (
 id bigint generated always as identity primary key, organisation_id uuid not null, document_id uuid not null,
 location_id uuid not null, item_id uuid not null, quantity numeric(38,12) not null,
 occurred_on date not null, created_at timestamptz not null default clock_timestamp(),
 foreign key(organisation_id,document_id) references public.stock_documents(organisation_id,id),
 foreign key(organisation_id,location_id) references public.stock_locations(organisation_id,id),
 foreign key(organisation_id,item_id) references public.items(organisation_id,id)
);
create index stock_balance_lookup on public.stock_ledger(organisation_id,location_id,item_id,id);

create function private.pp_stock_role(org uuid, role_name text, outlet uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisation_memberships m join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id
 where m.organisation_id=org and m.user_id=auth.uid() and m.status='active' and r.role_code=role_name
 and (r.location_id is null or (outlet is not null and r.location_id=outlet)));
$$;
create function private.pp_stock_manager(org uuid) returns boolean
language sql stable security definer set search_path='' as $$ select private.pp_stock_role(org,'restaurant_admin',null); $$;
create function private.pp_stock_site(org uuid, site uuid, mode text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.stock_locations s where s.organisation_id=org and s.id=site and
 (case when mode='read' then
   private.pp_stock_manager(org) or private.pp_stock_role(org,'ceo',null) or private.pp_stock_role(org,'finance',s.outlet_id)
   or private.pp_stock_role(org,'procurement',s.outlet_id) or private.pp_stock_role(org,'inventory',s.outlet_id) or private.pp_stock_role(org,'operations',s.outlet_id)
 when mode='request' then private.pp_stock_role(org,'inventory',s.outlet_id) or private.pp_stock_role(org,'operations',s.outlet_id)
 when mode='inventory' then private.pp_stock_role(org,'inventory',s.outlet_id)
 else false end));
$$;
create function private.pp_stock_read(org uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisation_memberships m join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id
 where m.organisation_id=org and m.user_id=auth.uid() and m.status='active' and r.role_code in ('ceo','restaurant_admin','finance','procurement','inventory','operations'));
$$;
create function private.pp_stock_doc_read(org uuid, doc uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.stock_documents d where d.organisation_id=org and d.id=doc
 and (private.pp_stock_site(org,d.source_id,'read') or private.pp_stock_site(org,d.destination_id,'read')));
$$;
-- Defence in depth: all writes use checked RPCs; the ledger has no client write grants.
do $$ declare t text; begin
 foreach t in array array['stock_locations','stock_routes','stock_recipe_bindings','stock_documents','stock_ledger'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
 end loop;
end $$;

create function private.pp_stock_number(value text, allow_zero boolean default false) returns numeric
language plpgsql immutable set search_path='' as $$
declare n numeric;
begin
 if coalesce(value,'')!~'^(0|[1-9][0-9]{0,13})(\.[0-9]{1,12})?$' then raise exception 'Enter a quantity without commas, with up to twelve decimal places.' using errcode='22023'; end if;
 n:=value::numeric;
 if n<0 or (not allow_zero and n=0) then raise exception 'Enter a positive quantity.' using errcode='22023'; end if;
 return n;
end $$;
create function private.pp_stock_balance(org uuid, site uuid, material uuid) returns numeric
language sql stable security definer set search_path='' as $$
 select coalesce(sum(quantity),0) from public.stock_ledger where organisation_id=org and location_id=site and item_id=material;
$$;
create function private.pp_stock_fingerprint(org uuid, site uuid) returns text
language sql stable security definer set search_path='' as $$
 select md5(coalesce(string_agg(id::text,',' order by id),'')) from public.stock_ledger where organisation_id=org and location_id=site;
$$;
create function private.pp_stock_entry(org uuid, doc uuid, site uuid, material uuid, qty numeric, day date) returns void
language plpgsql security definer set search_path='' as $$
begin
 if qty=0 then return; end if;
 if qty<>round(qty,12) or abs(qty)>=1e26 then raise exception 'Stock quantity exceeds supported precision.' using errcode='22023'; end if;
 if exists(select 1 from public.stock_ledger where organisation_id=org and location_id=site and item_id=material and occurred_on>day) then
  raise exception 'A later stock movement exists. Use the current movement date and explain any correction.' using errcode='22023'; end if;
 if private.pp_stock_balance(org,site,material)+qty<0 then raise exception 'Insufficient stock. Refresh balances before posting.' using errcode='22023'; end if;
 insert into public.stock_ledger(organisation_id,document_id,location_id,item_id,quantity,occurred_on) values(org,doc,site,material,qty,day);
end $$;

create function public.save_stock_configuration(p_organisation_id uuid,p_kind text,p_value jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid; src public.stock_locations; dst public.stock_locations; u public.units_of_measure; v public.units_of_measure;
begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'Business-wide Restaurant Administrator access is required.' using errcode='42501'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if p_kind='LOCATION' then
  if coalesce(p_value->>'code','')!~'^[A-Z0-9][A-Z0-9_-]{0,39}$' or length(trim(coalesce(p_value->>'name',''))) not between 1 and 120
   or coalesce(p_value->>'kind','') not in ('WAREHOUSE','STORE','KITCHEN','BAR','PRODUCTION') or length(coalesce(p_value->>'department',''))>80 then raise exception 'Enter a code, name, stock location type and optional department.' using errcode='22023'; end if;
  if nullif(p_value->>'outlet_id','') is not null and not exists(select 1 from public.locations where organisation_id=p_organisation_id and id=(p_value->>'outlet_id')::uuid and is_active) then raise exception 'Choose an active outlet in this business.' using errcode='22023'; end if;
  if exists(select 1 from public.stock_locations where organisation_id=p_organisation_id and code=p_value->>'code') then raise exception 'That stock location code already exists.' using errcode='22023'; end if;
  insert into public.stock_locations(organisation_id,code,name,kind,outlet_id,department) values(p_organisation_id,p_value->>'code',trim(p_value->>'name'),p_value->>'kind',nullif(p_value->>'outlet_id','')::uuid,trim(coalesce(p_value->>'department',''))) returning id into result;
 elsif p_kind='ROUTE' then
  select * into src from public.stock_locations where organisation_id=p_organisation_id and id=(p_value->>'source_id')::uuid and is_active;
  select * into dst from public.stock_locations where organisation_id=p_organisation_id and id=(p_value->>'destination_id')::uuid and is_active;
  if src.id is null or dst.id is null or src.id=dst.id or coalesce(p_value->>'kind','') not in ('TRANSFER','ISSUE') or coalesce(p_value->>'approval_role','') not in ('inventory','operations','restaurant_admin') then raise exception 'Choose different active stock locations, a movement type and an approval role.' using errcode='22023'; end if;
  insert into public.stock_routes(organisation_id,source_id,destination_id,kind,approval_role) values(p_organisation_id,src.id,dst.id,p_value->>'kind',p_value->>'approval_role')
   on conflict(organisation_id,source_id,destination_id,kind) do update set approval_role=excluded.approval_role,is_active=true returning id into result;
 elsif p_kind='BINDING' then
  select uom.* into u from public.recipe_outputs o join public.units_of_measure uom on uom.organisation_id=o.organisation_id and uom.id=o.uom_id where o.organisation_id=p_organisation_id and o.recipe_version_id=(p_value->>'recipe_version_id')::uuid;
  select uom.* into v from public.items i join public.units_of_measure uom on uom.organisation_id=i.organisation_id and uom.id=i.base_uom_id where i.organisation_id=p_organisation_id and i.id=(p_value->>'item_id')::uuid and i.is_active and i.stock_tracked and i.item_type in ('SEMI_FINISHED','FINISHED');
  if u.id is null or v.id is null or u.dimension<>v.dimension or u.dimension='PACKAGE' then raise exception 'Bind a published recipe to an active tracked semi-finished/finished material with a compatible base unit.' using errcode='22023'; end if;
  if exists(select 1 from public.stock_documents where organisation_id=p_organisation_id and kind='PRODUCTION' and state<>'CANCELLED' and (recipe_version_id=(p_value->>'recipe_version_id')::uuid or lines::text like '%'||(p_value->>'recipe_version_id')||'%')) then raise exception 'This recipe binding is already used. Publish a new recipe version to change its stock output.' using errcode='22023'; end if;
  insert into public.stock_recipe_bindings values(p_organisation_id,(p_value->>'recipe_version_id')::uuid,(p_value->>'item_id')::uuid) on conflict(organisation_id,recipe_version_id) do update set item_id=excluded.item_id;
  result:=(p_value->>'recipe_version_id')::uuid;
 elsif p_kind in ('LOCATION_STATE','ROUTE_STATE') then
  result:=(p_value->>'id')::uuid;
  if p_kind='LOCATION_STATE' then
   if exists(select 1 from public.stock_documents where organisation_id=p_organisation_id and state in ('REQUESTED','APPROVED','DISPATCHED') and (source_id=result or destination_id=result))
    or exists(select 1 from public.stock_ledger where organisation_id=p_organisation_id and location_id=result group by item_id having sum(quantity)<>0) then raise exception 'Clear stock and finish pending movements before deactivating a stock location.' using errcode='22023'; end if;
   update public.stock_locations set is_active=(p_value->>'active')::boolean where organisation_id=p_organisation_id and id=result;
  else
   update public.stock_routes set is_active=(p_value->>'active')::boolean where organisation_id=p_organisation_id and id=result;
  end if;
  if not found then raise exception 'Configuration unavailable.' using errcode='42501'; end if;
 else raise exception 'Unknown stock configuration.' using errcode='22023'; end if;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_CONFIGURATION',auth.uid(),result,jsonb_build_object('kind',p_kind,'value',p_value));
 return result;
end $$;

create function private.pp_stock_lines(org uuid, input jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare line jsonb; item public.items; seen uuid[]:='{}'; result jsonb:='[]'; qty numeric; unit text;
begin
 if jsonb_typeof(input) is distinct from 'array' or jsonb_array_length(input) not between 1 and 100 or octet_length(input::text)>65536 then raise exception 'Use between one and 100 stock lines.' using errcode='22023'; end if;
 for line in select value from jsonb_array_elements(input) loop
  select * into item from public.items where organisation_id=org and id=(line->>'item_id')::uuid and is_active and stock_tracked;
  if item.id is null or item.id=any(seen) then raise exception 'Choose distinct active stock-tracked materials in this business.' using errcode='22023'; end if;
  qty:=private.pp_stock_number(line->>'quantity',true);
  select code into unit from public.units_of_measure where organisation_id=org and id=item.base_uom_id;
  result:=result||jsonb_build_array(jsonb_build_object('item_id',item.id,'name',item.name,'code',item.code,'unit',unit,'quantity',qty::text));
  seen:=array_append(seen,item.id);
 end loop;
 return result;
end $$;

create function public.request_stock_document(p_organisation_id uuid,p_request_id uuid,p_document jsonb,p_lines jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid:=gen_random_uuid(); prior public.stock_documents; src public.stock_locations; dst public.stock_locations; route public.stock_routes;
 kind text:=p_document->>'kind'; day date; digest text; lines jsonb; output jsonb; rec public.goods_receipts; po public.purchase_orders;
 r record; qty numeric; planned numeric; actual numeric; base_factor numeric; bound uuid; out_qty numeric; expected numeric; fingerprint text;
begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock access is required.' using errcode='42501'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if p_request_id is null or octet_length(coalesce(p_document::text,''))>10000 then raise exception 'Refresh and enter a valid stock request.' using errcode='22023'; end if;
 digest:=md5(jsonb_build_array(p_document,p_lines)::text);
 select * into prior from public.stock_documents where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then
  if prior.input_hash<>digest or prior.created_by<>auth.uid() then raise exception 'This request was already used. Refresh before creating another.' using errcode='22023'; end if;
  return prior.id;
 end if;
 if kind not in ('OPENING','GRN','DIRECT_RECEIPT','TRANSFER','ISSUE','COUNT','WASTE','CONSUMPTION','PRODUCTION') or kind is null then raise exception 'Choose a stock movement type.' using errcode='22023'; end if;
 begin day:=(p_document->>'date')::date; exception when others then raise exception 'Choose a valid movement date.' using errcode='22023'; end;
 if day is null or day>(select(now() at time zone time_zone)::date from public.organisations where id=p_organisation_id) or length(trim(coalesce(p_document->>'note',''))) not between 1 and 1000 then raise exception 'Choose a date that is not in the future and enter the source/reason.' using errcode='22023'; end if;
 select * into src from public.stock_locations where organisation_id=p_organisation_id and id=nullif(p_document->>'source_id','')::uuid and is_active;
 select * into dst from public.stock_locations where organisation_id=p_organisation_id and id=nullif(p_document->>'destination_id','')::uuid and is_active;
 if kind in ('TRANSFER','ISSUE') then
  select * into route from public.stock_routes where organisation_id=p_organisation_id and id=nullif(p_document->>'route_id','')::uuid and is_active;
  if route.id is null or route.kind<>kind then raise exception 'Choose a configured active route for this movement type.' using errcode='22023'; end if;
  select * into src from public.stock_locations where organisation_id=p_organisation_id and id=route.source_id and is_active;
  select * into dst from public.stock_locations where organisation_id=p_organisation_id and id=route.destination_id and is_active;
  if src.id is null or dst.id is null or not (private.pp_stock_site(p_organisation_id,dst.id,'request') or private.pp_stock_site(p_organisation_id,src.id,'inventory')) then raise exception 'Request access is required at the receiving department, or Inventory access at the source.' using errcode='42501'; end if;
 elsif kind in ('OPENING','GRN','DIRECT_RECEIPT') then
  src.id:=null;
  if dst.id is null or not private.pp_stock_site(p_organisation_id,dst.id,'inventory') then raise exception 'Inventory access is required at the receiving stock location.' using errcode='42501'; end if;
 else
  dst.id:=null;
  if src.id is null or not private.pp_stock_site(p_organisation_id,src.id,'request') then raise exception 'Inventory or Operations access is required at this stock location.' using errcode='42501'; end if;
 end if;
 if kind='GRN' then
  select * into rec from public.goods_receipts where organisation_id=p_organisation_id and id=nullif(p_document->>'receipt_id','')::uuid;
  select * into po from public.purchase_orders where organisation_id=p_organisation_id and id=rec.order_id;
  if rec.id is null or private.pp_receipt_voided(p_organisation_id,rec.id) or exists(select 1 from public.goods_receipt_void_requests where organisation_id=p_organisation_id and receipt_id=rec.id and state='PENDING')
   or not private.pp_inventory_access(p_organisation_id,po.location_id) or (dst.outlet_id is not null and dst.outlet_id<>po.location_id) or day<rec.received_on then raise exception 'Choose an active GRN for this outlet (or a central store), with no pending void, on or before the stock date.' using errcode='22023'; end if;
  if exists(select 1 from public.stock_documents where organisation_id=p_organisation_id and receipt_id=rec.id and state<>'CANCELLED') then raise exception 'This GRN already has a stock request.' using errcode='22023'; end if;
  select jsonb_agg(jsonb_build_object('item_id',q.item_id,'quantity',q.qty::text)) into lines from (
   select l.item_id,sum(g.accepted*(l.payload->>'conversion_factor')::numeric) qty from public.goods_receipt_lines g join public.purchase_order_lines l on l.organisation_id=g.organisation_id and l.order_id=g.order_id and l.id=g.order_line_id
   where g.organisation_id=p_organisation_id and g.receipt_id=rec.id and g.accepted>0 group by l.item_id
  ) q;
  lines:=private.pp_stock_lines(p_organisation_id,lines);
 elsif kind='PRODUCTION' then
  planned:=private.pp_stock_number(p_document->>'planned_output'); actual:=private.pp_stock_number(p_document->>'actual_output',true);
  select b.item_id,o.quantity,u.canonical_factor/v.canonical_factor into bound,out_qty,base_factor
   from public.stock_recipe_bindings b join public.recipe_outputs o on o.organisation_id=b.organisation_id and o.recipe_version_id=b.recipe_version_id
   join public.recipe_versions rv on rv.organisation_id=b.organisation_id and rv.id=b.recipe_version_id
   join public.items i on i.organisation_id=b.organisation_id and i.id=b.item_id and i.is_active and i.stock_tracked
   join public.units_of_measure u on u.organisation_id=o.organisation_id and u.id=o.uom_id
   join public.units_of_measure v on v.organisation_id=i.organisation_id and v.id=i.base_uom_id
   where b.organisation_id=p_organisation_id and b.recipe_version_id=nullif(p_document->>'recipe_version_id','')::uuid and rv.effective_from<=day;
  if bound is null then raise exception 'Bind a recipe version to a stock output material before recording production. Its effective date must not be after the movement date.' using errcode='22023'; end if;
  lines:='[]';
  for r in select c.*,b.item_id child_item,bu.canonical_factor/bv.canonical_factor factor
   from public.recipe_components c left join public.stock_recipe_bindings b on b.organisation_id=c.organisation_id and b.recipe_version_id=c.child_recipe_version_id
   left join public.items i on i.organisation_id=b.organisation_id and i.id=b.item_id
   left join public.units_of_measure bu on bu.organisation_id=c.organisation_id and bu.id=c.base_uom_id
   left join public.units_of_measure bv on bv.organisation_id=i.organisation_id and bv.id=i.base_uom_id
   where c.organisation_id=p_organisation_id and c.recipe_version_id=(p_document->>'recipe_version_id')::uuid order by c.line_no loop
   if r.child_recipe_version_id is not null and r.child_item is null then raise exception 'Bind and produce each child sub-recipe before the parent batch. Ingredients are not deducted twice.' using errcode='22023'; end if;
   qty:=round(r.normalised_quantity*planned/out_qty*case when r.item_id is not null then 1 else r.factor end,12);
   if qty<=0 then raise exception 'A production input falls below supported precision.' using errcode='22023'; end if;
   lines:=lines||jsonb_build_array(jsonb_build_object('item_id',coalesce(r.item_id,r.child_item),'quantity',qty::text));
  end loop;
  select jsonb_agg(jsonb_build_object('item_id',q.item_id,'quantity',q.qty::text)) into lines from (select value->>'item_id' item_id,sum((value->>'quantity')::numeric) qty from jsonb_array_elements(lines) group by value->>'item_id') q;
  lines:=private.pp_stock_lines(p_organisation_id,lines);
  if exists(select 1 from jsonb_array_elements(lines) l where l->>'item_id'=bound::text) then raise exception 'Production output must differ from its stock inputs.' using errcode='22023'; end if;
  output:=jsonb_build_object('item_id',bound,'quantity',round(actual*base_factor,12)::text,'planned_output',planned::text,'actual_output',actual::text,'recipe_version_id',p_document->>'recipe_version_id');
  -- Pin child bindings as evidence; future changes cannot rewrite these inputs.
 else lines:=private.pp_stock_lines(p_organisation_id,p_lines); end if;
 if kind<>'COUNT' and exists(select 1 from jsonb_array_elements(lines) l where (l->>'quantity')::numeric<=0) then raise exception 'Movement quantities must be positive.' using errcode='22023'; end if;
 if kind='COUNT' then fingerprint:=private.pp_stock_fingerprint(p_organisation_id,src.id); end if;
 if kind='DIRECT_RECEIPT' then
  if nullif(p_document->>'supplier_id','') is null or not exists(select 1 from public.suppliers where organisation_id=p_organisation_id and id=(p_document->>'supplier_id')::uuid and is_active)
   or length(trim(coalesce(p_document->>'delivery_reference',''))) not between 1 and 100 then raise exception 'Choose the supplier and enter its delivery reference.' using errcode='22023'; end if;
  if exists(select 1 from public.stock_documents d where d.organisation_id=p_organisation_id and d.kind='DIRECT_RECEIPT' and d.state<>'CANCELLED' and d.output->>'supplier_id'=p_document->>'supplier_id' and lower(d.output->>'delivery_reference')=lower(trim(p_document->>'delivery_reference'))) then raise exception 'This supplier delivery reference already has a stock request. Review its existing record.' using errcode='22023'; end if;
 end if;
 if kind='OPENING' and exists(select 1 from public.stock_ledger e join jsonb_array_elements(lines) l on l->>'item_id'=e.item_id::text where e.organisation_id=p_organisation_id and e.location_id=dst.id) then raise exception 'Opening balances must be the first posting for each listed material at that stock location. Use a reviewed count for corrections.' using errcode='22023'; end if;
 insert into public.stock_documents(id,organisation_id,request_id,input_hash,reference,kind,source_id,destination_id,route_id,receipt_id,recipe_version_id,document_date,note,lines,output,count_fingerprint,created_by)
 values(result,p_organisation_id,p_request_id,digest,'STK-'||upper(substr(replace(result::text,'-',''),1,12)),kind,src.id,dst.id,route.id,rec.id,case when kind='PRODUCTION' then (p_document->>'recipe_version_id')::uuid end,day,trim(p_document->>'note'),lines,
 case when kind='DIRECT_RECEIPT' then jsonb_build_object('supplier_id',p_document->>'supplier_id','delivery_reference',trim(p_document->>'delivery_reference')) else output end,fingerprint,auth.uid());
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_REQUESTED',auth.uid(),result,jsonb_build_object('kind',kind));
 return result;
end $$;

create function public.stock_document_action(p_organisation_id uuid,p_document_id uuid,p_action text,p_note text,p_received jsonb default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare d public.stock_documents; route public.stock_routes; site public.stock_locations; line jsonb; rec jsonb; item uuid; qty numeric; accepted numeric; actor uuid:=auth.uid();
begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock access is required.' using errcode='42501'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into d from public.stock_documents where organisation_id=p_organisation_id and id=p_document_id;
 if d.id is null or not private.pp_stock_doc_read(p_organisation_id,d.id) then raise exception 'Stock document unavailable.' using errcode='42501'; end if;
 if length(trim(coalesce(p_note,''))) not between 1 and 1000 then raise exception 'Enter a decision/source note.' using errcode='22023'; end if;
 if p_action='CANCEL' then
  if d.created_by<>actor and not private.pp_stock_manager(p_organisation_id) then raise exception 'Only the requester or administrator may cancel.' using errcode='42501'; end if;
  if d.state not in ('REQUESTED','APPROVED') then raise exception 'Only unposted, undispatched requests may be cancelled.' using errcode='22023'; end if;
  update public.stock_documents set state='CANCELLED',decision_note=p_note,completed_by=actor,completed_at=clock_timestamp() where id=d.id;
 elsif p_action='APPROVE' then
  if d.created_by=actor then raise exception 'A different authorised colleague must approve this request.' using errcode='42501'; end if;
  if d.kind in ('TRANSFER','ISSUE') then
   select * into route from public.stock_routes where organisation_id=p_organisation_id and id=d.route_id and is_active;
   select * into site from public.stock_locations where organisation_id=p_organisation_id and id=d.source_id;
   if route.id is null or not (private.pp_stock_manager(p_organisation_id) or private.pp_stock_role(p_organisation_id,route.approval_role,site.outlet_id)) then raise exception 'The configured source approval role is required.' using errcode='42501'; end if;
  elsif not (private.pp_stock_manager(p_organisation_id) or private.pp_stock_role(p_organisation_id,'finance',null)) then raise exception 'Finance or Restaurant Administrator must approve stock adjustments, receipts and production.' using errcode='42501'; end if;
  if d.state<>'REQUESTED' then raise exception 'This request is no longer awaiting approval.' using errcode='22023'; end if;
  update public.stock_documents set state='APPROVED',approved_by=actor,approved_at=clock_timestamp(),decision_note=p_note where id=d.id;
 elsif p_action in ('POST','DISPATCH') then
  if d.state<>'APPROVED' then raise exception 'Refresh: this request must be approved and not already posted.' using errcode='22023'; end if;
  if not private.pp_stock_site(p_organisation_id,coalesce(d.source_id,d.destination_id),'inventory') then raise exception 'Inventory access is required at the source stock location.' using errcode='42501'; end if;
  if p_action='DISPATCH' and d.kind not in ('TRANSFER','ISSUE') or p_action='POST' and d.kind in ('TRANSFER','ISSUE') then raise exception 'Use dispatch for transfers/issues, or post for other stock records.' using errcode='22023'; end if;
  if exists(select 1 from public.stock_locations where organisation_id=p_organisation_id and id in(d.source_id,d.destination_id) and not is_active) then raise exception 'A stock location was deactivated.' using errcode='22023'; end if;
  if d.kind in ('TRANSFER','ISSUE') and not exists(select 1 from public.stock_routes where organisation_id=p_organisation_id and id=d.route_id and is_active) then raise exception 'This route is no longer active.' using errcode='22023'; end if;
  if d.kind='COUNT' and d.count_fingerprint<>private.pp_stock_fingerprint(p_organisation_id,d.source_id) then raise exception 'Stock changed after this count. Cancel and recount before posting.' using errcode='22023'; end if;
  if d.kind='OPENING' and exists(select 1 from public.stock_ledger e join jsonb_array_elements(d.lines) l on l->>'item_id'=e.item_id::text where e.organisation_id=p_organisation_id and e.location_id=d.destination_id) then raise exception 'Opening balances must be the first posting for each listed material at that stock location.' using errcode='22023'; end if;
  if d.kind='GRN' and (private.pp_receipt_voided(p_organisation_id,d.receipt_id) or exists(select 1 from public.goods_receipt_void_requests where organisation_id=p_organisation_id and receipt_id=d.receipt_id and state='PENDING')) then raise exception 'This GRN was voided or awaits a void decision. Cancel the stock request.' using errcode='22023'; end if;
  for line in select value from jsonb_array_elements(d.lines) loop
   item:=(line->>'item_id')::uuid;qty:=(line->>'quantity')::numeric;
   if d.kind='COUNT' then qty:=qty-private.pp_stock_balance(p_organisation_id,d.source_id,item);
   elsif d.source_id is not null then qty:=-qty; end if;
   perform private.pp_stock_entry(p_organisation_id,d.id,coalesce(d.source_id,d.destination_id),item,qty,d.document_date);
  end loop;
  if d.kind='PRODUCTION' then
   perform private.pp_stock_entry(p_organisation_id,d.id,d.source_id,(d.output->>'item_id')::uuid,(d.output->>'quantity')::numeric,d.document_date);
  end if;
  update public.stock_documents set state=case when p_action='DISPATCH' then 'DISPATCHED' else 'POSTED' end,
   dispatched_by=case when p_action='DISPATCH' then actor end,dispatched_at=case when p_action='DISPATCH' then clock_timestamp() end,
   completed_by=case when p_action='POST' then actor end,completed_at=case when p_action='POST' then clock_timestamp() end,decision_note=p_note where id=d.id;
 elsif p_action='RECEIVE' then
  if not private.pp_stock_site(p_organisation_id,d.destination_id,'inventory') or d.dispatched_by=actor then raise exception 'A different Inventory colleague with destination access must confirm receipt.' using errcode='42501'; end if;
  if d.state<>'DISPATCHED' then raise exception 'Only dispatched movements can be received.' using errcode='22023'; end if;
  if jsonb_typeof(p_received) is distinct from 'array' or jsonb_array_length(p_received)<>jsonb_array_length(d.lines) or octet_length(p_received::text)>65536 then raise exception 'Confirm every dispatched material exactly once.' using errcode='22023'; end if;
  for line in select value from jsonb_array_elements(d.lines) loop
   item:=(line->>'item_id')::uuid;qty:=(line->>'quantity')::numeric;
   if (select count(*) from jsonb_array_elements(p_received) r where r->>'item_id'=item::text)<>1 then raise exception 'Confirm every dispatched material exactly once.' using errcode='22023'; end if;
   select value into rec from jsonb_array_elements(p_received) where value->>'item_id'=item::text;
   accepted:=private.pp_stock_number(rec->>'quantity',true);
   if accepted>qty or (accepted<qty and length(trim(coalesce(rec->>'reason',''))) not between 1 and 500) then raise exception 'Received stock cannot exceed dispatched quantity; explain every shortage or damaged quantity.' using errcode='22023'; end if;
   perform private.pp_stock_entry(p_organisation_id,d.id,d.destination_id,item,accepted,greatest(d.document_date,(select(now() at time zone time_zone)::date from public.organisations where id=p_organisation_id)));
  end loop;
  update public.stock_documents set state='RECEIVED',received_lines=p_received,completed_by=actor,completed_at=clock_timestamp(),decision_note=p_note where id=d.id;
 else raise exception 'Choose an available stock action.' using errcode='22023'; end if;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'STOCK_'||p_action,actor,d.id,jsonb_build_object('note',p_note,'received',p_received));
 return d.id;
end $$;

-- A physical stock posting prevents Finance from invalidating its source GRN.
create function private.pp_stock_grn_void_guard() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.organisations where id=new.organisation_id for update;
 if new.state='APPROVED' and exists(select 1 from public.stock_documents where organisation_id=new.organisation_id and receipt_id=new.receipt_id and state='POSTED') then
  raise exception 'This GRN has posted stock. Retain the GRN and record a reviewed stock count/waste correction and the appropriate invoice correction.' using errcode='22023'; end if;
 return new;
end $$;
create trigger stock_grn_void_guard before insert or update on public.goods_receipt_void_requests for each row execute function private.pp_stock_grn_void_guard();

create function public.stock_workspace(p_organisation_id uuid,p_location_id uuid default null,p_page integer default 1) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_stock_read(p_organisation_id) then raise exception 'Stock access denied.' using errcode='42501'; end if;
 if p_page is null or p_page not between 1 and 100000 then raise exception 'Choose a valid page.' using errcode='22023'; end if;
 if p_location_id is not null and not private.pp_stock_site(p_organisation_id,p_location_id,'read') then raise exception 'Stock location unavailable.' using errcode='42501'; end if;
 select jsonb_build_object('manage',private.pp_stock_manager(p_organisation_id),
 'locations',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('read',private.pp_stock_site(p_organisation_id,s.id,'read'),'request',private.pp_stock_site(p_organisation_id,s.id,'request'),'inventory',private.pp_stock_site(p_organisation_id,s.id,'inventory'),'outlet_name',l.name) order by s.name) from public.stock_locations s left join public.locations l on l.organisation_id=s.organisation_id and l.id=s.outlet_id
  where s.organisation_id=p_organisation_id and (private.pp_stock_site(p_organisation_id,s.id,'read') or exists(select 1 from public.stock_routes r where r.organisation_id=s.organisation_id and r.is_active and r.source_id=s.id and private.pp_stock_site(p_organisation_id,r.destination_id,'request')))),'[]'::jsonb),
 'routes',coalesce((select jsonb_agg(to_jsonb(r) order by r.kind,r.id) from public.stock_routes r where r.organisation_id=p_organisation_id and (private.pp_stock_site(p_organisation_id,r.source_id,'read') or private.pp_stock_site(p_organisation_id,r.destination_id,'read'))),'[]'::jsonb),
 'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',i.name,'code',i.code,'unit',u.code,'item_type',i.item_type) order by i.name) from public.items i join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id where i.organisation_id=p_organisation_id and i.is_active and i.stock_tracked),'[]'::jsonb),
 'outlets',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.locations where organisation_id=p_organisation_id and is_active and private.pp_stock_manager(p_organisation_id)),'[]'::jsonb),
 'suppliers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.suppliers where organisation_id=p_organisation_id and is_active),'[]'::jsonb),
 'recipes',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'name',v.name,'version',v.version,'code',r.code,'yield',o.quantity::text,'unit',u.code,'item_id',b.item_id) order by r.code,v.version desc) from public.recipe_versions v join public.recipes r on r.organisation_id=v.organisation_id and r.id=v.recipe_id join public.recipe_outputs o on o.organisation_id=v.organisation_id and o.recipe_version_id=v.id join public.units_of_measure u on u.organisation_id=o.organisation_id and u.id=o.uom_id left join public.stock_recipe_bindings b on b.organisation_id=v.organisation_id and b.recipe_version_id=v.id where v.organisation_id=p_organisation_id),'[]'::jsonb),
 'grns',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'reference',g.reference,'outlet',l.name,'date',g.received_on) order by g.created_at desc) from public.goods_receipts g join public.purchase_orders po on po.organisation_id=g.organisation_id and po.id=g.order_id join public.locations l on l.organisation_id=po.organisation_id and l.id=po.location_id where g.organisation_id=p_organisation_id and private.pp_inventory_access(p_organisation_id,po.location_id) and not private.pp_receipt_voided(p_organisation_id,g.id) and not exists(select 1 from public.goods_receipt_void_requests where organisation_id=g.organisation_id and receipt_id=g.id and state='PENDING') and not exists(select 1 from public.stock_documents where organisation_id=g.organisation_id and receipt_id=g.id and state<>'CANCELLED')),'[]'::jsonb),
 'balances',coalesce((select jsonb_agg(jsonb_build_object('location_id',s.id,'location',s.name,'item_id',i.id,'name',i.name,'code',i.code,'unit',u.code,'quantity',q.qty::text) order by s.name,i.name) from (select location_id,item_id,sum(quantity) qty from public.stock_ledger where organisation_id=p_organisation_id group by location_id,item_id) q join public.stock_locations s on s.organisation_id=p_organisation_id and s.id=q.location_id join public.items i on i.organisation_id=p_organisation_id and i.id=q.item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id where private.pp_stock_site(p_organisation_id,s.id,'read') and (p_location_id is null or s.id=p_location_id)),'[]'::jsonb),
 'total',(select count(*) from public.stock_documents d where d.organisation_id=p_organisation_id and private.pp_stock_doc_read(p_organisation_id,d.id) and (p_location_id is null or d.source_id=p_location_id or d.destination_id=p_location_id)),
 'documents',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc,q.id) from (select d.*,s.name source_name,t.name destination_name,
   a.email created_label,b.email approved_label,c.email dispatched_label,e.email completed_label,
   jsonb_strip_nulls(jsonb_build_object('approve',case when d.state='REQUESTED' and d.created_by<>auth.uid() and (case when d.kind in ('TRANSFER','ISSUE') then private.pp_stock_manager(p_organisation_id) or private.pp_stock_role(p_organisation_id,r.approval_role,s.outlet_id) else private.pp_stock_manager(p_organisation_id) or private.pp_stock_role(p_organisation_id,'finance',null) end) then true end,
    'post',case when d.state='APPROVED' and d.kind not in ('TRANSFER','ISSUE') and private.pp_stock_site(p_organisation_id,coalesce(d.source_id,d.destination_id),'inventory') then true end,
    'dispatch',case when d.state='APPROVED' and d.kind in ('TRANSFER','ISSUE') and private.pp_stock_site(p_organisation_id,d.source_id,'inventory') then true end,
    'receive',case when d.state='DISPATCHED' and d.dispatched_by<>auth.uid() and private.pp_stock_site(p_organisation_id,d.destination_id,'inventory') then true end,
    'cancel',case when d.state in ('REQUESTED','APPROVED') and (d.created_by=auth.uid() or private.pp_stock_manager(p_organisation_id)) then true end)) actions
  from public.stock_documents d left join public.stock_locations s on s.organisation_id=d.organisation_id and s.id=d.source_id left join public.stock_locations t on t.organisation_id=d.organisation_id and t.id=d.destination_id left join public.stock_routes r on r.organisation_id=d.organisation_id and r.id=d.route_id
  left join auth.users a on a.id=d.created_by left join auth.users b on b.id=d.approved_by left join auth.users c on c.id=d.dispatched_by left join auth.users e on e.id=d.completed_by
  where d.organisation_id=p_organisation_id and private.pp_stock_doc_read(p_organisation_id,d.id) and (p_location_id is null or d.source_id=p_location_id or d.destination_id=p_location_id) order by d.created_at desc,d.id limit 25 offset (p_page-1)*25) q),'[]'::jsonb),
 'ledger',coalesce((select jsonb_agg(to_jsonb(q) order by q.id desc) from (select e.id,e.document_id,d.reference,s.name location,i.name material,u.code unit,e.quantity::text,e.occurred_on,e.created_at from public.stock_ledger e join public.stock_documents d on d.organisation_id=e.organisation_id and d.id=e.document_id join public.stock_locations s on s.organisation_id=e.organisation_id and s.id=e.location_id join public.items i on i.organisation_id=e.organisation_id and i.id=e.item_id join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id where e.organisation_id=p_organisation_id and private.pp_stock_site(p_organisation_id,e.location_id,'read') and (p_location_id is null or e.location_id=p_location_id) order by e.id desc limit 100) q),'[]'::jsonb)) into result;
 return result;
end $$;

-- Do not expose helpers with definer privileges through PostgREST.
do $$ declare f record; begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname like 'pp_stock_%' loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 end loop;
end $$;
revoke all on function public.save_stock_configuration(uuid,text,jsonb),public.request_stock_document(uuid,uuid,jsonb,jsonb),public.stock_document_action(uuid,uuid,text,text,jsonb),public.stock_workspace(uuid,uuid,integer) from public,anon;
grant execute on function public.save_stock_configuration(uuid,text,jsonb),public.request_stock_document(uuid,uuid,jsonb,jsonb),public.stock_document_action(uuid,uuid,text,text,jsonb),public.stock_workspace(uuid,uuid,integer) to authenticated;
create or replace function public.workspace_navigation_access(p_organisation_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('overview',private.pp_sales_read(p_organisation_id),'expenses',private.pp_sales_read(p_organisation_id),
 'sales',private.pp_sales_read(p_organisation_id),'purchases',private.pp_reference_price_read(p_organisation_id),
 'orders',private.pp_reference_price_read(p_organisation_id) or private.pp_inventory_access(p_organisation_id),'inventory',private.pp_stock_read(p_organisation_id),
 'menus',private.pp_reference_price_read(p_organisation_id),'recipes',private.pp_catalogue_read(p_organisation_id),
 'catalogue',private.pp_catalogue_read(p_organisation_id),'team',private.pp_team_manage(p_organisation_id));
$$;
notify pgrst,'reload schema';
commit;
