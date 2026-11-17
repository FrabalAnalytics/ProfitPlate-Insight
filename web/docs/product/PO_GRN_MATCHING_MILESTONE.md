# Purchase Orders, GRNs and invoice matching

## Agreed roles and separate records

The owner selected **Procurement issues POs directly; Finance reviews invoice
exceptions**. Procurement and Inventory / Receiving are now separate roles.
Existing operational administrator purchasing access remains; receiving requires
an explicit Inventory role. Finance-only
roles cannot raise/issue POs, confirm deliveries, enter bills or set procurement
links. Finance can inspect the records, review invoice exceptions and decide
submitted procurement corrections. Report approval authority is unchanged.

Inventory can read issued orders and confirm deliveries only at assigned locations
(or all locations with an organisation-wide Inventory assignment). It cannot create
POs or supplier invoices. The PO preparer and issuer cannot confirm its receipt,
even if either holds Inventory as an additional role. Inventory requests GRN voids;
Finance decides them. Existing evidence remains unchanged by this permissions update.
Apply `202611160020_inventory_receiving_separation.sql` after 019. Existing
Procurement assignments are renamed, without automatically granting Inventory.

An order records what was ordered. A GRN records physically accepted/rejected
delivery quantities. A supplier invoice records the supplier's billing claim.
This delivery implements no payment ledger or payment authorisation and posts no
inventory movements. Invoice matching is an operational comparison, not accounting
verification, a stock balance or proof of settlement.

## Orders and receiving

Procurement saves a draft with supplier, delivery outlet, order date, optional
quotation reference/delivery-needed date/notes, selected tax basis, up to 50 lines
and a quoted total. PostgreSQL reuses existing decimal-safe quantity, dated unit
conversion, tax and total validation. Drafts have optimistic revisions and can be
edited. Issuing requires explicit confirmation and revalidation; issued order
terms and lines become immutable. Generated PO numbers are stable and printable.

Confirmed deliveries against an issued PO generate numbered, printable GRNs.
Inventory records a received date, supplier delivery reference, accepted/rejected
quantities in the ordered unit, rejection reasons and notes. Quantities are not
automatically copied as accepted. Rejected goods do not consume the order balance.
Partial deliveries leave a visible outstanding quantity; accepted quantities cannot
exceed the remaining order. Excess goods can be recorded as rejected with a reason.
Delivery reference uniqueness is case-insensitive per PO, and matching request
retries return the same GRN rather than posting again. All lines record atomically.

A mistaken GRN is not edited. Inventory requests a void with a reason and Finance
approves/rejects the specific request, also with a reason. Confirmation, original
GRN lines and earlier requests remain in history. Only an approved void removes
its accepted quantities from the current receiving totals. Inventory can then
record a corrected delivery under a new delivery reference. Pending GRN corrections
block invoice exception acknowledgement until Finance resolves them.

## Invoice routes and matching

New manual bills explicitly choose PO-backed or Purchase without PO. Selecting an
issued PO copies its supplier, outlet, quoted prices/tax basis and lines as a
starting point; the user must enter the actual supplier invoice number/date/figures.
Every invoice line can link to a PO line, or remain unmatched with a visible
exception. Issued PO selection searches by number/supplier, returns up to 50
results, and retains a selected older order. It does not limit the number of POs.

A no-PO bill requires a reason and an evidence reference explaining where Finance
can inspect the supplier document. This is text evidence metadata, not a file
upload. A bill without a PO never implies physical delivery. Both PO and direct
routes retain the existing source validation, tax declaration, invoice-total
reconciliation and duplicate-safe posting. Metadata is committed with a newly
posted manual bill. Duplicate posting does not rewrite an existing bill's links.

Existing bills and CSV imports remain intact. They are explicitly Unclassified
until Procurement adds PO links or a no-PO reason/evidence reference. Such missing
context blocks Finance acknowledgement. Link changes append an auditable version;
they do not edit financial invoice values. Approved financial corrections make
previous links stale until Procurement reviews and re-saves them.

The invoice list exposes current matching status, and detail shows:

- PO link or no-PO reason/evidence, plus related GRNs.
- Ordered, accepted and cumulative billed quantities in saved base units.
- Missing/mismatched line links, material/unit differences, over-order and
  over-receipt billing, changed net prices/tax rates and invoice dates before POs.
- Latest Finance decision, whether it still applies, and recent link/review history.

Quantities include all current, non-voided invoices linked to the same PO line,
so splitting over-billing between invoices cannot hide it. Receiving includes all
confirmed, non-voided GRNs for the PO. Invoice quantities are not individually
allocated to GRNs in this milestone; the comparison is cumulative per PO line.
Net-price/tax comparisons use exact numeric cross-products and saved base-unit
conversions, without inventing tolerances or currency conversions.

Finance can acknowledge reviewed exceptions or request correction/missing
evidence, with a required note and confirmation. Exceptions remain visible even
after acknowledgement. Missing/stale links, voided invoices, currency/scope
mismatches or unresolved procurement corrections prevent acknowledgement.
Acknowledgement never records or authorises payment.

A source fingerprint covers current invoice/version, link version, PO terms,
receipts/void states, related invoices and pending corrections. Changes invalidate
an earlier Finance review; stale submissions fail with a refresh instruction.
If the current sources genuinely match after a later delivery, the status becomes
Matched rather than requiring an invented exception review.

## Database setup, safety and verification

Apply only `202611150018_purchase_orders_and_receipts.sql`, then
`202611150019_procurement_invoice_matching.sql`, after migration 017, followed by
`202611160020_inventory_receiving_separation.sql`. If 019 is already applied,
apply only 020. No live
Supabase migrations are applied by this implementation. Do not rerun initial
schema or earlier applied migrations.

Tables have tenant ownership, UUID identities, actor/time metadata, RLS and revoked
direct client privileges. Foreign keys and validation enforce same-tenant order,
receipt and invoice relationships. Issued/confirmed evidence and link/review
versions are protected against rewriting/deletion. Narrow security-definer RPCs
use an empty search path, current role checks, organisation locks, retry identities
and source/revision checks. Private wrappers preserve the existing purchase posting
algorithms. Source files, prior invoices and existing founder access are preserved.

Database tests cover role/tenant boundaries, draft/issue retries, immutable issue,
partial/rejected deliveries, over-receipt rollback, duplicate references, cumulative
billing, no-PO requirements, Finance review retries, stale corrected invoice links,
GRN voids and invalidated reviews. Browser checks exercise issue, partial delivery,
print/PDF GRN, PO-backed invoice entry, Finance exception review, later matching,
GRN void approval and mobile layouts. Existing expense/import/correction workflows
are regression checked. Fixtures use isolated PostgreSQL and simulated Auth; real
Supabase integration remains a manual check after setup.

Verification on 16 November 2026: production build passed; all 133 database tests,
29 form/value tests and 8 focused browser tests (procurement workflow, team and
workspace home) passed. Lint has no errors and three existing unused-variable
warnings in database test fixtures. Invitation capture and team forms no longer
set React state synchronously in effects. No live migration was applied.

## PO register and automatic totals update

Apply only `202611160021_purchase_order_register.sql` after 020. The new read-only
register filters all permitted orders before counting and paginating. Draft and
Issued describe order state; Pending delivery, Partially received and Completed
derive from accepted quantities on every order line, excluding approved GRN voids.
Rejected-only deliveries remain pending; an approved void can reopen a completed
order. Completed means fully received, without implying invoice approval or payment.
The agreed workflow still has Procurement issuing directly, so there is no separate
Approved PO state.

PO entry computes line and order totals using exact decimal arithmetic as quantities,
prices, discounts, tax amounts and price basis change. Tax-inclusive prices do not
add tax twice. Incomplete or invalid lines leave the total blank. The database
still validates saved totals. Supplier invoice totals remain entered from the
actual source document for independent reconciliation.

PO lists, GRN history within a PO and PO/GRN material lines use semantic tables.
Tables scroll within their panels on narrow screens, retain record links and
actor/status details, and adapt to printed documents. Existing evidence and
receiving/Finance permissions are unchanged. The new register uses the same
tenant and location checks as order detail.

The shared record-table styles load in the root layout for consistent direct
visits and navigation across Procurement, Inventory and Finance. PO/GRN registers
and lines, supplier-invoice lists and lines, matching comparisons and related GRNs,
purchase/expense import histories and expense category totals share aligned
headers, numeric columns, borders, responsive scrolling and status treatments.
The PO register groups supplier/outlet details and uses its PO number as the
record link to avoid a redundant action column. This visual update requires no
additional migration beyond 021 for the existing register filters.

## Further work

File attachments, standalone GRNs for non-PO purchases, issued-PO amendments/
cancellation, returns/credit notes, per-GRN invoice allocations, payment recording,
supplier distribution, inventory posting/valuation and high-volume background
matching remain separate deliveries. Native forms offer up to 1,000 active master
options; larger master catalogues still need searchable selectors. Recent link/
review history shows 20 entries of each kind while all records remain retained.
Hosted mobile access and real restaurant pilots remain release requirements.
