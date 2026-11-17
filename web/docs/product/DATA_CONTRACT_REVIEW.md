# Data model and import contract review

Reviewed 14 November 2026 against PRD v1.3 and the current initial schema.

## Source register and status

- [PRD v1.3](PRD-v1.3.md): product requirements and release boundaries.
- [Universal Data Model v1.1](DATA_MODEL-v1.1.md): supplied proposed engineering
  baseline. Its SQL examples are illustrative, not executable migration approval.
- [Workbook inventory](IMPORT_WORKBOOK-v1.1.json): extracted sheet names, exact
  headers, fictional examples and source SHA-256 for the supplied v1.1 XLSX.
- Original uploads were read without modification. No workbook content, formula,
  embedded instruction or illustrative SQL was executed. No Supabase change was
  made during this review.

The workbook contains 22 sheets: 20 customer-facing templates, START_HERE and
FIELD_DICTIONARY. The templates contain 168 columns in total and 60 fictional
sample rows. No cell formulas or spreadsheet data-validation rules were found.
The absence of Excel validation is not itself a defect; the importer must enforce
its own complete contract regardless of spreadsheet controls.

## Agreements across the sources

- Scope data by the authenticated organisation, not uploaded Organisation_Code.
- Resolve customer-facing codes into internal UUIDs inside that authorised scope.
- Keep source file, row, batch, mapping and posting provenance.
- Use same-organisation composite foreign keys and database-enforced permissions.
- Use effective dates and specific versions for reproducible historical costs.
- Preserve separate sales lines within a receipt. Count combo parent revenue once.
- Reconcile sales and purchases before posting; make posting duplicate-safe.
- Separate purchase-weighted recipe costs from inventory consumption valuation.
- Isolate simulations from live prices and reports; audit authorised publication.
- Keep advanced operational imports deferred/disabled until their module is ready.

## Material gaps and proposed treatment

These are proposed engineering treatments, not approved business defaults.

| ID | Finding and source evidence | Proposed treatment / decision needed |
| --- | --- | --- |
| D01 | UOM defines KG, L and PCS; UOM_Conversions and Purchases_Import reference BAG and CARTON. Existing schema only allows g/ml/each. | Add explicit UOM dictionary entries and item-specific package conversions. Define conversion direction, dimension compatibility, count fractions and effective dating. Never invent a universal BAG or CARTON size. |
| D02 | Recipe_Lines identifies a child recipe by Component_Code, but has no child version or output identifier. Menu_Components has the same recipe-binding gap. | Version a revised import contract or require an explicit, recorded mapping choice. Persist the resolved child recipe version/output; never bind silently to whichever version is latest. |
| D03 | Recipes has one Yield_Qty/Yield_UOM; the model permits multiple recipe_outputs. | Treat the v1.1 template as single-output only. Multiple outputs and co-product costing need an extension and an allocation policy. |
| D04 | Loss_Percent has no documented denominator or gross/net quantity semantics. | Agree whether Quantity is gross input or usable quantity and how loss/yield interact. Validate bounds and test against a hand-calculated example before costing. |
| D05 | Menu_Components supplies Selection_Group but not group min/max/defaults, permitted modifiers or effective component versions. Sales_Import has no dedicated option/variant field. | Define an extension for choices/modifiers, or explicitly limit first imports to fixed compositions with validated parent/child evidence. Validate menu cycles as well as recipe cycles. |
| D06 | FIELD_DICTIONARY marks many fields CONDITIONAL but gives no actual conditional rules; for example UOM_Code, recipe Version and transaction Status. | Write dataset-specific requiredness, enum, type, length, conditional and arithmetic rules before importer implementation. Version those rules; do not interpret CONDITIONAL as optional in every row. |
| D07 | Locations lacks timezone and parent-location columns even though the model requires location-local dates and supports hierarchy. Transaction sheets contain dates without timestamps. | Set timezone in authorised location setup and explain the date-only precision. Do not fabricate transaction times. Add versioned fields/mappings if intraday data or hierarchy is required. |
| D08 | Sales_Import has Gross_Sales, Discount, Tax and Net_Sales but no declared tax inclusion formula, refunds linkage, service charges or header control totals. | Agree source-specific financial mapping and refund/cancellation semantics. Capture external reconciliation controls in batch metadata or a contract extension. Derive totals only under a stated, versioned policy. |
| D09 | Purchases_Import has price/discount/tax and RECEIVED status, but no separate receipt event, invoice controls, freight or recoverable-tax treatment. | Keep invoice recognition and stock receipt distinct. Resolve landed-cost, discount/tax and credit-note rules. A RECEIVED label alone must not post inventory twice. |
| D10 | Operating_Costs is a monthly model with behaviour and allocation basis. It lacks actual period expense evidence, rate/base, location scope and allocation-driver values. Delivery Commission has Monthly_Amount = 0. | Separate modelled allocations from recognised expenses. Obtain rate/driver inputs for variable/mixed costs. Zero in the example cannot establish free delivery or verified operating profit. |
| D11 | Promotions contains an offer definition, not baseline/expected volume, campaign cost, cannibalisation or saved scenario results. | Map the offer definition separately and collect missing simulation inputs in Scenario Editor or a later contract. Never activate live discounts merely by importing a proposal. |
| D12 | The data model uses INCOMPLETE/ESTIMATED/PROVISIONAL/FINAL; the PRD uses VERIFIED/PROVISIONAL/ESTIMATED/MISSING/UNRECONCILED. | Separate report lifecycle (including FINAL) from data quality/readiness. Define the display mapping explicitly; a finalised report need not imply all data was verified. |
| D13 | Model recommends numeric(20,6) and numeric(12,4); initial schema mixes quantity and amount scales, including unit costs at scale 8. Currency rounding policy is unresolved. | Review precision/range and define line/document/report rounding. Preserve source decimals and do not silently truncate existing scale-8 costs during migration. Use decimal-safe application arithmetic. |
| D14 | Model SQL marks organisation code globally unique, while its prose says codes are organisation-scoped. UOM sheet has no organisation code. | Distinguish organisation identity/lookup code from tenant-local master codes. Decide dictionary ownership (shared read-only standards versus tenant definitions) and authorise imports explicitly. Do not blindly copy illustrative constraints. |
| D15 | Names vary across documents: organisation_members/memberships, branches/locations, ingredients/items, menu_prices/menu_price_versions, scenarios/simulation_scenarios, waste_records/waste_events. | Adopt one physical schema glossary in reviewed migrations. Document compatibility/backfill and references; avoid duplicate tables serving the same entity without a deliberate transition. |
| D16 | Production_Results lacks source-system/line identity and detailed consumed inputs. Waste_Import can reference a recipe but provides no recipe version. Neither is sufficient for a complete immutable operational ledger. | Keep these templates deferred for MVP; define module-specific extensions and duplicate/reversal rules before enabling them. Preserve the supplied templates as references, not evidence that the features are built. |
| D17 | Sales, purchase and menu-price examples only use NGN. There is no FX rate contract. | Require an explicit currency policy. Flag/reject unsupported currencies; do not combine different currencies into one profit total. No implicit FX conversion. |
| D18 | Example recipes are structural demonstrations, not complete validated menus: the Chicken Rice Plate example has rice and packaging lines but no chicken line. Combo example contains one selection-group component. | Treat examples as fictional parser/model fixtures only. Build complete, reviewed QSR/bakery/group fixtures before financial acceptance; do not present sample costs as business results. |

## External template to logical destination

This maps supplied names to the proposed model. It does not create tables or
enable imports. Any final physical naming changes require explicit migration
mapping and corresponding updates to server queries, RLS and tests.

| Template | Logical destination / treatment | Delivery phase |
| --- | --- | --- |
| Organisations | organisations; authorised onboarding/admin import only | 1 |
| Brands | brands | 1 |
| Locations | locations, optional brand and hierarchy | 1 |
| Departments | departments | 1 |
| Suppliers | suppliers | 1 |
| UOM | units_of_measure dictionary; scope decision required | 1 |
| Items | items and item_categories | 1 |
| UOM_Conversions | item_uom_conversions, effective dated | 1–2 |
| Recipes | recipes, recipe_versions, recipe_outputs | 2 |
| Recipe_Lines | recipe_components, resolved child version/output | 2 |
| Menu_Items | menu_items and categories | 2 |
| Menu_Components | menu_components; fixed composition/choice rules | 2, 6 |
| Menu_Prices | menu_price_versions, location/channel/effective dates | 2 |
| Sales_Import | sales_headers, sales_lines, sales_adjustments | 3 |
| Purchases_Import | purchase_headers, purchase_lines, purchase_adjustments | 3 |
| Inventory_Movements | inventory ledger; movement-specific validation/reversal | Deferred operations |
| Production_Results | production batches/outputs; input trace contract incomplete | Deferred operations |
| Waste_Import | waste_events; item/recipe-version resolution | Deferred operations |
| Operating_Costs | operating cost models and allocation rules; actuals separately evidenced | 4–5 |
| Promotions | offer/scenario input definition, separated from approved live changes | 6 |

Master import dependencies must be validated within the same authorised tenant:
organisation context and UOMs; brands/locations; categories/items/suppliers and
conversions; recipe graph; menu composition and prices; transactions. Recipe
components may require topological ordering. References missing from this file
can resolve to existing active masters; otherwise they become review findings.
The importer must not silently create a different organisation or auto-fill
missing financial facts to make a batch pass.

## Existing-schema migration strategy

1. Inventory current records and dependencies before changing tables. Preserve
   founder IDs, auth users, organisation IDs and deployed permission helpers.
2. Add canonical keys, lifecycle/audit columns and new entities incrementally.
   Review branches-to-locations and ingredients-to-items transitions, preserving
   reference identity or an explicit crosswalk. Do not drop/recreate the schema.
3. Replace the manager/analyst-only membership model with scoped multi-role
   memberships while keeping a tested access path for existing owners.
4. Add recipe/price/cost versions and explicit missing-data states. Backfill only
   known facts; identify legacy provenance rather than inventing effective dates.
5. Implement imports as staging, review and authorised posting, with source keys
   and an immutable audit. Never load workbook tabs directly into live tables.
6. Add canonical server queries and compatibility transitions, verify isolation,
   then retire old paths only after references and live data are accounted for.

## Verification required before posting is enabled

- All 168 template fields have explicit rules, including conditional requirements.
- Source codes resolve only inside the session-authorised organisation.
- Two tenants can reuse codes independently; cross-tenant FKs and storage fail.
- BAG/CARTON conversion examples validate with configured item-specific sizes.
- Receipt TX1002 keeps L1 and L2 separate; the parent contributes 8000 in the
  supplied example and the child contributes zero additional revenue.
- Reposting the same source lines creates no duplicates; conflicting corrections
  enter a reviewed reversal/supersession flow rather than being silently skipped.
- Recipes and menus resolve pinned child versions and reject cyclic composition.
- Reconciliations account for the agreed tax, discount, refund and rounding rules.
- Unknown commission/rate inputs and material costs remain incomplete, not zero.
- Finalised historical reports survive subsequent price/recipe changes.
- Full-workbook sample rows for ORG001/ORG002/ORG003 do not bypass session scope.
- Large-batch failures have a recorded recoverable state and duplicate-safe retry.

## Next implementation boundary

Proceed with the PRD design foundation and scoped onboarding design. Before
issuing the next schema migration, document the canonical naming, role/location
matrix and UOM ownership choices. Defer costing/import-specific decisions until
their milestone, but make them explicit prerequisites rather than hard-coded
business assumptions. The review does not require building all optional tables now.
