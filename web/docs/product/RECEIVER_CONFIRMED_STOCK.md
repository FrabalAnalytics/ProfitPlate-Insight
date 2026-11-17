# Inventory Manager-led, receiver-confirmed stock

Apply **202611170026_receiver_confirmed_stock.sql** after 025 and deploy the matching application. Skip already-applied migrations. This replaces the earlier dispatch-depletion instructions in milestones 023–025 and the original manual test pack.

## Accounts and responsibilities

The normal stock workflow uses one Inventory Manager account plus department accounts (for example Kitchen and Bar). There is no requirement to create a separate storekeeper, receiver or dispatcher account. The manager approves and dispatches a department requisition in the same session. Existing owner/administrator, Procurement and Finance accounts keep their business responsibilities.

| Role | Scope and process |
| --- | --- |
| Inventory Manager | Business-wide stock oversight, locations/routes, department stock access, approval, dispatch and quantity posting; Main Store/warehouse receipt of department returns |
| Department stock user | Explicit assigned locations only; request stock and accept/reject incoming transfers; request returns/excess transfers and usage/count/waste/production for manager posting |
| Stock receiver (optional) | Assigned stock receiving only; no approval, dispatch, arbitrary adjustment posting or financial powers. Existing supplier PO/GRN receiving follows its outlet role scope. |
| Stock dispatcher (optional) | Dispatch approved requests from assigned locations only; no approval, receiving or financial powers |

Assign business roles in Users & roles as a Restaurant Administrator. Assign stock locations/process permissions in Department access as Inventory Manager/Administrator. New department and delegated process roles default to no stock-location access and require explicit assignments. Their permissions cannot exceed their role or outlet scope.

Existing Inventory/Operations assignments remain compatible and can be narrowed further. The old Inventory staff role is not offered for new role selection unless already present on the edited assignment. Do not give departments Inventory Manager: that intentionally grants business-wide stock oversight.

## Configure Main Store, Kitchen and Bar

1. Add Main Store as STORE, Kitchen as KITCHEN and Bar as BAR at the restaurant outlet.
2. Give Kitchen and Bar users their own **Department stock user** role at that outlet.
3. In Department access choose Selected stock locations only; select the correct location with **Request stock** and **Accept / reject**. Leave dispatch and approval unavailable. Optional delegates can receive or dispatch independently of other stock permissions.
4. Create Main Store → Kitchen and Main Store → Bar ISSUE routes with Inventory Manager as approver.
5. Use **Allow reverse / excess return** to create the reverse TRANSFER routes. A department can then initiate a return from its own location.

## Quantity and status rules

| Stage | On-hand quantities | Reservation / next action |
| --- | --- | --- |
| Pending approval | Unchanged | Manager reviews the department's requisition |
| Approved | Unchanged | Same manager can authorise dispatch |
| Awaiting acceptance | Both unchanged | Source quantity reserved; receiving side accepts or rejects |
| Completed acceptance | Accepted quantity deducted at source and added at destination in one transaction | Reservation clears |
| Incomplete / partial | Only accepted quantities move on both sides | Rejected remainder stays in source on-hand stock and remains reserved until physical-return follow-up is resolved |
| Rejected | No new transfer quantity moves | If goods were dispatched, their source reservation remains until the manager confirms physical return. A declined request before dispatch reserves nothing. |
| Resolved follow-up | No on-hand change | Manager confirms rejected goods are physically back and records evidence; reservation releases. The original Incomplete/Rejected status remains in history. |

Example: Main Store has 100 KG. Dispatch 10 KG: on hand100, reserved10, available90; Kitchen unchanged. Kitchen accepts8 and rejects2: Main on hand92, reserved2, available90; Kitchen gains8. After the manager confirms the rejected2 physically returned and resolves follow-up, Main on hand stays92 and available becomes92. Rejection never silently becomes a transit loss or waste posting.

Use a new requisition for another shipment of the unfulfilled remainder. If returned goods are unusable, record a separately reviewed waste adjustment after return. A partial receipt is a final decision for that shipment; multiple incremental receipts against one internal transfer are not implemented.

Reservations prevent double allocation, consumption or production from spending stock that is awaiting confirmation/return. Counts are blocked while outgoing transfers at the stock location remain unresolved. Acceptance is dated on the current business date, serialised by the organisation lock, and all source/destination entries roll back together if any line fails. Repeating acceptance cannot post twice.

## Department excess returns

Kitchen submits a TRANSFER on Kitchen → Main Store. The manager approves and authorises dispatch; balances stay unchanged. The manager can then accept that **department-originated** return into Main Store without creating another inventory account. Acceptance deducts Kitchen and adds Main Store together. This same-operator return handoff is explicitly recorded in audit details.

The manager cannot accept their own outbound dispatch into Kitchen/Bar on behalf of the department. A manager-created return does not qualify for the department-originated exception. Optional independent receivers/dispatchers are supported when the business chooses to delegate.

Self-approval remains blocked. Department-created requests can be approved and posted/dispatched by the same manager. A manager-originated opening count or supplier stock-posting request still requires a different authorised manager/owner/Finance reviewer before posting; existing Finance/Administrator fallback remains available. This uses existing management accounts, not mandatory extra inventory staff.

## Records, filters and alerts

The register supports Pending, Approved/ready, Awaiting acceptance, Completed, Incomplete, Rejected, Cancelled and Needs follow-up, plus location and reference/reason search. Filters apply before counts/pagination. Stock balances, movement records and ledger views display10 records per page with compact shared table spacing. The ledger remains a latest100-entry view, not a full-history export.

The Inventory Manager workspace shows approval, dispatch/posting, department-confirmation and exception follow-up actions. A department workspace shows pending requisitions and incoming decisions for its stock scope; requesters see incomplete/rejected follow-up. Visible home workspaces refresh every30 seconds and on returning to the tab. Items older than24 hours are labelled. Alerts are derived from live authorised records, so completion/resolution clears the action automatically. No email/SMS delivery is implied.

Alert links fetch their exact authorised document even when it is not on the first filtered register page. Unrelated departments and other businesses cannot obtain its details. A restored/revoked permission is checked again by the database for each action, including an already-open tab.

## Upgrade and boundaries

Migration026 marks existing records with their historical ON_DISPATCH policy and makes new requests ON_ACCEPT. It does not rewrite existing ledger entries or reverse balances automatically. A historical dispatched receipt adds the accepted destination quantity without debiting the source twice; its rejected share is restored at source through an audited entry and held until follow-up resolution. The UI identifies historical pending dispatches.

PO/GRN receiving, invoice entry and explicit GRN stock posting remain separate. Original purchase documents, shared materials and recipe data retain their existing module/outlet permissions. Actual inventory valuation/COGS and automatic sales depletion remain outside this quantity workflow. Financial estimates continue to use their existing dated reference-price policy.

Use the **version2 manual test pack** (`profitplate-full-test-pack-2026-11-17-v2.zip`), which has84 cases and recalculated quantity checkpoints. The previous76-case pack describes the earlier dispatch-depletion rules and is retained as a historical artifact.
