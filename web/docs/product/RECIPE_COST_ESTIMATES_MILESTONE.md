# Recipe reference-cost estimates

This milestone connects optional material reference prices to saved recipe
versions. It does not select an accounting inventory policy or implement
purchase-weighted monthly costing.

## Delivered behaviour

- Open any saved recipe version under Profitability / Recipes & scaling to see
  **Estimated recipe cost**. Authorised users select a cost date, defaulting to
  the current business date, on or after the recipe version's effective date.
- The calculation expands the exact saved child recipe versions and their
  pinned normalised quantities. Repeated occurrences of a material aggregate
  before costing; direct packaging is included once per declared quantity.
- Select the most recent reference price dated on or before the cost date. For
  same-date corrections, the newest entry wins. The method identifier is
  `REFERENCE_ESTIMATE_V1`; the response includes source price IDs, entry versions,
  dates, notes and recipe version ID, with all decimals returned as strings.
- Each standard-batch material line shows quantity, reference unit price and
  estimated line cost. Complete coverage enables the batch total, cost per
  declared output unit and estimated target cost using the scaling quantity.
- A missing price, currency mismatch or unit mismatch leaves full batch,
  per-unit and target totals **null**, with state **MISSING**. A known subtotal
  appears only when at least one line is priced and is explicitly partial.
  Each missing line links to the material's initial-price screen.
- Complete coverage is **ESTIMATED**, never verified or actual. No additional
  labour, overhead or operating expenses are added. Reference amounts retain
  whatever assumptions their source contains; tax treatment is not inferred.
- The calculation uses PostgreSQL numeric arithmetic throughout. Intermediate
  expanded quantities are not rounded before costing. Line costs and final
  results round to 12 decimal places. Unsupported underflow/overflow returns an
  explicit error; positive costs are never replaced with displayed zero.

## Scope, access and history

The estimate is a **live preview**, not a saved or finalised historical report.
A new backdated price or same-date correction can change a later preview for
that cost date. Composition versions remain immutable. Finalised financial
reports will need separately persisted price/policy snapshots in a later milestone.

Only active, organisation-wide CEO, finance, restaurant administrator and
procurement roles can view business-wide estimates, consistent with the
reference-price permission boundary. Scoped staff and operations-only roles can
continue permitted recipe/quantity work but cannot call the financial function.
Unrelated tenants, anonymous accounts and founders without restaurant membership
cannot access estimates. Both UI and database enforce the boundary.

This read-only function creates no purchases, movements, stock balances, accounting
entries or recipe changes. It does not calculate selling margins or actual profit.

## Live database setup

After migration 006 has succeeded, run the complete new SQL file once in the
existing Supabase project's **SQL Editor → New query**:

`supabase/migrations/202611140007_recipe_reference_costs.sql`

The coding agent has not applied this migration remotely. Refresh the app after
running it. Existing recipes and quantity scaling remain available if the function
has not yet been installed; the estimate panel displays an unavailable message.

## Fictional beginner example

With reference prices of rice NGN 1,800/kg, chicken NGN 6,000/kg and boxes
NGN 100/piece, create a recipe with yield **12 PCS** and these batch quantities:

| Material | Quantity | Estimated line cost |
| --- | --- | --- |
| Rice | 2 KG | NGN 3,600 |
| Chicken | 1 KG | NGN 6,000 |
| Takeaway box | 12 PCS | NGN 1,200 |

Expected estimate: **NGN 10,800 per batch**, **NGN 900 per PCS**, or **NGN 21,600
for target output 24 PCS**. This simplified example excludes other ingredients
and expenses and is not a complete commercial recipe or selling-price recommendation.

## Verification

- Database tests apply migrations 001–007 in PGlite and test complete/incomplete
  coverage, nested recipes, repeated material aggregation, packaging, saved child
  versions, date selection, price corrections, currency mismatch, output precision,
  tenant isolation and financial role boundaries.
- Chrome tests exercise adding material prices, creating a recipe, missing
  packaging blocking totals, adding the packaging price, complete batch/per-unit
  estimates, scaling, retained cost dates, mobile overflow and read-only finance.
- Production build checks TypeScript and Next.js compilation.
- Live Supabase integration remains to be checked after applying migration 007.

## Next

Transaction purchase imports and their validation/mapping foundation, followed
by an explicitly approved period-costing policy. Selling-price history, margin
calculations and reproducible finalised reports remain separate deliverables.
