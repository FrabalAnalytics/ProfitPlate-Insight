-- Name-first POS imports retain dated menu identities and the existing financial/stock controls.
begin;
create table private.sales_menu_name_matches(
 organisation_id uuid not null,source_system text not null check(length(source_system) between 1 and 60),
 location_id uuid not null,source_name_key text not null check(length(source_name_key) between 1 and 200),
 effective_from date not null,source_name text not null,menu_item_id uuid not null,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 primary key(organisation_id,source_system,location_id,source_name_key,effective_from),
 foreign key(organisation_id,location_id) references public.locations(organisation_id,id),
 foreign key(organisation_id,menu_item_id) references public.menu_items(organisation_id,id)
);
revoke all on private.sales_menu_name_matches from public,anon,authenticated;
create trigger restaurant_active_write before insert or update or delete on private.sales_menu_name_matches for each row execute function private.pp_require_active_restaurant();
create function private.pp_sales_name(value text) returns text language sql immutable set search_path='' as $$select lower(regexp_replace(trim(value),'[[:space:]]+',' ','g'));$$;

-- Preserve the source header/name. Both contracts contain the same other fifteen columns.
do $$declare definition text;updated text;begin
 definition:=pg_get_functiondef('private.pp_sales_csv(text)'::regprocedure);
 updated:=replace(definition,$old$if cells<>headers then raise exception 'Use the exact Sales_Import template headers and order.' using errcode='22023'; end if;$old$,
 $new$if cardinality(cells)=16 and cells[7]='Menu_Name' then headers[7]:='Menu_Name';end if;
 if cells<>headers then raise exception 'Use the Sales_Import template headers and order: Menu_Name is recommended; the earlier Menu_Code format remains supported.' using errcode='22023';end if;$new$);
 if updated=definition then raise exception 'Expected sales CSV header guard missing';end if;execute updated;
end $$;

create function private.pp_resolve_sales_menu(org uuid,site uuid,day date,source jsonb,row_number integer,maps jsonb,all_rows jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare label text:=coalesce(source->>'Menu_Name',source->>'Menu_Code');by_name boolean:=source?'Menu_Name';chosen text;choices integer;item uuid;basis text;location_code text;previous public.sales_lines;candidate record;n integer;
begin
 if length(trim(coalesce(label,''))) not between 1 and 200 then raise exception 'Enter the POS menu name (up to 200 characters), or use the earlier Menu_Code template.' using errcode='22023';end if;
 select code into location_code from public.locations where organisation_id=org and id=site;
 -- Apply one explicit choice to the same POS label/outlet/sales-day group, including repeated receipt lines.
 select count(distinct choice),min(choice) into choices,chosen from(
  select coalesce(nullif(maps->'menu_rows'->>a.ordinality::text,''),nullif(maps->'menu_items'->>coalesce(a.value->>'Menu_Name',a.value->>'Menu_Code'),'')) choice
  from jsonb_array_elements(all_rows) with ordinality a
  where a.value->>'Source_System'=source->>'Source_System' and a.value->>'Sale_Date'=source->>'Sale_Date'
  and coalesce(nullif(maps->'locations'->>(a.value->>'Location_Code'),''),a.value->>'Location_Code')=location_code
  and case when by_name then private.pp_sales_name(a.value->>'Menu_Name')=private.pp_sales_name(label) else a.value->>'Menu_Code'=label end
 )q where choice is not null;
 if choices>1 then raise exception 'Choose one selling menu for the same POS name, outlet and sales date.' using errcode='22023';end if;
 if chosen is not null then
  select id into item from public.menu_items m where m.organisation_id=org and m.code=chosen and m.brand_id=(select brand_id from public.locations where id=site) and(m.location_id is null or m.location_id=site);
  if item is null then raise exception 'The selected selling menu is unavailable at this outlet. Choose a menu from the list.' using errcode='22023';end if;
  basis:='Selected during review';
 elsif by_name then
  -- Economic replays keep their recorded menu identity, even after a POS alias or menu name changes.
  select l.* into previous from public.sales_lines l join public.sales_headers h on h.organisation_id=l.organisation_id and h.id=l.sale_id
   where l.organisation_id=org and h.location_id=site and h.source_system=source->>'Source_System' and h.transaction_ref=source->>'Transaction_Ref' and l.line_ref=source->>'Line_Ref'
   and private.pp_sales_name(l.source_input->>'Menu_Name')=private.pp_sales_name(label);
  if previous.id is not null then item:=previous.menu_item_id;basis:='Recorded receipt';
  else
   select menu_item_id into item from private.sales_menu_name_matches where organisation_id=org and source_system=source->>'Source_System' and location_id=site and source_name_key=private.pp_sales_name(label) and effective_from<=day order by effective_from desc limit 1;
   if item is not null then basis:='Saved POS match';
   else
    select count(*),min(id::text)::uuid into n,item from(
     select m.id from public.menu_items m join lateral(select v.name from public.menu_item_versions v where v.organisation_id=m.organisation_id and v.menu_item_id=m.id and v.effective_from<=day order by v.effective_from desc,v.version desc limit 1)v on true
     where m.organisation_id=org and m.brand_id=(select brand_id from public.locations where id=site) and(m.location_id is null or m.location_id=site) and private.pp_sales_name(v.name)=private.pp_sales_name(label)
    )m;
    if n=0 then raise exception 'No matching menu name at this outlet on the sales date. Choose the selling menu during review.' using errcode='22023';end if;
    if n>1 then raise exception 'More than one selling menu has this name. Choose the correct recipe and centre during review.' using errcode='22023';end if;
    basis:='Name matched';
   end if;
  end if;
 else
  select id into item from public.menu_items m where m.organisation_id=org and m.code=label and m.brand_id=(select brand_id from public.locations where id=site) and(m.location_id is null or m.location_id=site);
  if item is null then raise exception 'Unknown menu code or menu brand does not match this location: %. Choose an existing recipe-linked menu.',label using errcode='22023';end if;
  basis:='Code matched';
 end if;
 if not exists(select 1 from public.menu_items m where m.organisation_id=org and m.id=item and m.brand_id=(select brand_id from public.locations where id=site) and(m.location_id is null or m.location_id=site)) then raise exception 'The saved POS match is unavailable at this outlet. Choose its selling menu again.' using errcode='22023';end if;
 if not exists(select 1 from public.menu_item_versions where organisation_id=org and menu_item_id=item and effective_from<=day) then raise exception 'No saved menu version is effective on the sale date. Review the menu setup and dates.' using errcode='22023';end if;
 select m.code,m.name into candidate from public.menu_items m where m.id=item;
 return jsonb_build_object('id',item,'code',candidate.code,'basis',basis);
end $$;

-- Extend the authoritative validator in place, preserving its configured-channel and receipt checks.
do $$declare definition text;updated text;begin
 definition:=replace(pg_get_functiondef('private.pp_validate_sales_csv(uuid,text,text,text,text,jsonb)'::regprocedure),chr(13),'');
 updated:=replace(definition,'declare input_rows jsonb;', 'declare resolution jsonb;stock_mapping jsonb;input_rows jsonb;');
 updated:=replace(updated,$old$select * into org from public.organisations where id=p_org;$old$,$new$
 if p_maps?'menu_rows' then
  if jsonb_typeof(p_maps->'menu_rows') is distinct from 'object' then raise exception 'Menu row matches must be an object.' using errcode='22023';end if;
  if (select count(*) from jsonb_object_keys(p_maps->'menu_rows'))>100 or exists(select 1 from jsonb_each(p_maps->'menu_rows')x where x.key!~'^(?:[1-9][0-9]?|100)$' or jsonb_typeof(x.value)<>'string' or length(trim(x.value#>>'{}')) not between 1 and 40) then raise exception 'Choose valid selling menus for at most 100 sales rows.' using errcode='22023';end if;
 end if;
 select * into org from public.organisations where id=p_org;$new$);
 updated:=replace(updated,replace($old$select * into menu from public.menu_items where organisation_id=p_org and code=menu_code and brand_id=loc.brand_id;
   if not found then raise exception 'Unknown menu code or menu brand does not match this location: %. Map to an existing recipe-linked menu.',r->>'Menu_Code' using errcode='22023'; end if;$old$,chr(13),''),
 $new$resolution:=private.pp_resolve_sales_menu(p_org,loc.id,day,r,n,p_maps,input_rows);
   select * into menu from public.menu_items where organisation_id=p_org and id=(resolution->>'id')::uuid;
   select jsonb_build_object('centre',s.name,'mode',m.mode,'mapping_id',m.id) into stock_mapping from private.menu_stock_mappings m join public.stock_locations s on s.organisation_id=m.organisation_id and s.id=m.site_id where m.organisation_id=p_org and m.menu_id=menu.id and m.outlet_id=loc.id and m.effective_from<=day order by m.effective_from desc,m.version desc limit 1;$new$);
 if updated=definition or position('pp_resolve_sales_menu' in updated)=0 then raise exception 'Expected sales menu resolution block missing';end if;
 updated:=replace(updated,$old$'menu_item_id',menu.id,'menu_code',menu.code,'menu_name',version_row.name,$old$,$new$'recipe_name',(select x.name from public.recipe_versions y join public.recipes x on x.organisation_id=y.organisation_id and x.id=y.recipe_id where y.id=version_row.recipe_version_id),'menu_match_basis',resolution->>'basis','stock_centre',stock_mapping->>'centre','consumption_mode',stock_mapping->>'mode','stock_mapping_id',stock_mapping->>'mapping_id','menu_item_id',menu.id,'menu_code',menu.code,'menu_name',version_row.name,$new$);
 execute updated;
end $$;

create function public.sales_menu_choices(p_organisation_id uuid,p_location_code text,p_day date,p_search text default '',p_page integer default 0) returns jsonb language plpgsql stable security definer set search_path='' as $$declare site public.locations;result jsonb;begin
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Sales import editing access required.' using errcode='42501';end if;
 if p_day is null or p_search is null or length(p_search)>80 or p_page is null or p_page not between 0 and 100000 then raise exception 'Choose a sales date and valid menu search.' using errcode='22023';end if;
 select * into site from public.locations where organisation_id=p_organisation_id and code=p_location_code;
 if not found then raise exception 'Map the POS outlet first, then choose its selling menu.' using errcode='22023';end if;
 with choices as(select m.id,m.code,v.name,v.version,r.name recipe_name,m.primary_category,m.subcategory,m.is_active,
  (select s.name from private.menu_stock_mappings x join public.stock_locations s on s.organisation_id=x.organisation_id and s.id=x.site_id where x.organisation_id=m.organisation_id and x.menu_id=m.id and x.outlet_id=site.id and x.effective_from<=p_day order by x.effective_from desc,x.version desc limit 1) centre
  from public.menu_items m join lateral(select * from public.menu_item_versions where organisation_id=m.organisation_id and menu_item_id=m.id and effective_from<=p_day order by effective_from desc,version desc limit 1)v on true join public.recipe_versions rv on rv.organisation_id=m.organisation_id and rv.id=v.recipe_version_id join public.recipes r on r.organisation_id=rv.organisation_id and r.id=rv.recipe_id
  where m.organisation_id=p_organisation_id and m.brand_id=site.brand_id and(m.location_id is null or m.location_id=site.id) and(p_search='' or v.name ilike '%'||p_search||'%' or m.code ilike '%'||p_search||'%')
  order by v.name,m.code limit 26 offset p_page*25)
 select jsonb_build_object('options',coalesce((select jsonb_agg(to_jsonb(q) order by name,code) from(select * from choices order by name,code limit 25)q),'[]'::jsonb),'more',(select count(*)>25 from choices)) into result;return result;
end $$;

alter function public.post_sales_import(uuid,uuid,jsonb) rename to post_sales_import_before_names;
revoke all on function public.post_sales_import_before_names(uuid,uuid,jsonb) from public,anon,authenticated;
create function public.post_sales_import(p_organisation_id uuid,p_batch_id uuid,p_controls jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb;b public.sales_import_batches;r jsonb;prior uuid;label text;begin
 result:=public.post_sales_import_before_names(p_organisation_id,p_batch_id,p_controls);
 if (result->>'posted')::boolean and not coalesce((result->>'already_posted')::boolean,false) then
  select * into b from public.sales_import_batches where organisation_id=p_organisation_id and id=p_batch_id;
  for r in select value from jsonb_array_elements(b.report->'rows') where value->>'state'='READY' and value->'source'?'Menu_Name' order by value->'prepared'->>'sale_date',(value->>'row')::integer loop
   label:=r->'source'->>'Menu_Name';
   select menu_item_id into prior from private.sales_menu_name_matches where organisation_id=p_organisation_id and source_system=r->'source'->>'Source_System' and location_id=(r->'prepared'->>'location_id')::uuid and source_name_key=private.pp_sales_name(label) and effective_from<=(r->'prepared'->>'sale_date')::date order by effective_from desc limit 1;
   if prior is distinct from (r->'prepared'->>'menu_item_id')::uuid then
    insert into private.sales_menu_name_matches(organisation_id,source_system,location_id,source_name_key,effective_from,source_name,menu_item_id,created_by)
    values(p_organisation_id,r->'source'->>'Source_System',(r->'prepared'->>'location_id')::uuid,private.pp_sales_name(label),(r->'prepared'->>'sale_date')::date,label,(r->'prepared'->>'menu_item_id')::uuid,auth.uid())
    on conflict(organisation_id,source_system,location_id,source_name_key,effective_from) do update set source_name=excluded.source_name,menu_item_id=excluded.menu_item_id,created_by=excluded.created_by,created_at=clock_timestamp();
    insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'SALES_MENU_NAME_MATCH',auth.uid(),(r->'prepared'->>'menu_item_id')::uuid,jsonb_build_object('source',r->'source'->>'Source_System','outlet',r->'prepared'->>'location_id','POS_name',label,'effective_from',r->'prepared'->>'sale_date','previous_menu',prior,'batch',p_batch_id));
   end if;
  end loop;
 end if;
 return result;
end $$;

create function public.sales_training_sample(p_organisation_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare day date;result jsonb;channel text;begin
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Sales import editing access required.' using errcode='42501';end if;
 select(now() at time zone time_zone)::date into day from public.organisations where id=p_organisation_id;
 select code into channel from public.restaurant_sales_channels where organisation_id=p_organisation_id and is_active and code<>'STANDARD' order by name,code limit 1;
 if channel is null then raise exception 'Set up one active sales channel first, such as General sales. Standard selling price is a pricing rule, not a POS sales channel.' using errcode='22023';end if;
 select jsonb_build_object('date',day,'location',l.code,'location_name',l.name,'menu_name',v.name,'menu_code',m.code,'channel',channel) into result
 from public.locations l join public.menu_items m on m.organisation_id=l.organisation_id and m.brand_id=l.brand_id and(m.location_id is null or m.location_id=l.id)
 join lateral(select name from public.menu_item_versions where organisation_id=m.organisation_id and menu_item_id=m.id and effective_from<=day order by effective_from desc,version desc limit 1)v on true
 where l.organisation_id=p_organisation_id and l.is_active and m.is_active order by l.name,v.name,m.code limit 1;
 if result is null then raise exception 'Publish a final-recipe-linked selling menu at an active outlet before downloading its training sample.' using errcode='22023';end if;
 return result;
end $$;

revoke all on function private.pp_sales_name(text),private.pp_resolve_sales_menu(uuid,uuid,date,jsonb,integer,jsonb,jsonb) from public,anon,authenticated;
revoke all on function public.sales_menu_choices(uuid,text,date,text,integer),public.post_sales_import(uuid,uuid,jsonb),public.sales_training_sample(uuid) from public,anon;
grant execute on function public.sales_menu_choices(uuid,text,date,text,integer),public.post_sales_import(uuid,uuid,jsonb),public.sales_training_sample(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
