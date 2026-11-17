This is a [Next.js](https://nextjs.org) project bootstrapped with [`create-next-app`](https://nextjs.org/docs/app/api-reference/cli/create-next-app).

## Restaurant onboarding milestone

**Separate purchasing reports (030)** provides PO register/material detail and GRN register/material detail views with supplier, material, user, outlet, date and status filters. A financial-access comparison highlights ordered/received/invoiced quantity and net-price differences. CSV and Excel exports preserve the selected report grain and filters; the desktop PO browser keeps a document list beside the selected order. Apply [migration 030](supabase/migrations/202611170030_purchasing_report_views.sql) once after 029 and deploy. [Definitions, export limits and pilot checks](docs/product/SEPARATE_PURCHASING_REPORTS.md).

**PO/GRN material visibility and Procurement separation (029)** adds **View materials & GRNs** to the PO register, expandable received-material tables for each GRN, and visible material links in historical reports. Procurement-only users no longer see or read stock requests/movements; supplier purchasing and Materials & suppliers remain available. Apply [migration 029](supabase/migrations/202611170029_procurement_stock_separation.sql) once after 028 and deploy. [How to inspect the material lines](docs/product/PO_GRN_MATERIAL_DETAILS.md).

**Role-based historical reports (028)** adds **Reports → Historical reports** for Inventory, Procurement, Finance, Kitchen, Bar and other authorised roles. Filter by date, outlet, stock department, status or search; inspect source documents, print a displayed page or export all filtered rows. Department scope and financial permissions are enforced in the database for both views and exports. Apply [migration 028](supabase/migrations/202611170028_role_historical_reports.sql) once after 027 and deploy. [Report matrix, definitions and pilot checks](docs/product/ROLE_HISTORICAL_REPORTS.md).

**CEO profitability briefing (027)** focuses the Executive workspace on sales and margin changes, procurement price pressure, waste/count-shortage exposure, menu margin risks and live material-handover accountability. Each panel identifies the affected location and responsible team, with source links; daily operational task cards are removed from this home. Apply [migration 027](supabase/migrations/202611170027_executive_profitability_briefing.sql) once after 026 and deploy. [Evidence, calculation limits and pilot checks](docs/product/EXECUTIVE_PROFITABILITY_BRIEFING.md).

**Receiver-confirmed stock (026)**: one Inventory Manager can approve and dispatch; departments accept/reject or return excess. Dispatch reserves stock; acceptance posts both sides atomically. Rejected remainders stay reserved until physical-return resolution. Apply [migration 026](supabase/migrations/202611170026_receiver_confirmed_stock.sql) after 025 and deploy. Includes optional stock receiver/dispatcher roles, requisition filters, live workspace alerts, compact paginated records and refreshed homepage/account pages. [Operating guide](docs/product/RECEIVER_CONFIRMED_STOCK.md).

The [full manual pilot test pack](public/templates/profitplate-full-test-pack-2026-11-17-v2.zip)
contains a 16-tab Excel test workbook, 84 detailed cases, a printable PDF/browser
guide, expected stock checkpoints, role/account setup, result tracking and sign-off.
All manual results start **Not run**. The workbook is not an application import;
the fictional CSV examples require their date/outlet placeholders to be replaced.
Rebuild with `python scripts/build-pilot-test-pack.py`, print with
`node scripts/print-pilot-test-guide.mjs`, then verify/package with
`python scripts/verify-pilot-test-pack.py`.

**Inventory Manager** is the business-wide stock control role. Apply
[migration 025](supabase/migrations/202611160025_inventory_manager.sql) after 024
and explicitly assign the role in Users & roles. It oversees physical stock,
locations, movement routes, department access and stock approvals without
granting financial or general team administration. [Role and setup guide](docs/product/INVENTORY_MANAGER.md).

**Department stock access** is available under **Inventory & movements → Department access**.
After applying 023, apply [migration 024](supabase/migrations/202611160024_stock_department_access.sql)
and deploy. Administrators can restrict Inventory/Operations staff to Main Store,
Kitchen, Bar or other stock locations with separate request, handling and route
approval permissions. Existing staff retain their prior outlet access until
explicitly assigned. [Fine-dining setup and checks](docs/product/STOCK_DEPARTMENT_ACCESS.md).

**Configurable inventory & movements** supports central warehouses, outlet stores,
department routes, independently approved requests, dispatch/receiving, opening
balances, physical counts, waste, consumption and recipe production. Apply
[migration 023](supabase/migrations/202611160023_stock_locations_and_movements.sql)
after 022, then deploy the application. Existing GRNs require explicit stock
posting; nothing is automatically backfilled. Quantity tracking does not change
reference-price financial estimates or introduce actual inventory valuation.
See [setup instructions and scope](docs/product/INVENTORY_MOVEMENTS.md).

**Menu Profitability** is available under **Menu & prices → Menu profitability**.
Apply only [migration 022](supabase/migrations/202611160022_menu_profitability.sql)
after 021. Compare estimated cost per serving, tax-exclusive selling prices,
food cost %, food profit and food gross margin % by outlet, channel and date.
Contribution margin remains explicitly unavailable until other variable costs
are connected. See [the profitability notes](docs/product/MENU_PROFITABILITY_MILESTONE.md).

**Consistent record tables across the workspace** extend the PO/GRN table design
to catalogues, reference prices, recipes, menus, sales, expenses, team records,
locations, executive comparisons and report histories/details. Forms, charts and
summary cards retain their purpose. This presentation update needs no new SQL.
See [the table layout review](docs/product/TABLE_LAYOUT_REVIEW.md).

**PO totals, status filters and record tables** add automatic decimal-safe order
totals and table layouts for Purchase Orders, GRN history and document lines.
Apply only [migration 021](supabase/migrations/202611160021_purchase_order_register.sql)
after 020 to enable the filtered PO register. Filters include Draft, Issued,
Pending delivery, Partially received and Completed. Completed means fully received
through non-voided GRNs; Procurement still issues POs directly. Existing records
and invoice-total reconciliation are preserved.

**Purchase Orders, GRNs and invoice matching** are available under Purchases.
Procurement raises/issues orders; Inventory / Receiving confirms partial deliveries
within assigned locations. Finance reviews invoice exceptions and submitted GRN
voids. New manual bills choose a PO or a
reason/evidence reference for buying without one. Apply only
[migration 018](supabase/migrations/202611150018_purchase_orders_and_receipts.sql), then
[migration 019](supabase/migrations/202611150019_procurement_invoice_matching.sql),
after 017, followed by [migration 020](supabase/migrations/202611160020_inventory_receiving_separation.sql).
If 019 is already applied, run only 020. Existing Procurement users retain purchasing
access and lose receiving access; administrators must explicitly assign the new
Inventory / Receiving role to a separate colleague in Users & roles. Neither the
preparer nor issuer may confirm that PO's delivery, even with both roles. Existing
POs and GRNs remain intact. This does not record payment or post stock. See
[the workflow notes](docs/product/PO_GRN_MATCHING_MILESTONE.md).

**Direct transaction entry** adds Finance expense recording, Procurement purchase
recording, named
supplier-invoice entry with multiple lines, and Finance-approved procurement
replacement/void requests. Apply only [migration 016](supabase/migrations/202611150016_direct_transactions.sql)
after 015, followed by [migration 017](supabase/migrations/202611150017_procurement_operational_permissions.sql)
to enforce the Procurement/Finance split. If 016 is already applied, apply only 017.
Finance reviews purchases and approves corrections; it does not perform purchase
operations through a Finance-only role. Original evidence remains preserved; invoice entry does not confirm
delivery or post stock. See [the transaction notes](docs/product/DIRECT_TRANSACTIONS_MILESTONE.md).

**Management-report review and approval** adds Finance submission/comments and
CEO/Restaurant Administrator decisions on saved reports. Apply only the new
[migration 015](supabase/migrations/202611150015_management_report_reviews.sql)
after 014. Approval preserves estimate/coverage warnings and does not close an
accounting period. Review decisions, reasons and withdrawal remain auditable.
See [the review notes](docs/product/REPORT_REVIEW_MILESTONE.md).

**Saved management-report history** is available from Management reports. Apply
only the new [migration 014](supabase/migrations/202611150014_management_report_history.sql)
after 013, then save a named management estimate and reopen it from Report history.
Saved copies retain their original figures, context and coverage warnings, with
CSV and print/PDF. These are not approved accounting statements or period close.
See [the report-history notes](docs/product/REPORT_HISTORY_MILESTONE.md).

**Recipes & scaling** is now available under Profitability. Apply the NEW
[`202611140005_versioned_recipes.sql`](supabase/migrations/202611140005_versioned_recipes.sql)
once after 004. Create material records first, then define batch recipes and
sub-recipes. New publications preserve previous versions, and the scaling preview
uses pinned sub-recipe versions and package conversions. It does not post stock
movements or calculate financial costs. The user deferred the costing policy;
missing costs remain explicitly marked. See
[the recipe implementation notes](docs/product/RECIPES_MILESTONE.md).

The next delivered module is **Materials & suppliers** under Data & Setup.
Run the NEW migration
[`202611140004_materials_and_suppliers.sql`](supabase/migrations/202611140004_materials_and_suppliers.sql)
once after 003, then open `/workspace/materials` using your restaurant-owner account.
It adds material/supplier editing, inactivity controls, name search, pagination,
standard units and effective-dated item-specific conversions. See the
[catalogue implementation notes](docs/product/CATALOGUE_MILESTONE.md) for access
rules, preserved legacy data and the limits of this milestone. Costs remain
unconnected until financial costing is implemented.

Apply **only** the new migration
[`202611140003_restaurant_onboarding.sql`](supabase/migrations/202611140003_restaurant_onboarding.sql)
once in Supabase SQL Editor after migrations 001/002. Existing founder records,
organisation IDs and branch IDs are preserved. Do not rerun the initial schema.

Set `NEXT_PUBLIC_SITE_URL=http://localhost:3000` in `.env.local` and restart dev.
In Supabase Authentication URL Configuration, allow
`http://localhost:3000/auth/confirm` for registration, alongside the existing
`http://localhost:3000/auth/callback` for password recovery. Use the corresponding
HTTPS app URLs in production. Keep the default confirmation email template using
`{{ .ConfirmationURL }}`; PKCE links should open in the same browser that registered.
Enable email/password signup and email confirmation in Supabase for production.
No service-role key is needed by the app.

Visit `/signup` using a **separate restaurant-owner email**, not the founder
account. Verify the email, sign in, and complete the three-step setup. Save for
later persists a private draft to the signed-in account. Finalisation creates
the business, brand, first outlet, scoped membership, CEO/admin roles and audit
event in one transaction. Repeating completion returns the same business ID.
Founders continue to use `/admin`; they are not automatically restaurant owners.

The customer workspace at `/workspace` is a role-based home. Invitation acceptance
and later sign-ins open Procurement, Finance, Executive, Administration or Operations
workspaces using active database membership roles. Shortcuts follow existing server
capabilities; combined roles retain their permitted tasks and location scopes.
Data & Setup is available explicitly at `/workspace/setup` to restaurant
administrators. New owners visit it once after completing onboarding. This routing
change requires no additional SQL migration.

Repeatable checks (database tests use embedded PostgreSQL; browser auth is simulated):

```powershell
npm.cmd run test:db
npm.cmd run build
npm.cmd run test:e2e
```

Browser tests require installed Google Chrome and free local ports 3101/54398.
They start their own isolated services, redirect Supabase calls within that test
process, and never connect to your live database. Production build is a prerequisite.
Real Supabase email delivery and signup settings require a manual integration check.

## Getting Started

The app uses `@supabase/supabase-js` for Supabase database, authentication, and
storage access. Set `NEXT_PUBLIC_SUPABASE_URL` and
`NEXT_PUBLIC_SUPABASE_ANON_KEY` in `.env.local`, then restart the development
server. Client Components can use the shared browser client:

```js
import { supabase } from "@/lib/supabase/Client";
```

First, run the development server:

```bash
npm run dev
# or
yarn dev
# or
pnpm dev
# or
bun dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

## Login and founder access

The sign-in page is at `/login`. Sessions use Supabase SSR cookies, with session
refresh in `proxy.ts`. Server pages validate the user with Supabase Auth before
rendering protected content. The founder page at `/admin` also checks the
`is_platform_admin()` database function on each request; it never trusts a role
stored in the browser or editable user metadata. `/dashboard` routes signed-in
users to their appropriate workspace. Sign-out clears the local session.

Before testing your founder login, run the NEW migration
[`202611140002_platform_admin_access.sql`](supabase/migrations/202611140002_platform_admin_access.sql)
in Supabase SQL Editor. It preserves the founder record already created in
`private.platform_admins` and adds the narrowly scoped permission-check function.
Do not rerun the initial schema migration. No service-role key is required.

If you signed in but saw an administrator-verification error, the permission-check
function may be missing. Run that same new migration and refresh `/dashboard`.
It is safe to rerun and requests a REST API schema-cache reload. Missing setup or
failed permission checks now open `/account-access`, without treating the account
as a restaurant member. After the check is restored, founders visiting
`/workspace` are automatically redirected to `/admin`.

Use the email and password created under **Authentication → Users**, which can
differ from the Supabase dashboard login. A successful founder login opens the
founder workspace. Restaurant members open their assigned role workspace.

### Password recovery

Set `NEXT_PUBLIC_SITE_URL=http://localhost:3000` in `.env.local` for local testing
(and the canonical HTTPS app URL in production). In Supabase **Authentication →
URL Configuration**, allow `http://localhost:3000/auth/callback`, plus the matching
production callback when deployed. Keep the default Supabase password reset email
template that uses `{{ .ConfirmationURL }}`. `/forgot-password` sends a PKCE reset
link, `/auth/callback` exchanges its code for a session, and `/reset-password`
saves the replacement password. Open the reset link in the same browser that
requested it, since PKCE uses a browser cookie. Expired or invalid links return
to the recovery form. Delivery depends on the project's Supabase email settings
and email rate limits.

The UI uses the existing forest-green, cream and gold theme and Geist font. A
separate product specification has not yet been supplied; final layout review
against that document is pending.

You can start editing the page by modifying `app/page.tsx`. The page auto-updates as you edit the file.

This project uses [`next/font`](https://nextjs.org/docs/app/building-your-application/optimizing/fonts) to automatically optimize and load [Geist](https://vercel.com/font), a new font family for Vercel.

## Learn More

To learn more about Next.js, take a look at the following resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.

You can check out [the Next.js GitHub repository](https://github.com/vercel/next.js) - your feedback and contributions are welcome!

## Deploy on Vercel

The easiest way to deploy your Next.js app is to use the [Vercel Platform](https://vercel.com/new?utm_medium=default-template&filter=next.js&utm_source=create-next-app&utm_campaign=create-next-app-readme) from the creators of Next.js.

Check out our [Next.js deployment documentation](https://nextjs.org/docs/app/building-your-application/deploying) for more details.

## Workspace attention and simpler navigation

Apply migration `202611170031_workspace_attention_and_platform.sql` after 030 and deploy the corresponding app version. PO approval remains out of scope. See [role workspace changes and pilot checks](docs/product/WORKSPACE_SIMPLICITY.md).
