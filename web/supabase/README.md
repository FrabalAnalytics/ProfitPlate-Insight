# ProfitPlate Insight database setup

The initial schema targets the existing Supabase project. It supports multiple
organisations, each with its own branches, menu, ingredients and financial data.
It is a starting operational schema, not a general accounting ledger.

## Run the SQL

1. Open the project's **Supabase Dashboard → SQL Editor → New query**.
2. Copy the complete contents of
   [202611140001_initial_schema.sql](migrations/202611140001_initial_schema.sql).
3. Run it once. The transaction creates all 15 tables, constraints, indexes and
   access policies together. It leaves the existing `connection_test` untouched.

This migration expects its table names to be unused. It deliberately fails on
conflicting tables instead of silently accepting an incompatible schema.

## Create your first organisation

First create a user through Supabase Authentication. Copy that user's UUID from
**Authentication → Users**, replace the UUID placeholder below, and run this in
the SQL Editor. The UUID must identify an existing authentication user.

```sql
insert into public.organisations (name, owner_id, currency_code, time_zone)
values (
  'My Restaurant',
  'REPLACE_WITH_AUTH_USER_UUID'::uuid,
  'NGN',
  'Africa/Lagos'
)
returning id;
```

Use the returned organisation ID to create your first branch:

```sql
insert into public.branches (organisation_id, name)
values ('REPLACE_WITH_ORGANISATION_UUID'::uuid, 'Main Branch')
returning id;
```

The default currency is NGN; change it during organisation creation if needed.
All monetary values in an organisation use that currency. Currency changes are
not granted through the client API because they would relabel historical amounts.
Supabase Auth stores login identities; do not create a passwords table.

## Tables

| Table | Purpose |
| --- | --- |
| `organisations` | Restaurant business, owner, currency and reporting timezone |
| `organisation_members` | Additional users and their manager or analyst role |
| `branches` | Restaurant locations |
| `suppliers` | Ingredient suppliers and contact details |
| `ingredients` | Ingredient catalogue, base units and current unit costs |
| `menu_categories` | Menu groups |
| `menu_items` | Dishes, current prices and recipe batch yield |
| `recipe_ingredients` | Ingredient quantities per recipe batch |
| `purchases` | Received supplier invoices by branch |
| `purchase_items` | Purchased quantities and historical unit costs |
| `sales` | Sales receipts, branch, time, status and channel |
| `sale_items` | Sold dishes, price and cost snapshots, discounts and tax |
| `inventory_movements` | Signed ingredient receipts, usage, waste and adjustments |
| `expense_categories` | Operating expense groups |
| `expenses` | Branch or organisation operating expenses |

## Access rules

- Owners read and maintain their organisation's operational data and manage members.
- Managers read and maintain operational data; they cannot manage membership.
- Analysts can read their organisation's data.
- Anonymous users have no access to these tables.
- Inventory movements are append-only through the client API. Operational record
  deletion is unavailable except for removing ingredients from a recipe.
- Composite foreign keys prevent references to another organisation's records.

Membership gives access to all branches within the organisation. Branch-specific
permissions are not implemented. Policies apply to normal authenticated clients;
the SQL Editor and service-role backend access bypass them.

## Conventions and remaining application work

- Quantities use ingredient base units: grams, millilitres or individual units.
  Convert a 5 kg rice bag to 5000 g before saving its purchase quantity. Once used,
  an ingredient's base unit must stay consistent; automatic conversion is not built.
- `menu_items.recipe_yield` is portions per batch. Divide the sum of recipe
  ingredient costs by the yield to calculate the current cost per portion.
- Sale prices exclude tax. `discount_amount` and `tax_amount` are totals for the
  whole line. Collected tax is separate from `net_revenue`.
- Set `sale_items.unit_cost` when posting the sale using the chosen costing method.
  Historical margin uses this snapshot rather than the current recipe cost.
- Only completed sales count toward revenue. Gross profit is net revenue less
  cost of goods. Operating profit also subtracts operating expenses and any
  separately recognised inventory losses. Do not also expense ingredient purchases.
- Current stock is the sum of signed inventory movements per ingredient and branch.
  Write opening balances as movements. Stock may become negative; preventing this
  needs a transactional stock-posting workflow.
- Purchases and sales do **not** automatically post movements, update ingredient
  costs, lock historical sales or reverse stock when voided. Build transactional
  database functions for these actions before using the schema for live operations.
  Give each movement a stable `reference_key` so retries cannot duplicate it.
- Managers can currently edit sales, purchases and expenses. Immutable posting,
  refunds, audit history, branch transfers, purchase orders, recipe versioning,
  payroll detail and accounting integrations are later workflow additions.
- Organisation-level expenses have no branch. Branch reports need an explicit
  allocation rule for those shared costs.
