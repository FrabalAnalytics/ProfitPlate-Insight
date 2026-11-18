# Processed material costs and display precision

Apply migration `202611180035_processed_material_costs.sql` after 034, before deploying the matching application. It preserves source prices, recipe composition and stock ledger quantities. It adds recipe-derived estimates; it does not value production batches or change posted stock.

## Your Snapper example: what to do next

1. Check **Snapper Fish** is the purchased/raw material with base unit **KG**, and enter its known initial net price or post the real supplier invoice.
2. Check **Snapper Cut** is an active, stock-tracked **Semi-finished** (or Finished) material with base unit **PCS** and supply source **Processed**.
3. Open the saved **Processed Snapper Fish** sub-recipe. Check the standard batch consumes **40 KG Snapper Fish** and yields **120 PCS**.
4. Open **Data & Setup > Processed material setup**. Under **Link recipe stock output**, select **Processed Snapper Fish** as Published recipe version, select **Snapper Cut** as Produced stock material, then click **Link recipe stock output**. The same link form remains under Inventory > Locations & routes.
5. Review **Processed SKU costs** on that page. It shows the linked recipe, standard output, estimated unit cost and missing setup. Do not manually copy that estimate into initial prices.
6. A final dish can use Snapper Cut as a material, such as two PCS per serving. Its estimated ingredient cost will use the recipe-derived cost automatically. Alternatively, an explicitly pinned sub-recipe component still uses its pinned composition; do not include both representations for the same portion.
7. To record the actual transformation, ensure the processing stock location has the whole fish, then have the Inventory Manager choose **Record a production batch**. Owners without stock-process permission see a handoff to the Inventory Manager instead. The movement form opens with Production batch selected. The Inventory Manager records the processing location, published recipe, planned output and measured actual output, then follows the existing review/posting controls. A link or a cost estimate alone never changes stock.

For the amounts in the screenshot:

- Whole fish unit cost: approximately 5,555.555555555556 per KG.
- Standard input: 40 KG.
- Estimated batch cost: **NGN 222,222.22**.
- Standard output: 120 pieces.
- Estimated Snapper Cut cost: **NGN 1,851.85 per piece**.
- Two pieces contribute approximately **NGN 3,703.70** to a final dish before other ingredients/packaging.

Displayed money rounds to two decimal places. Calculations retain database precision; two displayed unit costs may therefore not exactly sum to the displayed batch total. Very small nonzero amounts display as less than 0.01 rather than a false zero.

## Cost source rules

- A Processed SKU uses its linked processing recipe and the recipe inputs' current dated costs. A separate manual reference price for that SKU is not its estimate source.
- A bound SKU with source Purchased also uses its processing recipe, preserving existing output links. A SKU explicitly configured as Both uses available purchase/reference history first and falls back to its linked recipe where that history is missing. The displayed basis identifies which source was used; this is not a blended stock valuation.
- Raw/input costs retain the monthly quantity-weighted invoice policy and initial-price fallback from 034. Approved corrections/voids flow through that policy.
- If several versions of the same processing recipe are linked, estimates select the latest linked version effective on the cost date. Publishing a new recipe alone does not change the link. A future version cannot change an earlier-date estimate.
- A produced SKU cannot be newly linked to a different recipe family while already bound to another. Use a new version of the same recipe or a separate output SKU. Existing ambiguous bindings show an unavailable cost instead of choosing a recipe arbitrarily.
- Missing input prices, incompatible output units and dependency cycles never produce a substituted zero cost. New circular production links are rejected; legacy cycles return an incomplete estimate safely.
- Financial cost visibility retains the existing business-wide permissions. Inventory-only users can manage output bindings without gaining financial access.

## Where to check

- Processed material setup: produced SKU, linked recipe, batch output and estimated cost per base unit.
- Materials > Initial prices: current estimates and underlying reference entry history. Processed SKU detail points to its recipe instead of asking for a manually entered price.
- Monthly material price tracker: recipe-derived rows are labelled and link to their recipe. Purchase quantity/amount are not applicable for those rows.
- Recipe breakdown, menu margin, sales estimates and CEO loss estimates: derived processed inputs flow into the existing live estimates. Existing saved report snapshots are not overwritten.

This remains standard-recipe estimation. Measured waste, actual production yield, monetary stock valuation and multi-output cost allocation are separate concerns. Record actual trim/waste without assuming the 40 KG/120 PCS example proves zero loss or an individual piece weight.

Validation on 18 November 2026: the full database regression suite passed (212 checks), followed by the expanded 10-check processing suite. All 41 form/export checks and 11 distinct focused browser scenarios passed across the completed runs. The production build and TypeScript checks passed; lint reports zero errors and three pre-existing test warnings. The Snapper link, recipe and monthly cost displays, downstream recipe and Inventory Manager production handoff were checked in the browser. Desktop/mobile screenshots were reviewed. Production migration 035 was confirmed applied by the owner and its read-only RPC presence was verified. No live restaurant records were changed by the tests.
