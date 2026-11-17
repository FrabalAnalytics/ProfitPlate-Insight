# Labour and operating expenses: management reporting foundation

Apply `supabase/migrations/202611150013_expense_foundation.sql` ONCE after 012.
The coding agent has not applied this to live Supabase. Refresh and open
**Labour & expenses** in the restaurant workspace.

## Financial contract

- Manual entry and UTF-8 CSV use one review/record workflow. Amounts are positive
  source expense amounts, with up to 14 integer and six decimal digits. Currency
  must match the business; no conversion, payroll burden or tax treatment is
  inferred. Supply the reportable expense amount from the business's records.
- Every record identifies an expense coverage period separately from its optional
  actual payment date. A blank payment date means not provided, not zero or unpaid.
  Future payment dates are rejected; future coverage is permitted for explicit
  schedules such as prepayments. Reports cannot end after the current business day.
- ON_DATE assigns the whole amount to one date; start/end must match. DAILY is an
  explicitly selected equal-calendar-day management allocation over 1–3,660 days.
  It is not evidence of actual daily labour consumption. No method is preselected.
- Daily slicing uses cumulative differences rounded at six decimal places.
  Adjacent reporting slices reconcile back to the complete source amount. Reports
  display two decimals; exact source/period values remain available in details.
- Categories have a fixed LABOUR or OPERATING type. Seeded codes are WAGES,
  EMPLOYER_COSTS, OTHER_LABOUR, RENT, UTILITIES, ADMIN, MARKETING, CHANNEL_FEES and
  OTHER_OPERATING. Administrators may add codes, up to 100 per business. Historical
  classification is not editable through a category-update UI.
- LOCATION entries require an existing location code in this business. CENTRAL
  entries require a blank location code. Central costs remain unallocated: they
  enter the all-business report but are excluded from individual-outlet totals.
  No menu, outlet, revenue-share or preparation-time allocation is assumed.
- Ingredient purchases and recipe packaging already counted by the food-cost
  workflow should not be entered again as operating expenses. Owner drawings,
  financing, depreciation and tax classifications are not inferred. Imputed owner
  labour belongs in a separately labelled future model, not fabricated payroll.

## Completeness and estimated prime cost

Recorded labour and operating subtotals may be partial. Without entries and a
coverage review, the UI says Not confirmed rather than assuming zero.

An administrator explicitly reviews LABOUR and OPERATING coverage for an exact
reporting range and scope. This permits a declaration of genuinely known zero
costs. A review is not an accounting close, audit or proof of source completeness.
Review fingerprints include relevant entries/voids, currency, location identities
and legacy expense sources. Changes make the review stale. Unrelated operating
changes do not invalidate labour coverage. Reviews do not automatically carry
from an all-business selection into an outlet or another date range.

Estimated prime cost = the existing reference-based food-cost estimate + reviewed
recorded labour. Operating expenses are not added. Prime cost is unavailable if
labour is unreviewed, food cost is incomplete or no sales have been recorded.
Percentages use the same period/outlet's recorded net sales, excluding declared
sales tax; division by zero yields no percentage. Sales comparison limits/errors
do not hide valid expense entries. An expense review does not establish that all
sales were imported. Actual prime cost and operating profit remain unavailable.

## Source integrity and corrections

EXPENSE_CSV_V1 is an additive contract, not a change to the original workbook's
other imports. It uses these exact 14 headers:

```csv
Organisation_Code,Source_System,Expense_Ref,Line_Ref,Category_Code,Scope,Location_Code,Expense_From,Expense_To,Recognition_Method,Payment_Date,Amount,Currency,Description
```

Maximum 100 logical rows / 128 KB. Quoted commas, escaped quotes/newlines, BOM and
CRLF are supported. Original source text, filename and SHA-256 remain private.
Readable invalid attempts remain in history; corrections create a new attempt.
All rows must validate, and an independently entered grand total of every source
line, including duplicates, must reconcile before atomic posting.

Identity is organisation + source system + expense reference + line reference.
Equivalent numeric formatting is an unchanged duplicate. Changed source details
are blocked; nothing is overwritten. Creation requests and posting retries are
idempotent. Revalidation detects stale reviews and requires another explicit
review. An expense may be voided with a reason; it remains in the source and audit
history. An unchanged reimport of a voided expense never reactivates it. Replace a
corrected expense with a new stable source reference after voiding the original.

## Access and legacy data

Organisation-wide CEO, Finance and Restaurant Administrator roles may read.
Only organisation-wide Restaurant Administrators record, void, create categories
or confirm coverage. Procurement/operations-only, scoped-only, unrelated,
inactive and unassigned founder accounts cannot read the new payroll/cost data.
New tables have RLS and no direct client read/write path; authorised functions
enforce access independently of the interface. All mutations are audited.

The original `expenses` / `expense_categories` tables are preserved. Their direct
authenticated insert/update/delete path is disabled, and reads are restricted to
the same financial roles. New records use `expense_entries` and
`management_expense_categories`. Legacy amounts are not silently classified,
scheduled or merged. Relevant legacy rows produce an exclusion/reconciliation
warning and invalidate coverage fingerprints when changed. Reconcile applicable
legacy costs into the new workflow before declaring coverage complete.

## Beginner fictional sample

1. Download fictional-expenses.csv from Add expenses → CSV import. It uses ORG001,
   PRIMARY and NGN. Review the two rows and enter source total **3600**.
2. Select **2026-11-15 to 2026-11-15**, All business locations + central costs.
3. The wages entry contributes **NGN 600** on that date. The **NGN 3,000** central
   rent schedule covers November 1–30 and contributes **NGN 100** for this day.
4. Confirm labour coverage only after reviewing the fictional dataset. With the
   original sales sample and NGN 900 recipe reference cost, estimated food cost is
   **NGN 2,700**, estimated prime cost **NGN 3,300 / 75.86%**, labour **13.79%**.
5. Operating coverage is reviewed separately. Selecting the outlet excludes the
   central rent and requires a review of that exact outlet scope. Reimporting the
   same file must skip the original entries rather than double-count them.

## Verification and remaining scope

Database tests exercise migrations, legacy preservation/privacy, source totals,
duplicate/stale reviews, allocation rounding, payment/coverage separation,
review invalidation, known zero, prime-cost prerequisites, role/tenant isolation,
currency mismatch, caps and audit. Browser checks cover manual/CSV entry, quoted
descriptions, download, repeat imports, voids, mobile filters and read-only finance.

Live Supabase verification follows migration 013. The preview supports 93 days,
2,000 new entries and bounded legacy reconciliation, with paginated entry/source
history. It is not a full payroll, accounts-payable or statutory accounting system.
Credits, automated payroll/ERP feeds, recurring generators, inventory-based actual
COGS, menu/outlet allocation policies, locked reporting snapshots and full P&L
reporting remain separate work. The executive overview's existing food margins
are unchanged; its navigation links to the same period/outlet's expense report.
