# Restaurant controls and monthly costing release

## Database and deployment order

Migration 032 is already applied, as confirmed by the owner. Do not run it again.

1. Run `supabase/migrations/202611180033_restaurant_access_and_calendar.sql` in the Supabase SQL Editor. Wait for success.
2. Run `supabase/migrations/202611180034_monthly_weighted_prices.sql`. Wait for success.
3. Deploy the matching application release. Keep the current production application until these database changes succeed.
4. Sign out and sign back in, then run the checks below with separate browser profiles for Founder, Owner, Procurement, Finance and Inventory Manager.

033 preserves all existing restaurants as ACTIVE. Neither migration suspends or deletes a restaurant or changes existing purchase/recipe source records. New reporting calendar fields remain unconfigured for existing restaurants until an administrator chooses them. The existing onboarding API remains compatible; the new application onboarding requires a calendar before creating a workspace.

## Founder: restaurant access

1. Sign in with the Founder account. Find the restaurant in the directory.
2. Choose **Inspect business**, then open **Manage restaurant access**.
3. Enter a reason, tick the confirmation and choose **Confirm inactive status**.
4. In an already signed-in restaurant user's browser, refresh the workspace. Expect an inactive-workspace notice. Direct restaurant pages, reads and writes must also be blocked.
5. Inspect the restaurant again as Founder. The status and access-change history should be visible, and records should still exist.
6. Enter a restoration reason, confirm, and choose **Confirm reactivation**. Refresh the restaurant user's workspace.
7. Verify that a user disabled before the restaurant suspension remains disabled afterward.

Suspension is restaurant-specific. Supabase authentication still recognises the person; tenant access is blocked, including for existing sessions. Someone with another active restaurant membership can still use that other restaurant. Founder platform access remains available. This control does not delete tables or reduce the database schema. Payment collection and automatic suspension are not implemented.

## Owner: reporting calendar

New restaurants choose timezone, reporting week start, physical count day and local cutoff during step 2 of onboarding. There is no assumed Monday week or count deadline.

For existing restaurants: **Data & Setup > Reporting calendar & targets**. Choose and save the four settings, then reload and verify them. The page shows the current reporting week's date boundaries. The setup checklist and Founder progress include calendar readiness.

These are the team's reporting/calendar settings. Date filters remain editable. Physical count entry, review and posting remain manual; reaching the cutoff never changes stock or closes transactions automatically. Changing the business timezone may alter local-day interpretation around midnight. Outlet timezone records remain separately configured.

## Procurement/Finance/Owner: monthly prices

Open **Materials & suppliers > Initial prices > Monthly material price tracker**. Filter by month or material. The tracker shows cost amount, base quantity, weighted unit cost, source month and basis.

- Posted invoice lines use `sum(net_amount) / sum(base_quantity)` per material, business and calendar month. Tax is excluded from invoice costs. Established unit conversions normalise bags/cartons/etc. before averaging.
- For example, 10 kg at 1,000 plus 30 kg at 2,000 gives 70,000 / 40 = **1,750 per kg**.
- Multiple invoices on the same date all contribute. Pending corrections do not change the basis; an approved replacement substitutes its current lines, and an approved void removes its contribution.
- Initial references are a fallback for a material/month with no posted invoices. They are never added to invoices for that same material/month. Initial references use entered amounts; enter net material costs excluding tax for comparability.
- Reference entry history keeps its established correction rule: the latest entry for a material/date replaces earlier entries for that date. Different dates in the month are weighted by their stated base quantities.
- If the selected month has no price history, the latest earlier month carries forward and is labelled. Future-dated purchases are excluded from an estimate for an earlier date. Missing costs remain unavailable.
- Estimates are business-wide, not warehouse valuation or outlet-specific purchase averages. Current-month estimates are month-to-date. They can change after backdated invoices or approved corrections.
- Live recipe, menu, sales margin and CEO waste/shortage estimates use this policy. Saved recipe composition and pinned sub-recipe versions do not change. Existing finalised/saved report snapshots are not overwritten.

Check by recording two real test invoices in a disposable/test restaurant, inspecting the tracker and opening a recipe/menu estimate. Confirm the weighted amount, not a simple average of unit prices. Test a correction/void with the separate authorised Finance account. Never create fictitious invoices in a pilot restaurant's live books.

## Owner/Inventory Manager: processed material master data

Open **Data & Setup > Processed material setup**. This page connects existing material, recipe and stock-output setup in one place.

For the provided example:

1. Create **Whole Snapper Fish (SKU1)**, Raw, Purchased, stock tracked, base unit KG.
2. Create **Snapper Fish Cut (SKU2)**, Semi-finished, Processed, stock tracked, base unit PCS. Choose its category, location availability and weekly count requirement.
3. Publish a **Sub-recipe**, for example `SNAPPER-CUT`, with 40 KG of SKU1 and a standard yield of 120 PCS.
4. On Processed material setup, link that published version to SKU2. The Inventory Manager can also manage this binding under Inventory > Locations & routes.
5. Establish the actual opening stock or confirmed receipt in the processing store. A supplier invoice alone does not add stock.
6. Record production with the saved recipe, planned output 120 and measured actual output. Review and post through the existing inventory controls.
7. Verify the ledger consumes 40 KG of SKU1 and adds the measured PCS of SKU2. Recording the master recipe/binding alone never moves stock.

There is no general KG-to-PCS conversion: the recipe expresses a measured transformation. Forty kilograms producing 120 pieces does not establish individual cut weight, usable weight, or trim/waste. Record measured loss separately rather than assuming zero. This release supports the existing single-output production workflow. Several distinct usable outputs from one batch, complete monetary allocation and stock valuation remain later phases.

## Release verification

Automated checks cover schema installation, permissions, suspension/reactivation, explicit calendar selection, monthly weighted arithmetic, tax, date cutoffs, corrections/voids, initial fallback and the single-output processing mapping. Browser checks cover new onboarding, Founder status changes with an existing session, setup forms and mobile layouts. Follow with the live smoke checks above after deploying.

Verified locally on 18 November 2026: 203 database checks, 40 form/export checks and 20 distinct browser scenarios passed, with the new controls rechecked after the final styling changes. The production build and TypeScript checks passed. Lint has zero errors and three pre-existing test warnings. Final mobile screenshots were reviewed. No live restaurant was suspended or modified by these tests.
