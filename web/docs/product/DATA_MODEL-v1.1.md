# ProfitPlate Universal Restaurant Data Model v1.1

Status: Proposed engineering baseline, not deployed. Scope: restaurant concepts including QSR, dining, bars, cafés, bakeries, cloud kitchens, catering and multi-outlet groups.

## 1. Design boundaries

- One shared PostgreSQL database with strict organisation-level isolation; every tenant-owned row has `organisation_id uuid not null` referencing `organisations(id)`.
- Import templates are external contracts. Do not expose internal UUIDs to customer spreadsheets.
- Codes are unique per organisation, not globally. Do not trust `Organisation_Code` supplied in a file as authorisation; resolve the authorised organisation from the logged-in session.
- `numeric(20,6)` for amounts, quantities and conversions; `numeric(12,4)` for percentage rates. Use decimal calculations, not JS binary floats.
- `timestamptz` for audit timestamps; `date` for business-effective dates; local restaurant timezone stored per location.
- Use UUID primary keys, `created_at`, `updated_at`, `created_by` where applicable. For immutable ledger and snapshots, record supersession or reversals instead of destructive edits.
- Recipe versions, prices, conversion factors and costing policies require effective dating. Finalised reports reference the exact source versions and calculation version.

## 2. Logical Supabase tables

| Domain | Physical tables | Keys / important fields | Main constraints |
|---|---|---|---|
| Tenant | `organisations`, `organisation_memberships`, `roles`, `membership_roles` | organisation id, user id, role | active membership required |
| Structure | `brands`, `locations`, `departments`, `sales_channels` | organisation_id, code, location_type, timezone | unique `(organisation_id, code)` |
| Catalogue | `items`, `item_categories`, `units_of_measure`, `item_uom_conversions`, `suppliers` | item_type, base_uom, factor, effective_from | factor > 0; item base dimension compatible |
| Recipes | `recipes`, `recipe_versions`, `recipe_components`, `recipe_outputs` | recipe id, version, component_type, item_id/child_recipe_version_id, qty | positive qty; exactly one component target; no recipe cycles |
| Menu | `menu_items`, `menu_components`, `menu_variant_groups`, `menu_variants`, `menu_price_versions` | menu id, component type, qty, outlet/channel, effective dates | prevent overlapping effective price ranges per scope |
| Sales | `sales_headers`, `sales_lines`, `sales_adjustments` | source system, external transaction id, external line id, status, money amounts | unique tenant+source+location+transaction+line; combo children do not double-count revenue |
| Procurement | `purchase_headers`, `purchase_lines`, `purchase_adjustments` | supplier, invoice, external line id, UOM, qty, price, tax | unique tenant+source+purchase+line; tax and discounts reconciled |
| Inventory | `inventory_movements`, `inventory_cost_layers`, `stock_counts` | movement type, item, source/destination, quantity, reference | no direct ledger edits; correction/reversal only |
| Production | `production_batches`, `production_inputs`, `production_outputs`, `waste_events` | recipe_version, planned/actual yields, item, quantity | preserve input-output traceability |
| Events | `events`, `event_sales_links`, `event_cost_allocations` | event reference, guests, revenue and direct costs | optional module |
| Costs | `material_cost_periods`, `recipe_cost_snapshots`, `menu_cost_snapshots`, `costing_policy_versions`, `operating_costs`, `allocation_rules` | cost basis, effective period, confidence/status, source version | immutable finalised snapshots |
| Simulation | `simulation_scenarios`, `simulation_inputs`, `simulation_results`, `approval_requests` | scenario owner, assumptions, comparison basis | no changes to live prices without approved action |
| Imports | `import_batches`, `import_rows`, `import_mappings`, `import_findings`, `source_files` | file hash, source, row number, row status, batch state | idempotent posting, file retention, row trace |
| Reporting | `reporting_periods`, `financial_snapshots`, `report_runs`, `audit_events` | period, state, calculation version, inputs hash | close/lock controls, append-only audit |
| Commercial | `subscriptions`, `subscription_entitlements`, `usage_counters` | plan, status, limits | enforce entitlements server-side |

### 2.1 Key relationships

- Organisation 1:N brands, locations, users, items, suppliers, recipes, menu items, transactions.
- Brand 1:N locations and menu items; locations can optionally reference a brand and a parent location.
- Recipe 1:N recipe versions; recipe version 1:N recipe components and outputs.
- Recipe components reference either an item or a *specific* child recipe version; validate acyclic recipe graph.
- Menu components reference a recipe version, stockable item, or another sellable menu item. For combo choice groups, store permitted options and actual sold selections.
- Sales header 1:N sales lines; sales lines may reference parent combo line and selected component option.
- Purchase header 1:N purchase lines; receipt or inventory posting is separate from invoice recording when needed.
- Financial snapshots reference reporting period, cost basis, effective price versions and calculation version.

## 3. Suggested core SQL contracts (illustrative, not complete migrations)

```sql
create table organisations (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  country_code char(2) not null,
  base_currency char(3) not null,
  created_at timestamptz not null default now()
);

create table locations (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references organisations(id),
  code text not null,
  name text not null,
  location_type text not null check (location_type in
    ('OUTLET','WAREHOUSE','CENTRAL_KITCHEN','PRODUCTION','EVENT_SITE','OTHER')),
  timezone text not null default 'Africa/Lagos',
  unique (organisation_id, code),
  unique (organisation_id, id)
);

create table items (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references organisations(id),
  code text not null,
  name text not null,
  item_type text not null check (item_type in
    ('RAW','SEMI_FINISHED','FINISHED','PACKAGING','RESALE','CONSUMABLE','ASSET')),
  base_uom text not null,
  stock_tracked boolean not null default true,
  unique (organisation_id, code),
  unique (organisation_id, id)
);
```

**Tenant foreign key rule:** child tables referencing tenant-owned parents must use composite foreign keys `(organisation_id, parent_id)` to a matching unique `(organisation_id,id)` key, so a valid parent UUID from another tenant cannot be attached. Apply this consistently across all tenant-owned relationships.

## 4. RLS and authorisation contract

- Enable RLS on every tenant-owned table; deny unauthenticated access by default.
- SELECT/INSERT/UPDATE/DELETE policies must check active `organisation_memberships` and permitted role/action. Do not rely only on UI navigation hiding.
- Use a carefully audited security-definer membership helper to avoid recursive RLS policies; lock down `search_path` and execution grants.
- Tenant-owned INSERT and UPDATE require `WITH CHECK` for organisation ownership, and server-side approval controls for sensitive records.
- Storage object paths begin with an internal organisation UUID; storage RLS checks active membership and role. Never infer permission from the path alone.
- Service-role keys remain server-only; imports, period closing and finalisation require explicit application authorisation and audit.
- Automated tests: cross-tenant SELECT, INSERT, UPDATE, DELETE, foreign-key linking and Storage access must all fail.

## 5. Import processing contract

1. Upload original Excel/CSV to private storage; hash bytes and record `import_batch`.
2. Select import type and saved source mapping; parse into staged `import_rows`.
3. Validate field types, required fields, UOM dimensions, codes, effective dates, arithmetic, transaction statuses, cross-row identities and totals.
4. Present rejected, accepted and provisional rows and source-to-system reconciliation.
5. Authorised user approves posting; post transactionally in chunks with idempotency keys. Batch state is recorded.
6. Store source row references and mapped canonical values; refresh only affected cost periods and dashboards.
7. Corrections use reversal or authorised supersession, not silent rewriting of finalised records.

**Identity**: sales line uniqueness includes organisation, source system, source location, external transaction reference and external line reference. Purchase line uniqueness includes organisation, source system, external document and external line reference; add supplier/source scope if the external system does not guarantee document uniqueness. Do not deduplicate solely on date and item.

## 6. Financial integrity rules

- Food GP = net revenue less attributable ingredients and direct packaging; contribution additionally deducts all attributable variable costs. Operating profit requires recognised period costs, not arbitrary item allocation.
- Distinguish purchase-weighted material costs from inventory consumption valuation. Recipe cost basis must be displayed.
- Selling prices have outlet/channel/effective-date scope; a current-price/historical-cost view is labelled a scenario, not historical realised profit.
- Combo parent revenue is counted once; zero-priced child sales provide component/choice evidence but must not duplicate revenue or cost.
- Promotions use incremental contribution, sales uplift and cannibalisation assumptions; simulated scenarios do not update live prices.
- Missing costs are explicitly marked `INCOMPLETE`, carried-forward costs `ESTIMATED`, current open period costs `PROVISIONAL`, finalised snapshots `FINAL`.

## 7. Scope and outstanding engineering decisions

The workbook includes 20 customer-facing sheets, not every backend table. Before generating migrations, settle: default UOM dictionary and dimensional conversions; menu variant and modifier file contracts; refunds and service-charge allocation; receipt-vs-invoice posting; effective-date overlap policy; cost allocation bases; event and buffet import contracts; transaction timezone policy; and final reporting-close rules. For an intelligence-first MVP, these may be implemented as optional capabilities with clear exclusions.

## 8. Acceptance tests

- Two organisations can independently reuse the same item/menu/source codes without collision.
- A tenant cannot read or attach another tenant's location/item/recipe.
- Importing the same batch twice creates no duplicate posted lines.
- Two distinct sales lines under one receipt remain separate.
- Zero-priced combo children do not increase net revenue.
- Sub-recipe version changes do not alter locked prior-period reports.
- A material price change updates only open/recalculable periods and visibly affects relevant current recipe costs.
- Missing material costs result in incomplete profitability, not a zero-cost profit overstatement.
- Each imported number can be traced to its original file, row and posting event.
