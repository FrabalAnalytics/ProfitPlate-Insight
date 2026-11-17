-- ProfitPlate Insight: initial Supabase/PostgreSQL schema.
-- Run ONCE in Supabase > SQL Editor, as the project database administrator.
-- Assumes Supabase Auth exists. Does not modify the connection_test table.
-- All amounts use the organisation's currency; all timestamps are UTC instants.
begin;

create schema if not exists private;

create table public.organisations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  owner_id uuid not null references auth.users(id),
  currency_code text not null default 'NGN' check (currency_code ~ '^[A-Z]{3}$'),
  time_zone text not null default 'Africa/Lagos',
  created_at timestamptz not null default now()
);

-- The owner is recorded above; additional users are members here.
create table public.organisation_members (
  organisation_id uuid not null references public.organisations(id),
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('manager', 'analyst')),
  created_at timestamptz not null default now(),
  primary key (organisation_id, user_id)
);

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  name text not null check (length(trim(name)) > 0),
  address text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organisation_id, id),
  unique (organisation_id, name)
);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  name text not null check (length(trim(name)) > 0),
  email text,
  phone text,
  address text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organisation_id, id)
);

create table public.ingredients (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  name text not null check (length(trim(name)) > 0),
  -- Convert purchase packs and recipe quantities into this unit before saving.
  base_unit text not null check (base_unit in ('g', 'ml', 'each')),
  current_unit_cost numeric(20,8) not null default 0 check (current_unit_cost >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organisation_id, id),
  unique (organisation_id, name)
);

create table public.menu_categories (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  name text not null check (length(trim(name)) > 0),
  created_at timestamptz not null default now(),
  unique (organisation_id, id),
  unique (organisation_id, name)
);

create table public.menu_items (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  category_id uuid,
  name text not null check (length(trim(name)) > 0),
  selling_price numeric(16,2) not null check (selling_price >= 0),
  -- Recipe quantities below describe one batch yielding this many portions.
  recipe_yield numeric(14,4) not null default 1 check (recipe_yield > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organisation_id, id),
  unique (organisation_id, name),
  foreign key (organisation_id, category_id)
    references public.menu_categories(organisation_id, id)
);

create table public.recipe_ingredients (
  organisation_id uuid not null references public.organisations(id),
  menu_item_id uuid not null,
  ingredient_id uuid not null,
  quantity numeric(18,6) not null check (quantity > 0),
  primary key (organisation_id, menu_item_id, ingredient_id),
  foreign key (organisation_id, menu_item_id)
    references public.menu_items(organisation_id, id),
  foreign key (organisation_id, ingredient_id)
    references public.ingredients(organisation_id, id)
);

-- A purchase represents a received supplier invoice, not a purchase order.
create table public.purchases (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  branch_id uuid not null,
  supplier_id uuid not null,
  invoice_number text,
  received_at timestamptz not null default now(),
  notes text,
  created_at timestamptz not null default now(),
  unique (organisation_id, id),
  unique (organisation_id, supplier_id, invoice_number),
  foreign key (organisation_id, branch_id)
    references public.branches(organisation_id, id),
  foreign key (organisation_id, supplier_id)
    references public.suppliers(organisation_id, id)
);

create table public.purchase_items (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  purchase_id uuid not null,
  ingredient_id uuid not null,
  quantity numeric(18,6) not null check (quantity > 0),
  -- Cost per base unit; include allocated delivery and nonrecoverable taxes.
  unit_cost numeric(20,8) not null check (unit_cost >= 0),
  line_total numeric(20,2) generated always as (round(quantity * unit_cost, 2)) stored,
  unique (organisation_id, id),
  foreign key (organisation_id, purchase_id)
    references public.purchases(organisation_id, id),
  foreign key (organisation_id, ingredient_id)
    references public.ingredients(organisation_id, id)
);

create table public.sales (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  branch_id uuid not null,
  receipt_number text not null check (length(trim(receipt_number)) > 0),
  sold_at timestamptz not null default now(),
  status text not null default 'draft' check (status in ('draft', 'completed', 'void')),
  channel text not null default 'dine_in' check (channel in ('dine_in', 'takeaway', 'delivery')),
  notes text,
  created_at timestamptz not null default now(),
  unique (organisation_id, id),
  unique (organisation_id, branch_id, receipt_number),
  foreign key (organisation_id, branch_id)
    references public.branches(organisation_id, id)
);

create table public.sale_items (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  sale_id uuid not null,
  menu_item_id uuid not null,
  quantity numeric(14,4) not null check (quantity > 0),
  -- Snapshot these values when completing a sale; do not use today's prices later.
  unit_price numeric(16,2) not null check (unit_price >= 0),
  unit_cost numeric(20,8) not null check (unit_cost >= 0),
  discount_amount numeric(16,2) not null default 0
    check (discount_amount >= 0 and discount_amount <= round(quantity * unit_price, 2)),
  tax_amount numeric(16,2) not null default 0 check (tax_amount >= 0),
  net_revenue numeric(20,2) generated always as
    (round(quantity * unit_price, 2) - discount_amount) stored,
  cost_of_goods numeric(20,2) generated always as (round(quantity * unit_cost, 2)) stored,
  unique (organisation_id, id),
  foreign key (organisation_id, sale_id)
    references public.sales(organisation_id, id),
  foreign key (organisation_id, menu_item_id)
    references public.menu_items(organisation_id, id)
);

-- Append signed changes; current stock = sum(quantity_change) per branch/ingredient.
-- Purchases and sales do NOT automatically create inventory movements yet.
create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  branch_id uuid not null,
  ingredient_id uuid not null,
  movement_type text not null
    check (movement_type in ('opening', 'purchase', 'consumption', 'waste', 'adjustment')),
  quantity_change numeric(18,6) not null check (quantity_change <> 0),
  unit_cost numeric(20,8) not null check (unit_cost >= 0),
  occurred_at timestamptz not null default now(),
  -- Optional stable import/posting key prevents duplicate movements on retries.
  reference_key text,
  notes text,
  created_at timestamptz not null default now(),
  unique (organisation_id, reference_key),
  check (
    (movement_type in ('opening', 'purchase') and quantity_change > 0)
    or (movement_type in ('consumption', 'waste') and quantity_change < 0)
    or movement_type = 'adjustment'
  ),
  foreign key (organisation_id, branch_id)
    references public.branches(organisation_id, id),
  foreign key (organisation_id, ingredient_id)
    references public.ingredients(organisation_id, id)
);

create table public.expense_categories (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  name text not null check (length(trim(name)) > 0),
  created_at timestamptz not null default now(),
  unique (organisation_id, id),
  unique (organisation_id, name)
);

-- Operating expenses only. Ingredient purchases are accounted for via COGS.
create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id),
  branch_id uuid,
  category_id uuid not null,
  description text not null check (length(trim(description)) > 0),
  amount numeric(16,2) not null check (amount > 0),
  expense_date date not null default current_date,
  reference_number text,
  created_at timestamptz not null default now(),
  foreign key (organisation_id, branch_id)
    references public.branches(organisation_id, id),
  foreign key (organisation_id, category_id)
    references public.expense_categories(organisation_id, id)
);

create index organisation_members_user_idx on public.organisation_members(user_id);
create index purchases_branch_date_idx on public.purchases(organisation_id, branch_id, received_at);
create index purchase_items_purchase_idx on public.purchase_items(organisation_id, purchase_id);
create index sales_branch_date_idx on public.sales(organisation_id, branch_id, sold_at);
create index sale_items_sale_idx on public.sale_items(organisation_id, sale_id);
create index inventory_stock_idx on public.inventory_movements(organisation_id, branch_id, ingredient_id, occurred_at);
create index expenses_date_idx on public.expenses(organisation_id, expense_date);

-- SECURITY DEFINER avoids recursive membership policies. Fully qualified names
-- and an empty search_path protect these narrowly scoped permission checks.
create function private.pp_is_owner(target_organisation uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.organisations o
    where o.id = target_organisation and o.owner_id = (select auth.uid())
  );
$$;

create function private.pp_has_access(target_organisation uuid, needs_write boolean)
returns boolean language sql stable security definer set search_path = ''
as $$
  select private.pp_is_owner(target_organisation) or exists (
    select 1 from public.organisation_members m
    where m.organisation_id = target_organisation
      and m.user_id = (select auth.uid())
      and (not needs_write or m.role = 'manager')
  );
$$;

revoke all on function private.pp_is_owner(uuid) from public;
revoke all on function private.pp_has_access(uuid, boolean) from public;
grant usage on schema private to authenticated;
grant execute on function private.pp_is_owner(uuid) to authenticated;
grant execute on function private.pp_has_access(uuid, boolean) to authenticated;

alter table public.organisations enable row level security;
revoke all on public.organisations from anon, authenticated;
grant select, insert on public.organisations to authenticated;
grant update (name, time_zone) on public.organisations to authenticated;
create policy organisations_read on public.organisations for select to authenticated
  using (owner_id = (select auth.uid()) or private.pp_has_access(id, false));
create policy organisations_create on public.organisations for insert to authenticated
  with check (owner_id = (select auth.uid()));
create policy organisations_update on public.organisations for update to authenticated
  using (private.pp_is_owner(id)) with check (private.pp_is_owner(id));

alter table public.organisation_members enable row level security;
revoke all on public.organisation_members from anon, authenticated;
grant select, insert, update, delete on public.organisation_members to authenticated;
create policy members_read on public.organisation_members for select to authenticated
  using (private.pp_has_access(organisation_id, false));
create policy members_insert on public.organisation_members for insert to authenticated
  with check (private.pp_is_owner(organisation_id));
create policy members_update on public.organisation_members for update to authenticated
  using (private.pp_is_owner(organisation_id)) with check (private.pp_is_owner(organisation_id));
create policy members_delete on public.organisation_members for delete to authenticated
  using (private.pp_is_owner(organisation_id));

-- Owners/managers maintain operational records; analysts have read-only access.
-- Deletion is unavailable through the client API except for recipe composition.
do $$
declare table_name text;
begin
  foreach table_name in array array[
    'branches', 'suppliers', 'ingredients', 'menu_categories', 'menu_items',
    'recipe_ingredients', 'purchases', 'purchase_items', 'sales', 'sale_items',
    'inventory_movements', 'expense_categories', 'expenses'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on public.%I from anon, authenticated', table_name);
    execute format('grant select, insert on public.%I to authenticated', table_name);
    if table_name <> 'inventory_movements' then
      execute format('grant update on public.%I to authenticated', table_name);
    end if;
    execute format(
      'create policy tenant_read on public.%I for select to authenticated using (private.pp_has_access(organisation_id, false))',
      table_name
    );
    execute format(
      'create policy tenant_insert on public.%I for insert to authenticated with check (private.pp_has_access(organisation_id, true))',
      table_name
    );
    if table_name <> 'inventory_movements' then
      execute format(
        'create policy tenant_update on public.%I for update to authenticated using (private.pp_has_access(organisation_id, true)) with check (private.pp_has_access(organisation_id, true))',
        table_name
      );
    end if;
    execute format('create index %I on public.%I (organisation_id)', 'pp_' || table_name || '_org_idx', table_name);
  end loop;
end;
$$;

grant delete on public.recipe_ingredients to authenticated;
create policy recipe_ingredients_delete on public.recipe_ingredients
  for delete to authenticated using (private.pp_has_access(organisation_id, true));

commit;
