# First restaurant onboarding: step by step

Use one outlet and a small sample first. Have the restaurant manager, kitchen lead and person responsible for the source records check the results together before loading the full catalogue.

## 1. Collect the source records

Ask for the ingredient and packaging list, base units, package sizes, last purchase prices with dates, supplier list, measured recipe batch yields, menu prices by channel, and a small sample of sales and expenses. Collect names and email addresses of the people who need access and agree their roles and outlet access.

Use collection-only/ to organise this information. These sheets are for preparation and manual entry; the app cannot upload them. Keep passwords out of the pack. Use aggregated labour figures rather than individual employee records.

## 2. Create the restaurant workspace

The restaurant owner registers through Sign up, verifies their email, then completes business setup with the reporting currency, brand and first outlet. Record the actual organisation and location codes shown in the workspace; transaction imports must use the restaurant's codes, not codes copied from a fictional sample.

## 3. Invite the team

In Users & roles, create the required invitations and share each invitation link with its intended recipient. Each person registers or signs in with the invited email, verifies it and accepts the invitation. Invitations expire after seven days; create another if necessary.

Assign Procurement for ordering and supplier invoices, Inventory Manager for business-wide stock control, Department stock user for Kitchen/Bar requests and acceptance, Finance for expenses and financial review, and Operations for recipe work as needed. Configure selected department locations in Department access. Optional Stock receiver/dispatcher roles can be delegated; separate inventory staff accounts are not mandatory. Give management the appropriate management role. The PO issuer and receiver must be different people. Check access using separate browser profiles before entering live records.

## 4. Create materials, units and suppliers

Open Materials & suppliers and create the reviewed catalogue. Choose each material's base unit carefully. Enter material-specific package conversions where required: for example, one BAG of rice equals 50 KG. Make conversions effective on or before the dates that use them.

For the worked example, manually enter fictional-examples/materials-example.csv. It contains six items: rice, chicken, tomato, onion, cooking oil and meal boxes. Use exactly the listed codes. This file is a preparation sheet, not an upload.

## 5. Load known last purchase prices

Open Initial material prices from Materials & suppliers. Use upload-ready/initial-material-prices.csv for real data. Enter the actual source date, quantity, unit and total price, with a source note. Do not invent dates for undated prices; resolve them with the restaurant first.

For the fictional example, upload fictional-examples/last-purchase-prices-example.csv after creating the six materials. Review every resolved material and converted unit price before confirming. The example rice price is 90000 for 50 KG, giving 1800 per KG; boxes cost 1200 for 12 PCS, giving 100 each.

Check all costs in the same reporting currency and agree a consistent tax/cost basis. New supplier invoices do not automatically replace these reference prices. Reference prices estimate recipe costs; they do not establish opening stock or actual inventory COGS.

## 6. Create and publish the sub-recipe first

In Recipes & scaling, manually create BASE001, Tomato base, as a SUB_RECIPE. Use the example headers and components as your entry checklist:

| Ingredient | Batch quantity | Reference unit price | Extended cost |
| --- | ---: | ---: | ---: |
| Tomato | 6 KG | 1000 per KG | 6000 |
| Onion | 2 KG | 800 per KG | 1600 |
| Cooking oil | 1 L | 2500 per L | 2500 |
| Total | | | 10100 |

Set the measured usable batch yield to 8 KG and the effective date to 2026-11-14. Publish the version and note its saved version number. In a fresh example it should be version 1; use the actual saved version when selecting it in the parent.

The estimate should be 1262.50 per KG. A final recipe consuming 2 KG uses 2525 of this batch cost. Do not also add the tomato base's raw ingredients to the final recipe.

## 7. Create and publish the final recipe

Create PLATE001, Chicken rice plate, as FINAL. Add the following quantities for the complete batch, not for one serving:

| Component | Batch quantity | Extended cost |
| --- | ---: | ---: |
| Rice | 4 KG | 7200 |
| Chicken | 3 KG | 18000 |
| BASE001, selected published version | 2 KG | 2525 |
| Meal box | 20 PCS | 2000 |
| Total | | 29725 |

Set the final batch yield to 20 PCS and effective date to 2026-11-14, then publish. One complete serving should cost 1486.25, including its meal box. Use measured yields for real restaurant recipes; these example yields and costs are fictional.

## 8. Link the menu and set its price

In Menu & prices, create MENU001 using fictional-examples/menu-items-example.csv as a manual entry checklist. Choose your test brand, link the published FINAL recipe and set recipe quantity to 1 PCS per sold serving.

Use menu-selling-prices-example.csv as a manual checklist for a TAKEAWAY price of 3500 at your test outlet, effective 2026-11-14. Choose tax setting NONE with rate 0 for this fictional comparison only. Use the restaurant's actual tax treatment for real data. Neither menu example CSV is uploadable.

## 9. Check Menu profitability

Select your test outlet, TAKEAWAY channel and 2026-11-14 costing date. Search for MENU001. With the example data unchanged, expect:

| Measure | Expected result |
| --- | ---: |
| Estimated cost per serving, including direct packaging | 1486.25 |
| Selling price, excluding tax | 3500.00 |
| Food cost percentage | about 42.46% |
| Estimated food profit per serving | 2013.75 |
| Estimated food gross profit margin | about 57.54% |
| Full contribution margin | Unavailable |

Food cost percentage is serving cost divided by net selling price. Food profit is net selling price minus serving cost. The margin percentage is food profit divided by net selling price. These figures exclude labour and other operating costs.

If the result is missing or different, check the costing date, reference-price dates, units, yields, saved recipe version, brand, outlet, channel and selling-price effective date. Missing costs must be resolved before relying on a total. Publishing a new child recipe does not silently replace the version selected in an existing parent.

## 10. Run a small operating sample

Have Procurement issue a PO, the Inventory Manager confirm a partial supplier delivery, and Procurement record its supplier invoice. Check the remaining delivery quantity and any invoice/receipt exception with Finance. Complete receiving and confirm the order becomes Completed. Invoice entry alone does not confirm delivery or post stock.

Load a small sales CSV and an expense CSV using upload-ready/. Review the preview, source totals, dates, codes, tax declarations and recognition periods before confirming. For purchases imported from CSV, preserve the source identifiers and inspect the separate receiving/matching context; do not import an invoice already entered manually.

Review Sales & summary, Menu profitability and the management report for the same outlet and dates. Record labour/expense coverage honestly. Save a named report, have Finance submit it, and have management approve it or request changes. Compare recorded sales and expenses to the source documents and recipe estimates to the kitchen's checked calculations.

Only expand to the full restaurant dataset after these checks agree. If a posted record needs correction, use the app's correction/review workflow rather than changing its reference and importing it again.
