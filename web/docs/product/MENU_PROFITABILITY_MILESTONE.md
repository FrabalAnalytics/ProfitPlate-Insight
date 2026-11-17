# Menu profitability comparison

Open **Menu & prices → Menu profitability**. The catalogue remains available in
the adjacent tab. Compare active menu items for one outlet, channel and business
date, with name/code search and 25 rows per page.

## Figures and scope

- Estimated ingredient and direct packaging cost for one sold menu serving.
- Net selling price, excluding tax; the tax-inclusive customer price is shown
  beneath it when tax applies.
- Food cost percentage, estimated food profit per serving and estimated food
  gross profit margin percentage, using the existing database estimate service.
- Contribution margin explicitly remains unavailable: other required variable
  costs, including channel fees, are not connected. Food profit is not relabelled
  as full contribution or accounting profit.
- Readiness identifies missing/unusable material prices, absent or expired
  selling prices, currency mismatches and missing effective recipe-linked versions.
  Existing cost or selling revenue remains visible when the other input is missing.
  Missing values never become zero. Negative food profits and margins remain visible.

The comparison selects the newest effective menu version on or before the chosen
date, using version number only to break same-date ties. A later-created backdated
version cannot displace a more recent effective version. The existing pricing
service selects the scoped price and handles inclusive/exclusive tax, expiry and
same-date corrections. Costs follow that menu version's pinned recipe quantity
and saved recipe/sub-recipe bindings, so each row represents one sold menu item.

Only active items assigned to the selected outlet's brand appear. Inactive menus
are excluded; active unassigned-brand menus are counted and flagged separately.
Search and total counts apply before pagination. Breakdowns preserve the selected
version, outlet, channel and date. Future dates and unavailable outlets are rejected.

These are live reference-price food estimates. Later reference-price corrections
can change a historical-date preview. Labour, overheads, waste, discounts, service
charges and other variable-cost allocations are not added. No targets, actual
COGS, purchase-weighted costing policy or contribution policy are introduced.

## Setup and permissions

Apply only `202611160022_menu_profitability.sql` after migration 021. The migration
adds an effective-version lookup index and a read-only, security-definer RPC with
an empty search path and explicit tenant/financial-access checks. Anonymous calls
are revoked. It reuses the existing financial read permissions and costing RPC;
no legacy evidence, amounts, role assignments or price histories are rewritten.
No live Supabase migration is applied by the coding agent.

The page independently checks authentication and menu financial access. Finance
can compare and inspect breakdowns; Inventory and other accounts lacking existing
financial access cannot open the table via a copied URL. Menu publication and price
editing still use their existing permissions on the catalogue/detail screens.

## Verification

Database coverage includes exact estimate reuse, tax-aware prices, missing inputs,
negative margins, date-effective version selection, expiry, brand/tenant/role
boundaries, literal search, inactive exclusions and pagination across 26 items.
Browser checks cover the menu tabs, filters, serving figures, context-preserving
breakdowns, Finance mobile access, invalid dates and Inventory denial. Fixtures
use embedded PostgreSQL and simulated Auth; hosted Supabase integration follows
the manual migration setup.

Verified: production build, targeted lint, all 12 menu database checks and all six
menu/profitability browser checks passed. Desktop and mobile screenshots were
reviewed. The live migration remains a manual setup step.
