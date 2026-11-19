# Role workspace review ? 19 November 2026

The main sources of clutter were shared navigation that exposed reference/setup areas to Finance, equally prominent shortcuts for every capability, and invoice pages that led with matching explanations and repeated complete invoice histories.

| Workspace | Primary information | Supporting information |
| --- | --- | --- |
| CEO | Executive changes, margin impact and management reports | Source reports and menu profitability; administration when independently assigned |
| Finance | Invoice review, expenses, centre waste, management reports, sales and history | Menu profitability and financial source records; no setup for Finance-only accounts |
| Procurement | Purchase orders, supplier invoices and historical purchasing records | Materials/suppliers and purchase imports; no department requests or stock handling without a separate stock role |
| Inventory Manager | Stock, receiving, requests, own-centre waste and centre/team access | Ledger, processing and historical stock records |
| Kitchen / Bar / delegated stock roles | Permitted stock tasks, waste and history | Assigned centre records; no business administration or financial workspace shortcuts |
| Operations | Operational stock work, materials and recipes | Additional authorised operational records |
| Restaurant Administrator | Business setup and team administration | Operational records according to capabilities |
| Founder | Restaurant lifecycle and onboarding oversight | Existing founder controls remain separate from restaurant workspaces |

Primary home shortcuts are limited to six; additional authorised tools use a closed disclosure. Navigation groups are collapsed by default for CEO and Finance unless the current page is inside them. Multiple independently assigned roles retain their tools; role focus does not grant database permissions.

Invoice details now lead with invoice, supplier, date/outlet, total and material lines. Zero-only discount/tax columns are omitted. Delivery comparisons expand when an unreviewed exception requires attention; resolved reviews and supporting history collapse. Pending invoice corrections retain visible before/proposed values and Finance decisions. Original evidence and audit history are retained.

Finance has a combined, centre-filterable waste log covering processing loss and separate waste records. Source/status filters sit behind a disclosure; centre and date filters remain visible. Export uses the same database scope and one snapshot, with a 5,000-entry limit that rejects oversized exports rather than returning a partial file. Processing losses are not posted a second time. Quantities retain their units and are not presented as a monetary waste valuation. Finance-only users cannot record waste. Inventory Managers retain their own-centre restrictions.

Finance-only direct setup URLs redirect to the workspace. Migration 041 also restricts the setup_workspace RPC. Existing underlying financial reads, reporting calendars and independent admin/stock-manager roles remain available according to their database permissions.

Validation: database permission/reporting regression suite; role matrix tests; browser checks for Finance home/direct setup URLs, invoice matching/corrections, centre waste filtering/export, Procurement home and fresh stock setup; desktop/mobile screenshots; production build and lint.
