# Centre waste logging: no approval required

Apply `supabase/migrations/202611190039_simple_named_waste_logging.sql` after migrations 001-038, then deploy the matching app. This release replaces the approval workflow introduced in 038. No reviewer assignment is required.

## Set up access

1. Assign a responsible named user to every stock centre in **Data & Setup > Stock centres & responsibilities**.
2. In **Inventory & movements > Department access**, give each person access to their centre and **Request stock** permission. This also permits recording waste there.
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
