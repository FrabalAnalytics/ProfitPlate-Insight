# Optional initial material prices

Implemented following the founder's decision to let newly onboarding restaurants
add prices progressively. This is a reference-price foundation, not approval of
the inventory valuation or monthly purchase-costing policy.

## Delivered

- Materials & suppliers links to **Initial material prices**. Catalogue rows show
  Missing price or Estimated for authorised viewers; unavailable data is never
  interpreted as missing or zero. Financial access is checked separately from
  shared catalogue access.
- Manual entry covers one existing active material, a positive quantity, unit,
  total price, price date and mandatory source note. Prices use the business's
  reporting currency and are explicitly business-wide reference estimates.
- Optional CSV import uses a downloadable header-only template. Existing material
  and unit codes must match; no materials are silently created. Limits: 100 rows,
  128 KB, six exact decimal places for source amounts and quantities.
- Quoted commas, escaped quotes, UTF-8 BOM, CRLF and quoted multiline notes are
  supported. No formula execution, currency conversion or XLSX parsing.
- Review resolves standard unit dimensions and effective-dated item-specific
  package conversions, then shows the price per base unit. No review is saved
  automatically. Changing inputs hides the old review; changing a material,
  currency or conversion between review and commit requires another review.
- Batch commits are atomic, retry-safe and audited. Every price is append-only;
  corrections create new entries. The latest price date wins; on the same date,
  the newest entry wins. Earlier dates do not silently replace more recent prices.
- Active material totals and missing-price counts are shown. Each material has
  its latest 25 entries visible in history; search and catalogue lists paginate
  25 materials at a time. Every stored entry remains in the database.
- All saved costs are ESTIMATED. Source dates cannot be in the future, evaluated
  in the organisation's time zone. Normalised quantities and costs retain up to
  12 decimal places; underflow and overflow are rejected, never displayed as zero.

## Database setup (required in the live project)

Run **only the new migration** after migrations 001–005 have already succeeded:

`supabase/migrations/202611140006_material_reference_prices.sql`

1. Open that file and copy its entire contents.
2. In the existing Supabase project, choose **SQL Editor → New query**.
3. Paste and run the query once.
4. Refresh ProfitPlate; sign in with the restaurant owner account.
5. Open **Materials & suppliers → Initial material prices**.

No remote database change has been performed by the coding agent. Do not rerun
the initial schema. The new screen handles a missing migration without breaking
the existing catalogue.

## Example for a beginner

Create a material `RICE001` with base unit KG. Open its reference prices. Enter
quantity `50`, unit KG, total price `90000`, a past or current price date and a
source such as "Last supplier invoice — sample". Choose **Review prices**:
the result is **NGN 1,800.00 / KG**, labelled Estimated. Choose **Save estimated
prices** to retain it. No package conversion is required when using KG directly.

For CSV, download the template and add this explicitly fictional example using
an existing material code and a valid date:

```csv
material_code,quantity,unit_code,total_price,price_date,source_note
RICE001,50,KG,90000,2026-11-10,Fictional onboarding sample
```

## Access and integrity

Only active, organisation-wide restaurant administrators and procurement managers
can review or save prices. Organisation-wide CEO and finance roles can read.
Location-scoped roles, operations-only roles, other tenants, unauthorised founders
and anonymous users cannot read these business-wide financial records. RLS protects
both tables; writes are restricted to validated functions. Permissions are enforced
in database functions as well as Server Actions; no service-role key is used.

Price data does not insert purchases, purchase items, opening balances or inventory
movements. No legacy zero cost is copied. Catalogue and recipe setup remain usable
without any prices. This milestone does not calculate recipe financial costs,
weighted purchase prices, actual COGS, margins, stock valuation or reporting periods.
Recipes continue to show financial costing as pending until that engine is built.

## Verification

- `npm.cmd run test:db`: actual migrations and PostgreSQL/RLS under PGlite, including
  quantity precision, dated conversions, atomic batch validation, correction history,
  retry safety, stale-review rejection, no transaction posting and access boundaries.
- `npm.cmd run test:forms`: CSV parsing, limits, invalid numeric/calendar values,
  and tiny nonzero amount display, alongside existing onboarding regressions.
- `npm.cmd run build`: Next.js production compilation and TypeScript checks.
- `npm.cmd run test:e2e`: real Chrome against the isolated production app with
  simulated authentication and actual local database functions. Covers manual
  review/corrections, preserving quantity/unit inputs, CSV errors/import, mobile
  overflow and finance read-only access, plus existing app regressions.

Live Supabase integration remains to be checked after the migration is applied.

## Next

The follow-up [recipe-cost preview](RECIPE_COST_ESTIMATES_MILESTONE.md) now connects
these prices to saved recipe/sub-recipe quantities and direct packaging, with
missing-price warnings. It requires migration 007. Purchase transaction imports
and approved period-cost policies remain separate milestones.
