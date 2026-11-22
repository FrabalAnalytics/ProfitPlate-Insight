# Imported sales and stock-count controls

ProfitPlate records completed POS sales; it does not fulfil orders or reserve stock for customers.

## Set up sales consumption

1. Create the stock centres, materials and opening stock. Post verified openings through Inventory.
2. Publish the sub-recipes and final recipes, then create the selling menu items.
3. In each menu item's **Sales consumption centre**, choose its sales outlet, stock centre, effective date and consumption method.
4. Choose **Recipe ingredients** for a dish made to order. Raw ingredients are consumed directly. A linked, stocked sub-recipe is consumed as its produced SKU; its production inputs are not deducted again. Unstocked sub-recipes are expanded into their ingredients.
5. Choose **Stocked finished menu item** when production has already created the finished item in the ledger. Sales consume that output SKU only.
6. For bulk menu entry, use the optional `stock_centre_code` and `consumption_mode` columns (`RECIPE` or `FINISHED`). The import outlet determines the mapping's sales outlet. Blank fields preserve existing mappings. Earlier twelve-column CSV files remain accepted.

Stock mappings are dated and versioned. The sales line retains the menu version selected for its sales date. Subsequent recipe edits do not rewrite imported sales.

## Import completed sales

1. Review the POS CSV, source mappings and receipt totals as before.
2. Save the reviewed import. Revenue and margin analysis retain the imported financial amounts.
3. Valid lines automatically post standard material consumption at their mapped centres on the sales date.
4. Open **Sales stock consumption** from Sales & summary. Missing mappings, unavailable dated stock or overlapping completed counts remain **Pending**. Sales figures remain recorded; stock coverage is visibly incomplete until these exceptions are resolved.
5. Correct the underlying setup/stock evidence and review the pending record again. A stale review cannot post. Repeated imports and repeated posting requests do not create duplicate deductions.

Standard recipe usage is theoretical consumption. Actual usage and unexplained differences require physical counts, receipts, transfers, production and waste records. A financial refund is not a physical stock return; the existing sales importer still rejects refund/void rows and changed receipts rather than silently altering stock.

Existing historical imports are not depleted automatically on deployment. An administrator can prepare a limited date range for review using **Review sales imported before this update**. Preparing the backlog changes no stock.

## Monthly physical counts

1. Keep the agreed monthly schedule under Reporting calendar & targets. It defines the compliance obligation and deadline.
2. Open the scheduled monthly count. In **Physical count date & timing**, enter the reporting month being closed and the actual date.
3. Choose **Before opening** to exclude that day's movements, or **After closing** to include them. The boundary must already have passed. Date-only POS files cannot establish an accurate intraday cutoff.
4. An actual count can occur up to seven days before or after the scheduled day. Explain a changed date. The original scheduled day remains attached to the obligation; it is not silently moved to hide lateness.
5. Enter every physical quantity, including explicit zeros, and the submitter's name. Submit for review. Saving/submitting does not change stock.
6. A different authorised **Owner/CEO, Finance or Operations Manager** reviews the count. Inventory entry authority alone cannot approve it.
7. Inventory posts the approved variance once. Pending sales consumption through the boundary, stale snapshots and unresolved handovers block automatic adjustment.

Values describe the actual physical-count cutoff. They are not automatically reconstructed month-end balances when the actual count differs from month-end. Use the dated movement statement to investigate intervening activity. The reporting month groups the review; it does not invent a physical measurement on another date.

## Late sales after completed counts

Late sales overlapping a completed count require independent reconciliation. The reviewer sees the affected count and materials. If a posted count already brought current stock down to its physical quantity, reconciliation records the dated sales deduction plus a separately identified count reclassification, preserving that current balance instead of deducting it twice. Original count snapshots remain unchanged; reconciliation entries are retained separately and reflected in monthly analysis.

Legacy same-day counts require a reviewer to confirm their before-opening/after-closing timing before daily sales can be reconciled. Unsupported or inconsistent evidence remains pending rather than being guessed.

## Database rollout

Apply `202611220059_pos_sales_stock_consumption.sql`, then `202611220060_actual_count_dates_and_sales_reconciliation.sql`, before deploying the matching app. Existing production, transfer, waste and stock history are retained.
