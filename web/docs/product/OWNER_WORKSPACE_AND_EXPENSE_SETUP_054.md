# Owner workspace, current stock value and expense setup

Apply `202611210054_owner_workspace_and_expense_setup.sql` after 053, before deploying this app release. The migration adds read-only stock-value/menu checks and expense setup functions. It does not change balances, transfer posting, waste approvals or existing category identities.

## Owner's opening screen

The greeting is the page heading. The compact reporting selector sits above six cards: recorded net sales, estimated gross profit margin, food cost %, current estimated stock value, recorded estimated waste value, and recorded operating expenses. Missing sales/cost inputs remain unavailable; expense coverage remains explicit. The stock figure is current at page load/refresh, even when a historical reporting period is selected.

Weekly counts and waste compliance are combined into a compact Needs attention area. Upcoming counts do not create a large list or a misleading 0/0 summary. PO increases, overdue reports, count reviews, stock handovers and missing costs link to their source modules. Current menu checks include unsold items; counts are menu/outlet comparisons, with an outlet breakdown where appropriate.

Daily recorded sales, operating expenses by category and comparable known loss exposure appear below the cards. Unrecorded sales days and unavailable comparisons are not drawn as confirmed zero performance. Loss comparisons include waste and stock-count shortages, retain reference-estimate limits and link to detailed waste patterns. Drill-down evidence tables are collapsed by default. The redundant introductory slogan has been removed.

## Current stock value

Reports → Current stock value shows posted balances as of the query, not the selected sales period. Financial users see their permitted business/outlet scope. A responsible centre member can see their own centre's quantity and reference-value breakdown without receiving supplier invoices, another centre's costs or general financial reporting access.

Centre summaries show responsible member, estimated value and price coverage. Select a centre for on-hand, reserved and available quantities, reference unit cost and estimated held value. Download CSV or open the movement statement to investigate source quantities.

Reserved stock remains included at source until receiver acceptance; accepted transfers move quantities at both ends atomically. It is not counted twice or subtracted twice. Inactive centres with remaining balances remain included. Missing costs are disclosed and excluded from known values, not priced at zero. Empty stock balances have zero value. Stock figures use current dated monthly invoice averages, initial-price fallback and linked processing/recipe estimates. They are not an accounting valuation ledger or actual COGS.

## Expense category setup

New restaurants can choose operating expense categories during initial setup. Suggested shortcuts include Promotions, Maintenance, Logistics and Subscriptions; names and import codes remain editable before creation. This step can be skipped and revisited in Data & Setup → Expense categories.

Existing restaurants use the same setup page. Categories are shared with manual expense entry, CSV imports, category reports and dashboard charts. Existing category codes and reporting types remain fixed. Names can be updated, and categories can be deactivated or reactivated; historical IDs/expense links are preserved. Inactive categories are tucked under a disclosure. Finance can use configured categories but cannot manage setup.

When categories are chosen on initial onboarding, selected operating categories replace the active operating defaults; seeded labour categories remain. Skipping this step retains the initial categories. Completing onboarding again does not overwrite subsequent category edits. Setup uses an evidence check to reject stale concurrent edits.

## Acceptance checks

- Owner sees metrics before operational compliance; no redundant workspace heading/slogan.
- Historical sales-period changes do not change the current stock balance scope/date.
- Centre totals reconcile to business value; unpriced stock and inactive-centre balances remain explicit.
- Dispatch/acceptance does not duplicate stock value; reservation and availability reconcile.
- A centre owner cannot read another centre's value or use the new API to obtain company-wide financial access.
- Unsold menu items can still raise a current target/cost exception.
- Category choices survive save/resume/onboarding and appear in manual expense entry and imports.
- Category history/IDs survive rename/deactivation; stale edits and reporting-type changes are rejected.
- Mobile layouts, native filter state, exports and existing Finance/stock workflows remain usable.
