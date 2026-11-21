# Operations Manager workspace

Migration: `supabase/migrations/202611210055_operations_manager_workspace.sql` (after 054).
Apply it successfully in Supabase before deploying the matching application.

The existing `operations` role is retained, with its existing memberships, recipe permissions and history. No restaurant or staff member is automatically assigned this role.

## Assignment

1. As Restaurant Administrator, open Users & roles and invite or edit the colleague.
2. Select Operations Manager. Select All business locations for business oversight, or an outlet for local oversight. Add another scoped assignment when needed.
3. For narrower stock visibility, use selected centres in Centres & team access. A centre assignment does not extend the role's outlet scope. Shared central stores require business-wide coverage.
4. Oversight does not require selecting every stock task. Grant requests, waste recording, approval, dispatch and receiving only where this manager performs those tasks. Arbitrary stock adjustment posting still requires an independently assigned Inventory role.

An Operations-only account without explicit selected-centre tasks now defaults to oversight, not implicit request/approval authority. Existing explicit centre grants are retained. Independently assigned roles retain their own access.

## Workspace

- Priority cards: overdue waste centre-days, overdue weekly counts and menu/outlet comparisons above configured food-cost targets.
- Needs Attention: pending material movements, outstanding receiver confirmation, incomplete issued POs and posted production outside the saved tolerance during the last seven business dates. Up to twelve oldest source records appear; counts cover all matching permitted records. These are follow-up records, not new approval stages.
- Current stock value: estimated current holding and centre drilldown, with missing prices visible. This is a reference-price estimate, not accounting inventory valuation.
- Daily waste and weekly count status retain centre owners, dates and source links.
- Menu exceptions by permitted outlet and issued-PO price warnings for the current business month, with up to five priority lines per outlet. PO quotes remain early warnings; invoice-based recipe cost rules are unchanged.
- Links to plans, processing, waste analysis, movement statements and historical reports.

Unavailable inputs are shown as unavailable, not zero. Waste status refreshes the workspace every thirty seconds while visible.

## Permissions

Business-wide Operations Managers can read the financial and operational evidence needed for oversight, including menu margins, sales/cost reports and purchase prices. This does not grant Finance posting, invoice-correction decisions, team administration, restaurant activation or business configuration.

Outlet-scoped Operations Managers receive only their covered stock-centre records, PO/GRN history and outlet menu profitability. They do not gain company-wide invoice, sales or reference-price screens. Common recipe reference estimates remain available as operational costing inputs. The scoped menu comparison screen does not link into the business-wide menu catalogue or price-history editor.

Operations Managers may independently review submitted weekly counts at permitted centres. They cannot approve their own submission or post a stock adjustment without separate Inventory authority. Daily waste still has no approval stage. Reading compliance does not grant permission to certify another centre's day; named submitter, centre task and evidence rules remain enforced.

Centre assignments narrow stock oversight; outlet assignments determine menu and purchasing oversight. Independently assigned CEO, Finance, Inventory or Administrator roles continue to grant their own permissions.

No outbound reminders, automatic reassignment, new task-management workflow or automatic stock movement is introduced.

## Validation

Database checks cover business/outlet/centre scope, direct API denials, inactive and anonymous callers, count review separation, explicit stock tasks, menu calculation and unchanged stock. Browser checks cover both Operations scopes, financial navigation boundaries and mobile layout. Run the database, form, lint, build and targeted browser suites before release.
