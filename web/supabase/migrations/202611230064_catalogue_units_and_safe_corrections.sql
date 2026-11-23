-- Safe catalogue corrections and tenant-owned unit creation. No stock is rewritten.
begin;

-- Check relational references and embedded document/import/snapshot evidence.
-- Conservative: even draft/cancelled documents retain the unit basis they captured.
create function private.pp_material_usage(target_org uuid,target_item uuid)
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
  where c.contype='f' and c.confrelid='public.items'::regclass and b.attname='id'
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
revoke all on function private.pp_material_usage(uuid,uuid) from public,anon,authenticated;

create function public.material_editability(p_organisation_id uuid,p_item_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare reason text;
begin
 if not private.pp_catalogue_write(p_organisation_id) or not exists(select 1 from public.items where organisation_id=p_organisation_id and id=p_item_id) then raise exception 'Catalogue access denied.' using errcode='42501';end if;
 reason:=private.pp_material_usage(p_organisation_id,p_item_id);
 return jsonb_build_object('can_change_unit',reason is null,'can_delete',reason is null,'reason',reason);
end $$;

create or replace function public.save_catalogue_material(
  p_organisation_id uuid,p_id uuid,p_code text,p_name text,p_item_type text,
  p_category text,p_base_uom_id uuid,p_stock_tracked boolean,p_is_active boolean
) returns uuid language plpgsql security definer set search_path = '' as $$
declare result_id uuid; v_category_id uuid; previous public.items%rowtype; u public.units_of_measure%rowtype;
begin
  if not private.pp_catalogue_write(p_organisation_id) then raise exception 'Catalogue access denied.' using errcode='42501'; end if;
  if p_code is null or p_code !~ '^[A-Z0-9][A-Z0-9_-]{0,39}$' or length(trim(p_name)) not between 1 and 120
    or length(p_category)>60 or p_item_type not in ('RAW','PACKAGING','RESALE','CONSUMABLE','SEMI_FINISHED','FINISHED','GENERAL')
    then raise exception 'Check your material details.' using errcode='22023'; end if;
  select * into u from public.units_of_measure where organisation_id=p_organisation_id and id=p_base_uom_id;
  if p_base_uom_id is not null and (u.id is null or u.dimension='PACKAGE') then raise exception 'Choose a measurable base unit.' using errcode='22023'; end if;
  perform 1 from public.organisations where id=p_organisation_id for update;
  if p_id is not null then
    select * into previous from public.items where organisation_id=p_organisation_id and id=p_id for update;
    if not found then raise exception 'Material not available.' using errcode='42501'; end if;
    if previous.code<>p_code then raise exception 'Material codes stay fixed. Create a replacement material if needed.' using errcode='22023'; end if;
    if previous.base_uom_id is distinct from p_base_uom_id and private.pp_material_usage(p_organisation_id,p_id) is not null then
      raise exception 'This material is already used in recipes, prices, conversions or stock records. Its base unit must stay unchanged. Deactivate it and create a replacement if needed.' using errcode='22023';
    end if;
  end if;
  if nullif(trim(p_category),'') is not null then
    insert into public.item_categories(organisation_id,name,created_by) values(p_organisation_id,trim(p_category),auth.uid())
      on conflict(organisation_id,lower(name)) do update set name=public.item_categories.name
      returning id into v_category_id;
  end if;
  if p_id is null then
    insert into public.items(organisation_id,code,name,item_type,category_id,base_uom_id,stock_tracked,is_active,created_by)
      values(p_organisation_id,p_code,trim(p_name),p_item_type,v_category_id,p_base_uom_id,p_stock_tracked,p_is_active,auth.uid()) returning id into result_id;
  else
    update public.items set base_uom_id=p_base_uom_id,name=trim(p_name),item_type=p_item_type,category_id=v_category_id,
      stock_tracked=p_stock_tracked,is_active=p_is_active,updated_at=now()
      where organisation_id=p_organisation_id and id=p_id returning id into result_id;
  end if;
  insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details)
    values(p_organisation_id,case when p_id is null then 'material.created' else 'material.updated' end,auth.uid(),result_id,
      jsonb_build_object('code',p_code,'is_active',p_is_active,'previous',case when p_id is null then null else to_jsonb(previous) end));
  return result_id;
end; $$;

create function public.delete_unused_material(p_organisation_id uuid,p_item_id uuid,p_code text)
returns void language plpgsql security definer set search_path='' as $$
declare old public.items%rowtype;
begin
 if not private.pp_catalogue_write(p_organisation_id) then raise exception 'Catalogue access denied.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into old from public.items where organisation_id=p_organisation_id and id=p_item_id for update;
 if not found then raise exception 'Material no longer available. Refresh the catalogue.' using errcode='22023';end if;
 if p_code is distinct from old.code then raise exception 'Enter the material code to confirm deletion.' using errcode='22023';end if;
 if private.pp_material_usage(p_organisation_id,p_item_id) is not null then raise exception 'This material has linked records and cannot be deleted. Mark it inactive to preserve its history.' using errcode='22023';end if;
 delete from public.items where organisation_id=p_organisation_id and id=p_item_id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'material.deleted',auth.uid(),p_item_id,jsonb_build_object('previous',to_jsonb(old)));
end $$;

create function public.create_catalogue_unit(p_organisation_id uuid,p_code text,p_name text,p_dimension text,p_factor text)
returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid;factor numeric;unit_code text:=upper(trim(p_code));unit_name text:=trim(p_name);
begin
 if not private.pp_catalogue_write(p_organisation_id) then raise exception 'Catalogue access denied.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if unit_code is null or unit_code !~ '^[A-Z0-9][A-Z0-9_-]{0,39}$' or unit_name is null or length(unit_name) not between 1 and 80 or p_dimension is null or p_dimension not in ('MASS','VOLUME','COUNT','PACKAGE') then raise exception 'Enter a valid unit code, name and measurement type.' using errcode='22023';end if;
 if p_dimension='PACKAGE' then
  if nullif(trim(p_factor),'') is not null then raise exception 'Package sizes must be configured per material.' using errcode='22023';end if;
 else
  if p_factor is null or p_factor !~ '^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' then raise exception 'Enter a positive factor with up to six decimal places.' using errcode='22023';end if;
  factor:=p_factor::numeric;
  if factor<=0 then raise exception 'The factor must be greater than zero.' using errcode='22023';end if;
 end if;
 -- Repeated identical submissions return the same unit; existing definitions never change.
 select id into result_id from public.units_of_measure where organisation_id=p_organisation_id and code=unit_code and name=unit_name and dimension=p_dimension and canonical_factor is not distinct from factor;
 if found then return result_id;end if;
 insert into public.units_of_measure(organisation_id,code,name,dimension,canonical_factor) values(p_organisation_id,unit_code,unit_name,p_dimension,factor) returning id into result_id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'unit.created',auth.uid(),result_id,jsonb_build_object('code',unit_code,'name',unit_name,'dimension',p_dimension,'canonical_factor',factor));
 return result_id;
end $$;

revoke all on function public.material_editability(uuid,uuid),public.delete_unused_material(uuid,uuid,text),public.create_catalogue_unit(uuid,text,text,text,text) from public,anon;
grant execute on function public.material_editability(uuid,uuid),public.delete_unused_material(uuid,uuid,text),public.create_catalogue_unit(uuid,text,text,text,text) to authenticated;
notify pgrst,'reload schema';
commit;
