# Historical reports by role

**Update 030:** PO and supplier GRN reports now each have separate **Register** and **Material detail** views, plus purchasing filters and Excel export. PO receiving progress is separate from order status. Invoice-authorised users also have an ordered/received/invoiced comparison. See [the current purchasing report guide](SEPARATE_PURCHASING_REPORTS.md). The definitions below describe the original 028 milestone; stock, invoice and sales report behaviour remains as described.

Apply `202611170028_role_historical_reports.sql` once after 027 and deploy the matching application. Skip migrations already applied. This migration adds read-only reporting functions and indexes; it does not change stock posting, approvals or supplier invoice accounting.

Open **Reports → Historical reports** from navigation, or **Open historical reports** from an operational user's workspace. The CEO home remains a focused profitability briefing; historical reports are available through its navigation.

## Available reports

| Role | Historical reports |
| --- | --- |
| Inventory Manager | Issued POs and supplier GRNs; requisitions/transfers, waste, counts, consumption, production, stock receipts/opening balances and all stock documents. |
| Inventory / Receiving, optional stock receiver | Issued POs and supplier GRNs within existing outlet receiving scope; stock reports only for stock locations readable under their assignments. |
| Procurement | POs (including drafts), supplier GRNs and current supplier invoices. Stock and sales reports require another independently assigned role. |
| Kitchen or Bar department stock user | Requisitions/transfers, waste and other stock-document reports involving their explicitly assigned locations. No purchasing, sales or financial cost exposure is granted. |
| Optional dispatcher / Operations | Stock reports within existing readable stock-location assignments. No new approval or posting permissions. |
| Business-wide Finance | Sales, POs, supplier GRNs, invoices and stock reports, including waste quantities and dated reference-cost exposure. |
| CEO / Restaurant Administrator | Reports permitted by their existing financial and stock access. |

Roles are combined when a member has more than one. Location-scoped Finance retains its existing stock-location scope and does not gain business-wide invoice or sales access through this reporting feature. Supplier PO/GRN receiving scope and department stock-location scope remain distinct. Changing or revoking a role or stock assignment is enforced again for every report and export.

## How to use the reports

1. Choose a report. Only report types permitted for the signed-in member appear.
2. Choose **From date** and **Through date**. Month to date is the default, using the restaurant's business timezone. **This month**, **Last month** and **This year** are shortcuts. Any earlier year can be selected; each request covers up to 366 days, without the executive overview's 1,000-sales-line limit.
3. Select an outlet and, for stock reports, an assigned stock location/department. Historical inactive locations remain selectable where the member still has read access. Selecting an outlet restricts documents to the visible endpoint in that outlet; unrelated departments are not included.
4. Select a status or search a reference, related PO, material/menu, supplier/channel, location, notes or recorded/requested person. Changing report type clears incompatible location, status and search filters.
5. Click **Apply report filters**. All filters apply before row counts, totals and pagination. Tables show 10 rows per page. Filtering from another page starts at page one.
6. Click a reference to inspect its source document, receipt, invoice or sales batch and existing decision history. A supplier invoice link opens the exact purchase; a GRN opens the exact supplier receipt. An outlet ID is never passed as a stock-location filter to the source screen.
7. **Export filtered CSV** exports the full filtered result, not only the current table page. Up to 5,000 rows are supported per export. Larger results return a clear error and create no partial file; narrow the selection and retry. CSV rows carry the business, reporting dates, filters and generation timestamp, with source decimal precision and spreadsheet formula protection.
8. **Print this page** prints the displayed page with business, report, dates, filters and page context. Use CSV for the complete filtered result. **Refresh report** reloads current evidence without modifying source records.

## What the rows mean

- **POs:** one row per order, with order status and delivery progress derived from accepted quantities in non-voided GRNs. Quoted amounts are not invoices or actual expenditure. When All statuses is selected, quotation totals may include drafts.
- **Supplier GRNs:** one row per delivered order line, with accepted and rejected quantities and the related PO. Active, pending-void and voided records are all filterable. A GRN is not proof of stock-ledger posting.
- **Supplier invoices:** one row per current approved invoice projection. Approved replacements, dates/outlets and voids are respected; pending changes do not replace the current values. Voided amounts remain visible but are excluded from active totals. Full source/correction evidence stays on the invoice detail.
- **Sales:** one row per recorded receipt, using saved net revenue. CSV additionally includes source discounts, tax and customer total, with a source batch link. This is recorded-sales history, not an estimate of unrecorded trading.
- **Requisitions/transfers:** one row per material line. Requested, approved, awaiting-acceptance, completed, incomplete, rejected and cancelled records remain visible. Needs follow-up excludes resolved exceptions. Requested quantity is distinct from accepted and rejected quantity; a rejection is not automatically waste. Stock quantities change only on receiver confirmation under migration 026.
- **Waste:** one row per waste request/material. Pending and rejected requests are not posted waste. Financial roles additionally receive reference-cost exposure on posted rows, using the latest compatible price on or before the actual stock event date. Missing costs remain unpriced, with an explicit incomplete-subtotal warning. Operational-only users get quantities and accountability without financial price exposure.
- **Counts:** physical counted quantity and posted stock change are separate. A posted count with no ledger change shows zero change; pending counts do not imply a posting.
- **Production:** material inputs and produced outputs appear as separate rows, labelled Input/Output. Quantities in unlike units are never added into one report total.
- **Stock receipts/opening balances:** supplier GRN stock postings, direct receipts and openings are separate from the supplier delivery report. All stock documents combines the permitted stock-document types.

The date filter uses the **business document date**; a separate posting date is displayed when available and different. Statuses and approved invoice projections are **current**. This is historical record retrieval, not a frozen reconstruction of status at a past instant. Saved management reports remain the separate reviewed snapshot workflow.

Stock exposure is a reference-price estimate, not actual stock valuation or operating profit. Financial totals are separated by currency. No financial totals are inferred by adding unlike physical quantities. Record histories remain live and can change after approved source corrections.

## Pilot checks

- Inventory Manager: filter an earlier PO period and compare active/voided supplier GRNs against the original order; then inspect posted waste and pending requisitions.
- Procurement: confirm only purchasing reports appear. Inspect partial/completed orders, active/voided GRNs and corrected/voided invoices; confirm the source links open exact documents.
- Kitchen and Bar: give each a different stock-location assignment. Verify each sees only its own requests, waste and production, including internal transfers involving that department. A forged other-department filter or invoice/sales export must fail.
- Finance: reconcile recorded receipt net sales against source sales; reconcile invoice totals after an approved replacement/void. Check reference-valued waste and the missing-price warning. Confirm report access does not enable stock posting or invoice entry.
- Record more than ten matching rows. Compare both table pages with the full CSV and verify identical filters. Try a result over 5,000 rows: it must require narrower filters, with no silently truncated export.
- Test an older year, an empty period, inactive locations, a revoked assignment and another business's ID. Check phone-width tables and print context.

Automated tests exercise role/type boundaries, outlet and department restrictions, correction/void projections, sales reconciliation, filtering before pagination, complete CSV export, oversize refusal, permission revocation, spreadsheet safety, desktop/mobile layout and source links.
