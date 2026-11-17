# Executive overview: recorded sales and live food-margin estimates

Apply `supabase/migrations/202611150012_executive_overview.sql` once after 011,
then refresh and open **Executive overview**. The coding agent has not applied
this migration to live Supabase. Existing login destinations remain unchanged.

## Delivered view

- One selected business, reporting period and location, with business-time-zone
  dates, declared currency, reference-price basis, coverage and a last-successful
  refresh timestamp. Refresh reloads the current selection.
- Recorded net sales after source discounts and excluding declared tax; live
  estimated food cost/margin; receipt/unit counts and days with recorded rows.
- The same `sales_period_summary` supplies totals and saved-version recipe costs
  used on Sales & summary. There is no separate dashboard costing policy.
- A daily SVG trend with date inspection and an accessible exact-value table.
  Days with no recorded rows have null revenue and chart gaps, rather than an
  invented zero. Genuine recorded zero-net lines remain zero and incur food cost.
- Channel revenue mix, revenue-only outlet comparisons, top five menu items by
  exact recorded net revenue, and latest ten receipts in the selected context.
- Missing-cost alerts suppress full cost/margin and link to the saved menu
  version and sale date. Complete-cost menu items with negative estimated food
  margins are prioritised by the most negative amount. No target threshold is
  guessed. Partial known-cost subtotals are explicitly labelled partial.
- A preceding period of the same calendar length provides recorded revenue and
  percentage comparison only. No comparison percentage is given for an empty
  current period, missing prior records or zero prior revenue. Mismatched prior
  currency or more than 1,000 prior lines suppress the comparison without hiding
  valid current figures. Coverage differences are disclosed.
- Receipt drill-down opens the original sales import, retaining dates/location.
  Overview and Sales & summary navigation preserve the selected reporting context.
  Switching business resets context to prevent carrying a foreign location.

## Access and integrity

Organisation-wide CEO, Finance and Restaurant Administrator roles can read the
overview. Procurement-only, operations-only, scoped-only, unrelated tenants,
inactive members and unassigned platform founders cannot read it. All new RPCs
enforce the underlying database permissions; UI visibility is not authorisation.

The shared shell now fetches a read-only navigation capability map on the server.
Unsupported/unauthorised module links are hidden. If migration 012 is missing,
the pre-existing navigation remains available; other permission-fetch failures
hide protected module links. The database checks on each page remain in place.

No new sales, prices, stock, memberships or accounting records are written by this
milestone. Reporting is read-only and bounded to 93 days / 1,000 current lines.
The current selection uses a consistent SQL statement snapshot. Financial sums
and percentages remain PostgreSQL numeric strings; floating point is used only
for chart geometry and display scaling.

## Verify with the existing fictional sample

Select 2026-11-15 (or the month containing it) and the existing demo outlet.
The original sample should still show net sales NGN 4,350, estimated food cost
NGN 2,700, estimated food margin NGN 1,650 / 37.93%, two receipts and three units,
provided the original NGN 900 reference recipe cost is unchanged. One recorded
day does not establish that other days had no trading.

Database checks cover totals, trend gaps, channel/outlet reconciliation, saved
source links, zero/negative/missing costs, location scope, currency/volume limits
and role isolation. Browser checks cover desktop/mobile, exact daily figures,
refresh, comparison, empty states and context-preserving source navigation,
alongside existing authentication, setup, team and import workflows.

## Still deferred

Contribution, operating profit, actual inventory COGS, waste and menu-level overhead allocation,
channel fees, target-margin configuration, period close/snapshots, exports,
saved personal reporting context and large/background reporting. Historical
reference-price corrections can change these live estimates. Live Supabase
integration still needs confirmation after applying migration 012.

## Labour and operating costs connected to the overview

The overview reads `expense_period_report` using the same organisation, inclusive
coverage dates and outlet selection as its sales view. It reuses migration 013;
no new migration or live-data update is needed. The cost section is read-only,
including for administrators, and links to Labour & expenses with context intact.

Recorded labour and operating expenses retain completeness warnings. Missing
entries without an exact-scope review show Not confirmed; reviewed known-zero
costs show zero. Estimated prime cost uses the existing expense-report result,
which requires reviewed labour, recorded sales and complete reference food costs.
Operating expenses remain separate. Central costs stay included for all outlets
and excluded for individual outlets, with an explicit notice. Legacy expense
records requiring reconciliation remain visible as a warning and excluded.

Expense-report errors leave the sales overview readable and show an unavailable
cost section. Costs are still displayed for periods without recorded sales;
prime cost remains unavailable. No actual COGS, contribution or operating profit
is inferred. Separate sales and expense refresh timestamps identify the live
reads; these are not a locked period snapshot.

Browser checks cover reviewed totals, unreviewed labour after a new entry,
known-zero labour without sales, outlet exclusions, context-preserving drill-down,
mobile overflow and hydration errors, alongside existing overview regressions.
