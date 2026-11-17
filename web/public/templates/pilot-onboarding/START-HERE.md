# ProfitPlate pilot onboarding templates
Prepared 16 November 2026 against the current application.

Start with PILOT-WALKTHROUGH.md for a beginner sequence and a worked menu-cost example. Use the blank sheets for the restaurant's own data. Fictional examples belong in a test workspace.

Current stock workflow: one Inventory Manager plus Department stock users. Manager approval/dispatch is followed by department acceptance; only acceptance posts transfer quantities. Optional receiver/dispatcher roles can be delegated. Use the version2 pilot test pack for current instructions.

## What can be uploaded now
Only the four files in upload-ready/ match implemented upload screens. Their headers are copied unchanged from the application templates.

| File | Screen | Prerequisites |
| --- | --- | --- |
| initial-material-prices.csv | Materials & suppliers > Initial material prices > Import initial prices | Existing material/unit codes; package conversions when applicable |
| purchases-import.csv | Purchases > Purchase imports > Import purchases | Existing suppliers, materials, units and locations, or explicit supported code mappings |
| sales-import.csv | Sales & summary > Import sales | Menu codes, effective saved recipe links and locations; review receipt totals and source-tax declaration |
| expense-import.csv | Labour & expenses > Add expenses > CSV import | Existing category/location codes; explicit cost scope and recognition method |

Use CSV UTF-8, keep the exact headers and order, use YYYY-MM-DD dates, and enter decimal values without thousands separators or currency symbols. Current upload screens accept up to 100 data rows and 128 KB per file. Split larger datasets into reviewed batches. Preserve codes and phone numbers as text in Excel. Use the restaurant's reporting currency; no currency conversion is performed.

Use explicit zero values for absent purchase/sales discounts and source tax where their templates require them. Purchase unit prices must declare whether tax is included in the upload screen. Sales must declare their source-tax format and reconcile receipt customer totals. Expenses declare ON_DATE or DAILY recognition, and LOCATION or CENTRAL scope; CENTRAL rows have a blank Location_Code. Purchase CSV Status uses RECEIVED as required by the existing source contract, but posting an invoice does not confirm a physical delivery or post stock. Supported sales are normal paid sales; combo/refund workflows are not a general supported import route.

Every upload is reviewed and confirmed in the app before recording. Missing or unknown codes must be corrected or mapped explicitly. No materials or recipes are silently created from these uploads.

## Collection sheets are not import files
The eight files in collection-only/ help a restaurant organise master data before entry. There are currently NO upload screens for these sheets. Enter the reviewed data using the corresponding catalogue, recipe, menu or team forms. Do not upload these sheets into the four implemented import screens.

- materials.csv: item_type is RAW, PACKAGING, RESALE, CONSUMABLE, SEMI_FINISHED or FINISHED. Set the correct base unit first.
- suppliers.csv: collect supplier identities/contact details; retain leading zeroes in phone numbers.
- unit-conversions.csv: factor is the number of to_unit_code units in one from_unit_code unit, specific to the material and effective date. Example: one BAG of rice = 50 KG.
- recipe-headers.csv: one row per recipe version being prepared; recipe_type is SUB_RECIPE or FINAL. Yield is usable output from the complete batch, not the quantity of one ingredient.
- recipe-components.csv: one row per ingredient, packaging item or child recipe. component_type is ITEM for materials/packaging or RECIPE for a saved sub-recipe. For RECIPE, record the specific saved sub_recipe_version. Leave that field blank for ITEM. Quantities cover the entire parent batch.
- menu-items.csv: recipe_quantity is the output from the chosen saved FINAL recipe used in one sold menu serving. For a recipe yielding 20 PCS, one plate normally uses 1 PCS.
- menu-selling-prices.csv: channel_code is DINE_IN, TAKEAWAY or DELIVERY. tax_setting is NONE, EXCLUSIVE or INCLUSIVE. Tax rates are explicit; NONE uses 0. Record outlet and effective dates.
- users-and-roles.csv: one assignment per row. role_code is ceo, restaurant_admin, finance, procurement, inventory_manager, stock_department, stock_receiver, stock_dispatcher or operations. The old inventory role is retained for existing assignments, not required for the normal setup. Blank location_name means All business locations. Inventory Manager requires All business locations (leave location_name blank); it oversees stock and department access without Finance or general team administration. No passwords belong in these sheets. Assignments are created/reviewed through Users & roles and accepted invitations.

## Using last purchase prices
The initial-material-prices.csv upload can use the restaurant's known last-purchase prices as dated reference estimates. It does not require importing every historical invoice first.

- If the price is NGN 1800 per KG: quantity=1, unit_code=KG, total_price=1800.
- If a 50 KG bag cost NGN 90000: quantity=50, unit_code=KG, total_price=90000. Alternatively use quantity=1 and unit_code=BAG after saving the material's 50 KG package conversion effective on the price date.
- price_date is when the price was obtained; source_note identifies the invoice, purchase record, quotation or other evidence.
- If the known price date is unavailable, check the source before assigning a date. Do not invent one.
- The initial-price file has no tax-rate/recoverability fields. Review the restaurant's intended costing basis and avoid mixing differently treated source prices without review; the app does not infer that policy.

These remain reference-price estimates, not an inventory valuation or automatic last-purchase-cost engine. Subsequent purchase invoices do not automatically update reference prices. On a costing date the existing engine selects a usable reference price dated on or before that date; latest same-date corrections take priority.

## Sub-recipe and final-recipe entry sequence
1. Create ingredients, packaging and required conversions.
2. Review/import reference prices for those materials.
3. Create the lowest-level sub-recipes with their ingredients and measured batch yield; publish each version.
4. Create parent sub-recipes if needed, selecting the exact saved child versions. Work from the bottom of the dependency chain upward.
5. Create FINAL recipes using direct materials and saved sub-recipes. Include direct packaging once.
6. Enter the final batch yield. Link a menu item to the saved FINAL version and specify the output used per sold serving.
7. Set dated selling prices by outlet/channel, then check Menu profitability.

For the fictional example, publish BASE001 v1 first (8 KG usable tomato-base yield). PLATE001 then consumes 2 KG of BASE001 v1 and yields 20 complete portions. The system allocates the consumed share of the sub-recipe ingredients and packaging, rather than charging its entire batch to the parent. A later sub-recipe version does not silently replace the version pinned in an existing parent. To adopt it, publish an updated parent version and review the menu's final-recipe binding.

## Fictional examples
fictional-examples/ contains a material list, last-purchase-price example, recipe headers, component lines, menu item and selling price. The prices CSV matches the implemented reference-price upload format only after those material records exist. The material, recipe and menu example sheets are preparation aids for manual entry. Replace the example brand and outlet names with those in your test workspace. All figures and recipes are fictional, not recommended restaurant recipes or business defaults. Use a test restaurant when trying the examples.

## Current limits
Bulk recipe/master imports, actual inventory costing, full contribution margin and direct POS/XLSX integrations remain future work. Saved report approval is a management-review workflow, not an accounting period close.
