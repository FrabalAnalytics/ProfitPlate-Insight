# Configurable restaurant inventory

Current workflow after migration 026: see [Receiver-confirmed stock](RECEIVER_CONFIRMED_STOCK.md). The milestone details below describe the earlier release; use the version2 test pack and current guide for acceptance-only posting, department accounts and returns.

Apply `supabase/migrations/202611160023_stock_locations_and_movements.sql` after migration 022, then apply migrations 024 for department-level stock access and 025 for the Inventory Manager role and deploy the application. If 023 is already applied, apply 024 and 025 in order, skipping any already-applied migration. No existing GRN, invoice, sale or legacy inventory row is automatically converted into stock. Existing recipe costing and management reports retain their current reference-price basis.

Open **Inventory & movements** from the workspace navigation. Stock records use the shared table style, including horizontally scrollable tables on small screens.

## Supported operating patterns

| Pattern | Configuration |
| --- | --- |
| One restaurant | Outlet store, kitchen and/or bar; ISSUE routes between them |
| Central warehouse | Central WAREHOUSE with no outlet assignment; TRANSFER routes to outlet stores |
| Departments | KITCHEN, BAR or PRODUCTION stock locations with a department label and outlet assignment |
| Direct delivery | Choose the physical receiving stock location when posting a GRN, or record a supplier-backed DIRECT_RECEIPT without a GRN |
| Central production | Bind published sub-recipes/final recipes to stocked output materials; produce batches, then transfer the output |
| Returns between stores | Configure the permitted route in the reverse direction; supplier return/credit-note workflows remain separate future work |

Stock locations are quantity buckets separate from commercial outlets. Existing POs still use their outlet delivery scope. Their GRNs can be explicitly posted into a stock location within that outlet, or into a central stock location by an appropriately authorised Inventory member. This release does not change purchase invoice allocation or supplier accounting.

## Configure a first pilot

1. As an Inventory Manager or business-wide Restaurant Administrator, open **Locations & routes**.
2. Add `CENTRAL`, a warehouse with no outlet assignment. Add `OUTLET_STORE`, a store assigned to the pilot outlet. Add `KITCHEN`, a kitchen at that outlet with department `Kitchen`.
3. Configure CENTRAL → OUTLET_STORE as TRANSFER, then OUTLET_STORE → KITCHEN as ISSUE. Choose the approval role for each route. A reverse flow needs its own permitted route.
4. Assign business-wide Inventory access to warehouse staff; assign outlet-scoped Inventory access to receiving staff. Operations can request departmental movements within its assigned outlet. Use different people for dispatch and receipt.
5. As Inventory, open **Movements & requests** and select Opening balance. Enter checked quantities in material base units. Submit the count with a source note.
6. A different business-wide Finance member or Restaurant Administrator approves the opening request. Inventory then posts it. Opening quantities must be the first stock posting for each listed material at that location; split larger counts across requests with distinct materials. A reviewed count corrects later balances.
7. For every new supplier delivery, post its accepted GRN once to the correct stock location. Rejected quantities do not enter stock. Never post deliveries already included in the opening count. Direct supplier receipts require a supplier, a unique supplier delivery reference and source note; do not also post a GRN for the same delivery.
8. Request a transfer or department issue using a permitted route. A different authorised source approver approves it, source Inventory dispatches, and a different destination Inventory colleague receives it.
9. Confirm accepted quantities for every line. A shortage requires a reason; the difference is retained as transit shortage/loss evidence. The movement remains In transit until its single final receipt. Partial dispatches and multiple receipts against one internal movement are not implemented: create separate requests for separate shipments.
10. Record consumption when stock is actually used. An issue to the kitchen remains stock in the kitchen until consumption, production or waste is posted.

## Counts, waste and approvals

- Counts record the physical quantity, including zero, for explicitly listed materials. Unlisted materials remain unchanged. Posting writes the difference from book stock; no absolute balance is overwritten.
- Any intervening ledger movement at that location makes a count stale. Cancel and recount rather than posting an old count.
- Waste/spoilage and consumption deduct quantities with source notes. These and receipts, opening counts and production require independent Finance/Administrator approval before Inventory posts them.
- Negative stock is blocked atomically. Approved requests do not reserve stock: the posting/dispatch step checks the then-current balance.
- Backdated postings before a later movement for the same stock location/material are blocked. Explain corrections and use a valid current posting date.
- Only requested/approved documents can be cancelled. Posted and dispatched documents retain their history; use a reviewed physical correction and a new movement as appropriate.
- A GRN with posted stock cannot be Finance-voided. Keep the source evidence and review physical stock and invoice corrections separately. Unposted stock requests cannot post a voided GRN or one with an unresolved void request.
- Deactivation retains history and blocks new requests/dispatches. A stock location with stock or pending movements cannot be deactivated. Already-dispatched movements can still be received if their route is later disabled.

## Sub-recipe and final-recipe production

1. In Materials & suppliers create a stock-tracked SEMI_FINISHED material for each stored sub-recipe, and a FINISHED material for a stored final product. Use a base unit compatible with the recipe's saved output unit.
2. In Locations & routes, link each published recipe version to its output material. Bindings already used in production cannot be changed; use a new recipe version for a changed binding.
3. Request Production batch at the physical production stock location. Select the saved recipe version, planned output and actual usable output. Both quantities use the recipe's saved output unit.
4. The request snapshots its direct material requirements and the stocked output of each pinned child recipe. Produce child recipes first. The parent consumes the child stock once; it does not also deduct that child's raw ingredients.
5. Review the calculated input lines before approval. Posting consumes the planned recipe inputs and adds the actual output in the material's base unit in one transaction. An input shortage blocks the entire batch.
6. Planned/actual yield differences stay in the production record. This release assumes recipe-standard input quantities; record deviations as separately reviewed consumption/waste, or adjust the recipe version before requesting the batch. There is no lot-specific yield or monetary production-cost calculation.

## Permissions and boundaries

Organisation membership must be active. Outlet-scoped roles are limited to that outlet; central locations require business-wide roles. With migration 024, an administrator can further limit Inventory/Operations staff to selected stock locations with separate request, handling and route-approval permissions. Existing members retain outlet-based access until assigned explicitly. Department labels alone do not restrict access. A destination department may see a permitted route's source name so it can request stock, without access to that source's balances. Documents spanning locations are visible to authorised colleagues at either endpoint. See [the fine-dining setup and permission guide](STOCK_DEPARTMENT_ACCESS.md).

Inventory Managers lead stock controls and, alongside Restaurant Administrators, configure locations, routes and output bindings. Inventory dispatches/posts/receives; Operations can request. Finance, Procurement and management can inspect accessible stock data. Inventory Managers and business-wide Finance/Administrators approve non-route records, and nobody approves their own request. Route approval follows its configured source role with an administrator override. Independent destination receipt is always required. Direct table writes and private helper calls are denied to application users.

The new stock ledger is append-only through checked database functions. Requests, approvals, movements and corrections create audit events. Organisation locking serialises stock changes; repeated request IDs cannot create duplicate requests, repeated posting cannot create duplicate ledger entries, and a GRN can have only one uncancelled stock document.

## Current limits

This is quantity tracking, not actual inventory valuation or inventory COGS. Existing sales/menu reports do not automatically consume stock or calculate actual contribution. Batch/expiry/lot tracking, supplier returns, partial internal dispatch/receiving, count-sheet imports, inventory exports and automatic reorder alerts are not included. Opening and movement entry is manual, up to 100 distinct materials per request. Stock balances are current; the ledger displays the latest 100 entries and the movement register is paginated at 25 records.

## Verification

`tests/inventory-database.test.mjs` exercises location/role isolation, opening balances, approved department issues, source dispatch, independent receipt and shortages, nonnegative quantities, stale counts, historical posting guards, sub-recipe production and actual yield, direct receiving, GRN conversion/deduplication/void guards, tenant isolation and function/table ACLs. It runs as part of `npm run test:db`.

`tests/e2e/inventory.spec.ts` exercises configuration, opening request/approval/posting, route request/dispatch/receipt, outlet-scoped balances, Finance read access and mobile table layout against local PostgreSQL migrations. No production database is used by these checks.
