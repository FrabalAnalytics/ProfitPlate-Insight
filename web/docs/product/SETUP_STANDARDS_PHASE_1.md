# Phase 1: setup standards and readiness

Implemented against the 18 November 2026 product specification. Apply `202611180032_setup_standards.sql` once after 031, then deploy this application version. Existing migration files must not be rerun. No live Supabase change, GitHub push or production deployment was performed by the coding agent for this phase.

## Delivered

- Restaurant-defined maximum food and beverage cost percentages, with business defaults and independently inheriting location overrides. Blank is unconfigured/inherited, never an implicit zero. Explicit zero is a valid target. Restaurant administrators edit; financial readers and Inventory Managers can view setup standards.
- Food / Drink / Packaging menu categories and subcategories. Existing menu categories are not inferred as Food. Missing categories remain visible as incomplete records.
- Business-wide or one-location availability for materials, recipes and menu items. Menu availability remains within its assigned brand. New recipe components, price entries, purchases, sales and stock posting validate compatible scope on the database side. Scope is availability, not a replacement for role permissions.
- Material records can save without a base unit. The missing unit can be completed later; an established base unit stays fixed. Missing-unit records cannot post quantities. Missing unit, reference-price and opening coverage remain flagged.
- Material stock classes (Purchased / Processed / Both), General material type and the weekly-count flag. Existing semi-finished/finished material types initialise as Processed; other existing items initialise as Purchased. Review these defaults during setup. Flags are groundwork for scheduled weekly counting, not a claim that the weekly reconciliation engine is delivered.
- Incomplete menu drafts can save without a final recipe. Dated selling prices can be retained before recipe mapping. A usable mapping and ingredient prices still determine serving cost; no missing cost becomes zero. Mapping a recipe publishes a normal preserved version.
- Opening readiness per material and applicable stock location, including shared central storage. Positive opening balances use the existing controlled stock workflow. Explicit zero confirmation requires a measurable material, an eligible location, date and source note, with no ledger history or pending movements at that material/location. A zero confirmation does not post stock quantities. Once confirmed, corrections use reviewed physical counts, not another opening posting.
- For material/location pairs already carrying stock history, a posted reviewed physical count can establish a baseline. It does not reconstruct or rewrite an earlier opening quantity. Existing stock history cannot be replaced by a zero confirmation.
- Measured seven-stage setup progress for the restaurant and founder directory: business/locations, users/roles, suppliers, materials/prices/openings, recipes, mapped/priced menu, and cost targets. Counts update from saved data. This measures setup readiness, not confirmation that every day's transactions are complete or that all accounts have been trained.
- Menu profitability and the CEO menu watch use configured targets. Food and beverage targets resolve per location. Missing category/target is explicit, Packaging has no food/beverage target, and negative food margin remains a separate risk. Targets are current configuration; the existing recipe/reference-price financial basis is unchanged.

## Operating steps

1. Open Data & Setup and review the seven-stage checklist.
2. Open Food & beverage targets. Save the business defaults, then choose a location only when its target differs. Leaving one location field blank inherits that particular business field.
3. In Materials & suppliers, create/edit material classification, unit, availability and weekly-count flag. Review Incomplete Data reasons. Enter known dated prices through Initial material prices.
4. In Inventory, configure stock locations. Open Opening stock readiness from Locations & routes, or from setup targets. Enter positive opening quantities through the normal Inventory Manager workflow. Expand Confirm a zero opening only for a checked first zero balance. Use a reviewed count if movement history already exists.
5. Choose a recipe's scope before its first publication. A shared recipe uses shared inputs; a local recipe may also use inputs scoped to the same location. Produce stored child recipes before their parents under the existing inventory process.
6. Create a menu item, choose its primary category/subcategory and availability, and map a final recipe when ready. Save incomplete if mapping is pending. Add a known dated selling price independently.
7. Open Menu profitability for the intended outlet. Review serving cost, readiness and threshold status. The CEO's menu watch applies the same current location target to sold items.

## Boundaries and rollout

Scope is kept stable after references that would make a change misleading: material use in recipes/purchasing/stock, published recipe versions, and priced/sold menus. Create a separate scoped SKU/recipe/menu where needed instead of reinterpreting old records. Shared records remain available through existing business/brand rules. No existing invoice, price, recipe version, sale or stock ledger quantity is rewritten by this migration.

For migration 032 alone, reference prices remain the existing dated estimate source. Posting an invoice does not automatically replace reference prices, and no purchase-weighted inventory valuation or multi-output monetary allocation is introduced. Full contribution margin remains unavailable until its other variable-cost inputs are connected.

The subsequent [restaurant controls release](RESTAURANT_CONTROLS_RELEASE.md), migrations 033-034, adds manual restaurant suspension, reporting calendars, monthly invoice-weighted cost estimates and a processed-material setup page. The remaining boundaries below describe the original Phase 1 scope.

Bulk CSV/XLSX master-data onboarding is Phase 2. Restaurant activation controls, multi-output processing, sales-driven stock depletion and the dedicated weekly reconciliation/review remain subsequent phases. PO approval remains excluded.

## Verification

The production build and TypeScript checks passed. All 195 database checks and 39 form/export checks passed; database coverage includes scope isolation, nullable-unit completion, retry-safe recipe/menu setup, draft pricing, target inheritance/zero values, explicit zero openings, shared central-store coverage and reviewed-count baselines. Existing catalogue/menu/onboarding/CEO browser flows and recipe/inventory/receiver/founder browser flows were exercised. The final setup browser scenario passes end to end, including the 375px mobile layout. Lint has no errors and three pre-existing test warnings.

Testing uses local PostgreSQL/PGlite and simulated auth. Live email delivery, live Supabase migration application and production deployment remain separate operator steps.
