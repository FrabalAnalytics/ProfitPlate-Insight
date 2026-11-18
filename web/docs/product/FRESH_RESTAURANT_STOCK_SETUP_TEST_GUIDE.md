# Fresh restaurant: stock setup and daily accountability

Use a separate training restaurant. Keep the existing demo restaurant and its historical records. Automated tests create an isolated training restaurant locally; they do not create or change a live Supabase restaurant.

## Before using this release

Apply migration `supabase/migrations/202611180037_guided_stock_setup_and_named_teams.sql` after migrations 001-036, then deploy the matching app. This migration does not reset records or deactivate restaurants. Existing processing definitions and historic batches remain available. Restaurants with older processing settings must explicitly designate their processing unit; no centre is selected automatically.

## 1. Create the training restaurant

1. Use a fresh owner account and confirm its email.
2. Sign in and complete restaurant onboarding: Training Restaurant, Nigeria, NGN, restaurant concept, brand, outlet and Africa/Lagos timezone.
3. Choose the actual reporting week, stock-count day and cutoff time. Do not copy an example schedule unless it matches the restaurant.
4. Create the workspace. Existing material, supplier, recipe, menu, reporting and opening-stock setup remains available.
5. Open My workspace, expand **Set the name shown in your workspace**, enter your name and save. Expect a greeting using that name and the restaurant timezone.

## 2. Add named users

1. Open **Users & roles**, then **Invite colleague**.
2. Enter **Emeka**, his email and role **Inventory Manager**. Review permissions and create the invitation. Copy the link and share it manually; the app does not send an invitation email.
3. Repeat for **Ada**, role **Kitchen Manager**. Add **Bola**, role **Bar Lead**, if testing a Bar centre.
4. Each person signs into their verified invited email, opens their invitation link and accepts.
5. Confirm the team table shows their names and assigned roles. Use Edit name to correct an existing colleague's name. Changing a name grants no permissions.
6. Kitchen Manager and Bar Lead start with no stock centres. They cannot approve, dispatch, post stock, view financial costs or administer the team merely because of their role.
7. Operations Manager remains available. Custom roles are deferred; do not use an unrelated broader role as a substitute for a missing job title.

## 3. Define stock centres and choose the processing unit

1. Open **Data & Setup > Stock centres & responsibilities**.
2. Add `MAIN_STORE`, name **Main Store**, type **Main store**, responsible member **Emeka / Inventory Manager**.
3. Add `KITCHEN`, name **Kitchen**, type **Kitchen**, responsible member **Ada / Kitchen Manager**. Assign the appropriate outlet when it belongs to one outlet.
4. Add Bar or other actual centres as required. Every centre needs a responsible user; a job title alone is insufficient.
5. Under **Choose the business processing unit**, choose **Kitchen**, then **Save processing unit**. For a restaurant processing at Main Store, select Main Store instead.
6. Check only that centre is labelled Processing unit. Each centre has its own ledger, balances and waste records.
7. Open **Stock process permissions**. Choose Ada, Selected stock locations only, allow Kitchen, enable Request stock and Accept/reject, then confirm and save. Give Bola only Bar access when applicable.
8. Configure Main Store -> Kitchen transfer and the reverse transfer for excess returns in Inventory & movements > Locations & routes. Inventory Manager remains the source approver/dispatcher. Responsible ownership does not automatically grant process permissions.

## 4. Create the input and output materials

In **Materials & suppliers**, create:

| Setting | Input | Output |
| --- | --- | --- |
| Code | WHOLE_SNAPPER | SNAPPER_CUT |
| Name | Whole Snapper Fish | Snapper Cut |
| Type | Raw material | Semi-finished |
| Base unit | KG | PCS |
| Stock tracking | Yes | Yes |
| Supply source | Purchased | Processed |
| Requires processing | Yes | No, unless it undergoes another transformation |

Requires processing describes an input that undergoes transformation. Supply source Processed describes a SKU made by the restaurant. They are separate settings. Set the material's outlet scope as appropriate.

Enter a starting reference price for whole snapper, for example NGN 3,000 per KG. Do not enter a separate purchase price for a Processed-only Snapper Cut SKU. Its estimate comes from its baseline recipe. Posted invoices later update monthly quantity-weighted material prices.

## 5. Establish the processing baseline

1. Open **Data & Setup > Processed material setup**.
2. In **Material processing baseline**, enter code `SNAPPER_CUTTING`, name **Snapper cutting**.
3. Select Whole Snapper Fish, input **40 KG**.
4. Select Snapper Cut, expected output **120 PCS**.
5. Enter the approved cut specification, effective date and acceptable output variance percentage (use 0 for this exact training comparison).
6. Leave optional piece weights and trim blank unless measured and agreed. Never invent weight per piece.
7. Save. The system publishes the versioned processing recipe, links the output SKU and saves the baseline in one transaction. You do not need to perform those technical steps separately.
8. Expect 40 KG -> 120 PCS at Kitchen and estimated output cost **NGN 1,000 per PCS** when the input reference price is NGN 3,000/KG.
9. Existing processing recipes still have an expandable section for linking outputs or saving revised baselines. Existing recipe/sub-recipe setup is retained, including processes with multiple inputs.

If the output is missing, ensure it is active, stock tracked, Semi-finished/Finished, has a base unit and supply source Processed/Both. If the input is missing, check active, stock tracking, base unit and Requires processing = Yes.

## 6. Establish starting stock and transfer it

1. Inventory Manager requests an opening balance of 40 KG whole snapper at Main Store with a count-sheet reference.
2. A different authorised colleague approves it. Inventory Manager posts it. Expect Main Store 40 KG, Kitchen 0 KG.
3. Ada requests 40 KG from Main Store to Kitchen.
4. Inventory Manager approves and dispatches. Expect on-hand quantities still 40 KG and 0 KG, with the source quantity reserved.
5. Ada accepts all 40 KG. Only now expect Main Store 0 KG and Kitchen 40 KG.
6. Rejected/partially accepted transfers require reasons; unresolved rejected stock remains reserved pending follow-up. Do not process stock before receipt acceptance.

## 7. Record daily material processing

1. Ada opens **Daily operations > Material Processing Log > Record material processing**.
2. Choose Kitchen and the approved Snapper cutting baseline. The produced SKU should auto-fill as Snapper Cut (PCS).
3. Enter measured actual input **40 KG**, usable output **110 PCS**, and measured usable output weight **36 KG**.
4. Add measured waste **4 KG of Whole Snapper Fish**, reason **Measured trim**. This is part of the 40 KG consumed, not another deduction.
5. Explain the output shortage and enter the batch reference. Confirm the measured waste and submit.
6. Before posting, confirm Kitchen still has 40 KG whole fish and no new cut pieces from this batch.
7. Inventory Manager reviews and approves Ada's request, then posts it. A requester cannot approve their own request.
8. Expect Kitchen whole fish **0 KG**, Snapper Cut **110 PCS**. Raw deduction and output addition must succeed or fail together.
9. In the processing log expect:
   - Expected output: 120 PCS; actual output: 110 PCS.
   - Baseline achieved: 91.67%; output variance: -8.33%.
   - Usable weight yield: 90.00% (36 / 40).
   - Recorded waste: 10.00% (4 / 40).
   - No unexplained input weight for these measurements.
10. Do not create another waste entry for this 4 KG of trim. Combined waste reporting includes it once, marked Included in production inputs.

KG input and PCS output alone cannot establish a weight-yield percentage. Without measured usable weight the screen must say Usable weight needed, while still showing baseline achievement. Actual batch unit-cost estimates reflect the actual output; standard SKU estimates remain based on the approved baseline and current input cost.

## 8. Record a loss outside processing

1. Ada opens **Waste Log > Record waste**.
2. Choose Kitchen, Snapper Cut, quantity **2 PCS**, category **Spoilage**, and explain the loss.
3. Submit. Inventory Manager approves and posts.
4. Expect Kitchen cut stock **108 PCS**. Main Store and other centres remain unchanged.
5. Waste Log shows this independent 2 PCS loss. The earlier 4 KG processing trim stays inside its processing batch.
6. **Combined waste report** shows both records with their units and stock treatment. Do not add KG and PCS into one quantity total.
7. Test expiry, damage, bad production and another loss with their own explanations when needed.

## 9. Access and change checks

- Ada sees Kitchen records and incoming tasks, not Main Store/Bar private records or financial costs.
- Emeka sees stock review/posting tasks and the relevant request counts.
- Finance/CEO financial permissions remain separate; CEO workspace stays focused on profitability and accountability exceptions.
- A batch with insufficient input stock must fail completely with no output added.
- A batch outside tolerance requires an explanation. Waste cannot exceed the consumed input.
- Changing the processing unit is blocked while processing requests are pending. Finish/cancel them first. Changing the unit never relocates existing stock or rewrites history. Save/review baselines for the new unit explicitly.
- Reassign owned active centres before deactivating their responsible user once designated-unit setup is in use.
- Existing unassigned legacy centres must be completed before selecting a processing unit. No existing owner or location is guessed automatically.

## Verification included in this release

The isolated database test builds a fresh restaurant from onboarding, accepts named role invitations, configures centres and access, derives processed cost, confirms a transfer, posts processing and independent waste, and verifies ledger balances, historical evidence, retry safety and access restrictions. Browser tests exercise named invitations, greetings, centre setup, material flags, guided baseline creation, daily processing and waste entry, with mobile overflow checks.
