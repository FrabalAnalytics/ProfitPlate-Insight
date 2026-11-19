# Centre waste recording and review

Release prerequisite: apply `supabase/migrations/202611190038_centre_owned_waste.sql` after migrations 001-037, then deploy the matching app. Existing waste records remain intact. The new reviewer permission starts disabled; administrators must assign reviewers before department waste can be approved or posted.

## Set up each centre

1. In **Data & Setup > Stock centres & responsibilities**, assign the responsible named user. Assign the Inventory Manager to Main Store or the centre they manage.
2. Invite the colleagues who will record and review waste, using an appropriate operational role: Kitchen Manager, Bar Lead, Department stock user, Operations Manager or Inventory.
3. In **Inventory & movements > Department access**, choose the recorder. Select **Selected stock locations only**, allow their centre and enable **Request stock**. Save.
4. Choose a different colleague as reviewer. Allow the same centre and enable **Approve & post waste**. General stock posting and transfer approval are separate permissions; they are not required for waste review. Confirm and save.
5. Repeat for Kitchen, Bar, Main Store and every other centre. An Inventory Manager who owns a centre can review another colleague's waste there. If that manager records waste, another authorised reviewer at the same centre must review it.

## Record, approve and post

1. The recorder opens **Waste Log > Record waste**, chooses their centre, material, quantity, category and explanation, then submits.
2. A different authorised colleague opens the stock document, checks the evidence, enters a decision note and approves or declines.
3. An authorised colleague other than the recorder posts an approved request. Approval alone does not change stock; posting deducts the recorded quantity once from that centre.
4. Confirm the document is **Posted**, the centre balance decreased by that quantity, and its Waste Log contains the record.

The same independent colleague may approve and post. The recorder cannot approve or post their own waste. Revoking a reviewer's centre access blocks subsequent actions, including posting an already approved request.

## What each person sees

- An Inventory Manager's Waste Log, waste reports, exports and standalone waste documents are limited to centres where they are the responsible user. An unassigned manager sees no waste records and is prompted to request an assignment.
- Kitchen and Bar users see the centres allowed by their roles and assignments. Their reviewers need an explicit waste-review grant at those centres.
- Separately assigned CEO, Finance and Restaurant Administrator roles keep their permitted management reporting scope. A management reporting role alone does not grant waste approval or posting.
- Processing and other stock oversight retain their existing permissions. Processing trim is recorded in the processing batch and must not also be entered as standalone waste. Combined waste history labels its stock treatment.

## Check the controls

- Record Kitchen waste as Ada. The Main Store Inventory Manager must not see or approve it, including through a direct document link or a waste-report export.
- Approve and post it as a different authorised Kitchen colleague. Kitchen stock decreases; Main Store stock stays unchanged.
- Try self-approval, self-posting, a different centre and a revoked reviewer. Each action must be denied.
- Record Main Store waste using another Main Store colleague. Its responsible Inventory Manager can approve and post it.
- Confirm processing trim appears once and causes no second deduction through the standalone waste log.
