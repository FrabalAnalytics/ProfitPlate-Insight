# Management-report review and approval

## Delivered and agreed authority

The owner selected: **CEO and Restaurant Administrator approve; Finance submits**.
Only active organisation-wide CEO or Restaurant Administrator roles can approve,
request changes or withdraw approval. Financial report readers, including Finance,
can submit and comment. A person holding both Finance and an authorised approver
role retains the approver capability. A separate second reviewer is not required
by this policy; an authorised CEO/administrator may review a copy they created.

Saved copies start Not submitted. Submission moves a copy to Awaiting review.
An approver may request changes with a required reason, or explicitly acknowledge
the saved figures, estimates and coverage warnings and approve for management use.
Resubmission after requested changes requires a response. Approval can be withdrawn
with a required reason, returning the copy to Changes requested. Comments are
allowed in every state and do not change the review status or latest decision.

Financial values and saved coverage never change. Correcting figures requires a
new saved report. Review acknowledgement permits management decisions on reports
with visible missing-data warnings; it never verifies those missing inputs or
turns estimates into audited accounting results. No period close, inventory
valuation change, notification or email is performed.

The saved report shows status, latest decision, reviewer identity, time and note.
Review activity is newest first, 20 events per page. All events remain in the
database. History cards show the current status. If review setup or loading fails,
figures remain available with Review unavailable and no active decision controls.

## Database setup and controls

Apply only `202611150015_management_report_reviews.sql` after migration 014.
This implementation does not apply live Supabase migrations. Do not rerun the
initial schema. Existing saved copies and their immutable payloads are preserved.

An append-only, tenant-owned event table stores action, resulting state, revision,
actor ID and email label at that time, note, approval acknowledgement, request ID
and timestamp. Same-tenant foreign keys, RLS and revoked direct table privileges
protect it. A trigger denies updates/deletes, including accidental privileged
changes. Narrow security-definer RPCs have an empty search path, check current
financial access and separately enforce approval authority. Platform founders and
location-scoped roles gain no implicit access.

Each action locks the saved parent report, checks the expected revision and
appends an event plus an audit entry transactionally. Stale actions are rejected
with a refresh instruction. Matching request retries return the original event,
including after a subsequent decision; mismatched reuse is rejected. Retries
cannot downgrade the report or duplicate its audit event. Reviews do not update
the immutable financial snapshot.

## Export and print

An unsubmitted report with no activity retains its existing V1 financial export.
Once review activity exists, CSV uses `EXECUTIVE_MANAGEMENT_REVIEW_CSV_V1`, retains
the V1 financial figures and adds status, observed review revision and latest
decision identity/time/note. This describes review metadata as loaded with the
page, not a guarantee that no later review event exists. Reload to see later
decisions. Review changes can change export metadata, while financial figures
remain the original saved values. Spreadsheet formula protection also covers
review notes and actor labels.

Print/PDF includes the visible status, latest decision and selected activity page;
forms and paging controls are hidden. The printed page labels the activity page
and limit so a paginated extract is not mistaken for the entire audit history.

## Verification

Database checks cover Finance submission/commenting without approval authority,
CEO and administrator decisions, required acknowledgement/reasons, invalid state
transitions, matching/mismatched retries, stale actions, unchanged source payloads,
current history status, paginated events and audit counts. Cross-tenant, scoped,
founder, anonymous and deactivated accounts are denied. Direct table writes and
privileged event mutations are rejected.

Export checks preserve exact decimals, missing costs and partial coverage even
after management approval, capture decision provenance, neutralise formula text
and avoid approval claims when review data is unavailable. Browser checks cover
Finance submission, administrator changes requests, stale-session rejection,
explained resubmission, approval, CSV/print, withdrawal and mobile activity.
Automated fixtures are isolated; Supabase authentication is simulated. Real
tenant/role integration review remains necessary after applying migration 015.

## Live review and next work

Save a management report, submit it from a Finance account, and open the same
copy with an organisation-wide CEO/administrator. Request changes, respond from
Finance, approve with acknowledgement, then inspect CSV, print and review history.
Try a stale second browser and a location-scoped account. Confirm that withdrawing
approval retains the earlier event and that financial values never change.

Accounting-period close, approval supersession links between corrected report
copies, report delivery and configurable approval authority remain separate work.
The next product milestone can cover saved pricing scenarios against existing
reference costs without changing live selling prices; accounting costing policy
is still an explicit pending decision.
