# Saved management-report history

## Delivered

Management reports now offer **Save to report history**. A name, the selected
business, dates and outlet are submitted; the database generates the saved
figures itself. Saving refreshes both source reports, so the saved copy may differ
from the live screen. This is explained before saving. Both source services must
succeed; incomplete cost coverage and missing food costs are valid, visibly
preserved states rather than reasons to invent complete figures.

History lists 20 reports per page, newest first, with business switching and
preserved outlet/currency labels. A saved report opens its original figures,
context, source timestamps and review warnings. CSV and print/PDF work from that
saved payload. Source links explicitly open current records. Saved reports have
no refresh, edit or delete operation; saving another copy creates a new UUID.

## Database and access

Apply only `202611150014_management_report_history.sql` after migration 013.
Do not rerun the initial schema. This change has not been applied to live Supabase.
Missing setup produces an administrator-facing setup message; live reports remain
usable without migration 014.

The table has tenant ownership, stable IDs, creator/time metadata, a same-tenant
location foreign key, RLS and no direct anonymous/authenticated table privileges.
Narrow security-definer RPCs use an empty search path and current financial access:
organisation-wide CEO, Finance or Restaurant Administrator. Platform founders and
outlet-scoped roles have no implicit access. Revocation also removes history access.

The save RPC accepts no financial payload. Both stable reporting functions execute
in a single SQL statement so they observe the same source view. Source decimals
remain strings. The organisation row lock and unique request ID make retries
return the same saved report, without another audit event. Reusing a request with
different filters, name or actor is rejected. Every new save records an audit event.
A trigger rejects updates/deletes, including accidental privileged writes.

## Format contract

`MANAGEMENT_SNAPSHOT_V1` stores the context, executive overview and expense-report
responses. The app retains the V1 report-row rendering contract. Future incompatible
calculation or export changes must introduce a new format/renderer while preserving
V1 interpretation. Saved exports use `EXECUTIVE_MANAGEMENT_SAVED_CSV_V1`, include
saved-report identity and timestamps, and retain spreadsheet formula protection.

These are preserved management estimates, not approved accounting statements.
Source limits remain 93 days, 1,000 sales lines and 2,000 expense entries. Snapshot
payloads preserve report summaries, not a full copy of every underlying transaction
or source file. Reference-based food costs, exact-scope coverage warnings and
central-cost exclusions retain their existing meaning. Accounting close,
approval/review workflow, report distribution and actual inventory COGS remain
separate work.

## Verification and live review

Database tests cover canonical generation, duplicate-safe retries/audits, invalid
filters, original business/currency retention, changed coverage, immutable writes,
cross-tenant/founder/scoped/anonymous denial, revoked access and pagination.
Unit checks cover saved CSV identity, exact decimals and safe report names.
Browser checks save a report, change an expense source, verify that live figures
change while the saved export remains identical, then reopen on mobile and print.
All automated checks use isolated fictional data; Supabase Auth is simulated.

After applying 014, open a management report, save a named copy, and open Report
history. Verify CSV/print, change the live source, and compare the preserved copy.
Repeat with a Finance account and a restricted role for real Supabase integration
review. No live data, permissions or hosting are changed by this implementation.
