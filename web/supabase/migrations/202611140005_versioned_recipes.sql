-- Apply ONCE after 004. Versioned composition and scaling only; no financial policy.
begin;
create table public.recipes (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9_-]{0,39}$'),
  name text not null check(length(trim(name)) between 1 and 120),
  recipe_type text not null check(recipe_type in ('FINAL','SUB_RECIPE')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organisation_id,id), unique(organisation_id,code)
);
create table public.recipe_versions (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  recipe_id uuid not null,
  version integer not null check(version>0),
  name text not null check(length(trim(name)) between 1 and 120),
  effective_from date not null,
  notes text not null default '' check(length(notes)<=2000),
  request_id uuid not null,
  input_hash text not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique(organisation_id,id), unique(organisation_id,recipe_id,version), unique(organisation_id,request_id),
  foreign key(organisation_id,recipe_id) references public.recipes(organisation_id,id)
);
create table public.recipe_outputs (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  recipe_version_id uuid not null,
  quantity numeric(20,6) not null check(quantity>0),
  uom_id uuid not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique(organisation_id,id), unique(organisation_id,recipe_version_id),
  foreign key(organisation_id,recipe_version_id) references public.recipe_versions(organisation_id,id),
  foreign key(organisation_id,uom_id) references public.units_of_measure(organisation_id,id)
);
create table public.recipe_components (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  recipe_version_id uuid not null,
  line_no integer not null check(line_no>0),
  item_id uuid,
  child_recipe_version_id uuid,
  quantity numeric(20,6) not null check(quantity>0),
  uom_id uuid not null,
  normalised_quantity numeric(38,12) not null check(normalised_quantity>0),
  base_uom_id uuid not null,
  conversion_id uuid,
  target_name text not null,
  target_code text not null,
  target_type text not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  check(num_nonnulls(item_id,child_recipe_version_id)=1),
  unique(organisation_id,id), unique(organisation_id,recipe_version_id,line_no),
  foreign key(organisation_id,recipe_version_id) references public.recipe_versions(organisation_id,id),
  foreign key(organisation_id,item_id) references public.items(organisation_id,id),
  foreign key(organisation_id,child_recipe_version_id) references public.recipe_versions(organisation_id,id),
  foreign key(organisation_id,uom_id) references public.units_of_measure(organisation_id,id),
  foreign key(organisation_id,base_uom_id) references public.units_of_measure(organisation_id,id),
  foreign key(organisation_id,conversion_id) references public.item_uom_conversions(organisation_id,id)
);
create index pp_recipes_name_idx on public.recipes(organisation_id,name);
create index pp_recipe_components_parent_idx on public.recipe_components(organisation_id,recipe_version_id);

create function private.pp_recipe_write(target_org uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisation_memberships m join public.membership_roles r
 on r.organisation_id=m.organisation_id and r.membership_id=m.id
 where m.organisation_id=target_org and m.user_id=(select auth.uid()) and m.status='active'
 and r.location_id is null and r.role_code in ('restaurant_admin','operations'));
$$;
revoke all on function private.pp_recipe_write(uuid) from public,anon;
grant execute on function private.pp_recipe_write(uuid) to authenticated;
create function public.can_manage_recipes(p_organisation_id uuid)
returns boolean language sql stable security definer set search_path='' as $$ select private.pp_recipe_write(p_organisation_id); $$;
revoke all on function public.can_manage_recipes(uuid) from public,anon;
grant execute on function public.can_manage_recipes(uuid) to authenticated;

do $$ declare t text; begin
 foreach t in array array['recipes','recipe_versions','recipe_outputs','recipe_components'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('create policy recipe_read on public.%I for select to authenticated using(private.pp_catalogue_read(organisation_id))',t);
 end loop;
end; $$;

create function public.publish_recipe_version(
 p_organisation_id uuid,p_recipe_id uuid,p_request_id uuid,p_code text,p_name text,p_recipe_type text,
 p_effective_from date,p_yield_quantity numeric,p_yield_uom_id uuid,p_notes text,p_components jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare root_id uuid; version_id uuid; version_number integer; existing public.recipe_versions%rowtype;
 root public.recipes%rowtype; output_unit public.units_of_measure%rowtype; source_unit public.units_of_measure%rowtype;
 base_unit public.units_of_measure%rowtype; material public.items%rowtype; child public.recipe_versions%rowtype;
 child_root public.recipes%rowtype; child_output public.recipe_outputs%rowtype; line jsonb; line_number integer:=0;
 input_quantity numeric; normalised numeric; factor numeric; conversion uuid; target_name text; target_code text;
 target_type text; target_item uuid; target_version uuid; digest text;
begin
 if not private.pp_recipe_write(p_organisation_id) then raise exception 'Recipe access denied.' using errcode='42501'; end if;
 if p_request_id is null or p_code is null or p_code !~ '^[A-Z0-9][A-Z0-9_-]{0,39}$'
 or p_name is null or length(trim(p_name)) not between 1 and 120 or p_recipe_type not in ('FINAL','SUB_RECIPE')
 or p_effective_from is null or p_yield_quantity is null or p_yield_quantity<=0 or p_yield_quantity>=100000000000000
 or p_yield_quantity<>round(p_yield_quantity,6) or length(p_notes)>2000
 or jsonb_typeof(p_components) is distinct from 'array' then raise exception 'Check recipe details.' using errcode='22023'; end if;
 if jsonb_array_length(p_components) not between 1 and 100 then raise exception 'A recipe needs 1 to 100 component lines.' using errcode='22023'; end if;
 -- Serialise publication per tenant so retries and concurrent version allocation are safe.
 perform 1 from public.organisations where id=p_organisation_id for update;
 digest:=md5(jsonb_build_array(p_recipe_id,p_code,p_name,p_recipe_type,p_effective_from,p_yield_quantity,p_yield_uom_id,p_notes,p_components)::text);
 select * into existing from public.recipe_versions where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then
  if existing.input_hash<>digest then raise exception 'This save request was already used. Refresh before publishing different details.' using errcode='22023'; end if;
  return existing.id;
 end if;
 select * into output_unit from public.units_of_measure where organisation_id=p_organisation_id and id=p_yield_uom_id and dimension<>'PACKAGE';
 if not found then raise exception 'Choose a measurable output unit.' using errcode='22023'; end if;
 if p_recipe_id is null then
  insert into public.recipes(organisation_id,code,name,recipe_type,created_by)
  values(p_organisation_id,p_code,trim(p_name),p_recipe_type,auth.uid()) returning id into root_id;
 else
  select * into root from public.recipes where organisation_id=p_organisation_id and id=p_recipe_id for update;
  if not found then raise exception 'Recipe not available.' using errcode='42501'; end if;
  if root.code<>p_code or root.recipe_type<>p_recipe_type then raise exception 'Recipe code and type cannot be changed.' using errcode='22023'; end if;
  root_id:=root.id;
 end if;
 select coalesce(max(version),0)+1 into version_number from public.recipe_versions where organisation_id=p_organisation_id and recipe_id=root_id;
 insert into public.recipe_versions(organisation_id,recipe_id,version,name,effective_from,notes,request_id,input_hash,created_by)
 values(p_organisation_id,root_id,version_number,trim(p_name),p_effective_from,coalesce(p_notes,''),p_request_id,digest,auth.uid()) returning id into version_id;
 insert into public.recipe_outputs(organisation_id,recipe_version_id,quantity,uom_id,created_by)
 values(p_organisation_id,version_id,p_yield_quantity,p_yield_uom_id,auth.uid());
 for line in select value from jsonb_array_elements(p_components) loop
  line_number:=line_number+1; conversion:=null; factor:=null; target_item:=null; target_version:=null;
  if coalesce(line->>'quantity','') !~ '^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' then raise exception 'Invalid component quantity on line %.',line_number using errcode='22023'; end if;
  input_quantity:=(line->>'quantity')::numeric;
  if input_quantity<=0 then raise exception 'Component quantities must be positive.' using errcode='22023'; end if;
  select * into source_unit from public.units_of_measure where organisation_id=p_organisation_id and id=(line->>'uom_id')::uuid;
  if not found then raise exception 'Component unit not available.' using errcode='42501'; end if;
  if line->>'kind'='ITEM' then
   select * into material from public.items where organisation_id=p_organisation_id and id=(line->>'target_id')::uuid and is_active;
   if not found then raise exception 'Active material not available on line %.',line_number using errcode='42501'; end if;
   target_item:=material.id; target_name:=material.name; target_code:=material.code; target_type:=material.item_type;
   select * into base_unit from public.units_of_measure where organisation_id=p_organisation_id and id=material.base_uom_id;
   if source_unit.dimension='PACKAGE' then
    select c.id,c.factor into conversion,factor from public.item_uom_conversions c
    where c.organisation_id=p_organisation_id and c.item_id=material.id and c.from_uom_id=source_unit.id
    and c.effective_from<=p_effective_from order by c.effective_from desc limit 1;
    if not found then raise exception 'A package conversion is missing on line %. Save it in Materials & suppliers first.',line_number using errcode='22023'; end if;
   end if;
  elsif line->>'kind'='RECIPE' then
   select * into child from public.recipe_versions where organisation_id=p_organisation_id and id=(line->>'target_id')::uuid;
   if not found then raise exception 'Child recipe version not available.' using errcode='42501'; end if;
   select * into child_root from public.recipes where organisation_id=p_organisation_id and id=child.recipe_id;
   if child_root.recipe_type<>'SUB_RECIPE' or child.effective_from>p_effective_from then raise exception 'Choose a sub-recipe version effective by this recipe date.' using errcode='22023'; end if;
   if exists(with recursive tree(id,depth) as (
    select child.id,1 union select c.child_recipe_version_id,t.depth+1 from tree t
    join public.recipe_components c on c.organisation_id=p_organisation_id and c.recipe_version_id=t.id
    where c.child_recipe_version_id is not null and t.depth<20
   ) select 1 from tree t join public.recipe_versions v on v.organisation_id=p_organisation_id and v.id=t.id where v.recipe_id=root_id or t.depth>=20)
   then raise exception 'Recipe cycles or more than 20 nesting levels are not allowed.' using errcode='22023'; end if;
   select * into child_output from public.recipe_outputs where organisation_id=p_organisation_id and recipe_version_id=child.id;
   select * into base_unit from public.units_of_measure where organisation_id=p_organisation_id and id=child_output.uom_id;
   target_version:=child.id; target_name:=child.name||' · v'||child.version; target_code:=child_root.code; target_type:='SUB_RECIPE';
  else raise exception 'Choose a material or sub-recipe on every line.' using errcode='22023'; end if;
  if factor is null then
   if source_unit.dimension<>base_unit.dimension then raise exception 'Unit dimensions do not match on line %.',line_number using errcode='22023'; end if;
   factor:=source_unit.canonical_factor/base_unit.canonical_factor;
  end if;
  normalised:=input_quantity*factor;
  if normalised<=0 or normalised>=100000000000000000000000000 then raise exception 'Component quantity is out of range.' using errcode='22023'; end if;
  insert into public.recipe_components(organisation_id,recipe_version_id,line_no,item_id,child_recipe_version_id,quantity,uom_id,normalised_quantity,base_uom_id,conversion_id,target_name,target_code,target_type,created_by)
  values(p_organisation_id,version_id,line_number,target_item,target_version,input_quantity,source_unit.id,normalised,base_unit.id,conversion,target_name,target_code,target_type,auth.uid());
 end loop;
 if (with recursive expanded as (
  select c.id,c.child_recipe_version_id,1 as depth from public.recipe_components c
  where c.organisation_id=p_organisation_id and c.recipe_version_id=version_id
  union all select c.id,c.child_recipe_version_id,e.depth+1 from expanded e
  join public.recipe_components c on c.organisation_id=p_organisation_id and c.recipe_version_id=e.child_recipe_version_id where e.depth<20
 ) select count(*) from (select 1 from expanded limit 10001) bounded)>10000
 then raise exception 'This recipe expands to more than 10000 lines. Simplify the composition before publishing.' using errcode='22023'; end if;
 update public.recipes set name=trim(p_name),updated_at=now() where organisation_id=p_organisation_id and id=root_id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details)
 values(p_organisation_id,'recipe.version_published',auth.uid(),version_id,jsonb_build_object('recipe_id',root_id,'version',version_number,'component_lines',line_number));
 return version_id;
end; $$;

create function public.search_recipe_components(p_organisation_id uuid,p_kind text,p_search text,p_page integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.pp_catalogue_read(p_organisation_id) then raise exception 'Recipe access denied.' using errcode='42501'; end if;
 if p_kind not in ('ITEM','RECIPE') or p_page is null or p_page<0 or p_page>100000 or length(p_search)>80 then raise exception 'Invalid search.' using errcode='22023'; end if;
 if p_kind='ITEM' then
  select coalesce(jsonb_agg(to_jsonb(x)),'[]') into result from (
   select i.id,i.name as label,i.code,i.base_uom_id as uom_id,u.code as uom_code,u.dimension
   from public.items i join public.units_of_measure u on u.organisation_id=i.organisation_id and u.id=i.base_uom_id
   where i.organisation_id=p_organisation_id and i.is_active and (strpos(lower(i.name),lower(p_search))>0 or strpos(lower(i.code),lower(p_search))>0)
   order by i.name,i.id limit 26 offset p_page*25
  ) x;
 else
  select coalesce(jsonb_agg(to_jsonb(x)),'[]') into result from (
   select v.id,v.name||' · v'||v.version as label,r.code,o.uom_id,u.code as uom_code,u.dimension
   from public.recipe_versions v join public.recipes r on r.organisation_id=v.organisation_id and r.id=v.recipe_id
   join public.recipe_outputs o on o.organisation_id=v.organisation_id and o.recipe_version_id=v.id
   join public.units_of_measure u on u.organisation_id=v.organisation_id and u.id=o.uom_id
   where v.organisation_id=p_organisation_id and r.recipe_type='SUB_RECIPE'
    and (strpos(lower(v.name),lower(p_search))>0 or strpos(lower(r.code),lower(p_search))>0)
   order by v.name,v.version desc,v.id limit 26 offset p_page*25
  ) x;
 end if;
 return result;
end; $$;

create function public.get_recipe_version(p_organisation_id uuid,p_version_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare version_row public.recipe_versions%rowtype; result jsonb;
begin
 if not private.pp_catalogue_read(p_organisation_id) then raise exception 'Recipe access denied.' using errcode='42501'; end if;
 select * into version_row from public.recipe_versions where organisation_id=p_organisation_id and id=p_version_id;
 if not found then raise exception 'Recipe version not available.' using errcode='42501'; end if;
 select jsonb_build_object('recipe',to_jsonb(r),'version',to_jsonb(v),
  'output',jsonb_build_object('quantity',o.quantity::text,'uom_id',o.uom_id,'uom_code',u.code),
  'components',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'kind',case when c.item_id is not null then 'ITEM' else 'RECIPE' end,
   'target_id',coalesce(c.item_id,c.child_recipe_version_id),'label',c.target_name,'code',c.target_code,'target_type',c.target_type,
   'quantity',c.quantity::text,'uom_id',c.uom_id,'uom_code',su.code,'base_uom_id',c.base_uom_id,'base_uom_code',bu.code,
   'dimension',bu.dimension,'normalised_quantity',c.normalised_quantity::text,'conversion_id',c.conversion_id) order by c.line_no)
   from public.recipe_components c join public.units_of_measure su on su.organisation_id=c.organisation_id and su.id=c.uom_id
   join public.units_of_measure bu on bu.organisation_id=c.organisation_id and bu.id=c.base_uom_id
   where c.organisation_id=p_organisation_id and c.recipe_version_id=v.id),'[]'::jsonb), 'cost_state','MISSING') into result
 from public.recipe_versions v join public.recipes r on r.organisation_id=v.organisation_id and r.id=v.recipe_id
 join public.recipe_outputs o on o.organisation_id=v.organisation_id and o.recipe_version_id=v.id
 join public.units_of_measure u on u.organisation_id=v.organisation_id and u.id=o.uom_id
 where v.organisation_id=p_organisation_id and v.id=p_version_id;
 return result;
end; $$;

create function public.recipe_material_requirements(p_organisation_id uuid,p_version_id uuid,p_output_quantity numeric)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare output_row public.recipe_outputs%rowtype; result jsonb;
begin
 if not private.pp_catalogue_read(p_organisation_id) then raise exception 'Recipe access denied.' using errcode='42501'; end if;
 if p_output_quantity is null or p_output_quantity<=0 or p_output_quantity>=100000000000000 or p_output_quantity<>round(p_output_quantity,6)
  then raise exception 'Choose a positive output quantity with up to six decimal places.' using errcode='22023'; end if;
 select * into output_row from public.recipe_outputs where organisation_id=p_organisation_id and recipe_version_id=p_version_id;
 if not found then raise exception 'Recipe version not available.' using errcode='42501'; end if;
 with recursive expanded as (
  select c.*,p_output_quantity/output_row.quantity as multiplier,1 as depth from public.recipe_components c
  where c.organisation_id=p_organisation_id and c.recipe_version_id=p_version_id
  union all
  select c.*,e.multiplier*e.normalised_quantity/o.quantity,e.depth+1 from expanded e
  join public.recipe_outputs o on o.organisation_id=p_organisation_id and o.recipe_version_id=e.child_recipe_version_id
  join public.recipe_components c on c.organisation_id=p_organisation_id and c.recipe_version_id=e.child_recipe_version_id where e.depth<20
 ), totals as (
  select item_id,base_uom_id,target_type,min(target_name) as name,min(target_code) as code,
   round(sum(normalised_quantity*multiplier),12)::text as quantity,
   (sum(normalised_quantity*multiplier)>0 and round(sum(normalised_quantity*multiplier),12)=0) as below_precision
  from expanded where item_id is not null group by item_id,base_uom_id,target_type
 ) select coalesce(jsonb_agg(jsonb_build_object('item_id',t.item_id,'name',t.name,'code',t.code,'item_type',t.target_type,'quantity',t.quantity,'below_precision',t.below_precision,'uom_code',u.code) order by t.name),'[]'::jsonb)
 into result from totals t join public.units_of_measure u on u.organisation_id=p_organisation_id and u.id=t.base_uom_id;
 return result;
end; $$;

revoke all on function public.publish_recipe_version(uuid,uuid,uuid,text,text,text,date,numeric,uuid,text,jsonb) from public,anon;
revoke all on function public.search_recipe_components(uuid,text,text,integer) from public,anon;
revoke all on function public.get_recipe_version(uuid,uuid) from public,anon;
revoke all on function public.recipe_material_requirements(uuid,uuid,numeric) from public,anon;
grant execute on function public.publish_recipe_version(uuid,uuid,uuid,text,text,text,date,numeric,uuid,text,jsonb) to authenticated;
grant execute on function public.search_recipe_components(uuid,text,text,integer) to authenticated;
grant execute on function public.get_recipe_version(uuid,uuid) to authenticated;
grant execute on function public.recipe_material_requirements(uuid,uuid,numeric) to authenticated;
notify pgrst,'reload schema';
commit;
