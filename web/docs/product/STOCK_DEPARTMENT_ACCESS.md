# Main Store, Kitchen and Bar access

Current workflow after migration 026: see [Receiver-confirmed stock](RECEIVER_CONFIRMED_STOCK.md). The milestone details below describe the earlier release; use the version2 test pack and current guide for acceptance-only posting, department accounts and returns.

Apply **migration 024** (`202611160024_stock_department_access.sql`) after the already-applied 023, then deploy the updated application. Do not rerun 023. Open **Inventory & movements → Department access** as an Inventory Manager or business-wide Restaurant Administrator after migration 025.

## Configure the fine-dining restaurant

1. In **Locations & routes**, create Main Store (STORE), Kitchen (KITCHEN) and Bar (BAR), all assigned to the restaurant's outlet. Set the department labels to Stores, Kitchen and Bar.
2. In **Users & roles**, invite/activate the staff and assign their roles at that outlet. Staff who post stock, dispatch or confirm receipts need Inventory. Operations alone can request stock, counts, usage, waste or production but cannot post quantities or receive transfers.
3. In **Department access**, select each staff member and choose **Selected stock locations only**. Select Main Store for the storekeeper, Kitchen for kitchen staff and Bar for bar staff. Save each member separately after reviewing the confirmation.
4. Enable **Request stock** for staff who initiate requisitions, counts, receipts, production, waste or consumption. Enable **Handle stock** for Inventory staff who post quantities, dispatch or receive. Enable **Approve route requests** only for source approvers. Every selected stock location permits review, even if its three action permissions are off.
5. Configure Main Store → Kitchen and Main Store → Bar as ISSUE routes. Choose the appropriate source approval role. Add reverse routes only if the restaurant allows those returns.

| Person | Selected location | Request | Handle | Approve route requests |
| --- | --- | --- | --- | --- |
| Main storekeeper (Inventory) | Main Store | Yes | Yes | As authorised |
| Kitchen receiver (Inventory) | Kitchen | Yes | Yes | Usually no |
| Bar receiver (Inventory) | Bar | Yes | Yes | Usually no |
| Kitchen requester (Operations) | Kitchen | Yes | No | Usually no |
| Read-only operational colleague | Their location | No | No | No |

A person may have several assignments if they actually cover several departments. Central/shared warehouses still require a business-wide Inventory/Operations role; an outlet role cannot be expanded into a warehouse assignment through this screen.

## Permission behaviour

- **Existing role / outlet access** preserves the 023 behaviour. Migration 024 does not silently restrict existing staff. Change each intended department member to selected-locations mode to activate the restriction.
- **Selected stock locations only** is an explicit allowlist intersected with current roles and outlet scope. An empty list denies operational stock-location access, balances, ledger rows and movement documents.
- A destination department can request stock from a permitted source, without reading that source's stock balances. Permitted routes expose the counterpart's location name so requests and handoffs make sense.
- Movement documents are visible when the person can review either endpoint. A Kitchen colleague can review Main Store → Kitchen; they cannot review Main Store → Bar unless separately authorised at one of those endpoints.
- Only source-authorised colleagues with the configured role and the approval permission can approve route requests. An administrator retains the existing override. Nobody can approve their own request.
- Dispatch/posting requires handling permission at the source; receiving requires handling permission at the destination and a different colleague from the dispatcher. Handling without request permission can complete existing work but cannot initiate a new request.
- Inventory Manager approval covers physical counts, receipts, waste, consumption and production after migration 025; Finance/Administrator approval remains available. The department approval checkbox does not grant those management powers.
- Management, Finance and Procurement retain their existing stock-review access within their respective scopes. A combined-role person may therefore read more stock than an Inventory-only colleague; the administrator screen identifies these additional review roles.
- These assignments control the quantity stock workspace and its movement RPCs. Existing purchase orders, supplier GRNs, invoices, recipes, shared catalogue data and other modules retain their own role/outlet permissions. This does not introduce department-scoped purchasing or menu data.
- Revoking handling or approval permissions takes effect on the next action, including a document already open in another browser. Removing roles, making membership inactive or changing outlet scope also removes the corresponding authority. Already-posted history is retained.
- If roles/outlet scope change, grants outside the new scope become ineffective. The editor excludes unsupported grants when saving and explains the removal. Location assignments do not override current roles.
- Saves include a revision check. If another administrator changed the member first, refresh and review the new permissions rather than overwriting them. Changes retain prior assignments and new settings in audit history.

## First test after setup

Use separate browser profiles for the administrator, storekeeper, Kitchen and Bar.

1. Post reviewed opening quantities into each stock location using its assigned Inventory member and independent approval.
2. Kitchen signs in: its balance filter includes Kitchen, not Bar or Main Store balances. Its route picker offers Main Store → Kitchen, not Main Store → Bar.
3. Kitchen requests materials. An authorised Main Store approver approves; Main Store Inventory dispatches. A different Kitchen Inventory member confirms receipt. Bar cannot act on this movement.
4. Repeat for Bar and confirm Kitchen cannot read Bar's request or balance.
5. Request a Kitchen count/consumption/waste record and complete independent approval plus Kitchen posting. Verify that Main Store and Bar balances do not change.
6. Remove Kitchen handling permission while a movement is open. Its receive/post action must fail until permission is restored. Changing an assignment never alters historical quantities.
7. Save selected-locations mode with no locations for a test member. That member must have no stock balances, ledger entries or stock-request form. Restore only the intended location after the test.
8. As Finance, inspect all stock permitted by the Finance role. Confirm that Department access administration is unavailable.

The automated PostgreSQL tests cover these boundaries plus tenant separation, source approval revocation, role/outlet ceilings, direct-table ACLs and stale edits. Browser tests cover administrator assignments, staff screens, allowed routes, opening stock, revocation, Finance restrictions and mobile table layout.
