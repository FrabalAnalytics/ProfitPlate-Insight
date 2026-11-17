# Role workspaces and navigation

Apply `202611170031_workspace_attention_and_platform.sql` after migrations 001-030, then deploy this app version. This migration adds task queries, personal GRN review acknowledgements and the founder metadata query. No PO approval stage is introduced: Procurement saves drafts and issues orders directly.

## Needs Attention

Operational homes show only outstanding, permitted task categories, with a count of distinct documents in each category. Categories may overlap, so there is no summed total. Click a category to open its ten-row task queue, then open the exact source record. Counts refresh every 30 seconds while visible; the Refresh button updates immediately. Waiting over 24 hours is an elapsed-time indicator, not a delivery SLA.

Inventory sees issued POs without active GRNs, incomplete POs, material requests awaiting approval, approved records ready to dispatch/post, transfers awaiting department acceptance, incoming returns and unresolved stock follow-up. Counts follow existing record/action permissions, including the separate-person supplier-receiving rule. Kitchen and Bar only see their own permitted work. Stock balances and approval/dispatch/receiver responsibilities are unchanged.

Procurement sees draft orders awaiting issue, incomplete orders, overdue delivery dates, fresh GRN documentation and invoice exceptions or Finance reviews/corrections. There is no original-invoice approval workflow; Finance review and correction approval retain their existing meaning. These queues use the existing invoice matching engine.

Fresh GRNs mean receipts documented after both this update was installed and the user's membership began, which that user has not acknowledged. Review is personal: acknowledging the displayed batch of up to ten GRNs leaves other pages, new arrivals and other people's queues intact. It does not change receiving, billing or correction status. Old receipts remain searchable in the GRN register and reports rather than all being announced as fresh at rollout.

CEO homes retain the profitability briefing; they do not receive operational task lists just because the CEO also has an administrator role.

## Navigation and records

Purchase Orders and Goods Received Notes have separate sidebar links, pages and reports. Supplier invoices remain separate. Open a GRN to inspect its material lines, accepted/rejected quantities, receiver and correction history. Existing GRN URLs redirect to the new page. Receiving still starts from an issued PO so quantities remain tied to its materials.

The sidebar groups Purchasing, Daily operations, Profitability, Reports and Business administration. CEO groups start closed; Finance starts with Daily operations open. The current page's group opens automatically. Other preferences are remembered per business and signed-in email in that browser. Navigation visibility follows existing server permissions. The whole sidebar and mobile menu still work independently.

Historical reports show report, period, outlet and search first. Status, stock location, supplier, material and user are under More filters. Active optional filters remain visible as removable chips; Clear filters preserves the report, view and dates. CSV/Excel exports use the same filters even while their controls are collapsed.

## Founder workspace

The founder sees real restaurant/outlet/membership totals, onboarding drafts, access review indicators and a searchable paginated restaurant directory. Inspect business shows owner contact, role assignment counts and platform metadata. It does not grant restaurant membership, impersonate users or expose restaurant financial records. Active memberships are not live online users, and last activity is the latest saved audit event.

## Homepage

The homepage addresses restaurant owners and their teams directly: ingredient price pressure, waste, menu margins and unconfirmed handovers. Role benefits and available features are explicit. Financial estimates, reference prices, actual accounting limitations and future upload features remain distinguished.

## Manual pilot checks

1. Sign in as Inventory Manager. Open each Needs Attention category and compare its document count with the matching source records. Issue a new PO as Procurement and verify the receiving queue updates.
2. Record a partial GRN. Confirm the PO leaves the no-GRN queue but remains incomplete. Complete the order and verify it leaves the incomplete queue. A voided receipt must no longer count toward completion.
3. As Procurement, open fresh GRNs and inspect materials. Mark the displayed batch reviewed. Confirm this clears your documentation queue only, and Finance/receiving state is unchanged.
4. Request stock as Kitchen. As Inventory Manager approve and dispatch it. Verify Kitchen receives an incoming-transfer alert and the manager sees department confirmation outstanding. Accept it and confirm both alerts clear; verify balances change only on acceptance.
5. Return excess from Kitchen. Verify Inventory Manager sees the department return for acceptance. Test a partial rejection and resolve its outstanding physical-return follow-up.
6. As CEO/Finance, open and close sidebar groups, reload and confirm preferences. Open a report directly and confirm its group expands. Repeat on mobile using keyboard and menu controls.
7. In historical reports, open More filters, apply a material/status filter, collapse it and verify the chip and exported data. Remove one chip; clear optional filters; confirm the dates persist.
8. Sign in as founder. Search for a restaurant, inspect metadata and filter onboarding/access review. Confirm a restaurant member cannot open the founder page or call its RPC.
9. Review the homepage on desktop and phone; check role benefits, signup links, FAQ, cost slider and template downloads.

Automated checks use local PostgreSQL/PGlite migrations and browser authentication fixtures. They do not prove a live Supabase deployment or live email delivery.

## Verification

Production build and TypeScript checks passed. Lint has zero errors and three pre-existing test warnings. All 187 database checks and 39 form/export checks passed. Desktop/mobile browser coverage includes the separate PO/GRN flows, historical exports, CEO briefing, founder metadata, personal GRN review, saved reports, invitations, stock acceptance and sidebar preferences. The final follow-up run passed all 22 scenarios after updating older tests to use the grouped navigation.
