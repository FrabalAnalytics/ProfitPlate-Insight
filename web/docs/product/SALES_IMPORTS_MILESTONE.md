# Sales imports and live period food margins

Implements the approved next step: source sales → receipt review → immutable
recording → period/location revenue and estimated food margins. It follows the
supplied Sales_Import worksheet's exact 16-column order. This is not an actual
inventory COGS engine or a finalised financial report.

## Enable in Supabase

After migrations 001–009, run the entire new file once in SQL Editor:

`supabase/migrations/202611150010_sales_imports.sql`

The coding agent has not applied this remotely. Refresh ProfitPlate and open
**Sales & summary**, or **Data & Setup → Open sales imports**. Missing functions
show an unavailable screen without breaking existing features.

## Source contract: SALES_CSV_V1

CSV UTF-8 only, maximum 100 logical data rows and 128 KB. Export only Sales_Import
from Excel, or download the in-app template. Original UTF-8 source text, filename,
SHA-256, source settings, code mappings, validation findings and resolved values
are stored privately. UTF-8 BOM, quoted commas/quotes/newlines and CRLF/LF are
supported. Unreadable/non-UTF-8/oversized files fail before staging; readable CSV
format errors and row findings remain in private import history.

```csv
Organisation_Code,Source_System,Location_Code,Sale_Date,Transaction_Ref,Line_Ref,Menu_Code,Quantity,Gross_Sales,Discount,Tax,Net_Sales,Channel_Code,Line_Type,Parent_Line_Ref,Status
```

| Field | Rule |
| --- | --- |
| Organisation_Code | Every row matches the explicit source alias entered on upload, 1–40 characters. The selected authorised business defines the tenant, never this file field. |
| Source_System | Stable source identity, 1–60 characters, retained across repeats. |
| Location_Code | Existing location in this business, or explicit mapping. Current inactive locations may be used for historical records, with a review warning. |
| Sale_Date | YYYY-MM-DD, a real calendar date, not in the future in the location's time zone. No transaction timestamp is invented. |
| Transaction_Ref | Stable source receipt identity, 1–100 characters. |
| Line_Ref | Stable source line identity, 1–60 characters; leading zeros retained. |
| Menu_Code | Existing recipe-linked menu in the location's brand, or explicit mapping. The menu must have a version effective on Sale_Date. Current inactive menus are allowed as historical source data with a warning. |
| Quantity | Positive menu units sold; at most 14 integer and six decimal digits. Negative/zero quantities, scientific notation and formulas rejected. |
| Gross_Sales | Explicit nonnegative whole-line amount, not a unit price; up to six decimals and 14 integer digits. |
| Discount | Explicit nonnegative whole-line amount, not a percentage; enter 0 only when known to be absent. |
| Tax | Explicit nonnegative whole-line final tax amount, not a rate; no tax rate is inferred from menu prices. |
| Net_Sales | Explicit nonnegative source line amount, reconciled under the selected source format. Never inferred from today's menu price. |
| Channel_Code | DINE_IN, TAKEAWAY or DELIVERY, or explicit source-channel mapping. |
| Line_Type | NORMAL only. COMBO_PARENT and COMBO_CHILD are explicitly blocked, rather than partly imported or double-counted. |
| Parent_Line_Ref | Must be blank for NORMAL lines. |
| Status | PAID only. Refunds, voids, unpaid transactions and reversal/cancellation semantics are deferred. |

The worksheet has no currency column. The upload explicitly declares that all
amounts are in the selected business reporting currency; the database enforces
that declaration. No FX rate or conversion is guessed. Separate service charges,
tips, commission/fee lines and adjustments are not supported by this contract.

### Explicit source tax formats

The user must select one of these formats, with no preselected default:

| Format | Required source identity | Normalisation |
| --- | --- | --- |
| Gross_Sales and Net_Sales both exclude tax | Net_Sales = Gross_Sales − Discount | net revenue = Net_Sales; customer total = Net_Sales + Tax |
| Gross_Sales and Net_Sales both include tax | Net_Sales = Gross_Sales − Discount | net revenue = Net_Sales − Tax; customer total = Net_Sales |
| Gross_Sales includes tax; Net_Sales excludes tax | Net_Sales = Gross_Sales − Discount − Tax | net revenue = Net_Sales; customer total = Net_Sales + Tax |

All fields must be supplied, including explicit zero amounts. Negative normalised
net revenue is rejected. A genuine zero-net, fully discounted NORMAL line is
accepted when explicitly supplied and reconciled: its recipe still incurs estimated
cost, its food margin can be negative, and percentage margin is undefined for zero
net revenue. A zero source amount is never used as a substitute for missing cost.

## Menu bindings and review

For each sale date, resolve the latest effective menu version on or before that
date; same-date versions use the newest published version. The upload explanation,
row review and final confirmation explicitly disclose this resolution. The review
shows menu name/version and resolved location. Posting saves the specific menu
version ID; it is never silently rebound to a later version.

Dates are day-level because the source has no transaction times. Intraday recipe
changes cannot be distinguished automatically and need a future contract extension.
Source menu/location/channel codes can be mapped to existing codes during correction.
No menus, recipes or locations are created automatically. Correcting a file or
mapping creates a new auditable attempt; the old attempt remains in history.

Before posting, independently enter the **customer total from each new receipt**,
including tax where charged. The complete set of uploaded receipt lines must
match exactly. One receipt has one location, sale date, source currency/format and
sales channel. All rows must validate; one rejected row blocks the entire attempt.
Valid revenue can be recorded even if reference ingredient prices are missing.

## Duplicate protection and source integrity

- Receipt identity: organisation + source system + resolved location + transaction
  reference. Line identity additionally includes Line_Ref, preserving separate
  receipt lines and allowing receipt references to repeat across locations.
- Exact economic duplicates are shown and skipped; equivalent decimal formatting
  such as 2 and 2.0 matches. A changed or additional line on an existing receipt
  is blocked for a future correction/reversal workflow, never overwritten.
- Menu-version resolution is excluded from source duplicate fingerprints so a
  later menu correction does not cause unchanged source sales to be recorded twice.
  The originally posted line's binding remains unchanged.
- Stage request IDs and input hashes make upload retries idempotent. A posted
  batch's save is idempotent. Posting is atomic and serialised per organisation.
- Revalidation before saving detects newly recorded duplicates, changed dated menu
  versions, mappings/master metadata and review warnings. Updated findings return
  for explicit review before another save.
- Immutable canonical tables are `sales_headers` and `sales_lines`. Legacy `sales`
  and `sale_items` remain untouched; no legacy records are silently merged.
- Private source storage is bounded PostgreSQL text, as with purchase imports.
  Direct client SELECT on source batches is revoked. Metadata, paginated history,
  source retrieval and all writes use authenticated, authorised functions.
- Attempts, recordings and cancellations are audited. Unposted attempts may be
  cancelled but retain their source/history. Posted corrections remain deferred.

## Period/location summary

Defaults to the current business reporting month through today, with an all-location
or selected-location filter. Historical inactive locations remain available.

- Recorded net sales are the normalised imported amounts after source discounts
  and excluding declared tax. Current menu selling prices never replace source
  revenue. Tax, discounts, customer totals, receipt count and quantities remain
  separately visible.
- Each line's estimated ingredient/packaging cost uses the **posted menu version**,
  its saved recipe quantity and immutable recipe/sub-recipe links, with reference
  prices effective on or before the sale date. Calculations use PostgreSQL numeric;
  financial results are returned as decimal strings, with costs rounded to 12 digits.
- Later menu/recipe versions do not change old line bindings. Backdated reference
  price corrections can change this **live estimate**, which is explicitly not a
  finalised historical report or actual inventory consumption/operating profit.
- If any line lacks usable costs, the full period food cost and margin are null.
  A labelled known-cost subtotal, coverage counts and missing-cost links are shown.
  Recorded revenue remains available. Each menu group follows the same full-coverage
  rule. No missing financial amount becomes zero.
- Zero-net-revenue periods with known costs retain negative food margins; percentage
  margin is null rather than dividing by zero. An empty period is explicitly empty.
- Grouping is by stable menu-item identity/code; names use the current catalogue
  label. Underlying source rows retain their selected historical menu-version names.
- Preview limit: up to 93 days and 1,000 recorded lines. Larger ranges return an
  explicit narrowing message, never a truncated total. Background/materialised
  reporting for larger datasets remains a separate scale improvement.
- Recorded currencies are checked before aggregation; differing currencies cannot
  be silently combined after a business reporting-currency change.

Stock movement, actual waste, labour, overheads, service-charge/fee allocation and
purchase-weighted costing are not calculated by this summary. Source discounts and
declared tax are accounted for, unlike a simple undiscounted menu-price preview.

## Access

Active organisation-wide CEO, finance and restaurant-admin roles may read sales,
history, original sources and period summaries. Only organisation-wide restaurant
administrators may stage, correct, record or cancel. Procurement-only and
operations-only roles, location-scoped roles, unrelated tenants, anonymous users
and unassigned founders cannot read business-wide sales revenue. RLS and every
public function enforce this independently of UI controls.

## Fictional demo

Download **fictional-sales.csv** from the app. It uses source organisation ORG001,
location PRIMARY, menu MENU001, and Sale_Date **2026-11-15**. The saved menu version
must already be effective by that date; adjust fictional dates/codes if necessary.

1. Upload and choose **Gross_Sales and Net_Sales both exclude tax**.
2. Validate and review the recorded menu version and currency NGN.
3. Enter customer receipt controls **3000** for DEMO-S001 and **1350** for DEMO-S002.
4. Confirm review and save. Select 2026-11-15 in the period summary, or the current
   month if that date is included.

With the existing reference cost NGN 900 per menu unit:

| Measure | Expected |
| --- | ---: |
| Receipts / menu units | 2 / 3 |
| Gross source sales | NGN 4,500 |
| Source discounts / tax | NGN 150 / NGN 0 |
| Recorded net sales | NGN 4,350 |
| Estimated food cost | NGN 2,700 |
| Estimated food margin | NGN 1,650 |

This is fictional source data and reference-based estimated cost, not restaurant
trading evidence. A repeat upload must skip both already recorded lines.

## Verification

Database tests cover actual migrations/RLS/functions, source hash retrieval,
receipt controls, discounts, all three tax formats, combo/refund rejection, source
identity, repeated uploads, stale menu bindings, historical inactive masters,
missing costs and subsequent reference-price recovery, zero revenue, negative
margins, report limits, currency mismatch and financial access boundaries.
Chrome tests cover review, controls, source download, duplicate reimport, menu/
location/channel mappings, mobile summaries, missing-cost revenue retention,
unsupported combo cancellation and read-only finance. Form tests validate bounded
mapping inputs and special JSON keys; production compilation checks TypeScript.

Live Supabase integration still needs confirmation after migration 010. Direct
XLSX, source-column mapping profiles, combo/modifier sales, refunds/voids, posted
corrections, intraday bindings, large/background imports and finalised financial
reports remain future deliveries. No subscription, billing or actual profit
functionality is implied by this milestone.
