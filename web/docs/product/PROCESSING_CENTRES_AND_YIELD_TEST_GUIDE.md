# Stock centres, processing standards and yield control

Apply migration `202611180036_processing_centres_and_yield.sql` once after 035, then deploy the matching app. Existing stock, receipts, transfers, recipe links and production history are preserved. Existing centres start with processing disabled until deliberately configured. New production requests require an approved standard and measured inputs. Old pending production records retain their original evidence and existing stock controls.

## Setup order

Use the Owner/Restaurant Administrator account for initial setup. The Inventory Manager can also manage centres, processing links and standards without receiving financial permissions automatically.

1. Open **Data & Setup > Stock centres & responsibilities**.
2. Add the actual storage/working places: for example Main Store, Central Kitchen, Kitchen and Bar. Give each a unique code and a readable name.
3. Choose the storage type and outlet assignment. A central/shared centre is not a sales outlet; it can serve several outlets. A central kitchen may also be shared.
4. Assign its responsible member. This records accountability; it does not grant that person new stock permissions. Use **Users & roles** and **Inventory > Department access** to configure actual request/receive/dispatch permissions.
5. Tick **Allow material processing at this centre** only where processing happens. A warehouse can process fish; a kitchen can also process fish. The storage type alone does not determine this.
6. Save. Each centre row links to its ledger, production history and waste log. Existing centres can be edited to add responsibility and enable processing. Centres with movement history retain their outlet and storage type.
7. Complete material master data, opening balances/confirmed receipts, and movement routes using the existing setup screens. Missing opening stock is not automatically zero.

## Fixing an empty produced-material dropdown

Open **Data & Setup > Processed material setup**. Choose the published recipe, then search for the output material by name or code.

The search includes materials that are not yet eligible. Disabled options explain the problem. Open **Why some materials cannot be selected** to follow a correction link.

For **Snapper Cut**, check:

- Active material.
- Stock tracking enabled.
- Material type **Semi-finished** or **Finished**. Supply source **Processed** by itself does not make the item eligible.
- Base unit **PCS**, matching a count-based recipe output. A missing base unit can be completed. An established incompatible base unit requires a new SKU with the correct unit so old records are not reinterpreted.

Select **Processed Snapper Fish**, select **Snapper Cut**, then click **Link recipe stock output**. Its standard estimated unit cost comes from that recipe's inputs. Linking changes no stock.

## Establish the 40 KG to 120 PCS baseline

On the same page, open **Save processing baseline & permitted centres**:

1. Select the linked recipe version containing 40 KG whole snapper and a 120 PCS yield.
2. Choose whole snapper as **Main input for scaling expected yield**. The saved recipe provides the baseline quantities; change those by publishing a new recipe version rather than changing an old batch.
3. Describe the approved cut size/grade. This matters because 120 larger/smaller pieces are not an equivalent output.
4. Enter the output variance tolerance deliberately: **0** means every deviation needs an explanation. No default tolerance is imposed.
5. If measured and approved, enter target piece weight and expected trim weight in KG. Leave genuinely unknown weights blank. Forty KG yielding 120 pieces alone does not establish cut weight or waste weight.
6. Select every centre permitted to run this process, such as Main Store and Kitchen. A centre must be active, processing enabled and have an active responsible member.
7. Save. A standard revision is retained. A later revision or newly approved recipe version becomes the current standard for that recipe family; old batches retain their pinned standard.

## Record actual processing

The Inventory Manager records/post batches. A department user with request permission may record its department batch; the Inventory Manager can review and post it. Existing separate-review rules remain: the requester cannot approve their own production request.

1. Ensure input stock is physically available at the processing centre. If it comes from another centre, finish the transfer and destination acceptance first.
2. Open **Inventory & movements > Movements & requests**, choose **Production batch**, then choose **Processing centre** and **Processing standard**. The setup page also links directly to the production form.
3. Enter the actual quantity of every input taken into the process, in its base unit. Include the material that later becomes trim/waste in this total. Record explicit zero for an unused secondary input; main input must be positive.
4. Enter measured usable output in the produced SKU's base unit, such as PCS. Optionally record its measured total weight in KG.
5. Check the expected output preview. It scales from actual main input, not an assumed full batch: 36 KG at a 40 KG/120 PCS standard implies **108 expected pieces**.
6. Explain output deviations outside the approved tolerance. Fewer pieces do not automatically prove a waste weight.
7. Add measured trim/waste lines using the consumed input material, its base unit, quantity and reason. These quantities must not exceed recorded consumption. Confirm measured waste, or explicitly confirm there is no measured waste to record.
8. Enter the batch reference/processing note, review and submit.
9. A different authorised reviewer approves the record. The authorised Inventory poster then posts it. The actual input deduction and actual output addition occur together at the selected centre. A failed posting rolls back both sides.

If all inputs are weight-measurable and usable output weight is entered, the record compares total input weight with usable output plus recorded waste. Measurements exceeding consumed weight are rejected. A positive unexplained balance needs an explanation; it is not silently posted as additional waste. Unknown weights remain incomplete.

## Full test: Main Store and Kitchen

Use a disposable test restaurant, or clearly segregated test SKUs and centres. Do not enter fictional stock into a pilot restaurant's live records.

Configure 40 KG whole snapper -> 120 PCS cut snapper, with Main Store and Kitchen allowed. Establish 40 KG whole snapper at Main Store and a confirmed zero/opening baseline where appropriate elsewhere. Use a test whole-fish cost of NGN 1,000 per KG for easy arithmetic.

| Action | Expected result |
|---|---|
| Main Store processes actual input 36 KG, output 100 PCS | Expected output 108 PCS; output variance -8 PCS / -7.41%. Whole fish remaining at Main Store 4 KG; cut fish 100 PCS. |
| Record 2 KG trim within those 36 KG inputs | Main Store waste log shows 2 KG included in production. No extra raw-fish deduction. |
| Record usable output weight 32 KG | 36 - 32 - 2 = 2 KG not explained by these measurements; explanation retained. |
| Dispatch remaining 4 KG whole fish to Kitchen | Until acceptance, Main Store remains 4 KG and Kitchen remains 0 KG; reservation rules apply. |
| Kitchen accepts the 4 KG | Main Store becomes 0 KG; Kitchen becomes 4 KG. |
| Kitchen processes 4 KG into 10 PCS, with 0.5 KG trim and 3.5 KG usable weight | Expected output 12 PCS; actual output 10 PCS. Kitchen whole fish becomes 0 KG; cut fish becomes 10 PCS. Kitchen waste log shows 0.5 KG included in consumption; no second deduction. Weight reconciliation balances. |

For the Main Store batch, NGN 36,000 estimated consumed input / 100 usable pieces = **NGN 360.00 actual batch unit estimate**, compared with **NGN 333.33 standard unit estimate**. These cost estimates are saved at posting, preserve missing-price coverage and remain visible only to financial roles. Later price changes do not rewrite that batch snapshot.

The processed SKU's recipe-based standard estimate remains separate from actual batch performance. This release does not implement monetary inventory valuation or replace menu estimates with a moving average of produced stock.

## Review by role

- **Inventory Manager:** Inventory's **Production & waste** link shows filterable batches and waste by centre, date and state. Expand a batch for the baseline, actual inputs, measured waste, weight reconciliation, explanations and identities.
- **Kitchen/Bar:** users see only centres permitted by their stock access. Test that a Kitchen user cannot open Main Store history by changing a URL.
- **Finance/Owner:** see the same authorised history and financial batch estimates; stock-only users do not gain financial visibility.
- **CEO:** the executive workspace shows processing exceptions and where they happened, responsible member, yield variance, unexplained measured weight and standard-versus-actual unit estimates. It does not add overlapping processing waste to profit figures again.
- **Historical reports:** a link opens the combined centre logs. The existing Waste report remains separate waste stock movements; the combined centre waste log also includes processing trim already consumed in production.

## Checks that should fail safely

- Linking an inactive, untracked, wrongly classified or incompatible-unit output without correcting its settings.
- Enabling processing without a responsible member.
- Running a process at a centre not explicitly permitted by its standard, or outside an input/output SKU's outlet scope.
- Starting new production without a baseline, omitting an input, entering excessive waste, or leaving required variance evidence blank.
- Posting more input than available after transfer reservations. Confirm no output or cost snapshot was created by the failed posting.
- Editing a historical baseline, measured batch, waste line or cost snapshot directly.
- Using an outsider/anonymous account, or a stock-only account to request financial costing helpers.

Validation on 18 November 2026: all 222 database checks and 41 form/export checks passed. Nine distinct focused browser scenarios passed across the completed runs, including the full centre/material-repair/baseline/production/posting/history workflow and existing onboarding, inventory, costing and CEO scenarios. The final production build and TypeScript checks passed. Lint has zero errors and three pre-existing test warnings. Desktop and mobile screenshots were reviewed. Migration 036 was confirmed applied by the owner; a read-only production check confirmed its protected reporting function is available. No live restaurant records were altered by these local tests.
