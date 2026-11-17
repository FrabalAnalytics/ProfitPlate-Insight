# Purchase invoice imports — first delivery

This implements the approved upload → validate → review → record workflow using
the exact 15 columns from the supplied workbook's Purchases_Import sheet.
It records supplier invoice evidence, separate from inventory posting, reference
price entry, accounting recognition policy and purchase-weighted recipe costing.

## Import contract: PURCHASE_CSV_V1

Export **only Purchases_Import as CSV UTF-8**, or download the header-only template
from Purchase imports. Direct XLSX/workbook uploads are not supported in this
delivery. Limits are 100 logical data rows and 128 KB per file, processed
synchronously; larger/background imports remain future work.

Headers, case and order:

```csv
Organisation_Code,Source_System,Purchase_Date,Purchase_Ref,Line_Ref,Supplier_Code,Item_Code,Quantity,Purchase_UOM,Unit_Price,Line_Discount,Tax,Location_Code,Currency,Status
```

| Field | Required rules |
| --- | --- |
| Organisation_Code | All rows match the explicitly entered source organisation code, 1–40 characters. This source alias maps to the selected authorised business; it never chooses a tenant from the file. |
| Source_System | Stable source identity, 1–60 characters. Keep the same value when repeating or updating an extract. |
| Purchase_Date | Valid YYYY-MM-DD, no future dates in the resolved location's time zone. Stored as a date, not an invented timestamp. |
| Purchase_Ref | Stable source invoice reference, 1–100 characters. One supplier invoice has one date, currency and location in this first contract. |
| Line_Ref | Stable source line reference, 1–60 characters. Distinct within source/supplier/invoice. Leading zeros are retained. |
| Supplier_Code | Existing active supplier inside the selected business, or an explicit source-to-business code mapping. |
| Item_Code | Existing active material inside the selected business, or an explicit code mapping. |
| Quantity | Positive decimal, at most 14 integer and 6 decimal digits; no scientific notation, formulas or commas. |
| Purchase_UOM | Exact existing unit code. Standard dimensions must match; packages require an item-specific conversion effective on the purchase date. |
| Unit_Price | Positive price per Purchase_UOM with the same numeric precision as Quantity. User explicitly chooses tax-inclusive or tax-exclusive source format. |
| Line_Discount | Explicit nonnegative amount for the whole line, not a percentage. Enter 0 only when known to be absent. |
| Tax | Explicit nonnegative final tax amount for the whole line, not a percentage. Enter 0 only when known to be absent. |
| Location_Code | Existing active location in this business or an explicit code mapping. New onboarded businesses currently use PRIMARY for the first location. |
| Currency | Exactly the selected business reporting currency. No inferred FX rate or currency conversion. |
| Status | Exactly RECEIVED. This is preserved as source status and does not trigger stock posting. Orders, cancelled invoices, returns, credit notes and free lines are deferred. |

Source amounts allow six decimals. Multiplication and computed line/invoice amounts
use exact PostgreSQL numeric arithmetic up to 12 decimal places; no implicit
two-decimal invoice rounding. Positive converted quantities and totals must fit
numeric(38,12). Financial values are returned as strings to avoid JavaScript float
rounding. Missing amounts do not become zero.

### Explicit source arithmetic

- Tax-exclusive source: net = Quantity × Unit_Price − Line_Discount;
  invoice amount = net + Tax.
- Tax-inclusive source: invoice amount = Quantity × Unit_Price − Line_Discount;
  net = invoice amount − Tax.

Net must remain positive. This records source arithmetic; it does not determine
tax recoverability, landed cost, freight allocation, inventory valuation or
recognised period COGS. These policies remain pending. Users must independently
enter the complete supplier invoice total for every new invoice and confirm review.
Exact reconciliation is required before saving any purchases.

## Staging, history and source retention

- Server Actions authenticate, check business-wide write access and limit input
  size. The database independently parses the retained CSV and validates every
  row; callers cannot pass arbitrary prepared rows unrelated to the source file.
- UTF-8 BOM, CRLF/LF, quoted commas, escaped quotes and quoted newlines are handled.
  Empty logical records are ignored. Row labels are logical data-row numbers,
  starting at 1 after the header, not physical file line numbers.
- Each attempt retains the original UTF-8 CSV text, filename, SHA-256, source-org
  mapping, code mappings, selected price basis, contract version, findings and
  canonical resolved values. Invalid CSV and rejected rows remain in history.
  Files that are unreadable UTF-8, exceed limits or fail upload metadata checks are
  rejected before staging.
- In this bounded first importer, private source text is stored in PostgreSQL,
  not a public bucket. There is no client SELECT grant on batch/source records.
  Authorised RPCs provide scoped metadata, history and original-file retrieval.
  Object storage and retention-policy management are later scale improvements.
- There is no automatic master creation. The correction screen lets users map
  source material, supplier and location codes to existing business codes or
  choose a corrected CSV. Validation creates a new auditable attempt; prior
  attempts remain unchanged unless explicitly cancelled.
- History paginates 25 attempts. A source download is available to authorised
  readers. Rejected attempts may be cancelled but remain readable.

## Recording and duplicates

Canonical physical tables are `purchase_headers` and `purchase_lines`. Legacy
`purchases` and `purchase_items` remain untouched and are not written by this
importer. This is an additive migration, not a destructive legacy transition.

Identity is organisation + source system + resolved supplier + purchase reference
+ line reference. It does not depend on filename, date/item similarity or display
names. Equivalent numeric formatting such as 2 and 2.0 does not create a conflict.

- All valid new invoices are saved together atomically, after invoice controls
  reconcile. One rejected row blocks the entire attempt; ready rows are never
  partially recorded.
- Unchanged source lines already recorded are explicit duplicates and skipped.
  Reimporting a subset of an existing invoice records nothing new; displayed
  duplicate totals describe only uploaded lines.
- Changed or additional lines for an existing invoice are rejected. Correction,
  reversal and supersession workflows are deferred; no old line is silently
  overwritten or extended. Users must not rename source identities to circumvent
  a conflict.
- Organisation locking serialises recording. A second staged attempt that becomes
  stale is revalidated and returned for explicit review before another save.
  Changed conversions, names, master status and newly recorded duplicate lines
  cannot silently bypass the review screen.
- Stage requests are idempotent by request ID/input hash. Saving the same posted
  batch is idempotent. Attempts, recordings and cancellations are audited.
- Package conversion ID/factor and normalised quantities are pinned on recorded
  lines. Source identity comparison uses original economic inputs, preserving
  duplicate recognition after later catalogue conversion changes.

## Access

Only active organisation-wide restaurant administrators and procurement managers
may upload, map, record or cancel. Organisation-wide CEO and finance roles may
read history, invoice lines and sources. Location-scoped staff, operations-only
roles, unrelated businesses, unassigned founders and anonymous users cannot access
business-wide purchase data. Tables, source retrieval and every function enforce
this boundary independently of rendered buttons. No service-role key is required.

## Enable in Supabase

Run the complete new file once, after migrations 001–007:

`supabase/migrations/202611140008_purchase_imports.sql`

The agent has not applied this remotely. Refresh the app and open **Purchase
imports**, or **Data & Setup → Open purchase imports**. A missing migration shows
an unavailable screen without breaking existing catalogue or recipe features.

## Fictional first test

The supplied downloadable `public/templates/fictional-purchases.csv` is explicitly
fictional and uses the founder's existing demo material codes:

1. Under Materials & suppliers → Suppliers, add an active supplier with code
   **SUP001**, for example **Demo Supplier**, if it does not already exist.
2. Confirm materials **RICE001**, **CHICKEN001**, **BOX001** and the location code
   **PRIMARY**. Use code mappings if your codes differ.
3. Upload the fictional CSV; enter source organisation **ORG001** and select
   **Unit_Price excludes tax**.
4. Review 50 kg rice at 1,800/kg, 1 kg chicken at 6,000/kg and 12 boxes at 100 each.
   The source discount and tax fields explicitly contain 0.
5. Enter supplier invoice control total **97200**, confirm review and save.
6. Upload it again: all three lines should be labelled already recorded and no
   new purchases should be created.

This is test data, not actual supplier evidence. Saving it creates demo purchase
records only after review, never stock movements or reference prices.

## Verification and remaining work

Tests cover actual PostgreSQL migrations/functions/RLS, exact tax arithmetic,
invoice controls, row/file findings, private original-source hash/download,
duplicates and conflicting corrections, code mappings, conversion pinning,
stale/concurrent staging, cancellation, history paging and role/tenant isolation.
Chrome checks cover the complete review/save/reimport flow, mapping on mobile,
source download, malformed-file cancellation and read-only finance access.

Real Supabase integration still needs confirmation after migration 008 is applied.
Direct XLSX, custom column mapping, reusable source mapping profiles, large
background jobs, actual receipt posting, credit notes/returns, posted corrections,
sales imports, reference-price updates and purchase-weighted costing remain
separate deliveries. The Sales & procurement setup stage is labelled **Purchases
available**, not complete, and the overall setup-ready count is unchanged.
