# Direct transactions and Finance-approved procurement corrections

Procurement handles purchase recording, imports and correction proposals. Finance
records expenses, reviews purchase records, and approves/rejects Procurement's
submitted corrections. Finance-only accounts cannot stage/post/cancel purchases,
enter invoices or propose procurement corrections. Only active organisation-wide
roles receive these capabilities. Existing operational administrator access is
preserved; someone explicitly assigned multiple roles receives their combined
capabilities. Migration 017 supersedes the initial Finance-purchase grant in 016.
Finance can review expense coverage and void an erroneous expense with a reason.
Master-data editing is unchanged: Finance does not gain material/supplier/menu
editing, and expense category creation remains an administrator capability.

Manual expense entry no longer asks for source-system or line codes. A source
reference is optional; a missing reference is generated from the retry-safe entry
request. Existing coverage dates, review, recording and audit rules remain intact.

The Purchases sidebar now leads to supplier invoices. The named-supplier/outlet/
material/unit form accepts up to 50 lines, with quantity, unit price, line discount,
line tax and a supplier-declared invoice total. PostgreSQL reuses the existing
CSV validation/posting engine internally, preserving decimal precision, dated
package conversions, reconciliation and idempotent posting. The declared total
is retained for confirmation at review. Unposted reviews persist and can be
cancelled. CSV imports remain available as an alternative.

Manual bills have INVOICED status, separately from old source RECEIVED declarations.
Recording a bill does not confirm delivery, post stock or change reference prices.
Generated CSVs are labelled entry records rather than supplier originals.

## Corrections and permissions

Invoice details show effective current values, with a link to original source
evidence. An authorised purchaser can propose a replacement or void with a reason.
Only Finance approves/rejects; an administrator/CEO without a Finance role cannot
approve. Rejection requires a reason and both decisions require explicit on-screen
confirmation. A Finance-only user cannot create a purchase-correction request.

Pending proposals do not change values. Approved corrections create an effective
projection; original purchase headers/lines, source CSVs and earlier decisions
remain intact. Voids mark the effective invoice as voided, without deleting it.
Invoice list/detail use effective values; import screens label original values.
Purchase-based costing remains unimplemented, so correction approval does not
change a recipe cost or inventory valuation.

Proposals retain before/proposed values, creator identity/time and reason.
Decisions retain Finance identity/time/note with audit entries. RLS, revoked direct
table access, same-tenant foreign keys and a protection trigger restrict history.
Organisation locks, one pending request per invoice, base revisions and request
identities protect retries/stale requests. Approval revalidates the proposal;
changed supplier/material/outlet/conversion details require rejection and a fresh
request. Duplicate invoice identities are checked across sources at staging and
posting, and against approved effective identities for replacement corrections.

## Setup and verification

Apply `202611150016_direct_transactions.sql` after migration 015, then apply
`202611150017_procurement_operational_permissions.sql`. If 016 is already applied,
apply only 017. No live Supabase migration is applied by this implementation.
Do not rerun initial schema.
The migration changes only named transaction guards in existing functions and
aborts if the expected guards/validation statements cannot be found. Master-data
guards and existing reconciliation algorithms remain intact.

Database checks cover Procurement entry, Finance expense recording, denial of
Finance purchase operations, tax/package conversions,
idempotent recording, correction/decision retries, stale revisions, required
reasons, unchanged original rows, changed conversions at approval, voids, audit
counts and cross-tenant/scoped/founder/CEO-only/anonymous denial. Existing role
tests reflect the new Finance transaction permissions. Browser checks cover
multi-line entry, Procurement request/Finance decision, retained source values,
direct Finance expenses and mobile layouts. Fixtures use isolated PostgreSQL
with simulated authentication. Real Supabase integration review remains required.

## PO/GRN roadmap, before inventory

Purchase Orders and Goods Received Notes belong to procurement and should be
delivered before full inventory management:

1. Raise/issue a PO with supplier, destination, material lines and ordered amounts.
2. Confirm deliveries against a PO, including partial deliveries and accepted/
   rejected quantities, then generate a GRN.
3. Link invoices to PO/GRNs and review quantity/price differences. Preserve direct
   supplier bills for purchases without a preceding PO.
4. Later connect confirmed receipts to duplicate-safe inventory movements and
   controlled reversals.

Procurement owns the PO and receipt/GRN operations in this roadmap. Additional PO
approval thresholds and matching tolerances need policy decisions in that phase.
Report approval roles do not automatically decide them.

Receipt/invoice attachments, native editing of unposted reviews, returns/credit
notes, payment accounting, large-catalogue search and inventory remain further
work. This milestone is not a declaration of market readiness: hosted mobile
access, real Supabase checks and restaurant pilots are still required.
