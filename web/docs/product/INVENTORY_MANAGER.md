# Inventory Manager: stock control lead

Current workflow after migration 026: see [Receiver-confirmed stock](RECEIVER_CONFIRMED_STOCK.md). The milestone details below describe the earlier release; use the version2 test pack and current guide for acceptance-only posting, department accounts and returns.

Apply migration 025 after 024, then deploy the updated application. If only 023 is applied, apply 024 first, then 025. Do not rerun previously applied migrations. No staff role is automatically upgraded.

The Restaurant Administrator grants **Inventory Manager** through Users & roles, using an accepted invitation or an existing member's role assignment. This role covers **all business locations**, including central warehouses. Department staff retain Inventory/Receiving or Operations roles plus their selected stock-location assignments.

## Responsibility model

| Person | Responsibility |
| --- | --- |
| Inventory Manager | Own stock configuration, routes, department stock access and oversight; approve physical stock records; coordinate dispatch, receipt and discrepancies |
| Main Store staff | Receive/post authorised deliveries and dispatch approved issues from their assigned store |
| Kitchen / Bar staff | Request, receive, count, consume and record waste/production within their stock assignments |
| Procurement | Raise POs and record supplier invoices |
| Finance | Review invoices, matching exceptions and financial corrections; retain existing stock-approval fallback |
| Restaurant Administrator | Assign business roles and retain stock configuration/approval fallback |

The manager's home prioritises Inventory & movements, Stock approvals, Department stock access and Deliveries & GRNs. It does not grant access to supplier invoices, payroll/expenses, sales revenue, financial reports or general team/role administration.

## Configure approvals

In Locations & routes, choose **Inventory Manager** as the source approval role for Main Store → Kitchen and Main Store → Bar routes. It is the default for newly configured routes in the updated form. Existing routes keep their configured approval role until deliberately changed. The manager can oversee and approve movements across the business; existing authorised source approvers remain able to approve routes configured for their own role.

Opening balances, counts, direct supplier receipts, GRN stock postings, consumption, waste and production requests can be approved by a different Inventory Manager. Finance and Restaurant Administrator approval remain available for continuity; their existing permissions are not removed by this migration.

## Controls that remain in force

- Nobody approves their own request, including an Inventory Manager.
- A person who dispatches stock cannot confirm that movement's destination receipt.
- A PO preparer/issuer cannot receive their own PO, including when combined with the manager role.
- The manager role includes physical handling and receiving authority across stock locations, but it does not grant purchase-order preparation or supplier-invoice entry.
- Stock posting remains atomic and prevents negative quantities, stale counts, duplicate GRN posting and invalid backdating.
- The manager can narrow department stock access but cannot give a person a new business role or expand that person's underlying Inventory/Operations outlet scope. General role administration stays with Restaurant Administrators.
- An Inventory Manager is a business-wide stock lead, not a department-restricted role. Keep ordinary department staff on Inventory/Receiving or Operations. Combining a department role with Inventory Manager deliberately gives that person stock oversight across the business.
- Inactive membership revokes the manager's authority. All stock configuration and physical movement decisions remain audited.
- This changes physical stock responsibility, not inventory valuation or financial costing.

## First operating test

1. Invite/assign a real Inventory Manager and sign in through their own browser profile.
2. Verify their Inventory Manager workspace and access to Locations & routes and Department access.
3. Configure Main Store, Kitchen and Bar and assign staff to their locations.
4. A storekeeper requests opening stock; the manager approves; authorised Inventory staff post it.
5. Kitchen submits a requisition; the manager approves; Main Store dispatches; a different Kitchen receiver confirms delivery.
6. Repeat for Bar. Review balances and any shortage reasons as the manager.
7. Submit a count or waste request from a department, approve it as manager and check the physical quantity change.
8. Verify that the manager cannot enter supplier invoices or access Users & roles without an additional separately assigned role.

Automated database tests cover invitation validation, manager capabilities, department assignments, route and adjustment approvals, self-approval/self-receipt prevention, financial/team denials and inactive membership. Browser tests complete a staff opening-stock request through manager approval and staff posting.
