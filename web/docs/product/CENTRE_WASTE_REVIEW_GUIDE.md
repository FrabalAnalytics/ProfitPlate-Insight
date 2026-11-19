# Centre waste logging: no approval required

Current test deployment: migrations through **041** are already applied. Do not rerun them. Standalone waste needs a submitter name and no reviewer assignment.

## Set up access

1. Assign a responsible named user to every stock centre in **Data & Setup > Centres & team access**.
2. Save the responsible owner and **Record waste** task together on the centre form. Use **Additional staff & detailed permissions** on the same page for other colleagues. Record waste is independent of Request materials. See [Centres & team access](CENTRES_AND_TEAM_ACCESS_GUIDE.md) for the combined setup flow.
3. The Inventory Manager's waste access remains limited to centres where they are the responsible user. Kitchen and Bar staff retain their assigned centre access. Management reporting roles retain their permitted reporting scope.

## Record waste

1. Open **Waste Log > Record waste**.
2. Select the date, centre, material and quantity in its base unit.
3. Enter the **Submitter name**, select a waste category and explain the loss.
4. Confirm the details and select **Record waste**.
5. The record is saved immediately and stock decreases once at that centre. No approval or separate posting is required. Stock availability and date checks still apply.

The submitted name is stored separately from the signed-in account and audit timestamp. It appears in the waste history, document detail and waste report CSV so the business can analyse recording patterns later. Previously posted entries retain their historical data; missing names are shown as unrecorded, not invented.

## Existing pending entries

Older waste requests are not automatically posted. Their original recorder opens the entry, adds the submitter name under **Complete waste recording**, and selects **Record waste**. This records the loss and updates stock once, with no approval. Cancelled, rejected and already posted records cannot be rewritten through this action.

## Processing waste

Record processing trim within the Material Processing Log. It remains part of that batch's input consumption and must not also be logged as standalone waste. The production batch keeps its existing controls; this release removes approval from standalone waste recording.

## Check this release

- Record Kitchen spoilage as Ada without a waste reviewer. Expect **Recorded**, the entered name and an immediate Kitchen stock deduction.
- Confirm there is no waste approval button or waste review permission checkbox.
- Leave the name blank or enter more waste than available stock. Expect a clear error and no partial posting.
- Repeat the same submission. Expect the same record and no second deduction.
- Confirm the Main Store Inventory Manager cannot retrieve Kitchen waste through the Waste Log, a direct document link or an export.

## Finance reporting

Finance-only users open **Review centre waste** from My workspace, or **Finance records > Waste across centres**. The default combines processing and other waste across permitted centres. Filter centre/dates, expand Source & status if needed, and export the same filtered scope. Finance has no waste recording action or setup access. Inventory Manager remains restricted to centres they own.
