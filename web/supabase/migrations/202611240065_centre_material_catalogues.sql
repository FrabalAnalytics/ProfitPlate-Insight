-- Centre-specific selectable catalogues. Existing centres keep their prior catalogue
-- until a manager reviews it. New centres created by the current UI start empty.
begin;
create table private.centre_catalogues(organisation_id uuid not null,site_id uuid not null,revision integer not null default 0,restricted_from date not null,primary key(organisation_id,site_id),foreign key(organisation_id,site_id) references public.stock_locations(organisation_id,id));
create table private.centre_materials(organisation_id uuid not null,site_id uuid not null,item_id uuid not null,active boolean not null default true,primary key(organisation_id,site_id,item_id),foreign key(organisation_id,site_id) references public.stock_locations(organisation_id,id),foreign key(organisation_id,item_id) references public.items(organisation_id,id) on delete cascade);
create table private.centre_catalogue_history(organisation_id uuid not null,site_id uuid not null,revision integer not null,day date not null,items uuid[] not null,actor uuid not null,changed_at timestamptz not null default now(),primary key(organisation_id,site_id,revision));
create table private.centre_catalogue_requests(organisation_id uuid not null,request_id uuid not null,actor uuid not null,digest text not null,revision integer not null,primary key(organisation_id,request_id));
revoke all on private.centre_catalogues,private.centre_materials,private.centre_catalogue_history,private.centre_catalogue_requests from public,anon,authenticated;
create trigger active_restaurant_write before insert or update or delete on private.centre_catalogues for each row execute function private.pp_require_active_restaurant();
create trigger active_restaurant_write before insert or update or delete on private.centre_materials for each row execute function private.pp_require_active_restaurant();
create trigger active_restaurant_write before insert or update or delete on private.centre_catalogue_history for each row execute function private.pp_require_active_restaurant();
create trigger active_restaurant_write before insert or update or delete on private.centre_catalogue_requests for each row execute function private.pp_require_active_restaurant();

create function private.pp_centre_material(org uuid,site uuid,item uuid,day date default null) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.items i join public.stock_locations s on s.organisation_id=i.organisation_id and s.id=site left join private.centre_catalogues c on c.organisation_id=s.organisation_id and c.site_id=s.id where i.organisation_id=org and i.id=item and(i.location_id is null or s.outlet_id is null or i.location_id=s.outlet_id) and(c.site_id is null or(day is not null and day<c.restricted_from) or(day is null and exists(select 1 from private.centre_materials m where m.organisation_id=org and m.site_id=site and m.item_id=item and m.active)) or(day is not null and item=any(coalesce((select h.items from private.centre_catalogue_history h where h.organisation_id=org and h.site_id=site and h.day<=$4 order by h.revision desc limit 1),'{}'::uuid[])))));
$$;
revoke all on function private.pp_centre_material(uuid,uuid,uuid,date) from public,anon,authenticated;

create function public.centre_material_catalogue(p_organisation_id uuid,p_site_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;begin
 if not private.pp_stock_manager(p_organisation_id) or not exists(select 1 from public.stock_locations where organisation_id=p_organisation_id and id=p_site_id) then raise exception 'Centre administration access required.' using errcode='42501';end if;
 select jsonb_build_object('centre',s.name,'active',s.is_active,'revision',coalesce(c.revision,0),'legacy',c.site_id is null,'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',i.name,'code',i.code,'unit',u.code,'active',i.is_active,'assigned',private.pp_centre_material(p_organisation_id,s.id,i.id),'held',coalesce((select sum(e.quantity) from public.stock_ledger e where e.organisation_id=i.organisation_id and e.location_id=s.id and e.item_id=i.id),0)::text) order by i.name,i.code) from public.items i left join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id where i.organisation_id=s.organisation_id and i.stock_tracked and(i.location_id is null or s.outlet_id is null or i.location_id=s.outlet_id)),'[]'::jsonb)) into result from public.stock_locations s left join private.centre_catalogues c on c.organisation_id=s.organisation_id and c.site_id=s.id where s.organisation_id=p_organisation_id and s.id=p_site_id;
 return result;
end $$;

create function public.save_centre_materials(p_organisation_id uuid,p_site_id uuid,p_revision integer,p_request_id uuid,p_items jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare site public.stock_locations;cfg private.centre_catalogues;ids uuid[];n integer;day date;old private.centre_catalogue_requests;fingerprint text:=md5(jsonb_build_array(p_site_id,p_revision,p_items)::text);begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'Centre administration access required.' using errcode='42501';end if;
 perform 1 from public.organisations o where o.id=p_organisation_id for update;
 if p_request_id is null or p_revision is null or p_revision<0 or p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)>5000 then raise exception 'Choose a valid material list.' using errcode='22023';end if;
 select * into old from private.centre_catalogue_requests where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then if old.actor<>auth.uid() or old.digest<>fingerprint then raise exception 'Refresh before changing this material list.' using errcode='22023';end if;return old.revision;end if;
 select * into site from public.stock_locations where organisation_id=p_organisation_id and id=p_site_id for update;
 if not found or not site.is_active then raise exception 'Choose an active centre in this restaurant.' using errcode='22023';end if;
 select * into cfg from private.centre_catalogues where organisation_id=p_organisation_id and site_id=p_site_id;
 if p_revision<>coalesce(cfg.revision,0) then raise exception 'This list changed. Refresh and review the latest assignments.' using errcode='22023';end if;
 begin select coalesce(array_agg(distinct v::uuid),'{}'::uuid[]) into ids from jsonb_array_elements_text(p_items)v;exception when invalid_text_representation then raise exception 'Choose valid materials from this restaurant.' using errcode='22023';end;
 if exists(select 1 from unnest(ids)x where not exists(select 1 from public.items i where i.organisation_id=p_organisation_id and i.id=x and i.stock_tracked and(i.location_id is null or site.outlet_id is null or i.location_id=site.outlet_id))) then raise exception 'A selected material belongs to another restaurant or outlet, or is not stock tracked.' using errcode='22023';end if;
 if exists(select 1 from public.stock_ledger e where e.organisation_id=p_organisation_id and e.location_id=p_site_id and not(e.item_id=any(ids)) group by e.item_id having sum(e.quantity)<>0) then raise exception 'Materials with stock held here must remain assigned. Transfer or reconcile that stock first.' using errcode='22023';end if;
 if exists(select 1 from public.stock_documents d cross join lateral jsonb_array_elements(coalesce(d.lines,'[]'))l where d.organisation_id=p_organisation_id and(d.source_id=p_site_id or d.destination_id=p_site_id) and d.state not in('POSTED','RECEIVED','CANCELLED') and d.resolved_at is null and not((l->>'item_id')::uuid=any(ids))) or exists(select 1 from public.stock_documents d where d.organisation_id=p_organisation_id and d.source_id=p_site_id and d.kind='PRODUCTION' and d.state not in('POSTED','RECEIVED','CANCELLED','REJECTED') and d.resolved_at is null and nullif(d.output->>'item_id','') is not null and not((d.output->>'item_id')::uuid=any(ids))) or exists(select 1 from private.weekly_counts c join private.weekly_count_lines l on l.count_id=c.id where c.organisation_id=p_organisation_id and c.site_id=p_site_id and c.state in('DRAFT','SUBMITTED','APPROVED') and not(l.item_id=any(ids))) then raise exception 'Materials on unfinished movements or stock counts must remain assigned. Complete or cancel those records first.' using errcode='22023';end if;
 select (now() at time zone time_zone)::date into day from public.organisations o where o.id=p_organisation_id;
 n:=p_revision+1;
 insert into private.centre_catalogues values(p_organisation_id,p_site_id,n,day) on conflict(organisation_id,site_id) do update set revision=excluded.revision;
 update private.centre_materials set active=false where organisation_id=p_organisation_id and site_id=p_site_id and not(item_id=any(ids));
 insert into private.centre_materials select p_organisation_id,p_site_id,x,true from unnest(ids)x on conflict(organisation_id,site_id,item_id) do update set active=true;
 insert into private.centre_catalogue_history values(p_organisation_id,p_site_id,n,day,ids,auth.uid(),now());
 insert into private.centre_catalogue_requests values(p_organisation_id,p_request_id,auth.uid(),fingerprint,n);
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'centre.materials_assigned',auth.uid(),p_site_id,jsonb_build_object('revision',n,'material_ids',ids));
 return n;
end $$;

-- New UI centres deliberately start with an empty selectable catalogue. Legacy
-- integration calls keep their existing behaviour until reviewed by a manager.
alter function public.save_stock_centre(uuid,jsonb) rename to pp_save_centre_before_catalogue;
alter function public.pp_save_centre_before_catalogue(uuid,jsonb) set schema private;
revoke all on function private.pp_save_centre_before_catalogue(uuid,jsonb) from public,anon,authenticated;
create function public.save_stock_centre(p_organisation_id uuid,p_value jsonb) returns uuid language plpgsql security definer set search_path='' as $$declare id uuid;day date;begin
 id:=private.pp_save_centre_before_catalogue(p_organisation_id,p_value);
 if nullif(p_value->>'id','') is null and coalesce((p_value->>'restrict_materials')::boolean,false) then
 select (now() at time zone time_zone)::date into day from public.organisations o where o.id=p_organisation_id;
 insert into private.centre_catalogues values(p_organisation_id,id,0,day) on conflict do nothing;
 insert into private.centre_catalogue_history values(p_organisation_id,id,0,day,'{}',auth.uid(),now()) on conflict do nothing;
 end if;return id;
end $$;

-- Selection packets carry centre IDs; document and ledger history are unchanged.
alter function public.stock_workspace_v2(uuid,uuid,integer,text,text,uuid) rename to pp_stock_workspace_before_catalogues;
alter function public.pp_stock_workspace_before_catalogues(uuid,uuid,integer,text,text,uuid) set schema private;
revoke all on function private.pp_stock_workspace_before_catalogues(uuid,uuid,integer,text,text,uuid) from public,anon,authenticated;
create function public.stock_workspace_v2(p_organisation_id uuid,p_location_id uuid default null,p_page integer default 1,p_status text default 'ALL',p_search text default '',p_document_id uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;begin
 result:=private.pp_stock_workspace_before_catalogues(p_organisation_id,p_location_id,p_page,p_status,p_search,p_document_id);
 return result||jsonb_build_object('items',coalesce((select jsonb_agg(i||jsonb_build_object('centre_ids',a.sites) order by i->>'name',i->>'code') from jsonb_array_elements(result->'items')i cross join lateral(select coalesce(jsonb_agg(s->'id'),'[]'::jsonb) sites from jsonb_array_elements(result->'locations')s where private.pp_centre_material(p_organisation_id,(s->>'id')::uuid,(i->>'id')::uuid))a where jsonb_array_length(a.sites)>0),'[]'::jsonb));
end $$;

create function private.pp_assert_centre_material(org uuid,site uuid,item uuid) returns void language plpgsql security definer set search_path='' as $$begin
 if site is not null and item is not null and not private.pp_centre_material(org,site,item) then raise exception 'This material is not assigned to this centre. Ask the Administrator or Inventory Manager to update its material list.' using errcode='22023';end if;
end $$;
revoke all on function private.pp_assert_centre_material(uuid,uuid,uuid) from public,anon,authenticated;
create function private.pp_guard_centre_material_document() returns trigger language plpgsql security definer set search_path='' as $$declare l jsonb;begin
 perform 1 from public.organisations where id=new.organisation_id for share;
 if new.state in('CANCELLED','REJECTED') then return new;end if;
 if TG_OP='UPDATE' and new.state is not distinct from old.state and new.lines is not distinct from old.lines and new.source_id is not distinct from old.source_id and new.destination_id is not distinct from old.destination_id and new.output is not distinct from old.output then return new;end if;
 for l in select value from jsonb_array_elements(coalesce(new.lines,'[]'))loop
 perform private.pp_assert_centre_material(new.organisation_id,new.source_id,nullif(l->>'item_id','')::uuid);
 perform private.pp_assert_centre_material(new.organisation_id,new.destination_id,nullif(l->>'item_id','')::uuid);
 end loop;
 if new.kind='PRODUCTION' then perform private.pp_assert_centre_material(new.organisation_id,new.source_id,nullif(new.output->>'item_id','')::uuid);end if;
 return new;
end $$;
create trigger centre_material_document_guard before insert or update on public.stock_documents for each row execute function private.pp_guard_centre_material_document();
create function private.pp_guard_centre_material_ledger() returns trigger language plpgsql security definer set search_path='' as $$begin
 perform 1 from public.organisations where id=new.organisation_id for share;
 -- Approved count snapshots and late-sales reconciliation retain their original basis.
 if not exists(select 1 from public.stock_documents d where d.organisation_id=new.organisation_id and d.id=new.document_id and d.kind in('COUNT','SALES_RECONCILIATION')) then perform private.pp_assert_centre_material(new.organisation_id,new.location_id,new.item_id);end if;
 return new;
end $$;
create trigger centre_material_ledger_guard before insert on public.stock_ledger for each row execute function private.pp_guard_centre_material_ledger();
revoke all on function private.pp_guard_centre_material_document(),private.pp_guard_centre_material_ledger() from public,anon,authenticated;

-- Count populations use assignment history; saved count sheets stay immutable.
alter function private.pp_weekly_items(uuid,uuid,date) rename to pp_weekly_items_before_catalogues;
create function private.pp_weekly_items(org uuid,site uuid,day date) returns table(item_id uuid) language sql stable security definer set search_path='' as $$select i.item_id from private.pp_weekly_items_before_catalogues(org,site,day)i where private.pp_centre_material(org,site,i.item_id,day);$$;
alter function private.pp_monthly_items(uuid,uuid,date) rename to pp_monthly_items_before_catalogues;
create function private.pp_monthly_items(org uuid,site uuid,day date) returns table(item_id uuid) language sql stable security definer set search_path='' as $$select i.item_id from private.pp_monthly_items_before_catalogues(org,site,day)i where private.pp_centre_material(org,site,i.item_id,day) or exists(select 1 from public.stock_ledger e where e.organisation_id=org and e.location_id=site and e.item_id=i.item_id and e.occurred_on<=day group by e.item_id having sum(e.quantity)<>0);$$;
revoke all on function private.pp_weekly_items(uuid,uuid,date),private.pp_monthly_items(uuid,uuid,date) from public,anon,authenticated;

revoke all on function public.centre_material_catalogue(uuid,uuid),public.save_centre_materials(uuid,uuid,integer,uuid,jsonb),public.save_stock_centre(uuid,jsonb),public.stock_workspace_v2(uuid,uuid,integer,text,text,uuid) from public,anon;
grant execute on function public.centre_material_catalogue(uuid,uuid),public.save_centre_materials(uuid,uuid,integer,uuid,jsonb),public.save_stock_centre(uuid,jsonb),public.stock_workspace_v2(uuid,uuid,integer,text,text,uuid) to authenticated;

alter function private.pp_opening_ready(uuid,uuid,uuid) rename to pp_opening_ready_before_catalogues;
create function private.pp_opening_ready(org uuid,item uuid,site uuid) returns boolean language sql stable security definer set search_path='' as $$select not private.pp_centre_material(org,site,item) or private.pp_opening_ready_before_catalogues(org,item,site);$$;
revoke all on function private.pp_opening_ready(uuid,uuid,uuid) from public,anon,authenticated;
create or replace function public.opening_readiness(p_organisation_id uuid,p_page integer default 1) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;begin
 if not private.pp_stock_manager(p_organisation_id) then raise exception 'Inventory setup access required.' using errcode='42501';end if;
 if p_page is null or p_page not between 1 and 100000 then raise exception 'Choose a valid page.' using errcode='22023';end if;
 with required as materialized(select i.id item_id,i.name material,i.base_uom_id,s.id site_id,s.name site,private.pp_opening_ready(i.organisation_id,i.id,s.id) ready from public.items i join public.stock_locations s on s.organisation_id=i.organisation_id and s.is_active and(i.location_id is null or s.outlet_id is null or s.outlet_id=i.location_id) where i.organisation_id=p_organisation_id and i.is_active and i.stock_tracked and private.pp_centre_material(p_organisation_id,s.id,i.id)),paged as(select * from required order by ready,material,item_id,site,site_id limit 10 offset(p_page-1)*10)
 select jsonb_build_object('total',(select count(*) from required),'missing',(select count(*) from required where not ready),'rows',coalesce((select jsonb_agg(to_jsonb(p) order by ready,material,item_id,site,site_id) from paged p),'[]'::jsonb)) into result;return result;
end $$;

alter function public.setup_profiles(uuid,text,uuid[]) rename to pp_setup_profiles_before_catalogues;
alter function public.pp_setup_profiles_before_catalogues(uuid,text,uuid[]) set schema private;
revoke all on function private.pp_setup_profiles_before_catalogues(uuid,text,uuid[]) from public,anon,authenticated;
create function public.setup_profiles(p_organisation_id uuid,p_kind text,p_ids uuid[]) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;r record;begin
 result:=private.pp_setup_profiles_before_catalogues(p_organisation_id,p_kind,p_ids);
 if p_kind='MATERIAL' then for r in select i.id from public.items i where i.organisation_id=p_organisation_id and i.id=any(p_ids) and i.stock_tracked and not exists(select 1 from public.stock_locations s where s.organisation_id=i.organisation_id and s.is_active and private.pp_centre_material(i.organisation_id,s.id,i.id)) loop
 result:=jsonb_set(result,array[r.id::text,'missing'],coalesce(result->r.id::text->'missing','[]'::jsonb)||jsonb_build_array('Centre assignment'));
 end loop;end if;return result;
end $$;
revoke all on function public.setup_profiles(uuid,text,uuid[]) from public,anon;
grant execute on function public.setup_profiles(uuid,text,uuid[]) to authenticated;

create or replace function private.pp_material_usage(target_org uuid,target_item uuid)
returns text language plpgsql volatile security definer set search_path='' as $$
declare r record; used boolean; item_code text; legacy uuid;
begin
 select code,legacy_ingredient_id into item_code,legacy from public.items where organisation_id=target_org and id=target_item;
 if not found then return 'Material unavailable';end if;
 if legacy is not null then return 'Legacy material history';end if;
 for r in
  select distinct ns.nspname schema_name,cl.relname table_name,a.attname column_name
  from pg_catalog.pg_constraint c
  join pg_catalog.pg_class cl on cl.oid=c.conrelid
  join pg_catalog.pg_namespace ns on ns.oid=cl.relnamespace
  cross join lateral unnest(c.conkey,c.confkey) k(local_key,foreign_key)
  join pg_catalog.pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.local_key
  join pg_catalog.pg_attribute b on b.attrelid=c.confrelid and b.attnum=k.foreign_key
  where c.contype='f' and c.confrelid='public.items'::regclass and b.attname='id' and not(ns.nspname='private' and cl.relname='centre_materials')
 loop
  execute format('select exists(select 1 from %I.%I where %I=$1)',r.schema_name,r.table_name,r.column_name) into used using target_item;
  if used then return 'Linked recipes, prices, conversions or stock records';end if;
 end loop;
 for r in
  select c.table_schema,c.table_name,c.column_name from information_schema.columns c
  where c.table_schema in ('public','private') and c.data_type in ('json','jsonb')
   and c.table_name not in ('audit_events','items')
   and exists(select 1 from information_schema.columns o where o.table_schema=c.table_schema and o.table_name=c.table_name and o.column_name='organisation_id')
 loop
  execute format('select exists(select 1 from %I.%I where organisation_id=$1 and (position($2 in %I::text)>0 or position($3 in %I::text)>0))',r.table_schema,r.table_name,r.column_name,r.column_name)
   into used using target_org,to_jsonb(target_item::text)::text,to_jsonb(item_code)::text;
  if used then return 'Saved documents, imports or review history';end if;
 end loop;
 return null;
end $$;


alter function public.weekly_count_scope(uuid,uuid) rename to pp_weekly_scope_before_catalogues;
alter function public.pp_weekly_scope_before_catalogues(uuid,uuid) set schema private;
revoke all on function private.pp_weekly_scope_before_catalogues(uuid,uuid) from public,anon,authenticated;
create function public.weekly_count_scope(p_organisation_id uuid,p_site_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare r jsonb;begin
 r:=private.pp_weekly_scope_before_catalogues(p_organisation_id,p_site_id);
 return r||jsonb_build_object('items',coalesce((select jsonb_agg(i) from jsonb_array_elements(r->'items')i where private.pp_centre_material(p_organisation_id,p_site_id,(i->>'id')::uuid)),'[]'::jsonb));
end $$;
revoke all on function public.weekly_count_scope(uuid,uuid) from public,anon;
grant execute on function public.weekly_count_scope(uuid,uuid) to authenticated;

notify pgrst,'reload schema';
commit;
