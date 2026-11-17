-- Apply ONCE after 005. Optional reference estimates; no purchases, stock or costing policy.
begin;

create function private.pp_reference_price_read(target_org uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisation_memberships m join public.membership_roles r
 on r.organisation_id=m.organisation_id and r.membership_id=m.id
 where m.organisation_id=target_org and m.user_id=(select auth.uid()) and m.status='active'
 and r.location_id is null and r.role_code in ('ceo','finance','procurement','restaurant_admin'));
$$;
revoke all on function private.pp_reference_price_read(uuid) from public,anon;
grant execute on function private.pp_reference_price_read(uuid) to authenticated;

create function public.reference_price_access(p_organisation_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('read',private.pp_reference_price_read(p_organisation_id),
 'write',private.pp_catalogue_write(p_organisation_id));
$$;

create table public.material_reference_price_batches (
 id uuid primary key default gen_random_uuid(),
 organisation_id uuid not null references public.organisations(id),
 request_id uuid not null, input_hash text not null,
 source text not null check(source in ('MANUAL','CSV')),
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 unique(organisation_id,id), unique(organisation_id,request_id)
);
create table public.material_reference_prices (
 id uuid primary key default gen_random_uuid(),
 organisation_id uuid not null references public.organisations(id),
 batch_id uuid not null, item_id uuid not null,
 version integer not null check(version>0),
 quantity numeric(20,6) not null check(quantity>0),
 uom_id uuid not null, base_uom_id uuid not null,
 conversion_id uuid, conversion_factor numeric(38,12) not null check(conversion_factor>0),
 base_quantity numeric(38,12) not null check(base_quantity>0),
 total_price numeric(20,6) not null check(total_price>0),
 cost_per_base_unit numeric(38,12) not null check(cost_per_base_unit>0),
 currency_code text not null check(currency_code ~ '^[A-Z]{3}$'),
 price_date date not null,
 source_note text not null check(length(trim(source_note)) between 1 and 300),
 cost_state text not null default 'ESTIMATED' check(cost_state='ESTIMATED'),
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 unique(organisation_id,id), unique(organisation_id,item_id,version),
 foreign key(organisation_id,batch_id) references public.material_reference_price_batches(organisation_id,id),
 foreign key(organisation_id,item_id) references public.items(organisation_id,id),
 foreign key(organisation_id,uom_id) references public.units_of_measure(organisation_id,id),
 foreign key(organisation_id,base_uom_id) references public.units_of_measure(organisation_id,id),
 foreign key(organisation_id,conversion_id) references public.item_uom_conversions(organisation_id,id)
);
create index pp_reference_price_latest_idx on public.material_reference_prices(organisation_id,item_id,price_date desc,version desc);
do $$ declare t text; begin
 foreach t in array array['material_reference_price_batches','material_reference_prices'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('create policy reference_price_read on public.%I for select to authenticated using(private.pp_reference_price_read(organisation_id))',t);
 end loop;
end; $$;

-- Preview and commit share this validator. JSON numeric strings preserve decimal precision.
create function public.preview_material_reference_prices(p_organisation_id uuid,p_rows jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r jsonb; material public.items%rowtype; source_unit public.units_of_measure%rowtype;
 base_unit public.units_of_measure%rowtype; org public.organisations%rowtype;
 conversion public.item_uom_conversions%rowtype; factor numeric; qty numeric; amount numeric;
 normalized numeric; unit_cost numeric; day date; output jsonb:='[]'; seen text[]:='{}'; key text; n integer:=0;
begin
 if not private.pp_catalogue_write(p_organisation_id) then raise exception 'Reference price access denied.' using errcode='42501'; end if;
 if jsonb_typeof(p_rows) is distinct from 'array' then raise exception 'Supply a list of prices.' using errcode='22023'; end if;
 if jsonb_array_length(p_rows) not between 1 and 100 then raise exception 'Include between 1 and 100 price rows.' using errcode='22023'; end if;
 select * into org from public.organisations where id=p_organisation_id;
 for r in select value from jsonb_array_elements(p_rows) loop
  n:=n+1;
  if coalesce(r->>'quantity','') !~ '^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$'
   or coalesce(r->>'total_price','') !~ '^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$'
   then raise exception 'Row %: use positive quantities and prices, up to six decimal places, without commas.',n using errcode='22023'; end if;
  qty:=(r->>'quantity')::numeric; amount:=(r->>'total_price')::numeric;
  if qty<=0 or amount<=0 then raise exception 'Row %: quantity and price must be positive. Leave unpriced materials out.',n using errcode='22023'; end if;
  if coalesce(r->>'price_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Row %: use a date in YYYY-MM-DD format.',n using errcode='22023'; end if;
  begin day:=(r->>'price_date')::date;
  exception when datetime_field_overflow or invalid_datetime_format then raise exception 'Row %: the price date is invalid.',n using errcode='22023'; end;
  if day>(now() at time zone org.time_zone)::date then raise exception 'Row %: a reference price cannot be dated in the future.',n using errcode='22023'; end if;
  if length(trim(coalesce(r->>'source_note',''))) not between 1 and 300 then raise exception 'Row %: provide a source note of 1 to 300 characters.',n using errcode='22023'; end if;
  select * into material from public.items where organisation_id=p_organisation_id and code=r->>'material_code' and is_active;
  if not found then raise exception 'Row %: material code is unknown or inactive in this business.',n using errcode='22023'; end if;
  key:=material.id::text||':'||day::text;
  if key=any(seen) then raise exception 'Row %: the material and price date appear more than once.',n using errcode='22023'; end if;
  seen:=array_append(seen,key);
  select * into source_unit from public.units_of_measure where organisation_id=p_organisation_id and code=r->>'unit_code';
  if not found then raise exception 'Row %: unit code is unknown in this business.',n using errcode='22023'; end if;
  select * into base_unit from public.units_of_measure where organisation_id=p_organisation_id and id=material.base_uom_id;
  conversion:=null;
  if source_unit.dimension='PACKAGE' then
   select * into conversion from public.item_uom_conversions where organisation_id=p_organisation_id
    and item_id=material.id and from_uom_id=source_unit.id and effective_from<=day order by effective_from desc limit 1;
   if not found then raise exception 'Row %: add a package conversion effective on or before the price date, or enter the quantity in the base unit.',n using errcode='22023'; end if;
   factor:=conversion.factor;
  elsif source_unit.dimension=base_unit.dimension then factor:=source_unit.canonical_factor/base_unit.canonical_factor;
  else raise exception 'Row %: the unit does not match the material dimension.',n using errcode='22023'; end if;
  normalized:=round(qty*factor,12); unit_cost:=round(amount/nullif(normalized,0),12);
  if normalized<=0 or normalized>=1e26 or unit_cost is null or unit_cost<=0 or unit_cost>=1e26 then
   raise exception 'Row %: the converted quantity or price exceeds supported precision.',n using errcode='22023'; end if;
  output:=output||jsonb_build_array(jsonb_build_object('item_id',material.id,'name',material.name,'material_code',material.code,
   'quantity',qty::text,'uom_id',source_unit.id,'unit_code',source_unit.code,'base_uom_id',base_unit.id,'base_unit_code',base_unit.code,
   'conversion_id',conversion.id,'conversion_factor',factor::text,'base_quantity',normalized::text,
   'total_price',amount::text,'cost_per_base_unit',unit_cost::text,'currency_code',org.currency_code,
   'price_date',day,'source_note',trim(r->>'source_note'),'cost_state','ESTIMATED'));
 end loop;
 return output;
end; $$;

create function public.save_material_reference_prices(p_organisation_id uuid,p_request_id uuid,p_source text,p_rows jsonb,p_preview jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare previous public.material_reference_price_batches%rowtype; batch uuid; digest text; prepared jsonb; r jsonb; next_version integer;
begin
 if not private.pp_catalogue_write(p_organisation_id) then raise exception 'Reference price access denied.' using errcode='42501'; end if;
 if p_request_id is null or p_source is null or p_source not in ('MANUAL','CSV') then raise exception 'Invalid save request.' using errcode='22023'; end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 digest:=md5(jsonb_build_array(p_source,p_rows)::text);
 select * into previous from public.material_reference_price_batches where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then
  if previous.input_hash<>digest then raise exception 'This save request has already been used. Refresh before saving different details.' using errcode='22023'; end if;
  return previous.id;
 end if;
 prepared:=public.preview_material_reference_prices(p_organisation_id,p_rows);
 if p_preview is distinct from prepared then raise exception 'The material or conversion details changed. Review your prices again before saving.' using errcode='22023'; end if;
 insert into public.material_reference_price_batches(organisation_id,request_id,input_hash,source,created_by)
 values(p_organisation_id,p_request_id,digest,p_source,auth.uid()) returning id into batch;
 for r in select value from jsonb_array_elements(prepared) loop
  select coalesce(max(version),0)+1 into next_version from public.material_reference_prices where organisation_id=p_organisation_id and item_id=(r->>'item_id')::uuid;
  insert into public.material_reference_prices(organisation_id,batch_id,item_id,version,quantity,uom_id,base_uom_id,
   conversion_id,conversion_factor,base_quantity,total_price,cost_per_base_unit,currency_code,price_date,source_note,created_by)
  values(p_organisation_id,batch,(r->>'item_id')::uuid,next_version,(r->>'quantity')::numeric,(r->>'uom_id')::uuid,
   (r->>'base_uom_id')::uuid,(r->>'conversion_id')::uuid,(r->>'conversion_factor')::numeric,(r->>'base_quantity')::numeric,
   (r->>'total_price')::numeric,(r->>'cost_per_base_unit')::numeric,r->>'currency_code',(r->>'price_date')::date,r->>'source_note',auth.uid());
 end loop;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details)
 values(p_organisation_id,'reference_prices.saved',auth.uid(),batch,jsonb_build_object('source',p_source,'rows',jsonb_array_length(prepared),'cost_state','ESTIMATED'));
 return batch;
end; $$;

create function public.list_material_reference_prices(p_organisation_id uuid,p_search text,p_page integer,p_item_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; history jsonb; today date;
begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Reference price access denied.' using errcode='42501'; end if;
 if p_page is null or p_page not between 1 and 100000 or p_search is null or length(p_search)>80 then raise exception 'Invalid search.' using errcode='22023'; end if;
 select (now() at time zone time_zone)::date into today from public.organisations where id=p_organisation_id;
 with matches as (
  select i.id,i.code,i.name,i.base_uom_id,u.code as base_unit_code,i.is_active from public.items i
  join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id
  where i.organisation_id=p_organisation_id and (p_item_id is null or i.id=p_item_id)
  and (p_search='' or strpos(lower(i.name),lower(p_search))>0 or strpos(lower(i.code),lower(p_search))>0)
 ), page as (select * from matches order by name,id limit 25 offset (p_page-1)*25)
 select jsonb_build_object('total',(select count(*) from matches),'items',coalesce((select jsonb_agg(jsonb_build_object(
  'id',i.id,'code',i.code,'name',i.name,'base_uom_id',i.base_uom_id,'base_unit_code',i.base_unit_code,'is_active',i.is_active,
  'latest',case when price.id is null then null else jsonb_build_object('cost_per_base_unit',price.cost_per_base_unit::text,
   'currency_code',price.currency_code,'price_date',price.price_date,'source_note',price.source_note,'version',price.version,'cost_state','ESTIMATED') end) order by i.name,i.id)
  from page i left join lateral(select * from public.material_reference_prices p where p.organisation_id=p_organisation_id
   and p.item_id=i.id and p.price_date<=today order by p.price_date desc,p.version desc limit 1) price on true),'[]'::jsonb),
  'active_materials',(select count(*) from public.items where organisation_id=p_organisation_id and is_active),
  'priced_materials',(select count(*) from public.items i where i.organisation_id=p_organisation_id and i.is_active and exists(
   select 1 from public.material_reference_prices p where p.organisation_id=p_organisation_id and p.item_id=i.id and p.price_date<=today))) into result;
 select coalesce(jsonb_agg(to_jsonb(h) order by h.version desc),'[]') into history from (
  select p.version,p.quantity::text,u.code as unit_code,p.base_quantity::text,p.total_price::text,p.cost_per_base_unit::text,
   p.currency_code,p.price_date,p.source_note,p.created_at,b.source
  from public.material_reference_prices p join public.units_of_measure u on u.organisation_id=p.organisation_id and u.id=p.uom_id
  join public.material_reference_price_batches b on b.organisation_id=p.organisation_id and b.id=p.batch_id
  where p.organisation_id=p_organisation_id and p.item_id=p_item_id order by p.version desc limit 25
 ) h;
 return result||jsonb_build_object('history',history);
end; $$;

create function public.material_reference_price_coverage(p_organisation_id uuid,p_item_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_reference_price_read(p_organisation_id) then raise exception 'Reference price access denied.' using errcode='42501'; end if;
 if p_item_ids is null or cardinality(p_item_ids)>25 then raise exception 'Supply up to 25 material IDs.' using errcode='22023'; end if;
 select coalesce(jsonb_object_agg(i.id::text,exists(select 1 from public.material_reference_prices p
  join public.organisations o on o.id=p.organisation_id where p.organisation_id=p_organisation_id and p.item_id=i.id
  and p.price_date<=(now() at time zone o.time_zone)::date)),'{}') into result
 from public.items i where i.organisation_id=p_organisation_id and i.id=any(p_item_ids);
 return result;
end; $$;

revoke all on function public.material_reference_price_coverage(uuid,uuid[]) from public,anon;
grant execute on function public.material_reference_price_coverage(uuid,uuid[]) to authenticated;
revoke all on function public.reference_price_access(uuid) from public,anon;
revoke all on function public.preview_material_reference_prices(uuid,jsonb) from public,anon;
revoke all on function public.save_material_reference_prices(uuid,uuid,text,jsonb,jsonb) from public,anon;
revoke all on function public.list_material_reference_prices(uuid,text,integer,uuid) from public,anon;
grant execute on function public.reference_price_access(uuid) to authenticated;
grant execute on function public.preview_material_reference_prices(uuid,jsonb) to authenticated;
grant execute on function public.save_material_reference_prices(uuid,uuid,text,jsonb,jsonb) to authenticated;
grant execute on function public.list_material_reference_prices(uuid,text,integer,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
