"""Build the manual restaurant UAT pack with Python's standard library only.

The workbook is a test record, never an application import. No live app is called.
"""
from pathlib import Path
from decimal import Decimal
from xml.sax.saxutils import escape
import csv
import io
import json
import zipfile
import html
import math
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "public/templates/pilot-testing-2026-11-17-v2"
OUT.mkdir(parents=True, exist_ok=True)
CASES = []


def case(sheet, code, role, prerequisite, steps, data, expected, critical=True):
    CASES.append(dict(sheet=sheet, id=code, role=role, prerequisite=prerequisite,
                      steps=steps, data=data, expected=expected, critical=critical))


case('1 Setup', 'SET-01', 'ADMIN', 'Access to deployed test environment', "Record the website URL, app version, tester and today's Lagos date D in Run details. Confirm migrations through 026 are applied and the updated code is deployed. Skip already-applied migrations; do not rerun 023. Use a fresh test restaurant with no existing stock or transactions.", 'D = your test date, on or before today; reporting currency NGN', 'The intended app opens and Inventory Manager / Department access features are available. Existing production data is untouched.', True)
case('1 Setup', 'SET-02', 'ADMIN', 'SET-01', 'Create the owner account through Sign up, open its verification email, sign in and complete business setup. Choose Fine dining, NGN, one brand and one outlet named UAT Dining. Record the actual outlet code shown by the app.', 'Business: UAT Fine Dining; brand: UAT Kitchen; outlet: UAT Dining', 'One restaurant workspace is created. Owner has CEO / Restaurant Administrator access. The outlet belongs to this restaurant.', True)
case('1 Setup', 'SET-03', 'ADMIN + all staff', 'SET-02', 'In Users & roles invite IM as Inventory Manager, KITCHEN and BAR as Department stock users, PROC as Procurement and FIN as Finance. Use separate verified accounts/profiles. OPS is an optional Department stock requester. STORE is only an operating alias for IM at Main Store: do not create a separate inventory staff account. Each invited user signs up with the exact email, verifies it, signs in and accepts the invitation into this restaurant.', 'Six core accounts including ADMIN; optional request-only/process delegates later; no passwords in the workbook', 'All core users share this restaurant. There is one Inventory Manager, not a separate storekeeper/receiver for each inventory action. Department accounts can request and confirm their own transfers without being Inventory staff.', True)
case('1 Setup', 'SET-04', 'IM', 'SET-03', 'Sign in as Inventory Manager. Check the Inventory Manager workspace, Review stock requests, Manage department stock access and Deliveries & GRNs. Open Inventory & movements.', 'IM has only inventory_manager, All business locations', 'Manager can open stock controls but has no supplier-invoice entry, expense entry or Users & roles authority.', True)
case('1 Setup', 'SET-05', 'PROC or ADMIN', 'SET-03', "Open Materials & suppliers. Create supplier UATSUP and all nine items listed in Test data. Choose the exact base unit, item type and stock-tracked setting. Keep generated IDs and record the supplier's name.", 'Seven raw/packaging/resale items plus UATBASE and UATPLATE', 'Nine active stock-tracked items exist in this restaurant. UATBASE is SEMI_FINISHED / KG and UATPLATE is FINISHED / PCS. No stock has been posted.', True)
case('1 Setup', 'SET-06', 'PROC or ADMIN', 'SET-05', 'Open Initial material prices. Enter the seven raw/packaging/resale reference prices from Test data, or edit and upload example-initial-prices.csv. Use D as the actual fictional test price date. Review the resolved items and units before confirming.', 'Rice 1800/KG; chicken 6000/KG; tomato 1000/KG; onion 800/KG; oil 2500/L; box 100/PCS; water 200/PCS', 'Seven dated reference prices are saved. UATBASE/UATPLATE need no invented price for the raw-ingredient menu estimate. Quantities and stock balances stay unchanged.', True)
case('1 Setup', 'SET-07', 'IM', 'SET-05', 'Open Inventory & movements > Locations & routes. Add Main Store (STORE), Kitchen (KITCHEN) and Bar (BAR), all assigned to UAT Dining. Use codes UATMAIN, UATKIT and UATBAR. Enter department labels Stores, Kitchen and Bar.', 'Do not choose Central/shared for these three locations', 'Three separate stock locations exist within the same outlet. A department name alone is not an access restriction.', True)
case('1 Setup', 'SET-08', 'IM', 'SET-03 and SET-07', 'IM opens Department access. Select KITCHEN, choose Selected stock locations only and Kitchen; enable Request stock and Accept / reject. Do the same for BAR at Bar. OPS, if used, gets Kitchen Request stock only. Do not enable dispatch, approval or arbitrary posting for department users. IM retains business-wide oversight; no STORE assignment is needed because STORE is IM.', 'KITCHEN / BAR role stock_department; IM role inventory_manager', 'Department accounts see their assigned stock location and permitted request/receiving processes. They cannot approve, dispatch or post adjustments. Normal use requires no separate inventory-staff account.', True)
case('1 Setup', 'SET-09', 'IM', 'SET-07', 'In Locations & routes create Main Store > Kitchen and Main Store > Bar. Choose Department issue for both and Inventory Manager as Source approval role. Save each route. Also use Allow reverse / excess return on each forward route to permit Kitchen/Bar returns to Main Store.', 'Two active ISSUE routes; not TRANSFER', 'Forward and reverse routes exist. The manager approves and dispatches; receiving departments accept or reject outgoing stock. The manager can accept department-originated returns at Main Store.', True)
case('1 Setup', 'SET-10', 'IM > ADMIN > IM', 'SET-05 through SET-09', "IM (acting at Main Store) submits one Opening balance request with the seven opening lines. Because this is the manager's own request, ADMIN or another authorised reviewer approves it. IM then posts the quantities. Record the STK reference. This uses an existing owner/reviewer, not another inventory staff account.", 'Rice 100 KG; chicken 40 KG; tomato 20 KG; onion 10 KG; oil 10 L; boxes 100 PCS; water 60 PCS', 'Requested and Approved stages do not affect stock. Only posting creates opening balances. Main Store matches checkpoint C0; Kitchen/Bar have no posted stock yet.', True)
case('2 Recipes', 'REC-01', 'ADMIN (or business-wide Operations)', 'SET-05 and SET-06', 'Open Recipes & scaling. Create UATSAUCE as SUB_RECIPE, effective D. Enter tomato 6 KG, onion 2 KG and oil 1 L for the WHOLE batch; set measured output 8 KG. Publish and record the saved version number.', 'Do not enter per-serving quantities as batch inputs', 'Recipe batch estimate is 10100; one KG is 1262.50. Publishing changes no inventory.', True)
case('2 Recipes', 'REC-02', 'ADMIN', 'REC-01', 'Create UATMEAL as FINAL, effective D. Add rice 4 KG, chicken 3 KG, the exact saved UATSAUCE version (quantity 2 KG) and meal boxes 20 PCS. Set batch output 20 PCS and publish. Record its version.', 'Use a child RECIPE component, not UATBASE as a raw item, for recipe costing', 'Batch estimate 29725; estimated cost per serving 1486.25 including a box. Parent pins the chosen sub-recipe version. Inventory remains unchanged.', True)
case('2 Recipes', 'REC-03', 'ADMIN', 'REC-02', 'In Menu & prices create menu UATMENU for UAT Kitchen brand. Link the saved UATMEAL FINAL version with recipe quantity 1 PCS per sold serving. Add a TAKEAWAY price at UAT Dining, effective D, price 3500, tax NONE /0.', 'Fictional tax setting only; one sold item uses 1 PCS, not the full 20-PCS batch', 'Menu item, recipe link and dated outlet/channel price are saved. No stock is consumed by menu setup.', True)
case('2 Recipes', 'REC-04', 'ADMIN or FIN', 'REC-03', 'Open Menu profitability. Select UAT Dining, TAKEAWAY, date D, and search UATMENU. Open the breakdown and compare its recipe version, quantity, ingredients and packaging with the source sheets.', 'Selling price 3500; serving cost 1486.25', 'Food cost 42.46%; estimated food profit 2013.75 per serving; estimated food GP margin 57.54%. Contribution margin stays unavailable. Missing values must not become zero.', True)
case('2 Recipes', 'REC-05', 'IM', 'REC-01 and REC-02', 'Open Locations & routes > Link recipe stock output. Link the published UATSAUCE version to UATBASE, then the published UATMEAL version to UATPLATE. Use the actual version IDs displayed, not assumed version 1 if you republished.', 'UATBASE: SEMI_FINISHED/KG; UATPLATE: FINISHED/PCS', 'Both bindings are visible under Recipe stock outputs. These bindings identify physical output stock; they do not create opening stock or change recipe cost.', True)
case('3 Movements', 'MOV-01', 'KITCHEN or OPS', 'SET-10 and REC-05', 'Open Movements & requests > Request a stock movement. Choose Department issue and Main Store to Kitchen. Enter all six input lines shown here, date D and a requisition note. Confirm and Submit stock request. Record its STK reference.', 'Rice 20 KG; chicken 10 KG; tomato 10 KG; onion 5 KG; oil 5 L; boxes 40 PCS', 'State Awaiting approval. Main Store remains C0; Kitchen is still empty. An unapproved request neither reserves nor transfers stock.', True)
case('3 Movements', 'MOV-02', 'IM', 'MOV-01', 'Open Review stock requests, find the recorded STK reference and Review it. Check source, destination, quantities and requester. Choose Approve request, enter a decision note, tick confirmation and save.', 'No quantity edits during approval', 'State Approved. Stock still matches C0. The manager is recorded as approver.', True)
case('3 Movements', 'MOV-03', 'IM (STORE alias)', 'MOV-02', 'In the same manager session that approved the requisition, open the approved record and choose Confirm dispatch. Verify quantities, enter a note and confirm. Check Stock balances before the department accepts.', 'Dispatch the complete six-line request once', 'State Awaiting acceptance. Main Store on-hand balances still equal C0 and Kitchen has no additions. Requested quantities are Reserved; Available shows the unreserved remainder. No dispatch ledger debit is created.', True)
case('3 Movements', 'MOV-04', 'KITCHEN', 'MOV-03', 'Open the dispatched STK record. Choose Accept transfer. Confirm every accepted quantity equals the dispatched quantity. Enter the receiver note, tick confirmation and save. Open Stock balances.', 'Receive 20/10/10/5/5/40 in the six base units', 'State Completed. Main now has rice80, chicken30, tomato10, onion5, oil5, boxes60, water60. Kitchen has rice20, chicken10, tomato10, onion5, oil5, boxes40. Both sides post together on acceptance, and their reservations clear.', True)
case('3 Movements', 'MOV-05', 'BAR > IM', 'MOV-04', 'BAR requests Department issue from Main Store to Bar for water24 PCS. IM approves then confirms dispatch in the same manager session. Record the STK reference before acceptance.', 'Only UATWATER 24 PCS', 'Main water remains60 on hand, with24 reserved and36 available. Bar remains zero. State Awaiting acceptance.', True)
case('3 Movements', 'MOV-06', 'BAR then IM', 'MOV-05', 'BAR chooses Accept transfer, accepts23 and gives reason "1 excess bottle not accepted; returned to Main Store". Confirm. IM checks the Incomplete record and alert, physically verifies that the usable rejected bottle is back, then chooses Resolve follow-up with evidence.', 'Requested24; accepted23; rejected1; no automatic transit loss', 'Bar water23 and Main water37. Before resolution, the rejected1 remains reserved at source. Resolution releases that reservation without changing either on-hand balance. The incomplete record and rejected reason remain in history.', True)
case('3 Movements', 'MOV-07', 'KITCHEN > IM', 'MOV-04 and REC-05', 'KITCHEN submits Production batch at Kitchen: choose the bound UATSAUCE version, planned output 8 and actual usable output 8 in KG. IM reviews calculated input lines and approves. IM posts.', 'Consumes tomato 6, onion 2, oil 1; produces UATBASE 8 KG', 'Kitchen tomato 4, onion 3, oil 4 and base 8. Rice/chicken/boxes unchanged. Input deductions and output addition happen together; no separate second raw-ingredient consumption.', True)
case('3 Movements', 'MOV-08', 'KITCHEN > IM', 'MOV-07', 'Submit Production batch for the bound UATMEAL version at Kitchen. Planned output 20 PCS; actual usable output 18 PCS. IM reviews the saved input lines and approves; IM posts. Open its production detail.', 'Consumes rice 4, chicken 3, stored base 2 and boxes 20', 'Kitchen rice 16, chicken 7, base 6, boxes 20, plates 18. Tomato 4/onion 3/oil 4 stay unchanged: child raw materials are not deducted again. Planned 20 versus actual 18 is retained.', True)
case('3 Movements', 'MOV-09', 'KITCHEN > IM', 'MOV-08', 'Submit Department consumption at Kitchen for rice 2 KG with a usage reference. IM approves; IM posts. Check that you did not use Department issue for this action.', 'Only UATRICE 2 KG', 'Kitchen rice 14. No Main Store or Bar balance changes. This is explicit consumption, separate from a transfer or production input deduction.', True)
case('3 Movements', 'MOV-10', 'KITCHEN > IM', 'MOV-09', "Submit Waste / spoilage at Kitchen for chicken 1 KG with reason 'Spoiled after preparation'. IM approves; IM posts.", 'Only UATCHICK 1 KG', 'Kitchen chicken 6. The reason, requester, approver and stock deduction remain traceable.', True)
case('3 Movements', 'MOV-11', 'BAR > IM', 'MOV-06', 'Submit Department consumption at Bar for water 5 PCS, get IM approval and post as IM.', 'UATWATER 5 PCS', 'Bar water 18. The issue itself was not treated as usage; only this consumption deducts the five bottles.', True)
case('3 Movements', 'MOV-12', 'BAR > IM', 'MOV-11', 'Submit Waste / spoilage at Bar for water 1 PCS with a breakage reason, get IM approval and post as IM.', 'UATWATER 1 PCS', 'Bar water 17. Main Store water remains 37.', True)
case('3 Movements', 'MOV-13', 'KITCHEN > IM', 'MOV-09', 'Submit Physical stock count at Kitchen for rice 13 KG. Stop moving stock at Kitchen until this count is approved and posted. IM approves; IM posts the physical count.', 'Book rice 14; physical rice 13', 'Kitchen rice 13; ledger adjustment is minus 1, not minus 13. Unlisted materials are unchanged.', True)
case('3 Movements', 'MOV-14', 'IM', 'MOV-07 through MOV-13', 'Filter Stock balances by each location, compare every material to C1 in Checkpoints, then inspect Stock ledger and movement references. Record the observed balances and any discrepancy before proceeding.', 'Checkpoint C1 (before supplier receipts)', 'Every listed C1 balance agrees; produced plates 18, base 6 and transit loss 1 are visible in their respective records. All approved happy-path requests are completed.', True)
case('4 Purchasing', 'BUY-01', 'PROC', 'MOV-14', 'Open Purchase Orders & GRNs > Raise Purchase Order. Choose UATSUP and UAT Dining. Enter rice quantity 10 KG and unit cost 1800, discount 0, tax 0, EXCLUSIVE price basis and date D. Check the automatically calculated total and save draft.', 'Quote reference UAT-QUOTE-001; total 18000', 'Total calculates to 18000 without manual multiplication. Draft is saved; no GRN, invoice or stock movement is created.', True)
case('4 Purchasing', 'BUY-02', 'PROC', 'BUY-01', 'Review the draft, tick the issue confirmation and select Issue Purchase Order. Record the generated PO reference. Inspect its status and the Pending delivery filter.', 'One order for 10 KG rice', 'PO is Issued / Pending delivery. Issued lines are fixed. Main Store rice is still 80.', True)
case('4 Purchasing', 'BUY-03', 'STORE', 'BUY-02', "Open that PO > Confirm delivery / GRN. Use received date D and delivery reference UAT-DN-001. Enter accepted 4 KG, rejected 1 KG and reason 'Damaged bag'. Confirm the physical delivery and generate the GRN. Record its GRN reference.", 'Only 4 KG is accepted; rejected 1 does not fulfil the order', 'PO is Partially received; accepted 4, remaining 6. Main Store rice remains 80 until the explicit stock-posting step.', True)
case('4 Purchasing', 'BUY-04', 'IM > ADMIN/FIN > IM', 'BUY-03', 'IM submits Post accepted GRN to stock, receiving location Main Store, selecting the new GRN. Review the generated lines. ADMIN/FIN approves the manager-originated request; IM posts. Do not type the accepted quantities manually as another receipt.', 'GRN1 accepted 4 KG', 'Main Store rice 84. Exactly 4 enters stock; rejected 1 is excluded. This GRN cannot be selected for a second active stock request.', True)
case('4 Purchasing', 'BUY-05', 'PROC', 'BUY-04', 'Open the PO and Record invoice against this PO. Enter supplier invoice UAT-INV-001 for all 10 KG at 1800, no discount/tax, total 18000, date D. Review and confirm the invoice; verify its line is mapped to the PO line.', 'Billed 10 while accepted delivery is currently 4', 'Invoice exists without logging the user out. It needs Finance review because billed quantity exceeds accepted deliveries. Posting the bill adds no stock; Main rice stays 84.', True)
case('4 Purchasing', 'BUY-06', 'FIN', 'BUY-05', 'Open the invoice and its matching panel. Review billed 10 versus accepted 4 and the evidence. Choose the Finance decision that acknowledges the current exceptions, enter a reason, confirm and Save Finance exception review.', 'Explain that final delivery is still outstanding', 'Current exceptions are marked reviewed by Finance, not removed. The decision is not payment or proof of receiving. Stock and PO quantities do not change.', True)
case('4 Purchasing', 'BUY-07', 'STORE', 'BUY-06', 'On the same PO create a second GRN, delivery reference UAT-DN-002, date D, accepted 6 KG, rejected 0. Record its GRN reference and open the Completed PO filter.', 'Second accepted delivery 6 KG', 'PO receiving status becomes Completed: total accepted 10, remaining 0. Main rice remains 84 until GRN2 is posted to stock. Completed does not mean paid.', True)
case('4 Purchasing', 'BUY-08', 'IM > ADMIN/FIN > IM', 'BUY-07', 'Post the second accepted GRN through stock request > ADMIN/FIN approval > IM posting. FIN refreshes invoice matching and reviews its current source quantities.', 'GRN2 accepted 6 KG', 'Main rice 90. Billed 10 matches accepted 10 and invoice has no remaining quantity exception in this example. The earlier Finance review no longer substitutes for the changed source state.', True)
case('4 Purchasing', 'BUY-09', 'IM > ADMIN/FIN > IM', 'BUY-08', 'Submit Direct supplier receipt into Main Store for water 12 PCS, supplier UATSUP, unique delivery reference UAT-DIRECT-001 and a source/reason note. ADMIN/FIN approves the manager-originated request; IM posts.', 'This separate delivery has NO GRN', 'Main water 49. Stock receipt is recorded once and does not manufacture a supplier invoice. Do not also post a GRN for this delivery.', True)
case('4 Purchasing', 'BUY-10', 'PROC then FIN', 'BUY-09', 'PROC records supplier invoice UAT-INV-002 without a PO for water 12 at 200, total 2400, date D. Enter the no-PO reason and delivery-evidence reference UAT-DIRECT-001. FIN reviews its no-PO exception.', 'DIRECT route, total 2400; separate from UAT-INV-001', 'Invoice and evidence are retained; Finance review remains explicit. No additional water enters stock. Invoice totals across the two baseline invoices are 20400; prices do not automatically update reference prices.', True)
case('4 Purchasing', 'BUY-11', 'IM', 'BUY-10', 'Compare every stock balance with C2 and both invoices with their source notes. Check all PO filters, recorded GRNs and Main Store ledger entries.', 'Checkpoint C2', 'Main rice 90 and water 49; all other C1 balances unchanged. Invoice entry, physical receiving and stock posting remain distinct.', True)
case('5 Finance', 'FIN-01', 'ADMIN', 'REC-03 and BUY-11', 'Edit example-sales.csv: replace TEST_DATE with D and LOCATION_CODE_HERE with the actual outlet code. In Sales & summary > Import sales choose source organisation code UAT_ORG and tax format Gross_Sales and Net_Sales both exclude tax. Upload, review mappings and receipt total 10500, then confirm.', 'UAT-SALE-001; UATMENU3 servings at 3500; no tax/discount', 'One paid receipt records net sales 10500 and quantity 3. Sales do not automatically deduct physical UATPLATE stock: Kitchen plates remain 18.', True)
case('5 Finance', 'FIN-02', 'FIN or ADMIN', 'FIN-01', 'Review Sales & summary and executive overview for D, UAT Dining. Compare the linked recipe, imported revenue and food estimate. Reopen Menu profitability for TAKEAWAY / D.', 'Reference recipe serving cost 1486.25', 'Estimated food cost 4458.75; estimated food margin 6041.25; food margin 57.54%. Menu serving cost stays 1486.25 despite actual production yield 18. This is reference-price costing, not actual inventory COGS.', True)
case('5 Finance', 'FIN-03', 'FIN', 'FIN-01', 'Edit example-expenses.csv date/outlet placeholders. In Labour & expenses > Add expenses > CSV import, use source organisation UAT_ORG; review the two category codes and total 1500 before confirming. Use existing WAGES and RENT categories, both LOCATION / ON_DATE at D.', 'WAGES1000 and RENT500, same outlet/date/currency', 'Two expenses total 1500. Labour 1000 and operating cost 500 remain distinct; payment dates do not change recognition dates. No material quantity changes.', True)
case('5 Finance', 'FIN-04', 'FIN', 'FIN-03', "Review and confirm the app's labour/expense coverage for D and UAT Dining, honestly based on the two complete fictional entries. Open the management report for that same scope and date.", 'Labour 1000; estimated food cost 4458.75', 'After required coverage reviews, estimated prime cost 5458.75, about 51.99% of net sales. Missing reviews/inputs stay flagged until completed. Operating/accounting profit is not invented.', True)
case('5 Finance', 'FIN-05', 'FIN', 'FIN-04', 'Save a named report UAT Dining D baseline. Open its saved copy and submit it for management review with a note.', 'Record the saved report reference', 'The named figures and basis are preserved; Finance submission is recorded. Saving/submitting changes no source transaction or stock quantity.', True)
case('5 Finance', 'FIN-06', 'ADMIN acting as CEO', 'FIN-05', 'Open the submitted saved report. Review its context and approve with the required acknowledgement and note. Reopen the report as FIN.', "Use the owner account's CEO/Administrator authority, not IM", 'Management approval and decision identity are visible. This is management approval of estimates, not accounting period close or payment.', True)
case('5 Finance', 'FIN-07', 'FIN', 'FIN-06', 'Download report CSV and use Print / save PDF. Open each output, check restaurant/date/outlet/currency, figures, coverage notes and saved-review status where provided.', 'Expected net sales 10500, food cost 4458.75, labour 1000, operating cost 500', 'Outputs open and match the report, with the estimate basis retained. No unexpected formula execution in CSV text fields.', False)
case('5 Finance', 'FIN-08', 'ADMIN / FIN', 'FIN-03', 'Upload exactly the same sales CSV and exactly the same expense CSV once more with the same source and record identifiers. Review the duplicate findings before confirming any allowed skip.', 'Stable UAT-SALE-001, UAT-WAGES-001, UAT-RENT-001', 'Duplicate economic records are skipped or blocked; no second sale/expense is created. Totals remain 10500 sales and 1500 expenses. Do not change reference IDs to force an import.', True)
case('6 Access', 'ACC-01', 'KITCHEN and BAR', 'BUY-11', "In separate profiles open Stock balances and the Stock location filter. KITCHEN must see Kitchen balances; BAR must see Bar balances. Try another department's saved filtered inventory URL and an unrelated movement URL copied by IM.", 'Kitchen must not access Main Store > Bar; Bar must not access Main Store > Kitchen', "Unauthorised balances, ledger rows and unrelated movement details are absent or restricted. A permitted route may reveal its other endpoint's name, never that endpoint's private balances.", True)
case('6 Access', 'ACC-02', 'KITCHEN / BAR', 'SET-09', "Open a Department issue request. Inspect permitted routes as each department. Attempt to select or submit the other department's route without changing permissions.", 'Kitchen: Main Store to Kitchen; Bar: Main Store to Bar', 'Only permitted requests can be initiated. No cross-department request is posted by guessing or sharing a URL.', True)
case('6 Access', 'ACC-03', 'OPS (optional Department requester)', 'SET-08', 'Sign in with a Department stock user restricted to Kitchen Request stock only. Review Kitchen data and submit a harmless request. Try to approve, dispatch, accept stock or post a quantity adjustment. IM cancels the test request without posting.', 'No Inventory, receiver, dispatcher or management role', 'Request-only access works within Kitchen. The account cannot approve, dispatch, receive or post. Adding a checkbox cannot exceed the underlying process role.', True)
case('6 Access', 'ACC-04', 'IM', 'SET-03', 'Try to open supplier-invoice entry, Labour & expenses entry and Users & roles from copied URLs. Verify stock configuration, Department access and stock approvals remain available.', 'IM has no additional Finance/Procurement/Admin role', 'Stock oversight works; financial entry and general role administration remain restricted. IM cannot grant themselves a Restaurant Administrator role.', True)
case('6 Access', 'ACC-05', 'PROC', 'SET-03', 'Check PO preparation and invoice entry. Try to open an unposted delivery and confirm its GRN or dispatch stock while holding only Procurement.', 'No Inventory or Inventory Manager role on PROC', 'Procurement can buy and bill, but cannot perform physical receiving/handling solely because they raised the PO.', True)
case('6 Access', 'ACC-06', 'FIN', 'SET-03', 'Inspect stock and invoices. Try Department access and Locations & routes configuration, PO creation, supplier-invoice entry and stock dispatch.', 'FIN holds only Finance', 'Finance can review permitted stock/invoices and financial corrections. It cannot configure departments, prepare purchases or physically dispatch stock. Existing non-route stock-approval fallback remains available.', True)
case('6 Access', 'ACC-07', 'IM then KITCHEN', 'Baseline C2 recorded', 'IM sets KITCHEN to Request=no and Accept / reject=yes at Kitchen. Refresh KITCHEN and try initiating a new request. Restore Request=yes afterwards.', 'Do not post any extra movement', 'No new request can be initiated, but the department can still accept/reject an authorised incoming transfer. Request and receiving permissions are independent.', True)
case('6 Access', 'ACC-08', 'IM then KITCHEN', 'ACC-07; record C2 first', 'After recording C2, use a separate small Kitchen transfer request. IM approves/dispatches it. Remove KITCHEN Accept / reject while its incoming record is open. Attempt acceptance/rejection, restore permission, then have Kitchen reject and IM resolve the physically returned quantity.', 'A temporary requisition after baseline; do not post a count as a department user', 'Revocation blocks both acceptance and rejection immediately, including through an old tab. Restoring permission permits the intended decision. Rejection changes no on-hand balances; resolution clears the reservation.', True)
case('6 Access', 'ACC-09', 'IM then KITCHEN', 'C2 recorded', "Save Selected stock locations only with no checked locations for KITCHEN. Refresh KITCHEN's balances, ledger and movements screens. Then restore Kitchen with Request and Handle enabled.", 'Never restore Existing outlet access by accident', 'No department stock balance/ledger/request form remains while the allowlist is empty. Restoration grants Kitchen only. Shared catalogue and existing PO/GRN permissions still follow their own module roles.', True)
case('6 Access', 'ACC-10', 'ADMIN and BAR', 'C2 recorded; use a staff account, not owner', 'Deactivate BAR through Users & roles while its other profile is signed in. Try a new protected read/action, then restore the active member with the original outlet Department stock user role and check its department assignment.', 'Keep a record of the original roles and stock assignments', 'Inactive membership loses business access. Reactivation does not silently expand the saved Bar allowlist. Historical stock remains intact.', True)
case('6 Access', 'ACC-11', 'ADMIN / authorised technical tester', 'Optional second separate test restaurant', 'Sign into a different restaurant account in a separate profile and try copied inventory, PO, invoice and report URLs from this test restaurant. Do not grant cross-business membership for this test.', 'Use a second isolated test tenant', 'No other-restaurant balances, records or updates are accessible. If no second tenant exists, mark Blocked, not Passed.', True)
case('6 Access', 'ACC-12', 'ADMIN', 'Any staff invitation test', 'For a disposable invitation, try opening it with the wrong verified email. Then retry with the invited email. Also sign out and verify a protected workspace URL redirects to sign-in.', "Do not use another person's password", 'Wrong-email invitation acceptance is rejected; intended verified email succeeds. Anonymous users cannot use protected stock pages.', True)
case('6 Access', 'ACC-13', 'ADMIN and IM', 'Optional delegation accounts if needed', 'Create optional Stock receiver and Stock dispatcher accounts. IM assigns only receiving at one location to the receiver and only dispatch at a source to the dispatcher. Attempt approval, arbitrary posting, other-process actions and financial access with each.', 'Optional; mark Not applicable with a reason if no delegation is planned', 'Receiver can accept/reject assigned incoming stock, dispatcher can dispatch approved requests, and neither receives management or financial powers.', False)
case('7 Guardrails', 'SAFE-01', 'IM then ADMIN', 'C2 recorded; separate disposable request', 'IM creates a harmless count request and tries to approve their own request. Confirm it is blocked. ADMIN cancels the unposted request. Also confirm that the same manager CAN approve and dispatch a department-created requisition; no second inventory account is required.', 'No extra quantity posting', 'Own-request approval is blocked. Approval plus dispatch by the same manager on a department-created request is allowed. No extra quantity posting occurs.', True)
case('7 Guardrails', 'SAFE-02', 'IM and KITCHEN', 'Disposable scenario after C2; record references', 'Use a separate small Main Store to Kitchen request after C2. IM approves and dispatches, then tries to accept it as though they were Kitchen. Kitchen must decide it. Afterwards test a Kitchen-originated reverse request: IM may approve/dispatch and separately accept it at Main Store, with the return decision recorded.', 'This case may change quantities: log them separately from the baseline', 'The manager cannot receive their own outbound dispatch into Kitchen/Bar. A department-originated return to Main Store is the explicit supported manager handoff; its audit records that exception. Log any extra accepted quantities separately.', True)
case('7 Guardrails', 'SAFE-03', 'KITCHEN > IM', 'C2 recorded', 'Submit consumption for 999 KG rice at Kitchen. IM may approve the request for this negative test; IM tries to post. Confirm the refusal, then IM cancels the unposted request.', 'Kitchen has 13 KG, not 999', 'Insufficient stock blocks the entire posting. Rice remains 13 and no partial ledger entries are created.', True)
case('7 Guardrails', 'SAFE-04', 'KITCHEN > IM', 'After C2; controlled adjustment test', 'Submit a Kitchen physical count and leave it pending. Post a separately approved real test movement at Kitchen. Try posting the old count; it must be rejected. Cancel it and recount. Record the extra movement and expected revised balances separately.', 'Any intervening ledger movement at Kitchen makes the count stale', 'Old count cannot overwrite newer stock. No claim of unchanged C2 after the extra test movement.', True)
case('7 Guardrails', 'SAFE-05', 'STORE', 'BUY-04 or BUY-08 completed', 'Try to select either baseline GRN for another stock request, or reopen its completed stock request and post again. Do not create a new manual direct receipt to bypass the duplicate guard.', 'Already-posted GRN references', 'A GRN cannot create another active stock document, and repeated posting cannot add stock twice.', True)
case('7 Guardrails', 'SAFE-06', 'STORE', 'BUY-09 completed', 'Try a new Direct supplier receipt with UATSUP and delivery reference UAT-DIRECT-001 (also try different letter case). Submit without changing the source identity.', 'Same supplier and delivery reference', 'Duplicate supplier delivery reference is rejected. Main Store water is not increased again.', True)
case('7 Guardrails', 'SAFE-07', 'STORE', 'SET-10 completed', 'Try another Opening balance for rice at Main Store. Do not use a new material code to evade the check. Cancel any harmless request left pending.', 'Rice already has posted movements', 'Repeated opening stock for the same material/location is rejected. Corrections use reviewed counts, not a second opening.', True)
case('7 Guardrails', 'SAFE-08', 'STORE then FIN', 'A baseline GRN has posted stock', 'Request a Finance-reviewed void for the already stock-posted GRN. FIN attempts approval, verifies the block, and rejects the void request with a note so it does not remain pending.', 'Use the baseline source GRN; do not alter its quantities', "Posted stock cannot lose its source through a GRN void. Use reviewed physical/invoice corrections separately. Rejecting the test void restores the original GRN's normal review state.", True)
case('7 Guardrails', 'SAFE-09', 'IM', 'After C2', 'Try to deactivate a stock location that still holds stock or has a pending movement. For an unrelated empty disposable route, deactivate it and try initiating/dispatching a request through it; reactivate afterward.', 'Do not deactivate a live baseline route before happy-path completion', 'A location with stock/pending work cannot be deactivated. An inactive route blocks new requests/dispatches; historical records remain.', True)
case('7 Guardrails', 'SAFE-10', 'IM in two browser profiles', 'Both profiles open the SAME staff assignment revision', 'In profile A change and save a disposable permission. In the already-open profile B submit a different change without refreshing. Record the stale-edit error. Refresh B, inspect the saved settings and restore the intended assignment.', 'Same member; two open editors', 'A stale editor cannot overwrite another save. The current revision must be reviewed first.', True)
case('7 Guardrails', 'SAFE-11', 'ADMIN', 'Recipe baseline completed; no new production', 'Publish a new version of UATSAUCE after changing a component quantity. Do not edit the UATMEAL/menu bindings. Reopen the old parent and menu breakdown. Do not produce the new version during this test.', 'Record actual new version; keep parent pinned to its old child', 'Existing parent/menu still reference their original saved versions. Publishing a new child does not silently rewrite them or create stock.', True)
case('7 Guardrails', 'SAFE-12', 'IM / KITCHEN', 'After C2; disposable requests', 'Try a negative quantity, a future movement date and a date before a later posted movement for the same material/location. If a request can be staged, check posting validation and cancel it afterward. Also try a production batch exceeding available ingredients.', 'Do not post an actual extra batch', 'Invalid quantities/dates or insufficient inputs cannot create a partial posting. Future dates are refused. Backdating behind later ledger activity is blocked when posting.', True)
case('7 Guardrails', 'SAFE-13', 'Receiving department', 'After C2', 'Create a separate small transfer, have IM approve and dispatch, and record both balances before receipt. Receiver chooses Reject transfer with a reason. IM verifies the goods physically returned, then resolves the follow-up.', 'No automatic waste/loss', 'On-hand balances never change. The rejected quantity stays reserved until physical-return resolution; a rejection alert appears and clears after resolution.', True)
case('7 Guardrails', 'SAFE-14', 'Receiving department and IM', 'After C2', 'Create a separate2-unit transfer. Dispatch as IM, then accept1 with a reason for rejecting1. Inspect both ledgers, reserves and Incomplete filter. IM verifies return of the rejected1 and resolves.', 'Track this extra accepted1 separately from C2', 'Only1 is deducted from source and added to destination; rejected1 is not depleted or added. Its reservation remains until resolved. No automatic transit loss is created.', True)
case('7 Guardrails', 'SAFE-15', 'KITCHEN > IM', 'Reverse route configured; after C2', 'Kitchen submits an excess return of1 unit to Main Store. IM approves and authorises dispatch. Confirm both balances stay unchanged, then IM accepts the department-originated return at Main Store.', 'Department stock user creates the return; manager accepts at Main Store', 'Kitchen decreases1 and Main Store increases1 only on acceptance. No separate inventory staff account is required. The manager-return decision is audited.', True)
case('7 Guardrails', 'SAFE-16', 'IM and receiving department', 'After C2', 'Dispatch a transfer that reserves most available stock. Try another dispatch or consumption that would use the held stock. Try a physical count while the first transfer is awaiting acceptance. Have the receiver reject and IM verify physical return/resolve before reusing it.', 'Do not actually over-allocate stock', 'Reservations block competing allocation and consumption; physical counts cannot overwrite unresolved transfer state. Stock becomes available only after acceptance or verified return resolution.', True)
case('8 Usability', 'UX-01', 'IM / STORE / KITCHEN / BAR / FIN', 'Any populated tables', 'Open stock balances, movement register, ledger, stock locations/routes, POs/GRNs and supplier invoices as the roles allowed to view them. Check headers, row spacing, status badges and readable action links.', 'Desktop and a phone-sized viewport', 'Tables use the shared layout. On a phone, horizontal scrolling stays inside each table; the page itself does not overflow. Roles without a module cannot open it.', False)
case('8 Usability', 'UX-02', 'IM', 'Populated movement register', 'Filter by Main Store, Kitchen and Bar. Open a record, close it, then change pages if more than 10 records exist. Open the ledger and check its stated 100-entry display limit.', 'If fewer than11 records, mark the extra-page sub-check Not applicable; test each requisition status filter.', 'Filters preserve the correct organisation and location; records remain consistent. The ledger does not pretend its latest 100 rows are a full export.', False)
case('8 Usability', 'UX-03', 'All roles', 'A completed record', 'Refresh a completed record, navigate away/back and sign out/sign in again. Verify status and quantities. If a save encounters a connection error, refresh the register before deciding to retry; keep the same source reference.', 'Never create a different reference just to force a retry', 'Saved state persists. Refresh/retry does not duplicate postings or log the user out unexpectedly.', True)
case('8 Usability', 'UX-04', 'Test lead', 'All applicable cases completed', 'Review every Not run, Failed and Blocked result. Attach issue IDs and evidence, retest fixes, then fill Sign-off. Record which guardrail tests changed the baseline and the final reconciled balances.', 'Release decision is manual, not a calculated approval', 'No critical access, duplication, negative-stock or reconciliation failure remains unresolved before real restaurant data is loaded.', True)
case('8 Usability', 'UX-05', 'IM', 'Populated requisition register', 'Use Pending, Awaiting acceptance, Completed, Incomplete, Rejected and Cancelled filters, then search an exact reference. Verify the total and page count against the matching scoped records.', 'Filters must apply before pagination', 'Only matching records appear, totals stay correct across pages, and alert links open their exact authorised record even when it is not on the first page.', True)
case('8 Usability', 'UX-06', 'IM and department', 'A new department requisition', 'Check the manager workspace for Approval needed. Approve and dispatch; check the receiving department workspace for Accept or reject incoming stock. Partially accept/reject and inspect follow-up alerts. Finish or resolve with evidence.', 'Leave the visible workspace open up to30 seconds or refresh', 'Relevant action alerts update for the right accounts, with no unrelated department data. Resolved work drops out. Items older than24 hours are labelled; no email/SMS is implied.', True)
case('8 Usability', 'UX-07', 'All testers', 'Desktop and mobile browser', 'Review the updated homepage and its stock handoff explanation. Open Sign in and Sign up; check readable labels, password visibility, keyboard focus, back link and narrow-screen layout. Open populated stock records and verify compact rows and10-row pagination.', "Do not alter another account's credentials", 'Pages are readable, keyboard-accessible and do not overflow the viewport. Authentication/invitation flows still work; tables retain readable numeric columns without excessive row height.', False)

ACCOUNTS = [
    ("ADMIN", "Restaurant owner / test lead", "CEO + Restaurant Administrator", "All business locations", "Owns setup, invitations and management report approval"),
    ("IM", "Inventory Manager", "Inventory Manager", "All business locations", "Leads stock configuration, staff stock access and physical approvals"),
    ("STORE", "Main Store operating alias for IM", "Inventory Manager (same IM account)", "All stock locations", "Do not create a separate STORE account; use IM"),
    ("KITCHEN", "Kitchen receiver", "Department stock user", "UAT Dining; stock allowlist Kitchen", "Request=yes, Accept/reject=yes; no dispatch or approval"),
    ("BAR", "Bar receiver", "Department stock user", "UAT Dining; stock allowlist Bar", "Request=yes, Accept/reject=yes; no dispatch or approval"),
    ("PROC", "Procurement", "Procurement", "All business locations", "Supplier/material setup, POs and supplier invoices"),
    ("FIN", "Finance reviewer", "Finance / Auditor", "All business locations", "Invoice exceptions, expenses and report submission"),
    ("OPS", "Kitchen requester", "Department stock user (optional)", "UAT Dining; stock allowlist Kitchen", "Request=yes; receiving/dispatch/approval=no"),
]
ITEMS = [
    ("UATRICE", "Rice", "RAW", "KG", "1800", "100"),
    ("UATCHICK", "Chicken", "RAW", "KG", "6000", "40"),
    ("UATTOM", "Tomato", "RAW", "KG", "1000", "20"),
    ("UATONION", "Onion", "RAW", "KG", "800", "10"),
    ("UATOIL", "Cooking oil", "RAW", "L", "2500", "10"),
    ("UATBOX", "Meal box", "PACKAGING", "PCS", "100", "100"),
    ("UATWATER", "Bottled water", "RESALE", "PCS", "200", "60"),
    ("UATBASE", "Stored tomato base", "SEMI_FINISHED", "KG", "Not required for this raw-recipe estimate", "0 - no opening request"),
    ("UATPLATE", "Finished chicken rice plate", "FINISHED", "PCS", "Not required for this raw-recipe estimate", "0 - no opening request"),
]
for entry in CASES:
    for field in ["steps", "data", "expected", "prerequisite"]:
        entry[field] = re.sub(r"(?<=[a-z])(?=\d)", " ", entry[field])
        for code, *_ in ITEMS:
            entry[field] = re.sub(r"("+code+r")(?=\d)", r"\1 ", entry[field])

BASE = {code: Decimal(qty) for code, _, _, _, _, qty in ITEMS[:7]}
main, kitchen, bar = BASE.copy(), {}, {}


def move(src, dst, code, qty, accepted=None):
    quantity = Decimal(qty)
    assert src.get(code, Decimal(0)) >= quantity
    src[code] -= quantity
    dst[code] = dst.get(code, Decimal(0)) + Decimal(accepted if accepted is not None else qty)


C0 = dict(main)
for code, qty in [("UATRICE", "20"), ("UATCHICK", "10"), ("UATTOM", "10"), ("UATONION", "5"), ("UATOIL", "5"), ("UATBOX", "40")]:
    move(main, kitchen, code, qty)
move(main, bar, "UATWATER", "23", "23")
for code, qty in [("UATTOM", "6"), ("UATONION", "2"), ("UATOIL", "1")]:
    kitchen[code] -= Decimal(qty)
kitchen["UATBASE"] = Decimal(8)
for code, qty in [("UATRICE", "4"), ("UATCHICK", "3"), ("UATBASE", "2"), ("UATBOX", "20")]:
    kitchen[code] -= Decimal(qty)
kitchen["UATPLATE"] = Decimal(18)
kitchen["UATRICE"] -= 2
kitchen["UATCHICK"] -= 1
bar["UATWATER"] -= 6
assert kitchen["UATRICE"] == 14
kitchen["UATRICE"] = Decimal(13)
C1 = [main.copy(), kitchen.copy(), bar.copy()]
main["UATRICE"] += 10
main["UATWATER"] += 12
C2 = [main.copy(), kitchen.copy(), bar.copy()]
assert all(q >= 0 for location in C2 for q in location.values())
batch = Decimal(6)*1000 + Decimal(2)*800 + Decimal(1)*2500
serving = (Decimal(4)*1800 + Decimal(3)*6000 + batch/8*2 + Decimal(20)*100)/20
assert batch == 10100 and serving == Decimal("1486.25")
assert serving*3 == Decimal("4458.75")
assert (serving*3+1000) == Decimal("5458.75")
assert len({c["id"] for c in CASES}) == len(CASES)

INTRO = """# ProfitPlate full pilot test sheet and beginner guide
Prepared 17 November 2026 against migrations through 026; version2 supersedes the earlier dispatch-depletion guide. These are manual test instructions, not a claim that your deployment has passed them.

## Start here
1. Use a fresh TEST restaurant. A populated demo/live restaurant will not match these expected balances. Keep the same run on one Lagos business date D where possible; receipt is dated today. If you continue on another day, use the actual permitted dates and record the change; do not backdate behind later stock postings.
2. Apply only pending migrations in order through 026 and deploy the matching app. If 023 is already applied, do not rerun it; apply 024/025/026 only if pending. Never paste test data into the migration editor.
3. Open ProfitPlate-Full-Test-Sheet-v2.xlsx in Excel or another compatible spreadsheet application. It is a TEST RECORD, not a file to upload into ProfitPlate. The app's implemented data uploads remain CSV.
4. Fill Run details and Accounts. Use one distinct verified email per real actor (STORE uses IM) and a separate browser profile per actor, or explicitly sign out before switching. Separate tabs share a session. STORE is an alias for the same IM account, not another person. Do not store passwords in the sheets.
5. Run worksheets 1 Setup, 2 Recipes, 3 Movements, 4 Purchasing and 5 Finance in that order. Preserve record references. Compare C0, C1 and C2 in Checkpoints. Then run 6 Access, 7 Guardrails and 8 Usability.
6. For EACH row read the prerequisite, sign in as the specified actor, perform the numbered procedure described in Exact steps, and compare Expected result. Enter Actual result, Status, Tester, Date, Record reference and Issue ID. Do not mark a case Passed just because a button exists.
7. For an expected rejection, a PASS means the action was blocked and no unintended data/stock changed. Failed means the observed behaviour contradicts the expected result. Blocked means a prerequisite, account, environment or source record prevents testing. Not applicable needs a reason. New sheets start Not run.
8. If a happy-path case fails, stop dependent cases and mark them Blocked. Log the issue, retain screenshots/reference IDs, fix/retest, and resume from a known checkpoint. Do not delete rows, invent compensating stock or change source IDs to force success.
9. Negative/permission tests run AFTER the baseline. Some deliberately post extra movements; record and reconcile those separately, or use another fresh test run. C2 is the baseline before these extra tests, not a promise about later altered balances.
10. The test lead completes Sign-off manually after retesting. Do not load real restaurant stock while any critical access, duplicate posting, negative-stock or reconciliation issue remains unresolved.

## Accounts, aliases and Supabase registration
Use actual email addresses you control. If your email provider supports plus aliases, you may use youraddress+im@yourdomain, +kitchen, +bar, +proc, +fin and +ops; replace these examples with your own valid mailbox addresses. A plus alias does not create a separate inbox, and support depends on the provider. Otherwise use distinct real mailboxes.

The owner registers in the app, verifies the email, signs in and completes restaurant setup once. ADMIN creates staff invitations in Users & roles and shares each copyable link with its intended test actor. The invited person opens the app's Sign up using the exact invited address, verifies that email, signs in and accepts the invitation. If signup initially asks for business setup, follow the invitation flow rather than creating a second business. Expired invitations must be recreated by ADMIN. Do not grant Inventory Manager to ordinary Kitchen/Bar staff: it deliberately grants business-wide stock authority. An Auth user in Supabase alone does not establish restaurant membership or stock permissions.

Optional operator check: in your existing Supabase project, verify the registered test addresses in Authentication / Users. Do not create another Supabase project or edit membership tables by hand to bypass invitations. No service-role keys or passwords belong in this test pack.

## Common stock procedure (use every time a case says submit > approve > post)
1. REQUESTER: Inventory & movements > Movements & requests > Request a stock movement. Choose Movement type, location or permitted route, date D and the material/base-unit quantities (or recipe version/planned/actual output). Enter Source reference and reason, tick the confirmation, then Submit stock request. Record the generated STK reference.
2. IM: open the same record through Review stock requests / Movement register > Review. Check quantities and source. Under Review and act choose Approve request, enter Decision note, tick confirmation and save. A different person must approve the request.
3. IM: after approving a department-created request, post its non-transfer quantities or choose Confirm dispatch for an issue/transfer. The receiving department chooses Accept transfer or Reject transfer and explains every unaccepted quantity. Receipt is dated today. Enter notes, tick confirmation and save.
4. CHECK: open Stock balances for the relevant stock location and Stock ledger. Requested/Approved do not affect quantities. Dispatch reserves stock; only acceptance posts source deduction and destination addition together. Rejected remainders stay reserved at source until IM verifies physical return and resolves the follow-up. A supplier GRN does not add stock until its accepted quantities are explicitly posted through this stock procedure.

## What this test proves and what it does not
This covers onboarding, roles, material/reference data, recipes, menu profitability, quantity inventory, PO/GRN/invoice separation, Finance review, sales/expense imports and management reports. Financial figures use dated reference estimates. It does not test unbuilt actual inventory valuation/COGS, lot/expiry tracking, POS integration, payroll, supplier credit notes or automated sales-to-stock depletion. Do not expect those features.

Stock department assignments narrow quantity-stock access. Existing PO/GRN documents, shared materials/recipes and other modules retain their own role/outlet permissions. Finance/Administrator stock-approval fallback is retained. The Inventory Manager is the lead stock approver but cannot approve their own requests or accept an outbound dispatch for Kitchen/Bar. A department-originated return can be accepted by the manager at Main Store, with an explicit audit record.

The sample assumes NGN, no tax, one outlet and one currency. The sample tax setting is fictional, not restaurant tax guidance. Menu estimates use the standard 20-serving recipe, even when the physical batch yields18; actual production cost per serving is not calculated by the current costing engine.

## Supplied CSV files
example-initial-prices.csv is upload-ready only after the matching materials exist and you replace TEST_DATE. example-sales.csv and example-expenses.csv require replacing TEST_DATE and LOCATION_CODE_HERE; use source organisation alias UAT_ORG in the relevant upload screen. Match category codes to existing WAGES/RENT. These are fictional source records. Do not upload the Excel test workbook, account sheet, result log or issue log as application data. Each CSV import accepts up to100 data rows and128 KB, using the exact template headers.

## Recording failures and requesting help
Record test ID, actor/role, screen/URL, exact click sequence, source/document references, expected versus observed result, date/time, screenshot and whether anything was posted. Never include passwords, verification/invitation tokens, session cookies or Supabase keys in evidence. Critical: cross-tenant/department stock exposure, unauthorised posting, duplicate posting, negative stock or wrong reconciliation. High: a core legitimate workflow cannot complete. Medium/Low: non-blocking usability or presentation.

The developer's automated checks and your manual UAT are separate. Every row here starts Not run. A passing test does not imply a backup/restore drill or production hosting/email readiness check has happened; record those confirmations in Run details/Sign-off as operator tasks.
"""

HEADERS = ["Test ID", "Critical?", "Actor", "Prerequisite", "Exact steps", "Test data", "Expected result", "Actual result", "Status", "Tester", "Test date", "Record reference", "Issue ID"]
ORDER = list(dict.fromkeys(c["sheet"] for c in CASES))


def col(n):
    result = ""
    while n:
        n, r = divmod(n-1, 26)
        result = chr(65+r)+result
    return result


def cell_xml(row, column, value, style=0):
    address = f"{col(column)}{row}"
    if isinstance(value, tuple) and value[0] == "formula":
        return f'<c r="{address}" s="{style}"><f>{escape(value[1])}</f><v>{value[2]}</v></c>'
    if isinstance(value, (int, float)):
        return f'<c r="{address}" s="{style}"><v>{value}</v></c>'
    return f'<c r="{address}" s="{style}" t="inlineStr"><is><t xml:space="preserve">{escape(str(value))}</t></is></c>'


SHEETS = []


def sheet(name, headers, rows, widths, description, statuses=False, editable=(), height=72):
    assert len(name) <= 31
    assert all(len(row) == len(headers) for row in rows), name
    SHEETS.append(dict(name=name, headers=headers, rows=rows, widths=widths, description=description,
                       statuses=statuses, editable=editable, height=height))


readme_blocks = []
for block in INTRO.split("\n\n"):
    readme_blocks.extend(block.splitlines() if block.startswith("## Start here") else [block])
sheet("Read me", ["Order", "Instruction"], [[i+1, line] for i, line in enumerate(readme_blocks)], [12, 140], "Read this before entering test data. All scenario results initially remain Not run.", height=56)
sheet("Run details", ["Field", "Value / confirmation", "Notes"], [
    ["Test run ID", "", "Use one unique run ID; keep it with all screenshots and issue records."],
    ["Prepared", "2026-11-17", "Guide preparation date, not evidence of your test date."],
    ["Restaurant / organisation", "", "Fresh test workspace; never copy another tenant's data."],
    ["App URL and deployed version", "", "Record the actual deployment being tested."],
    ["Lagos business date D", "", "Replace TEST_DATE in example CSVs. Prefer one day for the baseline."],
    ["Actual outlet code", "", "Replace LOCATION_CODE_HERE in the sales/expense CSVs."],
    ["Reporting currency", "NGN", "Use the sample unchanged only for this currency."],
    ["Migrations through 026 confirmed", "", "Record applied versions; do not rerun applied migrations."],
    ["Owner / test lead", "", "No passwords, tokens or keys."],
    ["Test start / finish", "", "Your local date/time."],
    ["Account verification / reset check", "", "Run the app's verify-email and password-reset flow on a test account; record outcome."],
    ["Backup / restore verification", "", "Project operator records actual evidence/date; leave unverified if not performed."],
    ["Hosting / email / error monitoring", "", "Project operator confirms production-like readiness separately."],
], [38, 60, 90], "Fill yellow Value cells. This is a manual test record, not an application upload.", editable=(2,), height=48)
sheet("Accounts", ["Actor", "Person", "App role", "Role and stock scope", "Responsibilities", "Actual email", "Invitation / verified / accepted", "Browser profile"], [list(a)+["", "", ""] for a in ACCOUNTS], [14, 25, 32, 48, 65, 40, 38, 28], "Create distinct verified accounts. Never enter passwords. ADMIN is the owner; IM is explicitly invited/assigned.", editable=(6, 7, 8), height=90)
sheet("Test data", ["Code", "Name", "Item type", "Base unit", "Reference price / base unit NGN", "Opening Main Store quantity"], [list(i) for i in ITEMS]+[
    ["UATSUP", "UAT supplier", "Supplier", "", "", ""],
    ["UATSAUCE", "Tomato base", "SUB_RECIPE", "8 KG yield", "6 KG tomato +2 KG onion +1 L oil", "Batch10100; output1262.50/KG"],
    ["UATMEAL", "Chicken rice", "FINAL", "20 PCS yield", "4 KG rice +3 KG chicken +2 KG saved sauce +20 boxes", "Batch29725; serving1486.25"],
    ["UATMENU", "Chicken rice plate", "Menu", "1 PCS recipe per sale", "TAKEAWAY3500; tax NONE/0; effective D", "Brand UAT Kitchen; outlet UAT Dining"],
], [22, 30, 26, 25, 75, 48], "Fictional sample. All nine items are active and stock tracked. Recipe input quantities cover the complete batch.", height=64)
checkpoint_rows = []
for code, name, _, unit, _, _ in ITEMS:
    checkpoint_rows.append([code, name, unit, str(C0.get(code, 0)), str(C1[0].get(code, 0)), str(C1[1].get(code, 0)), str(C1[2].get(code, 0)), str(C2[0].get(code, 0)), str(C2[1].get(code, 0)), str(C2[2].get(code, 0)), "", ""])
sheet("Checkpoints", ["Material", "Name", "Unit", "C0 Main", "C1 Main", "C1 Kitchen", "C1 Bar", "C2 Main", "C2 Kitchen", "C2 Bar", "Observed / discrepancy", "Evidence reference"], checkpoint_rows, [23, 30, 12, 14, 14, 16, 14, 14, 16, 14, 60, 35], "C0 after opening; C1 after MOV-14; C2 after BUY-11 and before guardrails. Kitchen/Bar C0 are zero. Zero rows may be absent until first posting. The unaccepted water1 stays at Main Store; there is no automatic transit loss. Complete its physical-return resolution before C1.", editable=(11, 12), height=45)
for name in ORDER:
    rows = [[c["id"], "Yes" if c["critical"] else "No", c["role"], c["prerequisite"], c["steps"], c["data"], c["expected"], "", "Not run", "", "", "", ""] for c in CASES if c["sheet"] == name]
    sheet(name, HEADERS, rows, [15, 12, 26, 30, 85, 48, 85, 60, 20, 24, 20, 35, 24], "Run cases top to bottom; never mark a rejection Passed unless data/stock stayed correct. Fill Actual result and yellow result columns.", statuses=True, editable=tuple(range(8, 14)), height=150)
summary = []
for name in ORDER:
    count = sum(c["sheet"] == name for c in CASES)
    summary.append([name, count]+[("formula", f'COUNTIF(\'{name}\'!I5:I{count+4},"{status}")', count if status == "Not run" else 0) for status in ["Passed", "Failed", "Blocked", "Not run", "Not applicable"]])
summary.append(["ALL MANUAL CASES"]+[("formula", f"SUM({col(i)}5:{col(i)}{4+len(ORDER)})", len(CASES) if i in [2, 6] else 0) for i in range(2, 8)])
sheet("Summary", ["Test worksheet", "Cases", "Passed", "Failed", "Blocked", "Not run", "Not applicable"], summary, [28, 15, 15, 15, 15, 15, 20], "Counts recalculate when opened in a compatible spreadsheet app. This summary does not approve release; use manual Sign-off.", height=32)
sheet("Issues", ["Issue ID", "Test ID", "Severity", "Actor / environment", "Expected", "Observed / reproduction", "Record IDs / screenshot", "Owner", "State", "Fix / retest evidence"], [[""]*10 for _ in range(20)], [20, 18, 18, 35, 60, 85, 50, 25, 22, 70], "Severity: Critical / High / Medium / Low. Record exact source references. Never include secrets or invitation tokens.", editable=tuple(range(1, 11)), height=90)
sheet("Sign-off", ["Check", "Decision / evidence", "Responsible person / date"], [
    ["All applicable critical tests passed", "", ""],
    ["Baseline C0/C1/C2 reconciled", "", ""],
    ["Extra negative-test movements reconciled separately", "", ""],
    ["No unresolved access / duplication / negative-stock issue", "", ""],
    ["Inventory Manager accepts operational workflow", "", ""],
    ["Procurement and Finance accept their workflows", "", ""],
    ["Kitchen and Bar confirm department separation", "", ""],
    ["Hosting / email / backup-restore operator checks evidenced", "", ""],
    ["Known limitations and exclusions accepted", "", ""],
    ["Pilot decision: Ready / Not ready / Conditional", "", ""],
    ["Conditions, owner and target retest date", "", ""],
    ["Final owner approval", "", ""],
], [68, 85, 45], "Manual decision only. A spreadsheet count is not release approval. Every Not applicable decision needs a reason.", editable=(2, 3), height=60)


def worksheet_xml(spec):
    rows, headers = spec["rows"], spec["headers"]
    n, end = len(headers), len(rows)+4
    xml = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>', '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">', f'<dimension ref="A1:{col(n)}{end}"/>', '<sheetViews><sheetView workbookViewId="0"><pane ySplit="4" topLeftCell="A5" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>', '<sheetFormatPr defaultRowHeight="22"/><cols>']
    xml.extend(f'<col min="{i}" max="{i}" width="{w}" customWidth="1"/>' for i, w in enumerate(spec["widths"], 1))
    xml.append('</cols><sheetData>')
    xml.append('<row r="1" ht="32" customHeight="1">'+cell_xml(1, 1, "ProfitPlate | "+spec["name"], 1)+'</row>')
    xml.append('<row r="2" ht="50" customHeight="1">'+cell_xml(2, 1, spec["description"], 2)+'</row>')
    xml.append('<row r="4" ht="30" customHeight="1">'+''.join(cell_xml(4, i, h, 4) for i, h in enumerate(headers, 1))+'</row>')
    for row_no, data in enumerate(rows, 5):
        lines = max(sum(max(1, math.ceil(len(part)/max(1, spec["widths"][i]*0.88))) for part in str(v).split("\n")) for i, v in enumerate(data))
        row_height = min(409, max(spec["height"], lines*14+12))
        xml.append(f'<row r="{row_no}" ht="{row_height}" customHeight="1">'+''.join(cell_xml(row_no, i, v, 3 if i in spec["editable"] else 0) for i, v in enumerate(data, 1))+'</row>')
    xml.append(f'</sheetData><autoFilter ref="A4:{col(n)}{end}"/><mergeCells count="2"><mergeCell ref="A1:{col(n)}1"/><mergeCell ref="A2:{col(n)}2"/></mergeCells>')
    if spec["statuses"]:
        xml.append(f'<conditionalFormatting sqref="I5:I{end}"><cfRule type="cellIs" dxfId="0" priority="1" operator="equal"><formula>"Passed"</formula></cfRule><cfRule type="cellIs" dxfId="1" priority="2" operator="equal"><formula>"Failed"</formula></cfRule></conditionalFormatting>')
        xml.append(f'<dataValidations count="1"><dataValidation type="list" errorStyle="stop" allowBlank="0" showErrorMessage="1" errorTitle="Choose a test status" error="Use the status dropdown." sqref="I5:I{end}"><formula1>"Not run,Passed,Failed,Blocked,Not applicable"</formula1></dataValidation></dataValidations>')
    xml.append('<pageMargins left="0.25" right="0.25" top="0.4" bottom="0.4" header="0.2" footer="0.2"/><pageSetup paperSize="9" orientation="landscape" fitToWidth="1" fitToHeight="0"/></worksheet>')
    return ''.join(xml)


STYLES = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="3"><font><sz val="11"/><name val="Calibri"/><color rgb="FF203A32"/></font><font><b/><sz val="18"/><name val="Calibri"/><color rgb="FFFFFFFF"/></font><font><b/><sz val="11"/><name val="Calibri"/><color rgb="FFFFFFFF"/></font></fonts><fills count="5"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF184D3D"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFFF5D9"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFEDF4EF"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="5"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="center"/></xf><xf numFmtId="0" fontId="0" fillId="4" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="3" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="0" fontId="2" fillId="2" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles><dxfs count="2"><dxf><fill><patternFill patternType="solid"><fgColor rgb="FFDDF2E3"/></patternFill></fill></dxf><dxf><fill><patternFill patternType="solid"><fgColor rgb="FFFFDDDD"/></patternFill></fill></dxf></dxfs></styleSheet>'''

workbook_path = OUT / "ProfitPlate-Full-Test-Sheet-v2.xlsx"
with zipfile.ZipFile(workbook_path, 'w', zipfile.ZIP_DEFLATED) as book:
    overrides = ''.join(f'<Override PartName="/xl/worksheets/sheet{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' for i in range(1, len(SHEETS)+1))
    book.writestr('[Content_Types].xml', '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'+overrides+'</Types>')
    book.writestr('_rels/.rels', '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
    sheets_xml = ''.join(f'<sheet name="{escape(s["name"])}" sheetId="{i}" r:id="rId{i}"/>' for i, s in enumerate(SHEETS, 1))
    book.writestr('xl/workbook.xml', '<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><bookViews><workbookView activeTab="0"/></bookViews><sheets>'+sheets_xml+'</sheets><calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>')
    relationships = ''.join(f'<Relationship Id="rId{i}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet{i}.xml"/>' for i in range(1, len(SHEETS)+1))
    book.writestr('xl/_rels/workbook.xml.rels', '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'+relationships+f'<Relationship Id="rId{len(SHEETS)+1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>')
    book.writestr('xl/styles.xml', STYLES)
    for i, spec in enumerate(SHEETS, 1):
        book.writestr(f'xl/worksheets/sheet{i}.xml', worksheet_xml(spec))

guide = INTRO + '\n## Accounts\n\n' + '\n'.join(f'- {a[0]}: {a[2]}; {a[3]}. {a[4]}.' for a in ACCOUNTS)
guide += '\n\n## Balance checkpoints\n\nMaterial | Unit | C0 Main | C1 Main | C1 Kitchen | C1 Bar | C2 Main | C2 Kitchen | C2 Bar\n---|---|---|---|---|---|---|---|---\n'
guide += '\n'.join('|'.join(map(str, r[:1]+r[2:10])) for r in checkpoint_rows)
for name in ORDER:
    guide += '\n\n## '+name+'\n'
    for c in (c for c in CASES if c['sheet'] == name):
        guide += f'\n### {c["id"]} — {c["role"]}\n\nPrerequisite: {c["prerequisite"]}.\n\nSteps: {c["steps"]}\n\nTest data: {c["data"]}.\n\nExpected: {c["expected"]}\n\nResult: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______\n'
(OUT / "Full-Test-Guide.md").write_text(guide, encoding='utf-8')

def markup(text):
    return '<p>'+html.escape(text).replace('\n', '<br>')+'</p>'


parts = ['<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>ProfitPlate full pilot test guide</title><style>body{font:16px/1.7 system-ui,sans-serif;color:#203a32;background:#f4f7f4;margin:0}main{max-width:1050px;margin:auto;padding:30px}h1,h2,h3{line-height:1.3}p,li,h1,h2,h3,h4{overflow-wrap:anywhere}li{margin-bottom:12px}h1{color:#184d3d}h2{margin-top:42px;border-bottom:2px solid #b8cbbd;padding-bottom:10px}article{background:white;border:1px solid #d7e3d9;border-radius:10px;padding:22px;margin:20px 0}small,.muted{color:#53685c}table{border-collapse:collapse;width:100%;background:white;font-size:13px}th,td{padding:10px;border:1px solid #d7e3d9;text-align:left;vertical-align:top}th{background:#184d3d;color:white}.scroll{overflow:auto}a{color:#184d3d}.result{background:#fff5d9;padding:12px}nav a{display:inline-block;margin-right:16px}@media print{body{background:white;font-size:11pt}main{max-width:none;padding:0}article{break-inside:avoid}nav{display:none}a{color:inherit;text-decoration:none}.scroll{overflow:visible}@page{size:A4;margin:14mm}}</style></head><body><main>']
parts.append('<h1>ProfitPlate full pilot test guide</h1>'+markup(f'{len(CASES)} manual cases • Inventory Manager-led fine-dining pilot • Prepared 17 November 2026. Start with the Excel workbook; print this guide using your browser’s Print / save PDF. All results initially Not run.'))
parts.append('<nav>'+''.join(f'<a href="#part{i}">{html.escape(name)}</a>' for i, name in enumerate(ORDER, 1))+'</nav>')
for block in INTRO.split('\n\n')[1:]:
    if block.startswith('## '):
        heading, _, block = block.partition('\n')
        parts.append('<h2>'+html.escape(heading[3:])+'</h2>')
    if block.strip():
        lines = block.splitlines()
        if all(re.match(r'^\d+\. ', line) for line in lines):
            parts.append('<ol>'+''.join('<li>'+html.escape(re.sub(r'^\d+\. ', '', line))+'</li>' for line in lines)+'</ol>')
        else:
            parts.append(markup(block))
for spec in (s for s in SHEETS if s['name'] in ['Accounts', 'Test data', 'Checkpoints']):
    parts.append('<h2>'+spec['name']+'</h2>'+markup(spec['description'])+'<div class="scroll"><table><thead><tr>'+''.join('<th>'+html.escape(h)+'</th>' for h in spec['headers'])+'</tr></thead><tbody>')
    for row in spec['rows']:
        parts.append('<tr>'+''.join('<td>'+html.escape(str(v))+'</td>' for v in row)+'</tr>')
    parts.append('</tbody></table></div>')
for i, name in enumerate(ORDER, 1):
    parts.append(f'<h2 id="part{i}">{name}</h2>')
    for c in (c for c in CASES if c['sheet'] == name):
        parts.append('<article><h3>'+html.escape(c['id']+' | '+c['role'])+'</h3><p class="muted">Prerequisite: '+html.escape(c['prerequisite'])+'</p><h4>What to do</h4>'+markup(c['steps'])+'<h4>Test data</h4>'+markup(c['data'])+'<h4>Expected result</h4>'+markup(c['expected'])+'<p class="result">Status: Not run / Passed / Failed / Blocked / Not applicable<br>Actual result: ______________________________<br>Tester/date: ______________________________<br>Record reference / issue ID: ______________________________</p></article>')
parts.append('</main></body></html>')
(OUT / "Full-Test-Guide.html").write_text(''.join(parts), encoding='utf-8')

with (OUT / 'Test-results.csv').open('w', newline='', encoding='utf-8-sig') as file:
    writer = csv.writer(file)
    writer.writerow(['Worksheet']+HEADERS)
    for c in CASES:
        writer.writerow([c['sheet'], c['id'], 'Yes' if c['critical'] else 'No', c['role'], c['prerequisite'], c['steps'], c['data'], c['expected'], '', 'Not run', '', '', '', ''])

def csv_file(name, headers, rows):
    with (OUT / name).open('w', newline='', encoding='utf-8-sig') as file:
        writer = csv.writer(file)
        writer.writerow(headers)
        writer.writerows(rows)


csv_file('example-initial-prices.csv', ['material_code', 'quantity', 'unit_code', 'total_price', 'price_date', 'source_note'], [[code, '1', unit, price, 'TEST_DATE', 'Fictional UAT last-purchase price'] for code, _, _, unit, price, _ in ITEMS[:7]])
sales_headers = (ROOT / 'public/templates/sales-import.csv').read_text(encoding='utf-8-sig').strip().split(',')
expense_headers = (ROOT / 'public/templates/expense-import.csv').read_text(encoding='utf-8-sig').strip().split(',')
csv_file('example-sales.csv', sales_headers, [['UAT_ORG', 'UAT_POS', 'LOCATION_CODE_HERE', 'TEST_DATE', 'UAT-SALE-001', '1', 'UATMENU', '3', '10500', '0', '0', '10500', 'TAKEAWAY', 'NORMAL', '', 'PAID']])
csv_file('example-expenses.csv', expense_headers, [
    ['UAT_ORG', 'UAT_EXP', 'UAT-WAGES-001', '1', 'WAGES', 'LOCATION', 'LOCATION_CODE_HERE', 'TEST_DATE', 'TEST_DATE', 'ON_DATE', 'TEST_DATE', '1000', 'NGN', 'Fictional UAT labour'],
    ['UAT_ORG', 'UAT_EXP', 'UAT-RENT-001', '1', 'RENT', 'LOCATION', 'LOCATION_CODE_HERE', 'TEST_DATE', 'TEST_DATE', 'ON_DATE', 'TEST_DATE', '500', 'NGN', 'Fictional UAT operating expense'],
])
(OUT / 'START-HERE.txt').write_text('Open ProfitPlate-Full-Test-Sheet-v2.xlsx for the updated editable test record. Open Full-Test-Guide.html in a browser for the readable/printable guide. Run sheets 1-5 first, then access/guardrail/usability checks.\n\nThe XLSX, result CSV and accounts are NOT application imports. The three example data CSVs need their date/outlet placeholders replaced before upload; see the guide. All test results start Not run. Never store passwords or tokens here.\n', encoding='utf-8')
(OUT / 'test-cases.json').write_text(json.dumps(CASES, indent=2), encoding='utf-8')

pack_path = OUT.parent / 'profitplate-full-test-pack-2026-11-17-v2.zip'
with zipfile.ZipFile(pack_path, 'w', zipfile.ZIP_DEFLATED) as pack:
    for file in sorted(OUT.iterdir()):
        if file.is_file():
            pack.write(file, file.name)

print(f'Built {len(CASES)} cases, {len(SHEETS)} workbook sheets and {len(list(OUT.iterdir()))} packaged files.')
