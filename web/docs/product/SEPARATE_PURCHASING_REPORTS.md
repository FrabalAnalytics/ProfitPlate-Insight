# Separate PO and GRN reports

Apply **202611170030_purchasing_report_views.sql** once after 029, then deploy the matching application. Skip migrations already applied. This adds read-only reporting functions; existing POs, GRNs, invoice evidence, approvals and stock-posting rules are preserved.

## Reports and their row definitions

Open **Reports → Historical reports**, select **Purchase Orders** or **Goods Received Notes**, then choose a view.

| Report | Each row represents | Main contents |
| --- | --- | --- |
| PO register | One order | PO/date, supplier, destination, material-line count, order status, receiving progress, quoted total and requester |
| PO material detail | One ordered line | Material/code/unit, ordered/accepted/outstanding quantities, quoted unit price, declared discount/tax and quoted line total |
| GRN register | One supplier delivery receipt | GRN/date, linked PO, supplier/destination, material-line count, receiving person and active/pending-void/voided status |
| GRN material detail | One received material line | GRN and PO references, material/code/unit, quantities accepted/rejected on that delivery, rejection reason and receiver |
| Ordered / received / invoiced | One ordered line | Ordered, accepted, outstanding and linked billed quantity, comparable net prices, net price variance exposure and review flags |

PO and GRN reports stay separate. A PO with two material lines and two deliveries remains **one PO register row**, becomes **two PO detail rows**, and may produce **two GRN register rows / four GRN detail rows**. The quoted PO total is not repeated or multiplied by joining deliveries.

The comparison view is available only to members who already have invoice/financial read access (Procurement, business-wide Finance, CEO or Administrator). Inventory-only roles retain PO/GRN reporting without acquiring supplier invoice access. Department users do not gain purchasing reports.

## Filters and totals

- Choose business dates, outlet, supplier, material, recorded/requesting user and free-text search. PO **Order status** and **Receiving progress** are separate filters. GRNs use their own correction status.
- Supplier, material, user and outlet choices come from records permitted for the signed-in user. Inactive historical parties/items remain reportable where their documents remain readable. The database rechecks every report and export.
- A material filter in a **register** selects complete documents containing that material. Its PO quoted total still describes the whole order. A material filter in a **detail** view selects matching material lines; totals cover only those lines.
- PO dates select the order period. Receiving progress and linked invoice comparisons are **current cumulative** values, including deliveries or invoices dated after that period. GRN dates select the receiving period. These are not frozen reconstructions of status at an earlier instant.
- Current PO receiving progress uses accepted quantities from non-voided GRNs. Rejected goods do not reduce outstanding quantities. Pending-void receipts continue to count until approved; their review state remains visible.
- Money totals are separated by currency. No unlike physical units are added into one total. GRN registers do not present PO quotation values as received inventory value.
- Queries cover up to 366 days. Tables show 10 rows per page. Filtering starts at page one, and filters apply before pagination/counts.

## Invoice comparison and accountability

Only the latest declared PO links and current, approved invoice projections are considered. Approved invoice voids are excluded. Replacements that invalidate saved invoice links produce **Invoice links need review** and withhold the affected cumulative billed figures; missing or stale evidence never silently becomes a valid zero.

Invoice quantities are normalised through the saved base-unit conversions, then expressed in the order's unit. Aggregation uses base quantities before division, avoiding artificial exceptions for recurring conversions such as three 1 KG invoices against a 30 KG bag. Exact cross-multiplication compares price bases before display rounding.

Prices are comparable **after discount, excluding tax**, per order unit. Net price variance exposure is linked invoiced net amount minus the PO net price applied to its linked billed quantity. This is a variance against the quotation, not actual profit, payment, inventory valuation or a proved employee/supplier fault. It must not be added to waste and other overlapping profitability estimates as a causal profit bridge.

Flags identify stale links, absent linked billing, pending corrections, billing above accepted quantities, net-price differences, or aligned linked quantities/prices. Invoice references link to their existing source and review workflow. Unlinked bills are not inferred to belong to an order. A line without linked invoices is not cleared merely because another line on the PO has been billed.

## Excel, CSV and printing

**Export filtered CSV** and **Export Excel** use the same date/location/supplier/material/user/status/view filters as the displayed report. They include all matching rows, up to 5,000 per export. Larger requests return an explicit error and produce no partial file; narrow the filters and retry.

Excel has **Report context** and **Data** sheets. The data sheet has frozen headers, column filters and repeated document dates/references on every material line, with no merged date-divider rows that would interrupt sorting or pivots. The context sheet records filters, generation time, counts, totals and reporting basis. Numeric values beyond Excel's 15 significant digits are stored as text to preserve source precision. Spreadsheet formulas are never emitted from source text; CSV formula prefixes are neutralised.

Printing covers the displayed report page with business, view, filters and dates. Use an export for the complete filtered dataset. Existing reviewed/saved management reports remain a separate snapshot workflow.

## Operational desktop browser

On **Purchase Orders & GRNs**, choose **View materials & GRNs**. On wide desktop screens, the selected order opens beside a document list showing reference, supplier, total, business date and status. Selecting another card changes the detail without discarding the filter/page context. The selected order includes ordered materials and its linked GRNs, with expandable received-material tables.

The regular register remains the initial overview and returns when details are closed. Narrow screens retain stacked details and tables that scroll inside their containers. Details are fetched only for the selected, authorised PO. Procurement-only users continue to have no inventory requisition/movement access under 029.

## Pilot verification

1. Create a PO with two materials and record two partial supplier deliveries. Confirm register/detail row counts and that the quoted order total appears once.
2. Filter by one material. Compare full-document register totals with selected-line detail totals. Check supplier, outlet, requester/receiver and status filters.
3. Receive quantities in separate GRNs; verify each detail row shows that delivery's quantity, while the PO shows cumulative active acceptance/outstanding quantities.
4. Link an invoice with a different price or quantity. Review the comparison, invoice link and source flags. Test a different purchase pack unit with a saved conversion.
5. Approve an invoice correction: stale links must be flagged until Procurement reviews them. Approve a GRN void: its history remains visible while PO receiving totals change.
6. Export a filtered detail view in CSV and Excel. Confirm every matching row appears, dates/references repeat, context is retained and totals match the selected view.
7. Test Inventory, Procurement, Finance, a department-only user and an unrelated account. Inventory must not obtain the comparison by a copied URL/export request.
8. Inspect the desktop document browser, narrow-screen tables and print context. Confirm Procurement still has no material requests/movement workspace.

Automated verification covers these report grains, totals, filters, conversions, corrections/voids, oversized exports, permissions, workbook structure/precision/formula protection, actual downloads and desktop/mobile flows.
