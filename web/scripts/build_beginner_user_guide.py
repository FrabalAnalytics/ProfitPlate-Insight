"""Build a self-contained, branded Word beginner guide using the standard library."""
from pathlib import Path
from html import escape
from zipfile import ZipFile, ZIP_DEFLATED
import re
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/exports/ProfitPlate_Insights_Beginner_Setup_and_Daily_Operations_Guide_050.docx'
PAGES = []

def page(title, text):
    PAGES.append((title, text.strip()))

page('ProfitPlate Insights', '''
### Your beginner guide
From restaurant setup to daily operations
Current application: 20 November 2026 | Includes multi-centre production and daily waste accountability

### What the product does
ProfitPlate Insights helps restaurant owners and their teams understand how everyday operating decisions affect estimated profitability and accountability. It connects material prices, recipe costs, selling menus, purchases, stock movements, processing, waste, sales and operating expenses in one restaurant workspace.
Owners can quickly see which menu items exceed food-cost targets, where purchase prices are rising, where stock handovers are waiting, and which centres have not completed their daily waste reporting. Teams work in role-focused workspaces, with records tied to the outlet, stock centre and person responsible.
The product supports a single restaurant or a business with several outlets and stock centres. A Main Store, Central Kitchen, Front Kitchen and Bar can hold separate stock records while following agreed movement routes.

### The business value
- Build discipline: assign centre owners and make daily waste reporting an explicit responsibility.
- Improve decision quality: distinguish a confirmed no-waste day from an unreported day.
- Expose margin pressure: compare cost per serving, selling price and food-cost targets.
- Strengthen stock accountability: follow purchasing, receiving, transfers and processing back to their source records.
- Understand losses: review waste reasons, centre patterns and processing yield alongside reporting coverage.
- Reduce clutter: give each person the tasks and information permitted by their role.

! The goal is a repeatable cycle: clear responsibilities -> consistent records -> more trustworthy data -> better operating decisions. The system makes issues visible; the team still investigates causes and takes action.
''')

page('1. Understand the numbers before you begin', '''
### What you can review
Menu profitability puts selling items first: cost per plate, selling price, food cost %, target %, Est. Contribution Margin and Gross Profit Margin. Food and Drink subcategories help you focus the review without repeating an item across several channels.
Purchase reporting separates orders, goods received and supplier invoices. Processing compares measured output with a saved baseline. Waste reporting shows both recorded losses and whether each expected daily report was completed.

| Business question | Useful place to start |
| Which dishes need attention? | Menu & prices: profitability |
| What is driving ingredient cost? | Material price history and monthly cost estimates |
| Did stock reach the department? | Inventory & movements: transfer status and ledger |
| Are centres reporting consistently? | Waste Log: Daily reporting |
| Where are losses recurring? | Waste Log: Waste analysis |
| What changed across the business? | Executive workspace, overview and management reports |

### Read estimates correctly
- Recipe and menu costs use usable dated material estimates. Posted invoices inform monthly quantity-weighted material costs; starting prices are fallbacks.
- Est. Contribution Margin currently means net selling revenue less connected ingredient and packaging estimates. It is not a complete contribution calculation after every variable cost.
- Gross Profit Margin on the menu screen is the percentage remaining on that same estimated food-cost basis. It is not the restaurant's actual net profit.
- Known waste value is an estimated subtotal. Missing prices remain visible, and historical loss snapshots are not silently repriced later.
- Stock balances and the ledger track physical quantities. They do not establish monetary inventory valuation.

! Publishing a recipe, saving a price, recording a sale and receiving stock are different events. A saved recipe is not stock production, and a sales upload is not proof of automatic ingredient depletion.
''')

page('2. How to use this guide', '''
### Your route through the guide
1. Prepare the restaurant data and create the owner workspace: chapters 3-4.
2. Invite the team and set up stock centres, permissions and reporting schedules: chapters 5-6.
3. Enter suppliers, materials, prices and opening stock: chapters 7-9.
4. Set up processing baselines, recipes and selling menus: chapters 10-12.
5. Complete the go-live checks: chapter 13.
6. Run daily purchasing, transfers, processing and waste reporting: chapters 14-17.
7. Review waste analysis, finance records and weekly performance: chapters 18-20.
8. Use the role checklists and troubleshooting pages: chapters 21-22.

### Four terms that prevent confusion
| Term | Plain meaning |
| Outlet | A business location used for sales and reporting, such as Lekki Restaurant |
| Stock centre | A place holding quantities, such as Main Store, Kitchen or Bar |
| Material / SKU | A stock identity with a unique code and base unit, such as WHOLE_SNAPPER in KG |
| Posting | The action that actually writes a stock movement to the ledger |

### Start small, then expand
Use a training restaurant and a few complete materials first. Prove one purchase, one accepted transfer, one processing batch and one daily waste confirmation. Then load the restaurant's approved data and agree the live cutover date.
Use the current complete test pack for fictional practice data. Its workbook includes preparation sheets and working CSV examples. A preparation sheet is not automatically an upload template.

! Buttons and pages depend on your assigned roles. If a step is not available, ask the restaurant administrator to check your role and centre tasks. Do not create another restaurant to work around missing access.
''')

page('3. Collect the data before opening forms', '''
### Prepare one approved source file
1. Agree the restaurant name, currency, country, brand and outlets.
2. Agree the business timezone, reporting week, stock-count day and cutoff.
3. List staff names, verified emails, roles, outlet access and centre responsibilities.
4. List stock centres, their owners, permitted production centres and permitted movement/return routes.
5. Collect supplier codes and contacts; material codes, types, base units and conversions.
6. Collect last purchase prices with dates; count opening stock by material and centre.
7. Collect processing standards, sub-recipes, final recipes, menu categories and selling prices.
8. Agree Food/Drink cost targets and the daily waste reporting schedule.

### Manual entry and uploads in this version
| Dataset | Current entry route |
| Profile, team, centres and routes | Manual setup and invitations |
| Suppliers, materials and unit conversions | Manual forms |
| Dated starting material prices | Manual entry or reviewed CSV |
| Processing baselines and recipes | Manual forms |
| Menu categories | Manual setup |
| Selling menus, recipe links and standard prices | Manual menu form or reviewed menu CSV |
| Opening stock | Reviewed stock workflow; no dedicated opening-stock CSV importer |
| Supplier invoices | Manual entry or reviewed purchase CSV |
| Sales | Supported sales CSV import |
| Labour and operating expenses | Manual entry or reviewed expense CSV |

Use unique codes consistently. Keep unknown values blank rather than inventing them. Do not upload the whole reference workbook: the supported upload screens use their specific CSV format. General XLSX/master-data import is not available for every dataset.
''')

page('4. Create the owner account and reporting calendar', '''
Who: the owner or authorised Restaurant Administrator.

1. Open ProfitPlate Insights and select Create your workspace / Get started.
2. Register with an email you control. Open the verification email and complete verification.
3. Sign in and complete the restaurant onboarding form. Enter the real business, brand, outlet, country and currency details.
4. Choose the restaurant's reporting timezone. For a Nigerian restaurant, Africa/Lagos is an example; use the actual business location.
5. Choose when your reporting week starts. A Wednesday-start week is valid if that matches the restaurant's working cycle.
6. Choose the physical count day and local cutoff time. This is the agreed counting schedule, not an automatic stock adjustment.
7. Add Food and Drink subcategories when prompted, such as Food / Mains, Food / Sides and Drink / Soft drinks.
8. Finish onboarding. If the platform presents an activation/access restriction, follow up with the platform administrator rather than creating a duplicate business.
9. Open Data & Setup, then Reporting calendar & targets. Confirm the saved settings and enter the business-approved Food and Drink cost targets; review outlet overrides where used.
10. In My workspace, save the name to use in your greeting if it has not already been entered.

### Check before moving on
- The workspace shows the correct restaurant, currency and outlet.
- The reporting calendar matches the restaurant's local working day.
- Your Food/Drink targets are approved business targets, not copied test values.

! The timezone affects which business date activity falls on near midnight. Changing a calendar is a management decision. Count schedules still require the team to measure, enter, review and post counts through the available workflow.
''')

page('5. Invite colleagues and give them the right access', '''
Who: Restaurant Administrator. Each colleague uses their own account.

1. Open Users & roles and choose Invite colleague.
2. Enter the colleague's name and exact email address.
3. Select an available role and the appropriate outlet scope.
4. If stock centres already exist, select the relevant centres and tasks in the invitation. If not, invite the person first and assign centre access in chapter 6 after they join.
5. Review the permissions and create the invitation. Check the displayed email status. If needed, use the copyable backup invitation link and share it privately with the intended person.
6. The colleague opens the sign-in/invitation link, verifies the invited email where required, reviews the invitation and accepts it. They must join this restaurant, not create a separate one.
7. Ask the colleague to sign in and check their greeting, workspace and permitted tasks.

| Role | Normal responsibility |
| Restaurant Administrator | Setup, team roles and access |
| CEO | Executive review; setup only where separately authorised |
| Procurement | Purchase Orders, invoices and purchasing history |
| Inventory Manager | Stock oversight, approvals, dispatch and quantity posting |
| Kitchen Manager / Bar Lead | Their assigned centre's permitted stock tasks |
| Operations Manager | Operational responsibilities within assigned permissions |
| Finance / Auditor | Financial review, expenses and permitted combined reports |

### Role, scope and ownership are different
A role defines the kind of work. Outlet scope limits where that role applies. Centre tasks determine actions at a particular stock centre. The responsible owner records accountability; naming someone does not automatically grant every task.
Inventory Manager has broad stock oversight, but waste access remains restricted to the centre(s) they own. Finance-only access does not include setup or stock entry. Do not assign Inventory Manager to a kitchen colleague just to fix a missing centre task.

! Invitation email delivery depends on the platform email service. An email request is not proof of inbox delivery. Use the backup link if necessary. Restaurants choose from the available roles; self-service custom role creation is not currently available.
''')

page('6. Set up centres, owners and daily schedules', '''
Who: Restaurant Administrator; authorised stock configuration users where permitted.

1. Open Data & Setup > Centres & team access.
2. Add Main Store. Enter its name and storage type; set a unique code under More centre details. Choose whether it is central/shared or assigned to an outlet.
3. Select its responsible member, for example Emeka / Inventory Manager. Review tasks and select Save centre & access.
4. Add Kitchen with Ada / Kitchen Manager as its owner. Enable Request materials, Record waste and Accept transfers, as appropriate. Save centre & access.
5. Add Bar with its responsible Bar Lead and approved tasks. Repeat for actual Front Kitchen, Central Kitchen or other storage centres.
6. Under Choose where material processing happens, select the centre used for controlled processing in this setup. Save permitted production centres. This may include Main Store and Kitchen; it does not transfer existing stock.
7. Use Additional staff & detailed permissions for other authorised colleagues. Give access only to the centres and tasks they need.
8. In Inventory & movements > Locations & routes, add the permitted source-to-destination routes. Use Inventory Manager as source approver for the normal store issue workflow. Add the reverse route for excess returns.
9. Open Waste reporting schedules from centre setup or Daily reporting. Review operating days, local deadline and any next-day cutoff needed for overnight trading.

### Example layout
| Centre | Owner | Typical flow |
| Main Store | Emeka / Inventory Manager | Receive goods; send stock to Kitchen and Bar |
| Kitchen | Ada / Kitchen Manager | Accept ingredients; process if designated; record waste |
| Bar | Bola / Bar Lead | Accept stock; record losses; return excess |

Every new active centre starts with daily reporting, due at 23:59 local time. Schedule changes apply prospectively from tomorrow. Confirm a responsible active user for every centre. Do not create a centre for a shelf unless you actually need to manage a separate stock balance and reporting responsibility.
''')

page('7. Add suppliers, materials and units', '''
Who: an authorised master-data user.

1. Open Materials & suppliers, select Suppliers and add each supplier with a unique code, name and available contact details. Keep suppliers needed for purchasing active.
2. Select Add material. Enter a unique material code and clear name.
3. Choose the material type, category, base unit and availability scope. Use KG for kilograms, L for litres or PCS for pieces as appropriate.
4. Set the supply source: Purchased, Processed, or both where genuinely used.
5. Enable stock tracking for materials that require quantity control.
6. Set Requires processing to Yes for a raw input that will be transformed into a separately controlled output SKU.
7. Select Include in weekly stock counts for SKUs that must be counted in the weekly routine. Include processed stock if the team physically counts it.
8. Save. Reopen the record and confirm the unit and classification.
9. Use the material's Units action for package conversions. A 50 KG rice bag needs the rice-specific factor: 1 BAG = 50 KG. Set an appropriate effective date.

| Example material | Base unit | Type / source | Requires processing |
| Whole Snapper Fish | KG | Raw / Purchased | Yes |
| Snapper Cut | PCS | Semi-finished / Processed | No, unless processed again |
| Rice | KG | Raw / Purchased | No |
| Takeaway Box | PCS | Packaging / Purchased | No |

### Avoid two common mistakes
The input's Requires processing flag and the output's Processed supply source mean different things. Also, transforming 40 KG fish into 120 cuts is not a unit conversion: it changes one material into another and belongs in a processing baseline.

! A saved material creates neither a price nor an opening stock balance. The base unit is fixed after creation to protect historical quantities. Suppliers and material masters currently use manual forms; their collection sheets are not working bulk uploaders.
''')

page('8. Enter last purchase prices and use CSV review', '''
Who: an authorised material-price user.

### Manual price entry
1. Open Materials & suppliers > Initial material prices.
2. Select the material. Enter the purchased quantity, unit, total price, actual price date and source note.
3. For Rice bought at NGN 1,800 per KG, enter 1 KG and total price 1800. For 50 KG at the same rate, enter 50 KG and total price 90000.
4. Review and save. Check the material's estimated unit cost using an estimate date on or after the price date.
5. Repeat for purchased ingredients and packaging. A Processed-only output should get its estimate from its linked processing definition, not an invented last purchase price.

### Starting-price CSV
1. Download the template from the initial price screen. Use the exact columns: material_code, quantity, unit_code, total_price, price_date, source_note.
2. Use material codes that already exist in this restaurant. Use dates such as 2026-11-20 and numeric values without NGN signs or thousands separators.
3. Save/export that sheet as UTF-8 CSV. The price uploader accepts up to 100 rows and 128 KB.
4. Upload, preview and inspect row errors. Correct the source file and preview again if necessary.
5. Confirm the reviewed batch once. Check the result before retrying or uploading another batch.

### How later prices affect costing
Posted invoices and approved corrections inform monthly quantity-weighted material estimates. For example, 10 KG at NGN 1,000/KG and 30 KG at NGN 2,000/KG gives an average of NGN 1,750/KG. This is weighted by quantity, not a simple average of the two prices.
Starting prices are fallbacks where usable invoice evidence is absent. Cost dates matter: a future-dated starting price does not supply an earlier estimate. Monthly estimates can change as valid source records change; review the basis shown on the cost screen.

! A price upload does not receive stock. Keep last purchase evidence and opening quantities in the same preparation workbook if convenient, but enter them through their separate current app workflows.
''')

page('9. Establish opening stock once', '''
Who: Inventory Manager and a different authorised reviewing colleague.

1. Agree a live cutover date and time. Physically count stock at each centre at that point.
2. Record each material's quantity in its base unit. Keep Main Store, Kitchen and Bar counts separate. Count any processed SKU already physically held.
3. Open Inventory & movements and choose the stock-entry/new request area. Select Opening balance, the destination centre and count date.
4. Add the counted materials and quantities. Include a count-sheet reference and note. Review and submit the opening record.
5. A different authorised colleague opens that record and approves the verified count. The recorder cannot approve their own opening request.
6. The authorised Inventory user returns to the approved record and chooses the posting action. Follow the review confirmation and submit.
7. Confirm the completed status and inspect Stock on hand and the Posted stock ledger for the correct centre. Approved alone is not proof that the quantities have been posted.
8. For a genuinely zero starting quantity, use the explicit zero-opening readiness option under Reporting calendar & targets / Opening stock readiness, where applicable. Do not invent a positive opening or treat an omitted count as zero.
9. If a readiness warning remains, check the relevant material, centre, date and final posting status before creating anything else.

### A small training opening
| Main Store material | Fictional starting quantity |
| Whole Snapper Fish | 40 KG |
| Rice | 20 KG |
| Tomato | 10 KG |
| Onion | 5 KG |
| Cooking Oil | 10 L |
| Takeaway Box | 100 PCS |

! Do not enter another opening to hide an unresolved posting. Do not count the same delivery as both opening stock and a later receipt. Current opening entry is a reviewed stock workflow, not a dedicated opening-stock CSV upload.
''')

page('10. Set the material processing baseline', '''
Who: an authorised setup user. Do this once before daily processing.

1. Confirm the enabled production centres and its owner in Centres & team access.
2. Create the raw input and output material first. Example: Whole Snapper Fish in KG, and Snapper Cut in PCS.
3. Open Data & Setup > Processed material setup and find Material processing baseline.
4. Enter a process code and name, such as SNAPPER_CUTTING / Snapper cutting.
5. Select Whole Snapper Fish and enter baseline input quantity 40 KG.
6. Select Snapper Cut and enter expected output quantity 120 PCS. If more ingredients are needed, use Add input material and enter their baseline quantities. The batch still has one output SKU. Select its permitted enabled production centres.
7. Describe the expected cut size or output specification. Use a measured, approved standard, not an arbitrary output target.
8. Set the effective date and approved output variance tolerance. Add measured baseline weights when available.
9. Save the baseline. This publishes the processing recipe, links the produced SKU and saves the standard together. It changes no stock.
10. Check the processed material's estimated unit cost. At NGN 3,000/KG, 40 KG costs NGN 120,000; dividing by 120 PCS gives NGN 1,000 per cut.

### If the output dropdown is empty
- The output must exist, be active and have stock tracking enabled.
- It must be a suitable Semi-finished or Finished material with Processed/Both supply source.
- Its base unit must match the intended recipe output dimension.
- The input must be marked Requires processing and the output must be a different SKU.

### Keep a standard and a daily result separate
The baseline is the expected conversion. Each processing log records what actually went in and came out that day. If the approved standard changes, create a new version instead of rewriting old results.
For an existing published processing recipe or more complex composition, use the expandable existing-recipe/output-link setup. Do not create a duplicate baseline after the simpler form has already saved and linked it.
''')

page('11. Build sub-recipes, then final recipes', '''
Who: the recipe owner or authorised master-data user.

1. Open Recipes & scaling > Create recipe.
2. Start with the lowest-level sub-recipe. Enter its code, name, Sub-recipe / preparation type, usable batch yield, unit and effective date.
3. Add component quantities for the entire batch, not for one plate unless the batch yield is one plate.
4. Publish and review its estimated batch and output-unit cost.
5. Create parent sub-recipes next, selecting the exact saved child versions. Continue from the bottom of the dependency chain upwards.
6. Create the final recipe with its usable batch yield. Add direct materials, the needed share of saved sub-recipes, processed materials and packaging.
7. Publish and review the cost per serving. Check missing costs rather than assuming blank ingredients cost zero.

### Worked example: Stew Base
5 KG Tomato at 1500/KG + 1 KG Onion at 1000/KG + 1 L Oil at 2500/L = NGN 11,000. If the measured usable yield is 10 L, cost is NGN 1,100/L. A parent using 2 L receives NGN 2,200 of that cost.

### Worked example: 10 complete Snapper Rice Plates
| Component | Full batch quantity | Allocated estimate |
| Rice | 2 KG | NGN 3,600 |
| Saved Stew Base | 2 L | NGN 2,200 |
| Snapper Cut | 10 PCS | NGN 10,000 |
| Takeaway Box | 10 PCS | NGN 1,000 |
| Total / usable yield | 10 PCS | NGN 16,800 / NGN 1,680 each |

! Recipe publishing does not produce stock. Where a preparation is separately stocked, configure its output and production explicitly. A parent stock process must not consume both the stocked child output and all its raw inputs again. Saved child versions remain pinned until a new parent version deliberately adopts changes.
''')

page('12. Create selling menus and review profitability', '''
Who: an authorised menu/pricing user; CEO reviews results.

1. In Data & Setup > Menu categories, add the restaurant's subcategories under Food or Drink. Examples: Food / Mains, Food / Extras, Drink / Cocktails.
2. Open Menu & prices > Create menu item. Enter code, name, brand/scope, major category and subcategory.
3. Link the saved final recipe version. Enter recipe output used per sale. If the recipe makes 10 PCS and a sale is one plate, enter 1 PCS, not 10.
4. Enter the standard selling price, target outlet, effective date and approved tax treatment in the same form. Save/publish. Unknown prices can be supplied later.
5. Use standard pricing when prices are the same across channels. Configure extra channels and price exceptions only when the restaurant actually needs them.
6. Alternatively choose Import menu CSV, select one target outlet, and use the current template. Categories and supplied recipe references must already exist. Review CREATE/UPDATE, warnings and prices before confirming. The menu CSV limit is 100 rows / 128 KB.
7. Open the profitability tab. Filter Food/Drink, then subcategory and status. Check outlet, date and pricing exceptions where needed. Each selling menu appears once; recipe costing stays in Recipes & scaling.

| With a no-tax selling price of NGN 6,000 | Result |
| Estimated ingredient/packaging cost per plate | NGN 1,680 |
| Food cost: 1680 / 6000 x 100 | 28% |
| Est. Contribution Margin: 6000 - 1680 | NGN 4,320 |
| Gross Profit Margin: 4320 / 6000 x 100 | 72% |

A food-cost percentage above the configured maximum target needs attention. Lower/equal food cost is within target. These estimates exclude unconnected labour, overheads and other variable costs; use the displayed net-of-tax revenue basis.

! Do not create the same code manually and then import CREATE. Use UPDATE deliberately. A blank imported price preserves an existing price; a blank recipe can leave the menu incomplete. Select the correct outlet and effective date before investigating a missing selling price.
''')

page('13. Complete the go-live check', '''
Who: owner, administrator and the responsible team leads together.

### Before the first live shift
1. Check restaurant, currency, timezone, reporting week and physical count cutoff.
2. Check every colleague has accepted their invitation and reaches the right workspace.
3. Check each centre has an active named owner and the required centre tasks.
4. Check permitted routes, return routes and enabled production centres.
5. Check waste reporting days/deadlines before the next scheduled period.
6. Review supplier and material codes, base units, conversions, stock tracking and weekly-count flags.
7. Confirm dated starting prices, processing baselines and usable recipe yields.
8. Check final recipes, packaging, menu links, categories, standard prices and targets.
9. Verify opening balances are posted once and match the signed physical counts.
10. Run a small transfer and check destination acceptance before quantities move.
11. Run a small processing batch and confirm raw deduction and output addition occur together.
12. Record an independent waste item and complete the day's waste declaration, or confirm no waste where that is true.
13. Have Finance/CEO inspect the same source records, filters and missing-data warnings.
14. Record who approved cutover and when live operations begin. Keep training transactions in the training business.

### Do not force a green dashboard
An incomplete warning is useful when data is genuinely missing. Resolve the underlying unit, price, recipe, centre, scope or posting issue. Do not enter a false zero, duplicate stock opening or invented price merely to remove the warning.

! Before repeating any submission after a slow response, inspect the saved record and status. If stock is wrong or a duplicate appears, stop dependent transactions, retain the reference and ask for help. Do not compensate with another unrelated movement.
''')

page('14. Daily purchasing: PO, GRN and invoice', '''
### Procurement: raise the Purchase Order
1. Open Purchase Orders and create an order. Choose supplier, outlet, date and reference.
2. Add each material, quantity and purchase unit. The last purchase unit price is displayed as a read-only comparison; enter the actual proposed order unit cost separately.
3. Check automatic line and order totals, then save/issue the PO using the available action. There is no PO approval stage in the current workflow.
4. Follow issued, incomplete and completed receiving status. Open the order to inspect material lines rather than relying only on its total.

### Inventory: document delivery and post quantities
1. When goods arrive, open Goods Received Notes > Receive a Purchase Order, or open the issued order's receiving action.
2. Count/weigh the actual delivery. Record accepted quantities and any rejected quantities/reasons against the right material lines. Save the GRN.
3. For physical stock entry, open Inventory & movements, choose the GRN-linked stock receipt and the actual destination centre, and select the saved GRN.
4. Submit the receipt for the required independent review. An authorised colleague approves; the authorised Inventory user posts the stock entry.
5. Check the final stock record and ledger. A GRN documents delivery; verify the associated stock posting rather than assuming the GRN register alone has updated centre balances.

### Procurement and Finance: record/review the invoice
1. Procurement records the supplier invoice, material lines, quantities, amounts, date and relevant PO links. The supported purchase CSV can also be previewed and confirmed.
2. Finance reviews billing-versus-receiving exceptions and source evidence. A review does not authorise payment or receive stock.
3. Use the invoice correction workflow for a genuine correction; Finance reviews before approved changes replace current figures. Preserve the original history.

Issued POs can show early potential price pressure to executives. GRNs show delivery progress. Posted invoice evidence informs monthly weighted costs. These are different stages; do not add the PO warning and invoice price impact together as if they were two separate losses.
''')

page('15. Daily stock: requests, acceptance and returns', '''
### Kitchen/Bar requests materials
1. Open Inventory & movements and start a material requisition/movement.
2. Choose the permitted source store, your receiving centre and required materials/quantities. Add a useful reason/reference and submit.
3. Follow its status in your workspace. Contact the manager if the request is genuinely urgent; do not submit duplicate requests for the same need.

### Inventory Manager approves and dispatches
1. Review the destination, available stock and quantities.
2. Approve the requisition, then dispatch the authorised quantities. The same manager can perform approval and dispatch in the normal workflow.
3. Dispatch reserves stock at source. On-hand balances have not yet transferred.

### Receiving centre accepts or rejects
1. Open the incoming transfer when the physical goods arrive.
2. Check material, unit and actual quantity. Accept the amount received and record a reason for rejected remainder.
3. Confirm the action. Only accepted quantities deduct from source and add to destination together.
4. Check balances. The dispatcher cannot confirm the same transfer's destination receipt.

### Example: Main Store has 100 KG Rice
| Event | Main Store on hand / reserved | Kitchen change |
| Dispatch 10 KG | 100 KG / 10 KG | None yet |
| Accept 8 KG, reject 2 KG | 92 KG / 2 KG | +8 KG |
| Manager verifies 2 KG physically returned and resolves follow-up | 92 KG / 0 KG | No additional change |

Rejected dispatched quantities remain reserved until physical-return follow-up is resolved. For later excess stock, the department starts a new return using the reverse route; Main Store accepts it. A return is a transfer, not waste.

! Use the status filters for pending, incomplete and completed records. Never force a new stock adjustment just because a dispatched transfer is still awaiting destination confirmation.
''')

page('16. Daily material processing', '''
Who: an authorised colleague at an authorised production centre.

1. Open Material Processing Log and choose the new processing entry.
2. Select the processing centre. Choose the input material/process from the saved setup.
3. Enter the actual main input quantity. The single produced SKU and expected output populate from the baseline. For several inputs, review Other actual inputs and adjust the suggested quantities to what was actually consumed.
4. Enter the actual output quantity. Review the calculated expected output, gap and percentage variance.
5. Expand Measured waste & weights when you have actual measurements. Enter processing waste and usable output weight in compatible units.
6. Enter the required submitter name. Add an optional reason or explanation of the result.
7. Use Add material for another processing line. Check total input availability across all lines using the same raw material.
8. If there is a red shortage warning, reduce/correct the entry or obtain stock through a legitimate received movement. Do not submit a quantity that was not physically available.
9. Submit once. This direct process consumes input and creates output together, with no approval from another centre.
10. Confirm Recorded/completed status, open the saved entry, and check the centre ledger and balances.

### Worked example
Baseline: 40 KG Whole Snapper Fish -> 120 PCS Snapper Cut.
Actual: input 40 KG; output 110 PCS; measured usable weight 36 KG; processing waste 4 KG.
- Output achievement = 110 / 120 x 100 = 91.67%.
- Output variance = -10 PCS, or -8.33% against expected output.
- Usable weight yield = 36 / 40 x 100 = 90%.
- Recorded processing waste weight = 4 / 40 x 100 = 10%.
- Stock result: raw fish -40 KG; Snapper Cut +110 PCS, at the processing centre.

! Do not enter the same 4 KG trim again in the standalone Waste Log. It is already part of processing input consumption. A piece shortfall is not automatically a measured KG waste quantity. Without usable weight, do not claim a weight yield.
''')

page('17. Daily waste: record the loss, then confirm the day', '''
Every active stock centre, including Main Store, has its own waste responsibility.

### A. Record independent waste as it happens
1. Open Waste Log > Record waste.
2. Select your authorised stock centre and the correct material.
3. Enter the actual wasted quantity in the material's unit.
4. Select the reason: spoilage, expiry, damage, bad production or other. Add an explanatory note where useful.
5. Enter the required submitter name and select Record waste.
6. Check the saved record and balance. Standalone waste posts immediately; no approval is required. For example, 110 PCS Snapper Cut less 2 PCS spoilage leaves 108 PCS.

### B. Confirm the whole day before its deadline
1. Open Waste Log > Daily reporting. Choose your centre and the correct local business date.
2. Review that day's standalone waste and any recorded processing loss. Complete or cancel unresolved older loss entries first.
3. If loss occurred and all entries are recorded, confirm Waste recorded / the waste report is complete, with your submitter name.
4. If no loss occurred, explicitly confirm No waste with your name. A blank log is not a no-waste declaration.
5. Check the completed status in the page and workspace. Daily confirmation creates no further stock deduction.

### Understand the status
Pending = not yet confirmed. In progress = activity or a reopened report needs completion. Overdue = its deadline passed without completion. Complete with waste / no waste = confirmed. Closed = an excluded scheduled or authorised exceptional closure, not a no-waste report.
New loss after confirmation reopens the day. Finish it again after checking the new record. Late completion clears the outstanding task but remains marked late. Exceptional closure/reopening needs an authorised action and reason.

! Inventory sees its own centre's waste; Kitchen/Bar see assigned centres. CEO/Finance can review permitted combined data; Finance does not submit declarations. Reminders are in the app, not automatic reminder emails.
''')

page('18. Turn waste reporting into useful decisions', '''
Who: CEO/Finance for permitted combined review; centre users for their own scope.

1. Open Waste Log > Daily reporting. Select the date range and centre, or all permitted centres.
2. Review expected, completed, overdue and late reports. Contact the responsible owner for missing confirmation. Export CSV when a reporting record is needed.
3. Open Waste analysis. Select the same period and centre scope before comparing results.
4. Start with reporting coverage. If reports are missing, a lower recorded loss may reflect missing data rather than improvement.
5. Review the recorded loss/value trend. Compare days and centres with comparable completeness.
6. Review reasons and centre patterns. Identify recurring spoilage, expiry, damage or production issues, then inspect the underlying Waste entries.
7. Review materials with high known waste value or frequent entries. Keep quantities in their own units; never add KG, L and PCS into one quantity total.
8. Review processing yield against the saved baseline. Treat count-based output achievement and measured usable-weight yield as different indicators.
9. Agree one action, its owner and review date. Examples: adjust purchase frequency for expiry, investigate storage conditions for spoilage, or review cut size and handling when output is repeatedly below baseline.

### Read compliance accurately
Reporting coverage is confirmed expected centre-days divided by expected operating centre-days. Three centres across seven operating days create 21 expected centre-days.
On-time compliance uses reports whose deadlines have already passed. Before today's deadline, Not due can be correct. A late report becomes complete but does not become on time retroactively.

### Read financial values accurately
Known loss values use saved estimates. Unpriced entries are excluded and disclosed; the subtotal is not a complete loss valuation. Existing rollout-era estimates may be labelled reconstructed. Processing trim appears once and is not another stock deduction or a second cost to add to production inputs.

! Confirmed no-waste days can be zero. Missing reports and all-unpriced days must not be read as zero financial loss. A yield gap alone is not an automatically recorded waste entry.
''')

page('19. Daily sales, invoices and operating costs', '''
### Sales: use the supported CSV route
1. Export the approved sales data from your current source.
2. Open Sales & summary and download/select the matching supported template/source format.
3. Match existing selling menu codes and outlet references. Check dates, quantity, tax and amount fields using the screen's contract.
4. Upload and inspect the preview, errors and control totals. Correct problems before confirming.
5. Confirm once and reconcile the recorded result with the source total.
6. Do not upload the same source transactions as a new batch simply because a page loaded slowly. Check import history first.

### Record actual department usage separately
Where the restaurant uses the stock consumption workflow, open Inventory & movements, choose Department consumption and the source centre, and enter the actual materials/quantities used. Submit for the required independent review and authorised posting, then check the ledger. Do not consume a stocked preparation and its raw ingredients again for the same use. A sales import does not replace this physical-stock process.

### Finance: record labour and operating expenses
1. Open Labour & expenses and choose Add expenses, or use the supported expense CSV.
2. Select the category, outlet or central/shared scope, amount and relevant recognition period/method.
3. Keep the period the cost belongs to separate from the date it was paid.
4. Review and save; reconcile the result with the source record. Do not enter the same cost through both manual and import routes.
5. Review unallocated central costs separately instead of silently assigning them to an outlet.

### Supplier invoice review
Open supplier invoices and inspect the total and material lines first. Expand delivery/billing exceptions when needed. Use the current correction/review controls for disputed evidence; keep decision reasons and preserved history.

### Import habits that apply to every supported CSV
Use the exact downloadable columns and selected restaurant/outlet scope. Preview before confirming. Correct unknown codes and incompatible units at source. Keep a copy of the uploaded file and the resulting reference. Whole Excel workbooks are preparation aids unless a screen explicitly says otherwise.

! Do not infer automatic POS integration, full recipe-driven stock depletion or complete actual net profit from a sales upload. Validate physical usage and counts separately. Finance-only users should not need setup access to do their daily review.
''')

page('20. Weekly counts and the management review', '''
### Physical stock count
1. Use the agreed business count day and cutoff. Agree how receipts, transfers and production around that point will be handled.
2. Count each included SKU separately at each relevant centre. Use the weekly-count flag to identify intended count materials, including processed stock where required.
3. Enter the physical count through the available inventory count workflow with the correct centre, date, materials and measured quantities.
4. Enter an explicit zero when the physical count is zero. Do not treat an omitted material as a zero count.
5. Follow the required independent review and posting. Check the resulting ledger and balance; investigate stale counts or intervening movements before retrying.
6. Record the cause of a variance using evidence. Do not label every unexplained shortage as waste to make the figures agree.

The weekly-count flag and reporting calendar are available. A fully automated weekly count-sheet/reminder and sales-driven theoretical-usage programme is not yet a complete end-to-end feature. Maintain a controlled count checklist alongside the available workflow.

### Owner/Finance weekly review
1. Open the executive workspace/overview and select the correct reporting period and outlet scope. Check coverage before drawing conclusions.
2. Review menu items above Food/Drink cost targets. Check price, portion, recipe version and material cost basis.
3. Review purchase price pressure. Separate issued-PO early warnings from posted invoice cost evidence.
4. Review waste reporting compliance, late reports and recurring loss reasons.
5. Review processing output exceptions and outstanding stock handovers/return follow-ups.
6. Review recorded sales, labour, expenses and unallocated central costs in management reports. Use saved reviews and the available CSV/print-to-PDF options when appropriate.
7. Assign each action to a person, centre/outlet and review date. At the next meeting, compare with a similar period and reporting basis.

! A dashboard highlights where to investigate. Keep the source date, scope, estimate basis and missing inputs visible in every management discussion.
''')

page('21. Daily checklist by role', '''
### CEO / owner
- Check reporting scope and missing-data warnings.
- Review menu target exceptions, purchase price pressure and material operational changes.
- Review centre waste completion and overdue reports.
- Assign action owners; leave detailed recording to the authorised teams.

### Restaurant Administrator
- Maintain accepted staff access, active centre ownership and accurate setup.
- Resolve missing role/centre tasks and maintain future reporting schedules.
- Keep category, unit, recipe and price changes controlled and versioned.

### Procurement
- Prepare/issue POs with material lines and check last-price comparisons.
- Follow incomplete receiving and fresh GRNs.
- Record supplier invoices and resolve review/correction issues.

### Inventory Manager
- Review requests, approve/dispatch, document deliveries and complete stock postings.
- Follow destination acceptance, rejected returns and available/reserved quantities.
- Record and confirm waste for the centre(s) you own; do not consolidate other centres' waste under your log.

### Kitchen Manager / Bar Lead
- Check incoming transfers and accept/reject the actual quantities.
- Request materials and return excess through the correct route.
- Record authorised processing at the configured unit, when applicable.
- Record independent waste, then confirm waste recorded or no waste before the daily deadline.

### Finance / Auditor
- Reconcile sales, invoices, recorded labour and expenses.
- Review permitted combined centre waste, completeness and historical reports.
- Keep missing inputs visible; investigate financial exceptions without changing stock or setup outside your permissions.

! Each person signs in as themselves. The submitter name supports operational accountability; the system also records the actual signed-in account. Shared accounts weaken the history.
''')

page('22. Troubleshooting and help', '''
| What you see | What to check next |
| Colleague reaches setup instead of their workspace | Sign in with the exact invited email, open pending invitations (/join) and accept. Do not create another restaurant. |
| Invitation email not received | Check Spam and invitation email status; use the private backup link or resend. Ask platform support about email delivery if persistent. |
| Centre visible, but actions missing | Administrator checks role, outlet scope, centre task permissions and active ownership where required. |
| Opening stock still incomplete | Check material/centre, date, explicit zero readiness and final posted state. Approval alone is not stock posting. |
| Produced SKU dropdown empty | Check active/tracked Semi-finished or Finished output, Processed/Both source and compatible base unit. |
| Processing says insufficient stock | Check available stock at the processing centre, reservations and combined input across lines. |
| Selling price unavailable | Check selected outlet, effective date and standard/exception basis; inspect price history before adding another price. |
| Recipe cost missing | Check dated ingredient prices, usable yield, units and saved component versions. |
| Transfer dispatched, balance unchanged | Receiver acceptance is still needed. Dispatch reserves; acceptance posts the transfer. |
| Waste day reopened | A new waste/processing loss was recorded after confirmation. Review and confirm the day again. |
| No-waste confirmation blocked | Check posted loss evidence and unresolved loss records. Do not declare no waste when a loss exists. |
| Charts look unusually low | Check coverage, unpriced entries, dates and centre scope before claiming improvement. |

### When to stop and ask for help
For an unexpected stock balance, suspected duplicate, inaccessible accepted invitation or failed submission: keep the document reference, centre/outlet, date, selected filters and a screenshot. Explain the expected result and actual result. Do not include passwords or verification links in a shared report.

### Your first successful operating day
You have succeeded when the correct team can receive/transfer stock, process available inputs, record independent waste, confirm every expected centre's day, and explain the owner/Finance results from the underlying records. Expand gradually from that complete, repeatable routine.
''')

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
REL = 'http://schemas.openxmlformats.org/package/2006/relationships'

def runs(text):
    chunks = re.split(r'(\*\*.*?\*\*)', text)
    return ''.join('<w:r>' + ('<w:rPr><w:b/></w:rPr>' if x.startswith('**') else '') + '<w:t xml:space="preserve">' + escape(x.strip('*') if x.startswith('**') else x) + '</w:t></w:r>' for x in chunks if x)

def paragraph(text, style='Normal', before='', extra=''):
    return f'<w:p><w:pPr><w:pStyle w:val="{style}"/>{before}</w:pPr>{runs(text)}{extra}</w:p>'

def table(rows):
    cols = len(rows[0])
    widths = [8800//cols]*cols
    xml = '<w:tbl><w:tblPr><w:tblStyle w:val="GuideTable"/><w:tblW w:w="8800" w:type="dxa"/><w:tblLayout w:type="fixed"/></w:tblPr><w:tblGrid>' + ''.join(f'<w:gridCol w:w="{width}"/>' for width in widths) + '</w:tblGrid>'
    for i, row in enumerate(rows):
        xml += '<w:tr><w:trPr><w:cantSplit/>' + ('<w:tblHeader/>' if i == 0 else '') + '</w:trPr>'
        for j, cell in enumerate(row):
            xml += f'<w:tc><w:tcPr><w:tcW w:w="{widths[j]}" w:type="dxa"/>' + ('<w:shd w:fill="174C3C"/>' if i == 0 else f'<w:shd w:fill="{"F0F5F1" if i%2 else "FFFFFF"}"/>') + '</w:tcPr>' + paragraph(cell, 'TableHeader' if i == 0 else 'TableText') + '</w:tc>'
        xml += '</w:tr>'
    return xml + '</w:tbl>' + paragraph('', 'Small')

def blocks(source):
    lines = source.splitlines()
    result = []
    index = 0
    while index < len(lines):
        line = lines[index].strip()
        if line.startswith('|'):
            rows = []
            while index < len(lines) and lines[index].strip().startswith('|'):
                cells = [c.strip() for c in lines[index].strip().strip('|').split('|')]
                if not all(re.fullmatch(r'[-: ]+', c) for c in cells):
                    rows.append(cells)
                index += 1
            assert all(len(r) == len(rows[0]) for r in rows)
            result.append(('table', rows))
            continue
        if line:
            if line.startswith('### '): result.append(('Heading2', line[4:]))
            elif line.startswith('! '): result.append(('Callout', line[2:]))
            elif line.startswith('- '): result.append(('Bullet', line[2:]))
            elif re.match(r'^\d+\. ', line): result.append(('Step', line))
            else: result.append(('Normal', line))
        index += 1
    return result

body = []
for i, (title, content) in enumerate(PAGES):
    body.append(paragraph(title, 'Title' if i == 0 else 'Heading1', before='<w:pageBreakBefore/>' if i else ''))
    for style, value in blocks(content):
        body.append(table(value) if style == 'table' else paragraph(value, style))

styles = f'''<w:styles xmlns:w="{W}">
<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="21"/><w:color w:val="23372E"/><w:lang w:val="en-GB"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="100" w:line="270" w:lineRule="auto"/><w:widowControl/></w:pPr></w:pPrDefault></w:docDefaults>
<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:after="160"/></w:pPr><w:rPr><w:b/><w:sz w:val="58"/><w:color w:val="174C3C"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:outlineLvl w:val="0"/><w:spacing w:after="180"/></w:pPr><w:rPr><w:b/><w:sz w:val="36"/><w:color w:val="174C3C"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:outlineLvl w:val="1"/><w:spacing w:before="140" w:after="80"/></w:pPr><w:rPr><w:b/><w:sz w:val="24"/><w:color w:val="174C3C"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Step"><w:name w:val="Step"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="270" w:hanging="270"/><w:spacing w:after="105"/></w:pPr></w:style>
<w:style w:type="paragraph" w:styleId="Bullet"><w:name w:val="Bullet"/><w:basedOn w:val="Normal"/><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr><w:spacing w:after="85"/></w:pPr></w:style>
<w:style w:type="paragraph" w:styleId="Callout"><w:name w:val="Note"/><w:basedOn w:val="Normal"/><w:pPr><w:shd w:fill="EEF4EF"/><w:spacing w:before="140" w:after="120"/><w:pBdr><w:left w:val="single" w:sz="18" w:color="C4A66A" w:space="8"/></w:pBdr><w:ind w:left="130" w:right="100"/></w:pPr><w:rPr><w:sz w:val="20"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="TableText"><w:name w:val="Table Text"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="60" w:line="240"/></w:pPr><w:rPr><w:sz w:val="19"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="TableHeader"><w:name w:val="Table Header"/><w:basedOn w:val="TableText"/><w:rPr><w:b/><w:color w:val="FFFFFF"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Small"><w:name w:val="Small"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="40"/></w:pPr><w:rPr><w:sz w:val="16"/><w:color w:val="64766A"/></w:rPr></w:style>
<w:style w:type="table" w:styleId="GuideTable"><w:name w:val="Guide Table"/><w:tblPr><w:tblCellMar><w:top w:w="90" w:type="dxa"/><w:left w:w="100" w:type="dxa"/><w:bottom w:w="90" w:type="dxa"/><w:right w:w="100" w:type="dxa"/></w:tblCellMar><w:tblBorders><w:bottom w:val="single" w:sz="4" w:color="DCE6DF"/></w:tblBorders></w:tblPr></w:style>
</w:styles>'''
numbering = f'<w:numbering xmlns:w="{W}"><w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="singleLevel"/><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="\u2022"/><w:lvlJc w:val="left"/><w:pPr><w:tabs><w:tab w:val="num" w:pos="250"/></w:tabs><w:ind w:left="250" w:hanging="250"/></w:pPr></w:lvl></w:abstractNum><w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num></w:numbering>'
section = '<w:sectPr><w:headerReference w:type="default" r:id="rId3"/><w:footerReference w:type="default" r:id="rId4"/><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1080" w:right="1440" w:bottom="1080" w:left="1440" w:header="480" w:footer="480"/></w:sectPr>'
document = f'<w:document xmlns:w="{W}" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>' + ''.join(body) + section + '</w:body></w:document>'
header = f'<w:hdr xmlns:w="{W}">' + paragraph('PROFITPLATE INSIGHTS   /   BEGINNER GUIDE', 'Small', before='<w:pBdr><w:bottom w:val="single" w:sz="6" w:color="C4A66A"/></w:pBdr>') + '</w:hdr>'
footer = f'<w:ftr xmlns:w="{W}">' + paragraph('Setup to daily operations   |   20 November 2026                                      ', 'Small', extra='<w:fldSimple w:instr="PAGE"><w:r><w:t>1</w:t></w:r></w:fldSimple>') + '</w:ftr>'
types = '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>' + ''.join(f'<Override PartName="/word/{part}.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.{kind}+xml"/>' for part, kind in [('document','document.main'),('styles','styles'),('numbering','numbering'),('header1','header'),('footer1','footer'),('settings','settings')]) + '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/></Types>'
relations = f'<Relationships xmlns="{REL}">' + ''.join(f'<Relationship Id="rId{i}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/{kind}" Target="{target}.xml"/>' for i, kind, target in [(1,'styles','styles'),(2,'numbering','numbering'),(3,'header','header1'),(4,'footer','footer1'),(5,'settings','settings')]) + '</Relationships>'
files = {'[Content_Types].xml':types, '_rels/.rels':f'<Relationships xmlns="{REL}"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>', 'word/document.xml':document, 'word/styles.xml':styles, 'word/numbering.xml':numbering, 'word/header1.xml':header, 'word/footer1.xml':footer, 'word/_rels/document.xml.rels':relations, 'word/settings.xml':f'<w:settings xmlns:w="{W}"><w:updateFields w:val="true"/></w:settings>', 'docProps/core.xml':'<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>ProfitPlate Insights - Beginner Setup and Daily Operations Guide</dc:title><dc:creator>ProfitPlate Insights</dc:creator><dc:description>Product value, complete setup and role-based daily operating guide, current through update 049.</dc:description></cp:coreProperties>'}
OUT.parent.mkdir(parents=True, exist_ok=True)
with ZipFile(OUT, 'w', ZIP_DEFLATED) as z:
    for name, content in files.items():
        ET.fromstring(content)
        z.writestr(name, '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + content)

# HTML layout companion is for local visual QA, not a substitute for the Word file.
html_pages = []
for title, content in PAGES:
    bits = [f'<h1>{escape(title)}</h1>']
    for style, value in blocks(content):
        if style == 'table': bits.append('<table>' + ''.join('<tr>' + ''.join(f'<{"th" if i == 0 else "td"}>{escape(c)}</{"th" if i == 0 else "td"}>' for c in row) + '</tr>' for i, row in enumerate(value)) + '</table>')
        elif style == 'Heading2': bits.append(f'<h2>{escape(value)}</h2>')
        else: bits.append(f'<p class="{style}">' + ('&#8226; ' if style == 'Bullet' else '') + escape(value) + '</p>')
    html_pages.append('<section class="sheet"><header>PROFITPLATE INSIGHTS / BEGINNER GUIDE</header><article>' + ''.join(bits) + '</article></section>')
preview = ROOT/'node_modules/.guide-preview'
preview.mkdir(exist_ok=True)
(preview/'beginner-guide.html').write_text('<!doctype html><html><meta charset="utf-8"><style>*{box-sizing:border-box}body{margin:0;background:#ddd;color:#23372e;font-family:Calibri,Arial,sans-serif;font-size:10.5pt}.sheet{background:#fff;width:210mm;min-height:297mm;margin:10px auto;padding:19.05mm 25.4mm;position:relative}header{font-size:8pt;color:#64766a;border-bottom:1px solid #c4a66a;padding-bottom:7px;margin-bottom:18px}h1{font-size:18pt;color:#174c3c;margin:0 0 12px}h2{font-size:12pt;color:#174c3c;margin:10px 0 5px}p{line-height:1.28;margin:0 0 7px}.Step{padding-left:18px;text-indent:-18px}.Bullet{padding-left:16px;text-indent:-11px}.Callout{background:#eef4ef;border-left:3px solid #c4a66a;padding:9px;font-size:10pt;margin-top:12px}table{border-collapse:collapse;width:100%;table-layout:fixed;margin:8px 0 12px}th,td{text-align:left;padding:6px 7px;font-size:9.5pt;line-height:1.15;vertical-align:top}th{background:#174c3c;color:#fff}tr:nth-child(even){background:#f0f5f1}article{overflow-wrap:break-word}@media print{body{background:#fff}.sheet{margin:0;page-break-after:always} @page{size:A4;margin:0}}</style>' + ''.join(html_pages) + '</html>', encoding='utf-8')
with ZipFile(OUT) as z:
    assert z.testzip() is None
    for name in z.namelist():
        if name.endswith(('.xml','.rels')): ET.fromstring(z.read(name))
    plain = ''.join(ET.fromstring(z.read('word/document.xml')).itertext())
    assert all(term in plain for term in ['No waste', 'Opening balance', 'Food', 'Drink', 'GRN', 'CSV', 'weighted', 'baseline', 'Department consumption'])
    assert len(re.findall('pageBreakBefore', document)) == len(PAGES)-1
print(json.dumps({'file':str(OUT),'chapters':len(PAGES)-1,'words':len(re.findall(r'\S+', ' '.join(t for _,t in PAGES))),'bytes':OUT.stat().st_size,'package_xml_valid':True}))
