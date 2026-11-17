# Executive management reports

## Delivered

The Reporting Centre provides an authenticated management report for any valid
selection of up to 93 days and one outlet or all business locations. Daily,
last-seven-days and current-month shortcuts preserve the selected business and
outlet. Custom date filters support other weekly or monthly periods.

Organisation-wide CEO, Finance and Restaurant Administrator access reuses the
existing sales-report permission. The underlying sales and expense RPCs continue
to enforce tenant and role checks. Navigation uses the same overview capability;
founder access remains separate. No new SQL migration is needed.

The report includes source-reconciled net revenue, reference-based food costs and
food margin, recorded labour and operating expenses, estimated prime cost and
available ratios, coverage declarations, central exclusions, legacy reconciliation
counts, daily/outlet/channel revenue, menu results and missing-cost details.
The screen shows at most 20 menu items ranked by sales; CSV includes all menu
items returned within the existing report limits. The report never adds operating
expenses to prime cost or invents accounting profit or a menu allocation policy.

## Export and print behaviour

Download report CSV exports the already displayed report, not a second hidden
fetch. The UTF-8 BOM CSV uses six columns: Section, Metric, Value, Unit, Status,
Notes. It preserves decimal strings, missing-value blanks, context, source refresh
timestamps, generated timestamp, version `EXECUTIVE_MANAGEMENT_CSV_V1`, and basis
and limits. Text fields are quoted and spreadsheet formula prefixes neutralised;
legitimate signed decimal financial values remain numeric strings.

Print / save PDF invokes the browser print dialog. Print styling hides navigation,
account details and controls, while retaining the business, currency, period,
outlet, basis, review status and timestamps. The user chooses the printer or PDF
destination. The application does not send reports to anyone automatically.

The report is a live management estimate. Downloads are portable copies, not
approved financial snapshots. Source RPC reads have independent refresh times.
Backdated reference-price changes and new source records can change a regenerated
report. Missing costs stay missing; no-record sales days do not imply zero trading.
An expense-report failure preserves sales and makes expense-based values unavailable.

## Verification

Unit checks cover exact source decimals, no arithmetic substitution, missing costs,
partial coverage, reviewed known zero, empty trading periods and CSV formula/
quote/newline safety. Browser checks cover reviewed versus partial cost downloads,
report context, mobile overflow, print layout/PDF generation, missing sales,
invalid/oversized filters, unavailable businesses and unauthenticated access.
Tests use isolated fictional data rather than live Supabase mutations.

## Live review

1. Open Management reports in the sidebar or from Executive overview.
2. Select 2026-11-15 through 2026-11-15 and All business locations.
3. With the existing sample and exact-scope reviews, compare sales NGN 4,350,
   food estimate NGN 2,700, labour NGN 600, operating expenses NGN 100 and
   estimated prime cost NGN 3,300 / 75.86% against the source reports.
4. Download CSV and try Print / save PDF. Change outlet or dates to verify
   that completeness is not inherited from another scope.

## Deferred

Saved report history, approved immutable snapshots, accounting period close,
scheduled distribution, XLSX/PDF server rendering, large background report jobs,
actual inventory COGS, contribution and operating profit remain separate work.

## Report presentation refresh

The screen now leads with six financial summary cards, available source ratios,
and a visible coverage/review message. Section links lead to financial detail,
coverage, sales breakdowns, menu performance and reporting basis. Detailed native
disclosures keep the phone view concise; missing-cost details remain open when
applicable. The menu table uses compact desktop rows and labelled mobile cells.

Printing expands all report disclosures and restores their previous state after
printing. CSV still exports the same full source values irrespective of which
sections the user has opened. Browser checks exercise keyboard disclosure use,
mobile menu-table layout, complete print output and post-print state restoration.
Financial RPCs, decimal values, permissions and export format are unchanged.

Food cost % and prime cost % are now prominent within their summary cards,
with category and percentage icons. Executive overview also exposes both ratios.
Food cost % divides the complete reference ingredient/packaging cost by recorded
net sales using exact decimal arithmetic, rounded to six places for the report
and two for display. Missing costs and zero revenue produce Unavailable, not zero.
Prime cost % continues to come from the existing reviewed-labour expense report.
The CSV also includes the new food-cost percentage measure with its estimate basis.

The public homepage now describes the delivered CSV imports, recipe costing,
executive overview, labour/expense reporting, report export and team access.
Its report preview uses explicitly fictional figures. Simulators, integrations,
approved snapshots and actual inventory costing remain labelled as future work.
