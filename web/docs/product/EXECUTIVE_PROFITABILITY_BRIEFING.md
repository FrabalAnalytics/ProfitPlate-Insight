# CEO profitability and accountability briefing

Apply `202611170027_executive_profitability_briefing.sql` once after 026, then deploy the matching application. Already applied migrations must not be rerun. This is an additive, read-only reporting migration.

## What the CEO sees

The business-wide CEO / Managing Director role opens an Executive workspace with four headline metrics: recorded net sales and its preceding-period change; estimated food-cost percentage and percentage-point change; estimated gross food margin and its percentage-point change; and stock handovers awaiting closure.

The default selection is month to date in the restaurant's business timezone. The CEO can select another period (up to 93 days) or an outlet. Comparisons use the immediately preceding period of equal length. Missing records do not establish zero trading or complete data coverage.

Four evidence panels identify operational pressure and the affected location, with links to source records:

| Panel | Change / impact | Where and accountability |
| --- | --- | --- |
| Procurement price pressure | Current and prior quantity-weighted invoice costs per material base unit. Positive increases multiplied by current purchased quantity provide purchase-cost exposure. | Material and outlet; Procurement and Finance review corrected invoice evidence. |
| Waste and count shortages | Posted waste and negative stock-count entries valued at dated reference prices; known exposure compared with prior recorded exposure. Positive count adjustments do not cancel shortages. | Stock location and outlet; Inventory Manager and department review the movement record. |
| Menu margin watch | Sold menu items with food cost above the visible 40% review guide, or negative food margin. Shows actual recorded revenue, estimated food cost %, monetary food margin and gross food margin %. | Outlets selling the menu item; Kitchen, pricing and Procurement investigate the saved recipe and source sales. |
| Material movement accountability | Current open transfer/issue controls, rejected/incomplete follow-ups, and waits over 24 hours. | Source/destination departments and outlets; next action identifies Inventory Manager or receiving department. |

Panels open when their evidence needs attention; quieter categories remain compact and can be expanded. Tables show at most five priority records, with total counts and source links. The CEO does not get general daily-work cards, stock-request forms or a recent-receipt list on this home. Other assigned permissions still work through navigation; this is not a permission revocation.

## Calculation and control boundaries

- Price pressure reads the latest **approved** invoice projection, including replacements, date/outlet changes and voids. Pending corrections do not change the current evidence. Prices exclude tax and include line discounts. Quantities are normalised to the material base unit; unlike pack units are not compared directly. Comparisons are by material and outlet, across suppliers: supplier mix, discounts and purchasing choices may contribute to the change. It does not prove market inflation or employee fault.
- Current purchase groups without a preceding-period baseline are counted explicitly. Foreign-currency invoices are excluded and counted. A 10,000-invoice history limit makes that panel unavailable rather than silently truncating corrected history.
- Loss exposure uses only posted, negative WASTE and COUNT ledger entries, with latest reference prices dated on/before the event. A missing price, mismatched currency or mismatched base unit remains unpriced. The known subtotal is labelled incomplete when needed. No quantities across unlike materials/units are summed as one total.
- Waste and stock shortages are estimated exposure, **not actual inventory valuation**. They are not deducted from the existing reference-price food margin. Purchase pressure, waste and food-margin changes overlap and must not be summed into a claimed profit bridge.
- Gross food margin excludes labour, overheads, waste, fees and other variable costs. The briefing does not calculate actual operating profit, theft, supplier fault or attributable causal profit changes.
- Menu thresholds are a clearly labelled starting review guide, not a configured restaurant budget or a universal benchmark. Uncosted and unsold menu items are not cleared by this check; the complete menu profitability table remains available for review.
- Accountability is **live now**, independent of the historical financial selection. An unaccepted transfer is not a confirmed loss. Resolved partial/rejected follow-ups disappear from the open controls; accepted quantities continue to post on both sides atomically under migration 026.
- Refresh briefing reloads current evidence. It does not change source records or replace a saved, reviewed management report.

## Pilot checks

1. Sign in as CEO (including a CEO who also has Administrator or Inventory Manager roles). Confirm the briefing replaces daily operational task cards. Confirm the other roles still work through navigation.
2. Select a period and outlet containing sales in both current and prior periods. Compare revenue and food-margin totals against Executive overview with exactly those filters. Verify percentage-point change is not presented as a percentage change.
3. Record comparable supplier purchases in adjacent periods, using the same material and outlet. For example, prior 10 KG at 100 and current 10 KG at 120 gives a 20% unit-cost increase and 200 of exposure. Approve a correction to current 110: exposure becomes 100. An approved void removes that invoice.
4. Post waste of 2 KG and a count shortage of 1 KG at a reference cost of 90/KG. Known exposure is 270. A positive count adjustment must not reduce it. A draft waste request must not increase it. Add an unpriced material: coverage becomes incomplete.
5. For a costed menu, prior sales of 200 against food cost 90 gives 55% food margin. Current sales of 300 against food cost 180 gives 40%, down 15 percentage points. The 60% food-cost ratio should trigger Menu margin watch and identify selling outlets.
6. Dispatch a department transfer and leave it unaccepted. Its live control should identify the receiving department. Acceptance closes it; a rejected/incomplete handover requires manager follow-up. Once resolved, that follow-up no longer appears. Historical financial filters must not hide a live control.
7. Open the briefing on a narrow phone screen. Tables scroll within their containers; the page must not overflow horizontally. Expand quieter panels and follow a movement link: an outlet filter must not be passed as a stock-location ID.
8. Try an empty sales period, missing food prices, invalid dates, another business's outlet, and a department-only account. Missing coverage stays explicit and financial access remains protected.

Automated checks cover reporting aggregates, corrected/voided invoices, location and role boundaries, empty periods, live accountability, desktop/mobile briefing, period filters, source links and the existing operational workflows.
