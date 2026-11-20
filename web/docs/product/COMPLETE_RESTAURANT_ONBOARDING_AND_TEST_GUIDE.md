# Complete Restaurant Onboarding & Test Guide

ProfitPlate Insight | Updated 20 November 2026 / centre material plans update 051 / migrations through 051 | Includes the full master-data setup and daily operational test sequence.

This replaces the stock-only walkthrough as the main onboarding guide. Use a fresh training restaurant; preserve the existing demo restaurant and its historical records. The examples are fictional training data, not recommended recipes, prices or operating defaults.

## Before you start this updated run

Use this guide with **profitplate-complete-test-data-2026-11-20.zip**. It supersedes earlier test-pack instructions. The example transaction date is **19 November 2026**, aligned across prices, recipes, openings and imports. Use that date in the app filters. Record your actual execution date separately in the workbook. If starting later, update the sample dates together before entry. Receiver acceptance posts on its actual business date; subsequent processing/waste must use that date or later. If the test spans days, use the current operational date for later stock activity and widen report filters; keep master versions effective on or before that date.

1. Use the deployed site at https://profit-plate-insight.vercel.app/ and confirm migrations through **051** are applied and the matching app is deployed. Do not rerun applied migrations.
2. During initial setup, add the Food/Drink subcategories in **menu-categories.csv**. Standard pricing is automatic; additional channels are optional.
3. Create a fresh training restaurant, for example **Training Restaurant - Run 041**. Keep the earlier demo and its histories intact.
4. Open **ProfitPlate_Complete_Test_Data.xlsx**. Complete **run-details**, then use **test-results** to record Not run, Pass, Fail, Blocked or Not available, actual result and evidence. Run the sections in order.
5. Replace example emails with verified accounts or aliases you control. For a Gmail account, a plus alias such as `yourname+finance@gmail.com` goes to the same inbox but is registered as a separate app login. Use a separate browser profile for each tester role. Do not save passwords in the pack.
6. Keep the five **upload-ready** CSVs separate from the manual-entry/checklist files. The full Excel workbook is a reference and test record, not an app upload.
7. Stop at a failed stock balance, duplicate posting or access restriction. Record the reference and screenshot; resolve it before continuing with dependent tests. An expected access denial is a Pass.

Changes in this revision: one-save centre/owner tasks; standalone waste without approval and with a submitter; Inventory own-centre waste restrictions; Finance combined waste reporting/export; Finance setup restrictions; concise role navigation and invoice layouts. Existing master data, pricing and recipe tests remain included.

## 1. What this guide covers

Set up the restaurant profile and reporting calendar; brands and outlets; named users and roles; stock centres, ownership and movement routes; suppliers; materials and packaging; unit conversions; starting material prices; processing baselines and processed SKUs; sub-recipes; final recipes; selling menu categories and items; standard outlet prices and optional channel exceptions; cost targets; opening stock; and trial transactions, processing, waste and reports.

**Both manual entry and bulk import are the required end state for master data. They are not both implemented for every dataset today.** A CSV collection sheet is not evidence of a working importer. The table below records the current application, checked against its source code on the preparation date.

| Dataset | Manual entry now | Bulk import now |
| --- | --- | --- |
| Restaurant, reporting calendar, brand and first outlet | Available through onboarding/setup | No general master-data importer |
| Named users and role assignments | Available through invitations/team forms | Not implemented |
| Stock centres, owners, production centres and routes | Available through setup forms | Not implemented |
| Suppliers | Available | Not implemented |
| Materials, packaging and processing flags | Available | Not implemented |
| Material-specific unit conversions | Available | Not implemented |
| Dated starting material prices | Available | Available: initial-material-prices.csv |
| Material processing baselines | Available | Not implemented |
| Sub-recipes, final recipes and their components | Available | Not implemented |
| Selling menu items, categories and final-recipe links | Available | Available: menu-catalogue-import.csv |
| Standard selling prices | Available with menu entry or in details | Available with menu-catalogue-import.csv |
| Optional channel price exceptions | Available | Not in the menu CSV |
| Opening stock by material and centre | Available through reviewed stock requests | No dedicated opening-stock CSV importer |
| Supplier invoices | Available | Available: purchases-import.csv |
| Sales records | CSV import route | Available: sales-import.csv |
| Labour and operating expenses | Available | Available: expense-import.csv |

Do not mark full dual-route onboarding as passed until the missing master-data importers are built and tested. This guide supplies the full manual path, the working import paths, and acceptance criteria for the missing bulk path. It does not introduce an app release or database migration.

## 2. Prepare the restaurant data before entry

1. Nominate one restaurant administrator to coordinate setup and one person to review the data.
2. Agree a cutover date. Keep transactions before and after cutover clearly separated so opening stock and deliveries are not counted twice.
3. Collect restaurant name, concept, currency, country, business timezone, brand and outlet details.
4. Collect staff names, verified email addresses, required roles and outlet/stock-centre scopes. Never put passwords in a spreadsheet.
5. Collect named storage centres, their actual responsible users, enabled production centres and permitted movement routes, including returns.
6. Collect supplier codes/names/contact details; material and packaging codes/names/types/base units; conversion factors; processing flags; and known last purchase prices with real dates and evidence.
7. Collect processing input/output standards, usable batch yields, sub-recipes, final recipes and component quantities for the whole batch.
8. Collect selling menu codes/names, brand, Food/Drink major category, restaurant-defined subcategory, linked final recipe, recipe output per serving, outlet, standard price, tax treatment and effective dates. Collect optional channel exceptions only where used.
9. Count opening stock separately for each material at each stock centre. Include processed stock already physically held at cutover.
10. Check duplicate codes and spelling. Use the same code consistently across every sheet. Do not invent unknown prices, yields, tax rates or conversion factors.

For the first training pass, enter a small complete sample manually. For bulk-route acceptance, use a second separate training restaurant once the required master-data importers exist, and compare the resulting records and calculations. Do not load the same dataset twice into one restaurant to compare methods.

## 3. Create the restaurant and reporting calendar

1. Register a fresh owner account, confirm the email and sign in.
2. Complete onboarding with business name **Training Restaurant - Run 041**, the actual restaurant concept, **Nigeria**, **NGN**, brand **Training Kitchen**, outlet **Dining Room**, and timezone **Africa/Lagos** for this example.
3. Choose the real reporting week start, physical count day and local cutoff time. These are restaurant decisions, not universal defaults.
4. Create the workspace. Check the displayed brand, outlet and currency.
5. Open **Data & Setup** and review the setup journey. An incomplete stage should remain visible until its required data exists.
6. Open **Reporting calendar & targets** to verify the saved calendar and enter approved Food/Drink targets where appropriate. Targets do not create selling prices or actual costs.
7. Keep outlet names distinct from stock centres. Dining Room is a business outlet; Main Store and Kitchen are places holding stock. An outlet may contain several stock centres, while a central store can be shared.

Expected result: a separate active restaurant with its own records and calendar. Existing restaurants remain unchanged. A CEO-only read role does not grant configuration writes; the owner/authorised Restaurant Administrator performs setup.

## 4. Add named users, roles and scopes

1. In My workspace, expand **Set the name shown in your workspace**, enter your name and save.
2. Open **Users & roles > Invite colleague**.
3. Enter colleague name, email, role and outlet scope. For Kitchen/Bar or stock-process roles, the **Stock centres** section lets you select existing centres and tasks. If centres are not created yet, assign them after the colleague joins. Review and create the invitation; the app requests an email sign-in link and shows a backup copyable link. Check email request/failure state; Resend email is available in invitation history. Custom SMTP in Supabase is required to email arbitrary staff when using its restricted default sender.
4. Each invited person opens the emailed sign-in link, reviews their pending restaurant invitation and accepts. They may set a password for future sign-ins. For the manual backup link, sign up/sign in with the exact invited email and verify it; pending invitations can be recovered at **/join**, even in another browser. Staff must not create a separate restaurant. App authentication creates the Supabase Auth identity automatically; do not insert users with SQL.
5. Use separate sessions or browser profiles when testing different people. Avoid accidentally completing several roles' actions as the same account.

| Example person | Role | Responsibility |
| --- | --- | --- |
| Francis | Restaurant Administrator; CEO when required | Setup/team access and executive review according to assigned roles |
| Emeka | Inventory Manager | Stock oversight, approvals, dispatch and posting |
| Ada | Kitchen Manager | Assigned Kitchen requests, receiving, processing, waste and counts |
| Bola | Bar Lead | Assigned Bar requests, receiving, waste and counts |
| Procurement tester | Procurement | Purchase Orders, supplier invoices and permitted purchasing records |
| Finance tester | Finance / Auditor | Financial review, expenses and permitted reports |
| Operations tester, if required | Operations Manager | Operational master-data responsibilities within assigned access |

Inventory Manager uses business-wide scope. Kitchen Manager and Bar Lead initially have no stock-centre assignments: configure those explicitly later. Save the responsible owner and their selected tasks together in Centres & team access. Naming a responsible person without enabling their tasks does not grant those tasks. Optional receiver/dispatcher roles remain available. Custom role creation is not implemented.

Expected result: names and roles appear correctly; greetings use the restaurant timezone; staff cannot access unrelated modules simply because their job title sounds senior. There is no current bulk user-import screen.

See [Team invitations and email setup](TEAM_INVITATIONS_AND_EMAIL_SETUP.md) for SMTP/template settings and recovery when an existing colleague was sent to setup.

## 5. Define stock centres, owners and movement routes

1. Open **Data & Setup > Centres & team access** (expand Business administration first).
2. Enter **Main Store**, type Main store, responsible user **Emeka / Inventory Manager**. Under More centre details set code **MAIN_STORE**. Select **Save centre & access**; existing Inventory Manager role-wide permissions remain intact.
3. Create **Kitchen**, code **KITCHEN**, type Kitchen, outlet Dining Room, responsible user **Ada / Kitchen Manager**. Enable **Request materials**, **Record waste** and **Accept transfers**, then select **Save centre & access**.
4. Create **Bar**, code **BAR**, outlet Dining Room, responsible user **Bola / Bar Lead**. Enable the same three owner tasks and select **Save centre & access**. Add other actual centres only for a separate test scenario.
5. Assign an active responsible person to every centre before enabling production centres.
6. Under **Choose where processing & production happen**, enable **Kitchen** for this core example and save production centres. Also enable Main Store or Central Kitchen when they produce stock; a baseline separately selects which enabled centres may use it.
7. Use **Additional staff & detailed permissions** only for other colleagues or extra controls. Confirm Ada has Kitchen only and Bola has Bar only. Waste permission is independent of requesting materials; no waste approver is needed.
8. In **Inventory & movements > Locations & routes**, configure Main Store to Kitchen and the reverse return route. Add Bar routes only if needed. Use Inventory Manager as source approver for the normal workflow.
9. Check that each centre has its own ledger/balances and that the intended production centres are enabled.

Expected result: stock is controlled by location and user. Transfers need destination acceptance before quantities move. Enabling centres does not move stock. Finish/cancel pending batches at a centre before disabling it; existing batch history is retained.

## 6. Create suppliers

1. Open **Materials & suppliers**, choose the Suppliers tab and select Add supplier.
2. Create code **FISH_SUP**, name **Training Fish Supplier**. Enter the supplier's actual email, phone and address when available.
3. Create code **DRY_SUP**, name **Training Dry Goods Supplier**.
4. Check the suppliers are active and searchable before raising a Purchase Order or importing an invoice.
5. Keep codes unique and phone numbers as text so leading zeroes are preserved. Use inactivity instead of deleting identities needed in history.

Expected result: supplier records can be selected in purchasing. The existing suppliers.csv collection sheet is for preparation; it cannot currently be uploaded into a supplier-master importer.

## 7. Create all materials, packaging and processed SKUs

Open **Materials & suppliers > Add material** for each row. Set the category and outlet availability as appropriate; enable stock tracking for the stock-controlled items used in this walkthrough.

| Code | Material | Base unit | Type / supply source | Requires processing |
| --- | --- | --- | --- | --- |
| WHOLE_SNAPPER | Whole Snapper Fish | KG | Raw / Purchased | Yes |
| SNAPPER_CUT | Snapper Cut | PCS | Semi-finished / Processed | No, unless processed again |
| RICE | Rice | KG | Raw / Purchased | No |
| TOMATO | Tomato | KG | Raw / Purchased | No |
| ONION | Onion | KG | Raw / Purchased | No |
| OIL | Cooking Oil | L | Raw / Purchased | No |
| BOX | Takeaway Box | PCS | Packaging / Purchased | No |

1. Enter code/name, material type and base unit carefully. The base unit remains fixed after creation to protect history.
2. Select the stock class/supply source: Purchased, Processed, or Purchased and processed when both routes genuinely apply.
3. Mark Requires processing = Yes for an input that must undergo a controlled transformation into another SKU.
4. Set stock tracking, active status and weekly count inclusion as appropriate. Set a business-wide or specific-outlet availability scope.
5. Save and verify the material appears once with the expected code and base unit.

Requires processing describes the input. Processed supply source describes the output. They are different settings. Do not mark every cooking ingredient Yes merely because it appears in a final dish; use the flag for the processing baselines you intend to control.

Expected result: ingredients, packaging and output SKUs are available for their correct recipe/stock uses. A material record alone creates neither a price nor opening stock. Bulk material import is not currently implemented.

## 8. Configure material-specific unit conversions

1. Open the Units action for Rice in Materials & suppliers.
2. If buying a 50 KG bag, add source unit BAG, factor **50**, with the correct effective date. This means one BAG of this Rice equals 50 KG.
3. Configure other actual pack sizes separately per material. A bag of another material need not weigh 50 KG.
4. Check the conversion is effective on the relevant purchase/price/recipe date.
5. Do not create a general conversion from 40 KG whole fish to 120 PCS cut fish. That is a transformation of one SKU into another, handled by a processing baseline.

Expected result: package purchases normalise to each material's base unit. KG/G or L/ML use compatible standard unit dimensions. A bulk conversion importer is not currently available.

## 9. Enter or import dated starting material prices

Existing last purchase prices can be used as starting reference estimates; importing years of invoices is not required first. The price date and source note must identify real evidence.

| Material code | Starting unit price | Base unit |
| --- | --- | --- |
| WHOLE_SNAPPER | NGN 3,000 | KG |
| RICE | NGN 1,800 | KG |
| TOMATO | NGN 1,500 | KG |
| ONION | NGN 1,000 | KG |
| OIL | NGN 2,500 | L |
| BOX | NGN 100 | PCS |

**Manual route:** open Materials & suppliers > Initial material prices, choose the material and record quantity, unit, total price, actual price date and source note. For Rice enter quantity 1, KG, total price 1800; alternatively 50 KG at total 90000.

**Working bulk route:** download initial-material-prices.csv from the implemented import screen. Keep the exact columns: material_code, quantity, unit_code, total_price, price_date, source_note. Use existing codes, CSV UTF-8, YYYY-MM-DD dates and numbers without currency symbols or thousands separators. Preview, correct row errors, then confirm/save. Current limits are 100 price rows and 128 KB per file.

1. Verify all six materials have usable dated estimates.
2. Leave Snapper Cut without a separate purchased price when it is Processed-only; its unit estimate comes from the processing baseline.
3. Confirm no cost is taken from a date after the selected estimate date.
4. Starting reference prices are fallbacks. Posted invoices and approved corrections update monthly quantity-weighted price estimates. Do not rely on older collection-pack notes stating that new invoices never update recipe estimates; that describes an earlier release.

Expected result: costs can be estimated without treating a price upload as a stock receipt. A price file creates no stock quantities and does not create missing material masters.

## 10. Establish material processing baselines

1. Open **Data & Setup > Processed material setup**.
2. In Material processing baseline enter code **SNAPPER_CUTTING**, name **Snapper cutting**.
3. Select Whole Snapper Fish and baseline input **40 KG**.
4. Select produced stock material Snapper Cut and expected output **120 PCS**.
5. Enter an approved cut specification, an effective date and tolerance percentage. Use 0 for the exact training baseline.
6. Leave optional piece weights and trim blank unless measured and agreed.
7. Select Kitchen under Permitted production centres, then save. This publishes the versioned processing recipe, links its output SKU and saves the yield baseline together. It changes no stock. Use Add input material when a baseline needs several ingredients; each batch still has exactly one output SKU.
8. Verify the baseline is available at Kitchen and standard output cost is **NGN 1,000 per PCS**: 40 x 3000 / 120.

If the dropdown is empty, check material active status, stock tracking, base unit and classification. The input must be marked Requires processing; the output must be a different tracked Semi-finished/Finished material with Processed/Both supply source. Existing recipe-based setup remains in expandable sections, including processes with multiple inputs. There is no processing-baseline bulk importer yet.

## 11. Create the lowest-level sub-recipes first

A processing baseline and a cooking sub-recipe serve different purposes. The example below is a reusable recipe composition for costing. Do not assume publishing it automatically produces stock.

1. Open **Recipes & scaling > Create recipe**.
2. Enter code **STEW_BASE**, name **Training Stew Base**, recipe type **Sub-recipe / preparation**.
3. Enter measured usable batch yield **10 L**, the relevant effective date and an appropriate availability scope.
4. Add the following material components, selecting Material / packaging for each line.

| Component | Quantity for the whole batch | Unit | Expected input cost |
| --- | --- | --- | --- |
| Tomato | 5 | KG | NGN 7,500 |
| Onion | 1 | KG | NGN 1,000 |
| Cooking Oil | 1 | L | NGN 2,500 |
| Total | Yield 10 | L | NGN 11,000 |

5. Publish the recipe version and check estimated batch cost **NGN 11,000**, equivalent to **NGN 1,100/L** at these example prices.
6. If a parent sub-recipe uses this base, create that parent next and choose the exact saved child version. Build from the bottom of the dependency chain upwards.
7. For a sub-recipe physically stocked as its own SKU, set up its produced material, binding/baseline and production recording separately. Do not deduct both its stocked output and all its original raw inputs again in the same parent stock process.

A final recipe consuming 2 L of this 10 L base should receive only the cost of that 2 L share, not the entire NGN 11,000 batch cost. Unknown yields must remain incomplete rather than being guessed. Recipe-header/component CSV collection sheets are not currently uploadable.

## 12. Create final recipes, including sub-recipes and packaging

1. In Recipes & scaling create code **SNAPPER_RICE_RECIPE**, name **Training Snapper Rice Plate**.
2. Choose **Final recipe**, usable batch yield **10 PCS**, an effective date on/after the components' availability, and the appropriate scope.
3. Add the components below. For Stew Base choose **Saved sub-recipe version**, then the published STEW_BASE version from step 11. Use Material / packaging for the other lines.

| Component | Quantity for the full final batch | Unit | Expected allocated cost |
| --- | --- | --- | --- |
| Rice | 2 | KG | NGN 3,600 |
| Saved STEW_BASE version | 2 | L | NGN 2,200 |
| Snapper Cut | 10 | PCS | NGN 10,000 |
| Takeaway Box | 10 | PCS | NGN 1,000 |
| Total | Yield 10 | PCS | NGN 16,800 |

4. Publish and verify estimated batch cost **NGN 16,800**, or **NGN 1,680 per complete serving**.
5. Include packaging once. This example represents a boxed offering; use the restaurant's real packaging requirements rather than applying a box to every channel automatically.
6. Verify changing a child recipe later does not silently replace the saved version pinned by this final recipe. To adopt changed quantities, publish a new final version and review its menu binding.
7. Missing material costs, yields or valid component versions should be flagged. They must not be interpreted as a zero-cost recipe.

Expected result: the final recipe combines direct materials, the correct share of the saved sub-recipe and packaging into one portion cost. Saving a recipe calculates composition and estimates; it is not automatically a stock posting. Bulk final/sub-recipe import is still missing.

## 13. Create selling menu items and link the final recipes

1. Open **Menu & prices > Create menu item**.
2. Enter menu code **SNAPPER_RICE_MENU**, name **Training Snapper Rice Plate**, brand **Training Kitchen**, primary category Food, and a suitable subcategory such as Mains.
3. Set the restaurant/outlet scope correctly.
4. Select the saved **SNAPPER_RICE_RECIPE** final-recipe version.
5. Set **Recipe output per menu item = 1 PCS**. The final recipe yields 10 PCS; one sold plate uses one of those servings, not all 10.
6. Enter an effective date consistent with the recipe. In Standard selling price, enter 6000, Dining Room outlet, the effective date and No tax applied for this fictional example; then publish. If the price is unavailable, leave it blank for now.
7. Verify the item appears once and its published final-recipe link is correct.

A selling menu item is the identity used for sales. A final recipe is how that item is composed. A sub-recipe is a preparation component. Keep their codes and responsibilities clear. An incomplete menu draft is allowed but must not be mistaken for a fully costed, priced item. Alternatively, use Import menu CSV with menu-catalogue-import.csv after setting up the categories and recipes. Review CREATE/UPDATE and save; do not create the same code manually and then import CREATE.

## 14. Verify standard selling prices and menu profitability

1. If the price was saved with menu creation or CSV import, skip to step 5. Otherwise open the menu item details and select **Add selling price**.
2. Choose Dining Room, **Standard selling price**, selling price **6000**, the effective date and a price-source note.
3. For this fictional arithmetic test only, choose **No tax applied**. This is not a recommendation about the restaurant's actual tax obligations. Real onboarding must use its approved tax treatment and rate.
4. Save the standard price. Add channel-specific exceptions only when the restaurant charges a different price through that channel.
5. Open **Menu & prices**: profitability now appears first. Filter Food, then Mains. Use **Outlet, date & pricing exceptions** to check the outlet and date. Each selling item appears once; recipes stay in Recipes & scaling. The catalogue remains available on its own tab. Check the results below; open a menu row for supporting recipe and price details.

| Check | Expected training result |
| --- | --- |
| Estimated recipe/packaging cost per serving | NGN 1,680 |
| Selling price / net revenue in this no-tax example | NGN 6,000 |
| Estimated food cost percentage | 28.00% |
| Est. Contribution Margin (ingredients/packaging basis) | NGN 4,320 |
| Gross Profit Margin (estimated food basis) | 72.00% |

These are recipe-based food margin estimates, not actual net profit or a complete contribution margin after every variable cost. Labour, operating expenses, service charges, delivery commissions and other adjustments are not silently included. When tax is included/excluded in a real price, compare food cost with the appropriate net revenue basis shown by the system.

Expected result: correct effective price and final-recipe version, no missing cost components, and the same figures in the table and detail preview. Bulk selling-price import is still missing.

## 15. Establish opening stock and prove a transfer

1. Select the cutover date and count each material separately at Main Store, Kitchen and Bar as applicable.
2. Inventory Manager requests opening stock with a count-sheet reference. A different authorised colleague approves; Inventory Manager posts it.
3. For the snapper training sequence start with **40 KG Whole Snapper Fish at Main Store** and no Snapper Cut stock.
4. Add reviewed opening stock for Rice, Tomato, Onion, Oil and Boxes where physically held. Use the recorded count; for this paper example these may be 20 KG, 10 KG, 5 KG, 10 L and 100 PCS at Main Store if those are the fictional counts you choose to test.
5. When a tracked material/centre has no stock, use the available explicit zero-opening readiness confirmation rather than assuming a missing record means zero.
6. Ada requests 40 KG whole fish from Main Store to Kitchen. Emeka approves and dispatches.
7. Confirm Main Store still has 40 KG on hand and Kitchen 0 KG before acceptance; dispatched stock is reserved at source.
8. Ada accepts all 40 KG. Only now expect Main Store 0 KG and Kitchen 40 KG.
9. Test a partial acceptance or rejection with a reason using a separate request; review follow-up/reservations. Use the reverse route for an actual excess return.

Before continuing, run a separate Main Store waste check: Emeka records **1 KG Rice**, submitter **Emeka**, reason **Spoilage**. Expect Rice to change from **20 KG to 19 KG** immediately, with no approval. Leave the processing inputs unchanged. Finance should later see both this Main Store entry and Ada's Kitchen entry.

Do not post an opening balance for stock already established by earlier movements, and do not post a GRN again for goods included in opening counts. A price import, invoice or recipe publication is not an opening-stock import. Dedicated opening-stock CSV import is not currently implemented.

## 16. Record material processing and separate daily waste

Follow [Centre waste logging](CENTRE_WASTE_REVIEW_GUIDE.md). Standalone waste requires a submitter name and records immediately without approval. Centre access restrictions remain in place.


1. Ada opens **Material Processing Log > Record material processing**, selects Kitchen and Whole Snapper Fish. Output should auto-fill **Snapper Cut (PCS)**.
2. Enter actual input **40 KG**, actual output **110 PCS**, measured usable output weight **36 KG**.
3. Under **Measured waste & weights (optional)**, record **4 KG** processing waste and **36 KG** usable weight. Enter submitter **Ada**. The reason / additional note is optional.
4. Before submission expect **120 PCS**, a gap of **-10 PCS** and **-8.33%** variance. Select **Submit processing** once. No approval is required; inputs and output update together at Kitchen.
5. Expect Kitchen Whole Snapper Fish **0 KG** and Snapper Cut **110 PCS**. Raw deduction and output addition must occur together.
6. Expect baseline achievement **91.67%**, usable weight yield **90.00%**, recorded waste **10.00%**, and no unexplained weight for these measurements.
7. Do not enter another standalone waste record for the same 4 KG trim. It is already included in the 40 KG consumption.
8. For an independent loss, Ada opens **Waste Log > Record waste**, selects Kitchen and Snapper Cut, quantity **2 PCS**, submitter name **Ada**, reason **Spoilage**, and optional explanatory notes. Select **Record waste**; no approval or separate posting is required.
9. After submission expect Kitchen Snapper Cut **108 PCS**. Waste Log shows the 2 PCS independent loss. Combined waste reporting includes it and the 4 KG processing trim once each, with their distinct stock treatment.

Before submitting, try **41 KG** input against 40 KG available: a red shortage must appear and submission must be disabled. Use **Add material** to test multiple lines; the form must check combined input quantities. Remove this trial line and restore 40 KG before submitting the core scenario. Repeating the same saved submission must not duplicate stock. Older Requested/Approved processing entries are not silently posted: the original recorder can expand the older entry in the Material Processing Log and complete it with a submitter name.

KG input and PCS output do not alone establish weight yield. Without measured usable weight show that the weight measurement is needed, while retaining the valid count-based baseline achievement. Actual batch cost can differ from the standard SKU estimate when actual yield differs; it does not automatically rewrite the approved baseline. Never add unlike units such as KG and PCS into a single waste quantity total.

## 17. Test purchasing, imports, sales, expenses and accountability

1. Procurement creates a PO with supplier, outlet, materials, quantities and unit costs. Check calculated line/order totals. Do not introduce a PO approval stage; it is excluded from the current workflow.
2. Inventory documents the delivery in Goods Received Notes, checking material-level accepted/rejected quantities. Verify the PO and GRN registers/reports remain separate and traceable.
3. Post accepted GRN quantities into stock through the stock workflow where required. Do not duplicate an opening count or direct receipt.
4. Procurement records the supplier invoice. Test invoice matching and a separate Finance-approved correction when appropriate. Invoice entry must not automatically stand in for receiving the goods.
5. Use the working **purchases-import.csv** screen for a small invoice batch with existing supplier, material, unit and location codes. Check preview, control totals and recorded results.
6. Use **sales-import.csv** in Sales & summary with the existing selling menu code, outlet and the source's actual tax/receipt format. Review totals before posting. This guide does not claim a separate general manual sales-entry form.
7. Finance tests a manual expense, then an **expense-import.csv** batch with correct category, location/central scope, period and recognition method. Do not duplicate the same expenses using both routes.
8. Check historical reports for each role using dates, outlet/centre and status. Trace records to their material lines and source documents.
9. Check Inventory Manager's Needs Attention counts and Kitchen/Bar incoming confirmations. Department users should see only permitted centres and permitted stock actions; they should not gain financial reports or manager approval/dispatch authority. Standalone waste recording itself posts the loss immediately.
10. Check CEO views for changes, profitability impact, location and accountable exceptions rather than a long operational task list.

A sales CSV is not proof of automatic actual ingredient depletion. Validate the existing consumption/count workflows separately. Use supported source formats; do not imply a general POS, XLSX, refund or combo integration from the existence of a CSV upload.

## 17A. Finance and role-workspace checks for release 041

1. Sign in as **Chioma / Finance**, holding only Finance (not Restaurant Administrator or Inventory Manager). My workspace should lead with invoice reviews, expenses, waste, management reports, sales and history. There are at most six primary shortcuts; additional tools appear under **More records & tools** when available.
2. Expand **Finance records** to find sales, waste and expenses. Expand Purchasing for separate PO, GRN and invoice pages. No **Data & Setup**, **Users & roles**, **Materials & suppliers**, **Inventory & movements** or **Material Processing Log** link should appear in Finance navigation.
3. Test a direct setup URL: copy the organisation UUID from an existing page, then open `/workspace/setup/centres?organisation=THAT_UUID`. Finance should return to its workspace. Repeat for `/workspace/setup`, `/workspace/setup/production` and `/workspace/setup/standards`. A separately assigned Admin or Inventory Manager retains its own setup responsibilities.
4. Open **Review centre waste**. Default scope is all permitted centres and source **Processing & other waste**. Use From **2026-11-19** and Through **2026-11-19**. Expect Main Store **1 KG Rice**, Kitchen **2 PCS Snapper Cut**, and Kitchen **4 KG processing trim**, after the production batch is posted. Do not sum KG and PCS.
5. Select Kitchen and apply **Filter waste log**. The Main Store entry disappears. Expand **Source & status** and choose **Processing loss only**; expect only the 4 KG trim. Choose **Waste outside processing**; expect only the 2 PCS spoilage. Choose Recorded to exclude unposted entries.
6. Export CSV for each filtered selection. Compare centre, material, quantity, unit, source and submitter with the displayed filters. The CSV includes the full filtered result, not only the current page. Finance should have no **Record waste** action. Recorded processing trim must not cause a second stock deduction.
7. Sign in as Emeka. Waste Log and waste reports should show Main Store only, not Kitchen/Bar. As Ada expect Kitchen only; as Bola expect Bar only. Opening a foreign-centre link must not reveal that centre's waste data. Keep these testers single-role so extra reporting roles do not intentionally widen access.
8. In Procurement use a separate **TRAIN-MANUAL-PO-001** reference: order **2 KG Rice at NGN 1,800/KG** (NGN **3,600**); issue it directly. Inventory records a GRN accepting **1 KG**. Procurement records an invoice for **2 KG / NGN 3,600**, linked to this PO. Do not reuse either uploaded invoice reference.
9. Finance opens that invoice. Invoice/supplier/date/outlet/total and the materials should appear before **Delivery & billing check**. The billed-more-than-received exception and Finance review action should be visible. Matching-only quantity details expand when the unreviewed exception requires attention; source and correction history remain collapsed until opened. Zero-only tax/discount columns may be omitted.
10. Finance records an exception review with a reason. This does not authorise payment or receive stock. Inventory records the remaining **1 KG** under a second GRN. On refreshing the invoice, matching and the earlier review validity must reflect the changed source records. Check PO/GRN materials and separate historical reports too.
11. Procurement requests a separate invoice correction with a reason. Until Finance decides, the current invoice figures stay unchanged. Finance sees the pending before/proposed values and decision controls. After approval the new figures appear; expand **Source & correction history** to inspect the preserved earlier values.
12. Check desktop and narrow mobile screens. Tables should remain readable within their own horizontal scroll area; the whole page should not overflow. Navigation groups open on selection and allow collapse. A CEO-only workspace should prioritise profitability changes; a CEO who also has Administrator duties retains the corresponding administration navigation.

The manual PO above changes later monthly recipe cost if its net unit price differs from the sample's reference price. Use the supplied 1,800/KG Rice price to keep the baseline arithmetic unchanged. Treat its deliveries as separate from starting counts and from imported invoice quantities; record actual stock receipt through the relevant workflow once.

## 17B. Weekly-count classification check

1. As Administrator, open each material and check **Include in weekly stock counts** (the material's weekly-count flag). All seven sample SKUs are included in this pack.
2. Save, reopen and confirm the choice persists, including for the processed **SNAPPER_CUT** SKU. For a separate inactive trial SKU, disable the flag and verify it stays off; do not change the seven sample quantities to test this.
3. Verify the reporting week starts Wednesday, physical count day Tuesday and cutoff 23:30 in Africa/Lagos for this fictional setup. Use your restaurant's own schedule for a real pilot.
4. Record counts at the correct centre through the available count workflow; verify that an explicit zero is accepted and an omitted count is not silently interpreted as zero.
5. A complete automatic weekly count-sheet/reminder/theoretical-usage programme remains a separate phase. Mark a missing automatic feature **Not available**; do not report it as Passed simply because the material flag saved.

## 18. Bulk-import requirements still to implement and test

The product requirement is to give restaurants a manual route for small additions and a real bulk route for initial master-data onboarding. The missing scope includes suppliers, materials/packaging, conversions, processing baselines, recipe headers/components, selling menu items/recipe links, selling prices, and opening stock. Named team/centre setup can be added as supported bulk workflows with explicit review; a spreadsheet must never bypass invitation acceptance or grant permissions silently.

1. Provide a downloadable template for each supported dataset, labelled with its version and required/optional fields.
2. Include newer fields such as material Requires processing, stock class, outlet scope, effective dates, named centre ownership and current role codes. Older collection sheets do not contain every new field and should not be presented as the latest upload contract.
3. Import in dependency order: business/centres/users as required; suppliers and units/materials; conversions and starting prices; processing definitions; child sub-recipes; parent/final recipes; selling menu items and recipe links; selling prices; then reviewed opening stock.
4. Validate permissions and restaurant boundaries before reading or writing records. Resolve referenced codes only within the selected restaurant and permitted scope.
5. Show row-level errors and a preview before confirmation. Reject unknown references, incompatible units, cycles, missing yields, conflicting codes and invalid dates without creating misleading partial setups.
6. Define create/update behaviour explicitly. Preserve immutable historical recipe/menu versions and posted stock; do not overwrite them silently.
7. Make retries safe so submitting a confirmed batch twice cannot duplicate materials, recipes, prices, invitations or opening stock.
8. Record who uploaded, reviewed and confirmed each batch, with source provenance and clear result counts.
9. Test both routes using the same small approved dataset in separate training restaurants. Compare codes, scopes, recipe links, effective dates, unit conversions, estimated costs, selling margins and opening balances.
10. Mark the bulk onboarding test **Blocked - importer not implemented** for a missing screen. Do not mark it Passed because a collection CSV exists or because manual entry worked.

## 19. Final onboarding sign-off

Use the following checklist as the restaurant's acceptance record. Add tester name, date, actual result and evidence for each item. A blocked import is a product gap, not a failure by the restaurant team.

- Business, brand/outlet, currency and reporting calendar verified.
- Named users accepted invitations; role and centre restrictions tested.
- Every centre has an active responsible user; production centres and movement/return routes correct.
- Suppliers, materials, packaging, conversions and processing flags reviewed.
- Dated starting prices present; processed SKU cost derived correctly.
- Processing baselines, lowest-level sub-recipes, parent sub-recipes and final recipes reviewed in dependency order.
- Selling menu items linked to the correct final versions, with one serving mapped correctly.
- Outlet/channel prices, tax treatment, effective dates, targets and menu margin checks verified.
- Opening counts established once per material/centre; transfer acceptance and return behaviour tested.
- Processing deductions/additions, yield measurements and standalone waste tested without duplicate loss entries.
- PO, GRN, invoices, permitted imports, sales, expenses and historical reports checked.
- Finance setup restrictions, invoice readability and combined centre waste/export checked.
- Inventory/Kitchen/Bar waste access stays centre-restricted; submitter names present without approval.
- Weekly-count material flags saved and reporting calendar verified; unavailable automation recorded separately.
- CEO profitability/accountability view and operational Needs Attention queues checked.
- All required manual-entry tests passed; working import routes passed; missing master-data importers explicitly tracked as blocked.

The previous stock-only guide remains useful as a focused operational exercise. This complete guide adds the master-data and selling-menu setup that must precede a full restaurant pilot.


## 18. Owner menu review and issued-PO price warnings

Menu & prices starts with profitability, target exceptions and missing-cost coverage. Food-cost percentages below or equal to the maximum target are favourable; higher percentages are exceptions. Configure a Food target of 30% for the sample dish: 28% food cost is within target; 4320 is the estimated contribution from ingredients/packaging and 72% is Gross Profit Margin on that basis. Other variable costs are not included. Filters and source details are expandable. Counts use the full searched scope; risk sorting and status filtering happen before pagination. The Back action retains comparison filters.

Run optional CEO-PO-01 and CEO-PO-02 after the core arithmetic checks. For example, 2 KG Rice quoted at 1980/KG against a saved 1800/KG baseline creates a 360 NGN potential warning when issued. A draft is not an executive alert. An active GRN updates received quantity; a valid invoice for 1 KG reduces the unbilled potential to 180 NGN. Invoice recording updates monthly weighted costs; the PO and GRN do not. Do not add this warning to the invoice-period price comparison. These optional transactions change later core totals, so use separate references and record the additional activity.

PO warnings select orders by their actual issue day in the business timezone, and show live delivery/billing progress. The baseline is pinned at issue. Corrected invoice links need review; approved voids update progress. Existing issued orders have a historical baseline reconstructed only from evidence recorded by issue time, or show no comparison baseline. No prices or stock are changed by this historical backfill.


## 19. Menu categories and standard prices

During onboarding, add your own subcategories under Food or Drink. For this training restaurant add Food / Mains, Food / Sides and Drink / Soft drinks. You can manage them later under Data & Setup > Menu categories. Retiring a subcategory preserves existing assignments. Extra sales channels are optional; a standard selling price is available without configuring Dine in, Takeaway or Delivery.

Create the selling menu manually with its major category, subcategory, recipe link and optional standard price in the same form, OR upload menu-catalogue-import.csv through Menu & prices > Import menu CSV. Choose the PRIMARY outlet. Review the CREATE action and price 6000, check the confirmation and save. Do not manually create the item and then import CREATE for the same code. Use UPDATE deliberately for existing items; unchanged rows and retries do not duplicate saved versions. A blank recipe saves an incomplete item. A blank imported price keeps existing prices. Food/Drink subcategories and any supplied recipe code/version must already exist. Export the relevant workbook sheet as CSV; the menu importer accepts CSV, not the whole workbook or XLSX file.

Menu profitability has one row per selling menu item. Filter Food/Drink, then subcategory, status, outlet and date. Recipes and their costs stay in Recipes & scaling. At the standard price of 6000 the training plate costs 1680, contributes an estimated 4320 and has a 72% Gross Profit Margin, before unconnected variable costs. Channel exceptions can be chosen under Outlet, date & pricing exceptions without duplicating rows. A missing standard price may use a sole consistent legacy price; conflicting legacy prices require choosing a pricing basis or saving a standard price. Prices are never averaged across channels.

The menu CSV is the fifth uploadable format in this pack. Suppliers, material masters, recipe definitions and opening-stock collection sheets remain manual-entry/reference sheets unless their specific screen offers an importer. Use the CHANNEL-01/02 cases to check category setup, one-row reporting and optional channel overrides.


## 20. Confirm each centre's daily waste report

Use the actual operational test date in the restaurant timezone for physical processing, spoilage and daily declarations. Do not try to confirm a historical sample date that precedes the centre's reporting start. Keep financial import sample dates explicit; widen the waste filters when the test spans dates.

1. Each newly created active centre automatically requires daily reporting, due at 23:59 local time. Administrators/CEOs can open Waste reporting schedules from Centres & team access or Daily reporting to choose operating days and an overnight deadline. Changes apply from tomorrow; past obligations are preserved.
2. Sign in as Emeka. Open Waste Log > Daily reporting, select Main Store and the operational date. After its 1 KG rice loss is recorded, review the entries, enter the submitter name and confirm the waste report is complete. No approval and no extra stock deduction occur.
3. Sign in as Ada. Confirm Kitchen's daily report after posting its processing batch and separate 2 PCS spoilage. Processing trim counts as loss evidence automatically; do not enter the trim again as standalone waste.
4. Sign in as Bola. Select Bar and explicitly confirm no waste if no waste occurred. An empty log alone is not a no-waste declaration.
5. CEO/Finance: review Daily reporting for all centres on the same operational date. Expect 3/3 complete. Export the compliance CSV and check the responsible owner, named submitter, actual account, deadline and lateness. On-time compliance uses deadlines that have passed; before today's deadline it may say Not due.
6. Open Waste analysis. The training scenario contains 1 KG Main Store rice, 4 KG measured Kitchen processing trim and 2 PCS Kitchen Snapper Cut spoilage. Never sum KG and PCS. With the saved sample prices the known estimated loss is NGN 15,800 (1800 + 12000 + 2000); it is not actual profit or inventory valuation and must not be added again to production costs. Output achievement is 110/120 = 91.67%; measured usable-weight yield is 36/40 = 90%.
7. Run WASTE-DAY-02 through WASTE-DAY-05 with separate references after core balance checks. Additional losses change the earlier quantities and totals. A new loss reopens a confirmed day; unposted losses block confirmation; stale or repeated requests cannot double-post stock. Late reporting remains late. Exceptional closures require an administrator/CEO and a reason, and closures declared after deadline are visible.
8. Inventory must still see only its own centre. Kitchen/Bar must see assigned centres. Finance reads permitted combined waste and compliance but cannot submit declarations, record stock or change schedules.

The daily-waste-declarations sheet is a manual test collection sheet, not an upload schema. In-app reminders do not send emails. Missing reports, missing prices and older unclassified reasons remain visible rather than being invented as zeros or guessed categories.


## 21. Multiple production centres and single-output batches

Enable each actual producing centre under Centres & team access > Choose where processing & production happen. A five-centre restaurant can enable Central Inventory Store and Central Kitchen, leaving Front Kitchen, Back Kitchen and Bar as storage/service centres unless they also need to record stock production. Each baseline selects one or several enabled centres. Users still need stock-task access at the actual centre.

A baseline can contain several material inputs and exactly one output. In the daily log, the main input scales expected output; secondary inputs start from the baseline ratio and can be edited to actual consumption. Shortages are checked across every material and every submitted line, then rechecked atomically in the database. Beef Small Cuts and Beef Big Cuts use separate batches and only their allocated raw input quantities, never the same full input twice.

Front Kitchen can request raw materials from Central Inventory and prepared SKUs from Central Kitchen using separate configured routes. Prepared items must be real tracked output SKUs. Receiver acceptance remains the stock-movement posting point. There is no new automatic production-order planner: the producing centre records any required production before dispatching the prepared stock.

Run PROD-CENTRE-01 through PROD-CENTRE-03 in a separate scenario after the original numeric checks. The core sample still uses only Kitchen production so its expected balances and costs remain unchanged.


## 22. Generate a centre material plan

Open Daily operations > Material Plan as a centre user with stock-request access or an authorised stock manager. Select the centre and plan date. Choose Training Snapper Rice Plate (final recipe) with target 10 PCS and Training Stew Base with target 10 L, then generate. Target quantities are output units, not number of batches. In the core sample the consolidated requirements are Rice 2 KG, Tomato 6 KG, Onion 1.2 KG, Oil 1.2 L, Snapper Cut 10 PCS and Takeaway Box 10 PCS. Stew Base has no stocked output binding in this sample, so its ingredients expand automatically.

Keep stocked preparations as SKUs uses a permitted baseline's pinned inputs where available. Other saved recipes retain bound sub-recipe outputs as prepared stock; unstocked sub-recipes expand. Expand saved sub-recipe ingredients expands those pinned child recipe versions instead. Direct material SKUs, including processed materials explicitly listed as components, remain materials in either basis. Do not select a child separately unless its target is additional demand beyond its parent's requirement.

Available now is current on-hand minus reservations at the selected centre. It is not a stock forecast for the plan date. Zero availability or shortages do not block generation. Plans never create requisitions, production, reservations, stock movements or cost postings. Download CSV or print to keep the generated snapshot; changing inputs requires regeneration. Operational records remain separate. Test PLAN-01 through PLAN-03 with separate targets.
