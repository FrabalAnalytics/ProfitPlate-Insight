# System record-table review

Reviewed the existing screens against the shared PO/GRN record-table design.
This update changes presentation and navigation labels; it does not add database
tables, change calculations, grant permissions or require a new migration.

## Record views using the shared design

| Area | Tabular data |
| --- | --- |
| Business setup | Locations, brands attached to each location, addresses, time zones and availability |
| Materials and suppliers | Material catalogue, supplier directory, effective-dated package conversions and standard unit dictionary |
| Reference prices | Material price coverage, saved price history and reviewed prices before saving |
| Recipes | Recipe library, pinned component quantities, scaled material requirements and reference-cost line breakdowns |
| Menus | Menu catalogue and dated selling-price history with outlet, channel, tax basis and notes |
| Purchases | PO register, PO lines, GRN register and lines, supplier invoices and lines, import history, reconciled invoice totals and import location codes |
| Matching | Ordered/received/billed comparisons, related GRNs, PO-link history and Finance review history |
| Sales | Menu sales breakdown, missing-cost findings, location-code lookup and import history |
| Expenses | Recorded entries, category totals, category/location import codes and import history |
| Executive overview | Outlet comparison, menu performance, recent receipts and the daily figures behind the trend chart |
| Management reports | Financial detail, coverage, daily/outlet/channel breakdowns, menu performance, missing-cost detail, saved reports and review activity |
| Team | Memberships, assigned role/location scopes and invitation lifecycle history, including existing management actions |

Purchase, sales and expense source lines reuse the interactive transaction table
with the same shared table appearance. Row detail controls retain their keyboard
labels, expanded state and links to original evidence. Mobile views retain all
columns inside a horizontal scrolling region rather than hiding record fields.

## Deliberately retained layouts

- KPI and completeness cards summarize one measure rather than a record list.
- Sales trend and channel mix remain visual charts; daily figures have a table.
- Setup instructions, onboarding steps, navigation/task shortcuts and marketing
  feature cards guide a workflow rather than represent stored record rows.
- Entry forms, source-code mapping controls, version selectors and confirmation
  screens keep their existing form controls and validation.
- Invoice/GRN correction cases retain the detailed comparison and decision forms
  needed to review a specific request. Their financial lines use shared tables.
- Founder and account-access screens currently contain access messages and planned
  capabilities, without an existing customer/activity register to convert.

## Shared behavior

Tables use named semantic headers, a row header, aligned numeric columns, consistent
cell spacing, status badges and visible record links. Long names and notes wrap;
missing prices, unavailable values, source dates, role scopes and audit notes stay
explicit. Scrolling is contained within the table panel on small screens. Report
printing retains table headers, source context and estimate/coverage warnings.

Existing search, pagination, record identities, permissions, original source
records, decimal formatting and estimate boundaries remain in force.

## Verification

The production build and 31 form/value checks pass. Lint has no errors; three
existing unused-variable warnings remain in database fixtures. The browser sweep
exercised 53 scenarios covering all modules, desktop/mobile layouts, read-only
access, team actions and printed reports. Retired card selectors were updated to
semantic table rows. A mobile overflow caused by visually hidden transaction
labels was fixed by containing their positioning inside the scrolling region;
all 10 transaction, expense and purchase-import scenarios passed the focused
recheck after that fix. No live database changes were made.
