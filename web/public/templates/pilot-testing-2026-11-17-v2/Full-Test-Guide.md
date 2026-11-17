# ProfitPlate full pilot test sheet and beginner guide
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

## Accounts

- ADMIN: CEO + Restaurant Administrator; All business locations. Owns setup, invitations and management report approval.
- IM: Inventory Manager; All business locations. Leads stock configuration, staff stock access and physical approvals.
- STORE: Inventory Manager (same IM account); All stock locations. Do not create a separate STORE account; use IM.
- KITCHEN: Department stock user; UAT Dining; stock allowlist Kitchen. Request=yes, Accept/reject=yes; no dispatch or approval.
- BAR: Department stock user; UAT Dining; stock allowlist Bar. Request=yes, Accept/reject=yes; no dispatch or approval.
- PROC: Procurement; All business locations. Supplier/material setup, POs and supplier invoices.
- FIN: Finance / Auditor; All business locations. Invoice exceptions, expenses and report submission.
- OPS: Department stock user (optional); UAT Dining; stock allowlist Kitchen. Request=yes; receiving/dispatch/approval=no.

## Balance checkpoints

Material | Unit | C0 Main | C1 Main | C1 Kitchen | C1 Bar | C2 Main | C2 Kitchen | C2 Bar
---|---|---|---|---|---|---|---|---
UATRICE|KG|100|80|13|0|90|13|0
UATCHICK|KG|40|30|6|0|30|6|0
UATTOM|KG|20|10|4|0|10|4|0
UATONION|KG|10|5|3|0|5|3|0
UATOIL|L|10|5|4|0|5|4|0
UATBOX|PCS|100|60|20|0|60|20|0
UATWATER|PCS|60|37|0|17|49|0|17
UATBASE|KG|0|0|6|0|0|6|0
UATPLATE|PCS|0|0|18|0|0|18|0

## 1 Setup

### SET-01 — ADMIN

Prerequisite: Access to deployed test environment.

Steps: Record the website URL, app version, tester and today's Lagos date D in Run details. Confirm migrations through 026 are applied and the updated code is deployed. Skip already-applied migrations; do not rerun 023. Use a fresh test restaurant with no existing stock or transactions.

Test data: D = your test date, on or before today; reporting currency NGN.

Expected: The intended app opens and Inventory Manager / Department access features are available. Existing production data is untouched.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SET-02 — ADMIN

Prerequisite: SET-01.

Steps: Create the owner account through Sign up, open its verification email, sign in and complete business setup. Choose Fine dining, NGN, one brand and one outlet named UAT Dining. Record the actual outlet code shown by the app.

Test data: Business: UAT Fine Dining; brand: UAT Kitchen; outlet: UAT Dining.

Expected: One restaurant workspace is created. Owner has CEO / Restaurant Administrator access. The outlet belongs to this restaurant.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SET-03 — ADMIN + all staff

Prerequisite: SET-02.

Steps: In Users & roles invite IM as Inventory Manager, KITCHEN and BAR as Department stock users, PROC as Procurement and FIN as Finance. Use separate verified accounts/profiles. OPS is an optional Department stock requester. STORE is only an operating alias for IM at Main Store: do not create a separate inventory staff account. Each invited user signs up with the exact email, verifies it, signs in and accepts the invitation into this restaurant.

Test data: Six core accounts including ADMIN; optional request-only/process delegates later; no passwords in the workbook.

Expected: All core users share this restaurant. There is one Inventory Manager, not a separate storekeeper/receiver for each inventory action. Department accounts can request and confirm their own transfers without being Inventory staff.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SET-04 — IM

Prerequisite: SET-03.

Steps: Sign in as Inventory Manager. Check the Inventory Manager workspace, Review stock requests, Manage department stock access and Deliveries & GRNs. Open Inventory & movements.

Test data: IM has only inventory_manager, All business locations.

Expected: Manager can open stock controls but has no supplier-invoice entry, expense entry or Users & roles authority.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SET-05 — PROC or ADMIN

Prerequisite: SET-03.

Steps: Open Materials & suppliers. Create supplier UATSUP and all nine items listed in Test data. Choose the exact base unit, item type and stock-tracked setting. Keep generated IDs and record the supplier's name.

Test data: Seven raw/packaging/resale items plus UATBASE and UATPLATE.

Expected: Nine active stock-tracked items exist in this restaurant. UATBASE is SEMI_FINISHED / KG and UATPLATE is FINISHED / PCS. No stock has been posted.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SET-06 — PROC or ADMIN

Prerequisite: SET-05.

Steps: Open Initial material prices. Enter the seven raw/packaging/resale reference prices from Test data, or edit and upload example-initial-prices.csv. Use D as the actual fictional test price date. Review the resolved items and units before confirming.

Test data: Rice 1800/KG; chicken 6000/KG; tomato 1000/KG; onion 800/KG; oil 2500/L; box 100/PCS; water 200/PCS.

Expected: Seven dated reference prices are saved. UATBASE/UATPLATE need no invented price for the raw-ingredient menu estimate. Quantities and stock balances stay unchanged.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SET-07 — IM

Prerequisite: SET-05.

Steps: Open Inventory & movements > Locations & routes. Add Main Store (STORE), Kitchen (KITCHEN) and Bar (BAR), all assigned to UAT Dining. Use codes UATMAIN, UATKIT and UATBAR. Enter department labels Stores, Kitchen and Bar.

Test data: Do not choose Central/shared for these three locations.

Expected: Three separate stock locations exist within the same outlet. A department name alone is not an access restriction.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SET-08 — IM

Prerequisite: SET-03 and SET-07.

Steps: IM opens Department access. Select KITCHEN, choose Selected stock locations only and Kitchen; enable Request stock and Accept / reject. Do the same for BAR at Bar. OPS, if used, gets Kitchen Request stock only. Do not enable dispatch, approval or arbitrary posting for department users. IM retains business-wide oversight; no STORE assignment is needed because STORE is IM.

Test data: KITCHEN / BAR role stock_department; IM role inventory_manager.

Expected: Department accounts see their assigned stock location and permitted request/receiving processes. They cannot approve, dispatch or post adjustments. Normal use requires no separate inventory-staff account.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SET-09 — IM

Prerequisite: SET-07.

Steps: In Locations & routes create Main Store > Kitchen and Main Store > Bar. Choose Department issue for both and Inventory Manager as Source approval role. Save each route. Also use Allow reverse / excess return on each forward route to permit Kitchen/Bar returns to Main Store.

Test data: Two active ISSUE routes; not TRANSFER.

Expected: Forward and reverse routes exist. The manager approves and dispatches; receiving departments accept or reject outgoing stock. The manager can accept department-originated returns at Main Store.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SET-10 — IM > ADMIN > IM

Prerequisite: SET-05 through SET-09.

Steps: IM (acting at Main Store) submits one Opening balance request with the seven opening lines. Because this is the manager's own request, ADMIN or another authorised reviewer approves it. IM then posts the quantities. Record the STK reference. This uses an existing owner/reviewer, not another inventory staff account.

Test data: Rice 100 KG; chicken 40 KG; tomato 20 KG; onion 10 KG; oil 10 L; boxes 100 PCS; water 60 PCS.

Expected: Requested and Approved stages do not affect stock. Only posting creates opening balances. Main Store matches checkpoint C0; Kitchen/Bar have no posted stock yet.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______


## 2 Recipes

### REC-01 — ADMIN (or business-wide Operations)

Prerequisite: SET-05 and SET-06.

Steps: Open Recipes & scaling. Create UATSAUCE as SUB_RECIPE, effective D. Enter tomato 6 KG, onion 2 KG and oil 1 L for the WHOLE batch; set measured output 8 KG. Publish and record the saved version number.

Test data: Do not enter per-serving quantities as batch inputs.

Expected: Recipe batch estimate is 10100; one KG is 1262.50. Publishing changes no inventory.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### REC-02 — ADMIN

Prerequisite: REC-01.

Steps: Create UATMEAL as FINAL, effective D. Add rice 4 KG, chicken 3 KG, the exact saved UATSAUCE version (quantity 2 KG) and meal boxes 20 PCS. Set batch output 20 PCS and publish. Record its version.

Test data: Use a child RECIPE component, not UATBASE as a raw item, for recipe costing.

Expected: Batch estimate 29725; estimated cost per serving 1486.25 including a box. Parent pins the chosen sub-recipe version. Inventory remains unchanged.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### REC-03 — ADMIN

Prerequisite: REC-02.

Steps: In Menu & prices create menu UATMENU for UAT Kitchen brand. Link the saved UATMEAL FINAL version with recipe quantity 1 PCS per sold serving. Add a TAKEAWAY price at UAT Dining, effective D, price 3500, tax NONE /0.

Test data: Fictional tax setting only; one sold item uses 1 PCS, not the full 20-PCS batch.

Expected: Menu item, recipe link and dated outlet/channel price are saved. No stock is consumed by menu setup.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### REC-04 — ADMIN or FIN

Prerequisite: REC-03.

Steps: Open Menu profitability. Select UAT Dining, TAKEAWAY, date D, and search UATMENU. Open the breakdown and compare its recipe version, quantity, ingredients and packaging with the source sheets.

Test data: Selling price 3500; serving cost 1486.25.

Expected: Food cost 42.46%; estimated food profit 2013.75 per serving; estimated food GP margin 57.54%. Contribution margin stays unavailable. Missing values must not become zero.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### REC-05 — IM

Prerequisite: REC-01 and REC-02.

Steps: Open Locations & routes > Link recipe stock output. Link the published UATSAUCE version to UATBASE, then the published UATMEAL version to UATPLATE. Use the actual version IDs displayed, not assumed version 1 if you republished.

Test data: UATBASE: SEMI_FINISHED/KG; UATPLATE: FINISHED/PCS.

Expected: Both bindings are visible under Recipe stock outputs. These bindings identify physical output stock; they do not create opening stock or change recipe cost.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______


## 3 Movements

### MOV-01 — KITCHEN or OPS

Prerequisite: SET-10 and REC-05.

Steps: Open Movements & requests > Request a stock movement. Choose Department issue and Main Store to Kitchen. Enter all six input lines shown here, date D and a requisition note. Confirm and Submit stock request. Record its STK reference.

Test data: Rice 20 KG; chicken 10 KG; tomato 10 KG; onion 5 KG; oil 5 L; boxes 40 PCS.

Expected: State Awaiting approval. Main Store remains C0; Kitchen is still empty. An unapproved request neither reserves nor transfers stock.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### MOV-02 — IM

Prerequisite: MOV-01.

Steps: Open Review stock requests, find the recorded STK reference and Review it. Check source, destination, quantities and requester. Choose Approve request, enter a decision note, tick confirmation and save.

Test data: No quantity edits during approval.

Expected: State Approved. Stock still matches C0. The manager is recorded as approver.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### MOV-03 — IM (STORE alias)

Prerequisite: MOV-02.

Steps: In the same manager session that approved the requisition, open the approved record and choose Confirm dispatch. Verify quantities, enter a note and confirm. Check Stock balances before the department accepts.

Test data: Dispatch the complete six-line request once.

Expected: State Awaiting acceptance. Main Store on-hand balances still equal C0 and Kitchen has no additions. Requested quantities are Reserved; Available shows the unreserved remainder. No dispatch ledger debit is created.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### MOV-04 — KITCHEN

Prerequisite: MOV-03.

Steps: Open the dispatched STK record. Choose Accept transfer. Confirm every accepted quantity equals the dispatched quantity. Enter the receiver note, tick confirmation and save. Open Stock balances.

Test data: Receive 20/10/10/5/5/40 in the six base units.

Expected: State Completed. Main now has rice 80, chicken 30, tomato 10, onion 5, oil 5, boxes 60, water 60. Kitchen has rice 20, chicken 10, tomato 10, onion 5, oil 5, boxes 40. Both sides post together on acceptance, and their reservations clear.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### MOV-05 — BAR > IM

Prerequisite: MOV-04.

Steps: BAR requests Department issue from Main Store to Bar for water 24 PCS. IM approves then confirms dispatch in the same manager session. Record the STK reference before acceptance.

Test data: Only UATWATER 24 PCS.

Expected: Main water remains 60 on hand, with 24 reserved and 36 available. Bar remains zero. State Awaiting acceptance.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### MOV-06 — BAR then IM

Prerequisite: MOV-05.

Steps: BAR chooses Accept transfer, accepts 23 and gives reason "1 excess bottle not accepted; returned to Main Store". Confirm. IM checks the Incomplete record and alert, physically verifies that the usable rejected bottle is back, then chooses Resolve follow-up with evidence.

Test data: Requested 24; accepted 23; rejected 1; no automatic transit loss.

Expected: Bar water 23 and Main water 37. Before resolution, the rejected 1 remains reserved at source. Resolution releases that reservation without changing either on-hand balance. The incomplete record and rejected reason remain in history.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### MOV-07 — KITCHEN > IM

Prerequisite: MOV-04 and REC-05.

Steps: KITCHEN submits Production batch at Kitchen: choose the bound UATSAUCE version, planned output 8 and actual usable output 8 in KG. IM reviews calculated input lines and approves. IM posts.

Test data: Consumes tomato 6, onion 2, oil 1; produces UATBASE 8 KG.

Expected: Kitchen tomato 4, onion 3, oil 4 and base 8. Rice/chicken/boxes unchanged. Input deductions and output addition happen together; no separate second raw-ingredient consumption.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### MOV-08 — KITCHEN > IM

Prerequisite: MOV-07.

Steps: Submit Production batch for the bound UATMEAL version at Kitchen. Planned output 20 PCS; actual usable output 18 PCS. IM reviews the saved input lines and approves; IM posts. Open its production detail.

Test data: Consumes rice 4, chicken 3, stored base 2 and boxes 20.

Expected: Kitchen rice 16, chicken 7, base 6, boxes 20, plates 18. Tomato 4/onion 3/oil 4 stay unchanged: child raw materials are not deducted again. Planned 20 versus actual 18 is retained.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### MOV-09 — KITCHEN > IM

Prerequisite: MOV-08.

Steps: Submit Department consumption at Kitchen for rice 2 KG with a usage reference. IM approves; IM posts. Check that you did not use Department issue for this action.

Test data: Only UATRICE 2 KG.

Expected: Kitchen rice 14. No Main Store or Bar balance changes. This is explicit consumption, separate from a transfer or production input deduction.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### MOV-10 — KITCHEN > IM

Prerequisite: MOV-09.

Steps: Submit Waste / spoilage at Kitchen for chicken 1 KG with reason 'Spoiled after preparation'. IM approves; IM posts.

Test data: Only UATCHICK 1 KG.

Expected: Kitchen chicken 6. The reason, requester, approver and stock deduction remain traceable.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### MOV-11 — BAR > IM

Prerequisite: MOV-06.

Steps: Submit Department consumption at Bar for water 5 PCS, get IM approval and post as IM.

Test data: UATWATER 5 PCS.

Expected: Bar water 18. The issue itself was not treated as usage; only this consumption deducts the five bottles.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### MOV-12 — BAR > IM

Prerequisite: MOV-11.

Steps: Submit Waste / spoilage at Bar for water 1 PCS with a breakage reason, get IM approval and post as IM.

Test data: UATWATER 1 PCS.

Expected: Bar water 17. Main Store water remains 37.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### MOV-13 — KITCHEN > IM

Prerequisite: MOV-09.

Steps: Submit Physical stock count at Kitchen for rice 13 KG. Stop moving stock at Kitchen until this count is approved and posted. IM approves; IM posts the physical count.

Test data: Book rice 14; physical rice 13.

Expected: Kitchen rice 13; ledger adjustment is minus 1, not minus 13. Unlisted materials are unchanged.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### MOV-14 — IM

Prerequisite: MOV-07 through MOV-13.

Steps: Filter Stock balances by each location, compare every material to C1 in Checkpoints, then inspect Stock ledger and movement references. Record the observed balances and any discrepancy before proceeding.

Test data: Checkpoint C1 (before supplier receipts).

Expected: Every listed C1 balance agrees; produced plates 18, base 6 and transit loss 1 are visible in their respective records. All approved happy-path requests are completed.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______


## 4 Purchasing

### BUY-01 — PROC

Prerequisite: MOV-14.

Steps: Open Purchase Orders & GRNs > Raise Purchase Order. Choose UATSUP and UAT Dining. Enter rice quantity 10 KG and unit cost 1800, discount 0, tax 0, EXCLUSIVE price basis and date D. Check the automatically calculated total and save draft.

Test data: Quote reference UAT-QUOTE-001; total 18000.

Expected: Total calculates to 18000 without manual multiplication. Draft is saved; no GRN, invoice or stock movement is created.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### BUY-02 — PROC

Prerequisite: BUY-01.

Steps: Review the draft, tick the issue confirmation and select Issue Purchase Order. Record the generated PO reference. Inspect its status and the Pending delivery filter.

Test data: One order for 10 KG rice.

Expected: PO is Issued / Pending delivery. Issued lines are fixed. Main Store rice is still 80.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### BUY-03 — STORE

Prerequisite: BUY-02.

Steps: Open that PO > Confirm delivery / GRN. Use received date D and delivery reference UAT-DN-001. Enter accepted 4 KG, rejected 1 KG and reason 'Damaged bag'. Confirm the physical delivery and generate the GRN. Record its GRN reference.

Test data: Only 4 KG is accepted; rejected 1 does not fulfil the order.

Expected: PO is Partially received; accepted 4, remaining 6. Main Store rice remains 80 until the explicit stock-posting step.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### BUY-04 — IM > ADMIN/FIN > IM

Prerequisite: BUY-03.

Steps: IM submits Post accepted GRN to stock, receiving location Main Store, selecting the new GRN. Review the generated lines. ADMIN/FIN approves the manager-originated request; IM posts. Do not type the accepted quantities manually as another receipt.

Test data: GRN1 accepted 4 KG.

Expected: Main Store rice 84. Exactly 4 enters stock; rejected 1 is excluded. This GRN cannot be selected for a second active stock request.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### BUY-05 — PROC

Prerequisite: BUY-04.

Steps: Open the PO and Record invoice against this PO. Enter supplier invoice UAT-INV-001 for all 10 KG at 1800, no discount/tax, total 18000, date D. Review and confirm the invoice; verify its line is mapped to the PO line.

Test data: Billed 10 while accepted delivery is currently 4.

Expected: Invoice exists without logging the user out. It needs Finance review because billed quantity exceeds accepted deliveries. Posting the bill adds no stock; Main rice stays 84.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### BUY-06 — FIN

Prerequisite: BUY-05.

Steps: Open the invoice and its matching panel. Review billed 10 versus accepted 4 and the evidence. Choose the Finance decision that acknowledges the current exceptions, enter a reason, confirm and Save Finance exception review.

Test data: Explain that final delivery is still outstanding.

Expected: Current exceptions are marked reviewed by Finance, not removed. The decision is not payment or proof of receiving. Stock and PO quantities do not change.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### BUY-07 — STORE

Prerequisite: BUY-06.

Steps: On the same PO create a second GRN, delivery reference UAT-DN-002, date D, accepted 6 KG, rejected 0. Record its GRN reference and open the Completed PO filter.

Test data: Second accepted delivery 6 KG.

Expected: PO receiving status becomes Completed: total accepted 10, remaining 0. Main rice remains 84 until GRN2 is posted to stock. Completed does not mean paid.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### BUY-08 — IM > ADMIN/FIN > IM

Prerequisite: BUY-07.

Steps: Post the second accepted GRN through stock request > ADMIN/FIN approval > IM posting. FIN refreshes invoice matching and reviews its current source quantities.

Test data: GRN2 accepted 6 KG.

Expected: Main rice 90. Billed 10 matches accepted 10 and invoice has no remaining quantity exception in this example. The earlier Finance review no longer substitutes for the changed source state.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### BUY-09 — IM > ADMIN/FIN > IM

Prerequisite: BUY-08.

Steps: Submit Direct supplier receipt into Main Store for water 12 PCS, supplier UATSUP, unique delivery reference UAT-DIRECT-001 and a source/reason note. ADMIN/FIN approves the manager-originated request; IM posts.

Test data: This separate delivery has NO GRN.

Expected: Main water 49. Stock receipt is recorded once and does not manufacture a supplier invoice. Do not also post a GRN for this delivery.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### BUY-10 — PROC then FIN

Prerequisite: BUY-09.

Steps: PROC records supplier invoice UAT-INV-002 without a PO for water 12 at 200, total 2400, date D. Enter the no-PO reason and delivery-evidence reference UAT-DIRECT-001. FIN reviews its no-PO exception.

Test data: DIRECT route, total 2400; separate from UAT-INV-001.

Expected: Invoice and evidence are retained; Finance review remains explicit. No additional water enters stock. Invoice totals across the two baseline invoices are 20400; prices do not automatically update reference prices.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### BUY-11 — IM

Prerequisite: BUY-10.

Steps: Compare every stock balance with C2 and both invoices with their source notes. Check all PO filters, recorded GRNs and Main Store ledger entries.

Test data: Checkpoint C2.

Expected: Main rice 90 and water 49; all other C1 balances unchanged. Invoice entry, physical receiving and stock posting remain distinct.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______


## 5 Finance

### FIN-01 — ADMIN

Prerequisite: REC-03 and BUY-11.

Steps: Edit example-sales.csv: replace TEST_DATE with D and LOCATION_CODE_HERE with the actual outlet code. In Sales & summary > Import sales choose source organisation code UAT_ORG and tax format Gross_Sales and Net_Sales both exclude tax. Upload, review mappings and receipt total 10500, then confirm.

Test data: UAT-SALE-001; UATMENU3 servings at 3500; no tax/discount.

Expected: One paid receipt records net sales 10500 and quantity 3. Sales do not automatically deduct physical UATPLATE stock: Kitchen plates remain 18.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### FIN-02 — FIN or ADMIN

Prerequisite: FIN-01.

Steps: Review Sales & summary and executive overview for D, UAT Dining. Compare the linked recipe, imported revenue and food estimate. Reopen Menu profitability for TAKEAWAY / D.

Test data: Reference recipe serving cost 1486.25.

Expected: Estimated food cost 4458.75; estimated food margin 6041.25; food margin 57.54%. Menu serving cost stays 1486.25 despite actual production yield 18. This is reference-price costing, not actual inventory COGS.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### FIN-03 — FIN

Prerequisite: FIN-01.

Steps: Edit example-expenses.csv date/outlet placeholders. In Labour & expenses > Add expenses > CSV import, use source organisation UAT_ORG; review the two category codes and total 1500 before confirming. Use existing WAGES and RENT categories, both LOCATION / ON_DATE at D.

Test data: WAGES1000 and RENT500, same outlet/date/currency.

Expected: Two expenses total 1500. Labour 1000 and operating cost 500 remain distinct; payment dates do not change recognition dates. No material quantity changes.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### FIN-04 — FIN

Prerequisite: FIN-03.

Steps: Review and confirm the app's labour/expense coverage for D and UAT Dining, honestly based on the two complete fictional entries. Open the management report for that same scope and date.

Test data: Labour 1000; estimated food cost 4458.75.

Expected: After required coverage reviews, estimated prime cost 5458.75, about 51.99% of net sales. Missing reviews/inputs stay flagged until completed. Operating/accounting profit is not invented.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### FIN-05 — FIN

Prerequisite: FIN-04.

Steps: Save a named report UAT Dining D baseline. Open its saved copy and submit it for management review with a note.

Test data: Record the saved report reference.

Expected: The named figures and basis are preserved; Finance submission is recorded. Saving/submitting changes no source transaction or stock quantity.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### FIN-06 — ADMIN acting as CEO

Prerequisite: FIN-05.

Steps: Open the submitted saved report. Review its context and approve with the required acknowledgement and note. Reopen the report as FIN.

Test data: Use the owner account's CEO/Administrator authority, not IM.

Expected: Management approval and decision identity are visible. This is management approval of estimates, not accounting period close or payment.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### FIN-07 — FIN

Prerequisite: FIN-06.

Steps: Download report CSV and use Print / save PDF. Open each output, check restaurant/date/outlet/currency, figures, coverage notes and saved-review status where provided.

Test data: Expected net sales 10500, food cost 4458.75, labour 1000, operating cost 500.

Expected: Outputs open and match the report, with the estimate basis retained. No unexpected formula execution in CSV text fields.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### FIN-08 — ADMIN / FIN

Prerequisite: FIN-03.

Steps: Upload exactly the same sales CSV and exactly the same expense CSV once more with the same source and record identifiers. Review the duplicate findings before confirming any allowed skip.

Test data: Stable UAT-SALE-001, UAT-WAGES-001, UAT-RENT-001.

Expected: Duplicate economic records are skipped or blocked; no second sale/expense is created. Totals remain 10500 sales and 1500 expenses. Do not change reference IDs to force an import.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______


## 6 Access

### ACC-01 — KITCHEN and BAR

Prerequisite: BUY-11.

Steps: In separate profiles open Stock balances and the Stock location filter. KITCHEN must see Kitchen balances; BAR must see Bar balances. Try another department's saved filtered inventory URL and an unrelated movement URL copied by IM.

Test data: Kitchen must not access Main Store > Bar; Bar must not access Main Store > Kitchen.

Expected: Unauthorised balances, ledger rows and unrelated movement details are absent or restricted. A permitted route may reveal its other endpoint's name, never that endpoint's private balances.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### ACC-02 — KITCHEN / BAR

Prerequisite: SET-09.

Steps: Open a Department issue request. Inspect permitted routes as each department. Attempt to select or submit the other department's route without changing permissions.

Test data: Kitchen: Main Store to Kitchen; Bar: Main Store to Bar.

Expected: Only permitted requests can be initiated. No cross-department request is posted by guessing or sharing a URL.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### ACC-03 — OPS (optional Department requester)

Prerequisite: SET-08.

Steps: Sign in with a Department stock user restricted to Kitchen Request stock only. Review Kitchen data and submit a harmless request. Try to approve, dispatch, accept stock or post a quantity adjustment. IM cancels the test request without posting.

Test data: No Inventory, receiver, dispatcher or management role.

Expected: Request-only access works within Kitchen. The account cannot approve, dispatch, receive or post. Adding a checkbox cannot exceed the underlying process role.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### ACC-04 — IM

Prerequisite: SET-03.

Steps: Try to open supplier-invoice entry, Labour & expenses entry and Users & roles from copied URLs. Verify stock configuration, Department access and stock approvals remain available.

Test data: IM has no additional Finance/Procurement/Admin role.

Expected: Stock oversight works; financial entry and general role administration remain restricted. IM cannot grant themselves a Restaurant Administrator role.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### ACC-05 — PROC

Prerequisite: SET-03.

Steps: Check PO preparation and invoice entry. Try to open an unposted delivery and confirm its GRN or dispatch stock while holding only Procurement.

Test data: No Inventory or Inventory Manager role on PROC.

Expected: Procurement can buy and bill, but cannot perform physical receiving/handling solely because they raised the PO.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### ACC-06 — FIN

Prerequisite: SET-03.

Steps: Inspect stock and invoices. Try Department access and Locations & routes configuration, PO creation, supplier-invoice entry and stock dispatch.

Test data: FIN holds only Finance.

Expected: Finance can review permitted stock/invoices and financial corrections. It cannot configure departments, prepare purchases or physically dispatch stock. Existing non-route stock-approval fallback remains available.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### ACC-07 — IM then KITCHEN

Prerequisite: Baseline C2 recorded.

Steps: IM sets KITCHEN to Request=no and Accept / reject=yes at Kitchen. Refresh KITCHEN and try initiating a new request. Restore Request=yes afterwards.

Test data: Do not post any extra movement.

Expected: No new request can be initiated, but the department can still accept/reject an authorised incoming transfer. Request and receiving permissions are independent.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### ACC-08 — IM then KITCHEN

Prerequisite: ACC-07; record C2 first.

Steps: After recording C2, use a separate small Kitchen transfer request. IM approves/dispatches it. Remove KITCHEN Accept / reject while its incoming record is open. Attempt acceptance/rejection, restore permission, then have Kitchen reject and IM resolve the physically returned quantity.

Test data: A temporary requisition after baseline; do not post a count as a department user.

Expected: Revocation blocks both acceptance and rejection immediately, including through an old tab. Restoring permission permits the intended decision. Rejection changes no on-hand balances; resolution clears the reservation.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### ACC-09 — IM then KITCHEN

Prerequisite: C2 recorded.

Steps: Save Selected stock locations only with no checked locations for KITCHEN. Refresh KITCHEN's balances, ledger and movements screens. Then restore Kitchen with Request and Handle enabled.

Test data: Never restore Existing outlet access by accident.

Expected: No department stock balance/ledger/request form remains while the allowlist is empty. Restoration grants Kitchen only. Shared catalogue and existing PO/GRN permissions still follow their own module roles.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### ACC-10 — ADMIN and BAR

Prerequisite: C2 recorded; use a staff account, not owner.

Steps: Deactivate BAR through Users & roles while its other profile is signed in. Try a new protected read/action, then restore the active member with the original outlet Department stock user role and check its department assignment.

Test data: Keep a record of the original roles and stock assignments.

Expected: Inactive membership loses business access. Reactivation does not silently expand the saved Bar allowlist. Historical stock remains intact.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### ACC-11 — ADMIN / authorised technical tester

Prerequisite: Optional second separate test restaurant.

Steps: Sign into a different restaurant account in a separate profile and try copied inventory, PO, invoice and report URLs from this test restaurant. Do not grant cross-business membership for this test.

Test data: Use a second isolated test tenant.

Expected: No other-restaurant balances, records or updates are accessible. If no second tenant exists, mark Blocked, not Passed.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### ACC-12 — ADMIN

Prerequisite: Any staff invitation test.

Steps: For a disposable invitation, try opening it with the wrong verified email. Then retry with the invited email. Also sign out and verify a protected workspace URL redirects to sign-in.

Test data: Do not use another person's password.

Expected: Wrong-email invitation acceptance is rejected; intended verified email succeeds. Anonymous users cannot use protected stock pages.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### ACC-13 — ADMIN and IM

Prerequisite: Optional delegation accounts if needed.

Steps: Create optional Stock receiver and Stock dispatcher accounts. IM assigns only receiving at one location to the receiver and only dispatch at a source to the dispatcher. Attempt approval, arbitrary posting, other-process actions and financial access with each.

Test data: Optional; mark Not applicable with a reason if no delegation is planned.

Expected: Receiver can accept/reject assigned incoming stock, dispatcher can dispatch approved requests, and neither receives management or financial powers.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______


## 7 Guardrails

### SAFE-01 — IM then ADMIN

Prerequisite: C2 recorded; separate disposable request.

Steps: IM creates a harmless count request and tries to approve their own request. Confirm it is blocked. ADMIN cancels the unposted request. Also confirm that the same manager CAN approve and dispatch a department-created requisition; no second inventory account is required.

Test data: No extra quantity posting.

Expected: Own-request approval is blocked. Approval plus dispatch by the same manager on a department-created request is allowed. No extra quantity posting occurs.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SAFE-02 — IM and KITCHEN

Prerequisite: Disposable scenario after C2; record references.

Steps: Use a separate small Main Store to Kitchen request after C2. IM approves and dispatches, then tries to accept it as though they were Kitchen. Kitchen must decide it. Afterwards test a Kitchen-originated reverse request: IM may approve/dispatch and separately accept it at Main Store, with the return decision recorded.

Test data: This case may change quantities: log them separately from the baseline.

Expected: The manager cannot receive their own outbound dispatch into Kitchen/Bar. A department-originated return to Main Store is the explicit supported manager handoff; its audit records that exception. Log any extra accepted quantities separately.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SAFE-03 — KITCHEN > IM

Prerequisite: C2 recorded.

Steps: Submit consumption for 999 KG rice at Kitchen. IM may approve the request for this negative test; IM tries to post. Confirm the refusal, then IM cancels the unposted request.

Test data: Kitchen has 13 KG, not 999.

Expected: Insufficient stock blocks the entire posting. Rice remains 13 and no partial ledger entries are created.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SAFE-04 — KITCHEN > IM

Prerequisite: After C2; controlled adjustment test.

Steps: Submit a Kitchen physical count and leave it pending. Post a separately approved real test movement at Kitchen. Try posting the old count; it must be rejected. Cancel it and recount. Record the extra movement and expected revised balances separately.

Test data: Any intervening ledger movement at Kitchen makes the count stale.

Expected: Old count cannot overwrite newer stock. No claim of unchanged C2 after the extra test movement.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SAFE-05 — STORE

Prerequisite: BUY-04 or BUY-08 completed.

Steps: Try to select either baseline GRN for another stock request, or reopen its completed stock request and post again. Do not create a new manual direct receipt to bypass the duplicate guard.

Test data: Already-posted GRN references.

Expected: A GRN cannot create another active stock document, and repeated posting cannot add stock twice.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SAFE-06 — STORE

Prerequisite: BUY-09 completed.

Steps: Try a new Direct supplier receipt with UATSUP and delivery reference UAT-DIRECT-001 (also try different letter case). Submit without changing the source identity.

Test data: Same supplier and delivery reference.

Expected: Duplicate supplier delivery reference is rejected. Main Store water is not increased again.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SAFE-07 — STORE

Prerequisite: SET-10 completed.

Steps: Try another Opening balance for rice at Main Store. Do not use a new material code to evade the check. Cancel any harmless request left pending.

Test data: Rice already has posted movements.

Expected: Repeated opening stock for the same material/location is rejected. Corrections use reviewed counts, not a second opening.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SAFE-08 — STORE then FIN

Prerequisite: A baseline GRN has posted stock.

Steps: Request a Finance-reviewed void for the already stock-posted GRN. FIN attempts approval, verifies the block, and rejects the void request with a note so it does not remain pending.

Test data: Use the baseline source GRN; do not alter its quantities.

Expected: Posted stock cannot lose its source through a GRN void. Use reviewed physical/invoice corrections separately. Rejecting the test void restores the original GRN's normal review state.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SAFE-09 — IM

Prerequisite: After C2.

Steps: Try to deactivate a stock location that still holds stock or has a pending movement. For an unrelated empty disposable route, deactivate it and try initiating/dispatching a request through it; reactivate afterward.

Test data: Do not deactivate a live baseline route before happy-path completion.

Expected: A location with stock/pending work cannot be deactivated. An inactive route blocks new requests/dispatches; historical records remain.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SAFE-10 — IM in two browser profiles

Prerequisite: Both profiles open the SAME staff assignment revision.

Steps: In profile A change and save a disposable permission. In the already-open profile B submit a different change without refreshing. Record the stale-edit error. Refresh B, inspect the saved settings and restore the intended assignment.

Test data: Same member; two open editors.

Expected: A stale editor cannot overwrite another save. The current revision must be reviewed first.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SAFE-11 — ADMIN

Prerequisite: Recipe baseline completed; no new production.

Steps: Publish a new version of UATSAUCE after changing a component quantity. Do not edit the UATMEAL/menu bindings. Reopen the old parent and menu breakdown. Do not produce the new version during this test.

Test data: Record actual new version; keep parent pinned to its old child.

Expected: Existing parent/menu still reference their original saved versions. Publishing a new child does not silently rewrite them or create stock.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SAFE-12 — IM / KITCHEN

Prerequisite: After C2; disposable requests.

Steps: Try a negative quantity, a future movement date and a date before a later posted movement for the same material/location. If a request can be staged, check posting validation and cancel it afterward. Also try a production batch exceeding available ingredients.

Test data: Do not post an actual extra batch.

Expected: Invalid quantities/dates or insufficient inputs cannot create a partial posting. Future dates are refused. Backdating behind later ledger activity is blocked when posting.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SAFE-13 — Receiving department

Prerequisite: After C2.

Steps: Create a separate small transfer, have IM approve and dispatch, and record both balances before receipt. Receiver chooses Reject transfer with a reason. IM verifies the goods physically returned, then resolves the follow-up.

Test data: No automatic waste/loss.

Expected: On-hand balances never change. The rejected quantity stays reserved until physical-return resolution; a rejection alert appears and clears after resolution.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SAFE-14 — Receiving department and IM

Prerequisite: After C2.

Steps: Create a separate 2-unit transfer. Dispatch as IM, then accept 1 with a reason for rejecting 1. Inspect both ledgers, reserves and Incomplete filter. IM verifies return of the rejected 1 and resolves.

Test data: Track this extra accepted 1 separately from C2.

Expected: Only 1 is deducted from source and added to destination; rejected 1 is not depleted or added. Its reservation remains until resolved. No automatic transit loss is created.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SAFE-15 — KITCHEN > IM

Prerequisite: Reverse route configured; after C2.

Steps: Kitchen submits an excess return of 1 unit to Main Store. IM approves and authorises dispatch. Confirm both balances stay unchanged, then IM accepts the department-originated return at Main Store.

Test data: Department stock user creates the return; manager accepts at Main Store.

Expected: Kitchen decreases 1 and Main Store increases 1 only on acceptance. No separate inventory staff account is required. The manager-return decision is audited.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### SAFE-16 — IM and receiving department

Prerequisite: After C2.

Steps: Dispatch a transfer that reserves most available stock. Try another dispatch or consumption that would use the held stock. Try a physical count while the first transfer is awaiting acceptance. Have the receiver reject and IM verify physical return/resolve before reusing it.

Test data: Do not actually over-allocate stock.

Expected: Reservations block competing allocation and consumption; physical counts cannot overwrite unresolved transfer state. Stock becomes available only after acceptance or verified return resolution.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______


## 8 Usability

### UX-01 — IM / STORE / KITCHEN / BAR / FIN

Prerequisite: Any populated tables.

Steps: Open stock balances, movement register, ledger, stock locations/routes, POs/GRNs and supplier invoices as the roles allowed to view them. Check headers, row spacing, status badges and readable action links.

Test data: Desktop and a phone-sized viewport.

Expected: Tables use the shared layout. On a phone, horizontal scrolling stays inside each table; the page itself does not overflow. Roles without a module cannot open it.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### UX-02 — IM

Prerequisite: Populated movement register.

Steps: Filter by Main Store, Kitchen and Bar. Open a record, close it, then change pages if more than 10 records exist. Open the ledger and check its stated 100-entry display limit.

Test data: If fewer than 11 records, mark the extra-page sub-check Not applicable; test each requisition status filter..

Expected: Filters preserve the correct organisation and location; records remain consistent. The ledger does not pretend its latest 100 rows are a full export.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### UX-03 — All roles

Prerequisite: A completed record.

Steps: Refresh a completed record, navigate away/back and sign out/sign in again. Verify status and quantities. If a save encounters a connection error, refresh the register before deciding to retry; keep the same source reference.

Test data: Never create a different reference just to force a retry.

Expected: Saved state persists. Refresh/retry does not duplicate postings or log the user out unexpectedly.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### UX-04 — Test lead

Prerequisite: All applicable cases completed.

Steps: Review every Not run, Failed and Blocked result. Attach issue IDs and evidence, retest fixes, then fill Sign-off. Record which guardrail tests changed the baseline and the final reconciled balances.

Test data: Release decision is manual, not a calculated approval.

Expected: No critical access, duplication, negative-stock or reconciliation failure remains unresolved before real restaurant data is loaded.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### UX-05 — IM

Prerequisite: Populated requisition register.

Steps: Use Pending, Awaiting acceptance, Completed, Incomplete, Rejected and Cancelled filters, then search an exact reference. Verify the total and page count against the matching scoped records.

Test data: Filters must apply before pagination.

Expected: Only matching records appear, totals stay correct across pages, and alert links open their exact authorised record even when it is not on the first page.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### UX-06 — IM and department

Prerequisite: A new department requisition.

Steps: Check the manager workspace for Approval needed. Approve and dispatch; check the receiving department workspace for Accept or reject incoming stock. Partially accept/reject and inspect follow-up alerts. Finish or resolve with evidence.

Test data: Leave the visible workspace open up to 30 seconds or refresh.

Expected: Relevant action alerts update for the right accounts, with no unrelated department data. Resolved work drops out. Items older than 24 hours are labelled; no email/SMS is implied.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______

### UX-07 — All testers

Prerequisite: Desktop and mobile browser.

Steps: Review the updated homepage and its stock handoff explanation. Open Sign in and Sign up; check readable labels, password visibility, keyboard focus, back link and narrow-screen layout. Open populated stock records and verify compact rows and 10-row pagination.

Test data: Do not alter another account's credentials.

Expected: Pages are readable, keyboard-accessible and do not overflow the viewport. Authentication/invitation flows still work; tables retain readable numeric columns without excessive row height.

Result: Not run | Actual: ______ | Tester/date: ______ | Record/issue: ______
