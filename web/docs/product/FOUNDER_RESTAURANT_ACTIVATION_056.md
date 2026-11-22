# Founder activation of restaurant applications

Migration: `supabase/migrations/202611220056_founder_restaurant_activation.sql`.
Apply after 055 and before deploying the matching app. Existing Active and Inactive restaurants retain their states, identities and records.

## Applicant workflow

1. Register and verify the account email.
2. Enter the initial restaurant profile, brand, first outlet and calendar. Initial category/channel choices are retained with the application.
3. Submit for approval. The new restaurant is Pending and the applicant sees an approval-status page.
4. The applicant can sign in and check status, but cannot invite staff, enter/import master data or post operational records before activation.
5. After activation, check access again and continue to the workspace. The owner can invite an Administrator to finish detailed setup.

Pending applicants are not automatically activated, billed or given a timed trial. No outbound approval email is introduced; the Founder sees the queue in the platform dashboard.

## Founder workflow

1. Open Founder workspace > Restaurants awaiting activation.
2. Search or filter the queue and inspect the restaurant and owner contact.
3. Open Manage restaurant access. Choose Approve and activate or Decline - keep inactive.
4. Enter a reason, confirm and submit. Stale decisions fail and require a refresh.
5. Active restaurants can later be made Inactive and reactivated. The history records the decision, actor, time and reason.

Founder status alone does not grant access to restaurant operational or financial records. Directory information is platform metadata.

## Enforcement

- New restaurants default to Pending. All five current and legacy setup-completion APIs are wrapped in private, transaction-bound provisioning. Initial seed records are created atomically; membership access is suspended before registration returns. No committed new application is exposed as Active.
- Replays return the same organisation without resetting setup or reapplying categories.
- Pending/Inactive users have no active tenant membership. Existing database permission checks deny read/write access, not merely sidebar links.
- All current organisation-scoped public and private tables have active-restaurant write guards, excluding lifecycle bookkeeping and audit trails.
- Only the Founder API may change lifecycle state in normal authenticated use. Its private transition context allows membership suspension/restoration; ordinary administrators cannot create that context.
- Suspension snapshots active memberships. Reactivation restores only those memberships, preserving accounts previously deactivated. Centre-owner protections remain for ordinary colleague deactivation but do not prevent Founder suspension.
- Signup verification, password recovery and invitations into already Active restaurants continue through their existing flows.

## Efficiency and validation

The directory has an access-state/date index, ten-row pagination and an exact Pending count. Detailed setup progress is calculated for displayed existing restaurants, not for every registered business or Pending application.

Activation-specific database checks use raw PostgreSQL/PGlite and test all registration entrypoints, denial paths, replays, activation, suspension, tenant isolation and retained settings. Operational test fixtures explicitly approve their newly created restaurants through the real Founder API. Browser fixtures seed existing restaurants before applying 056, then test new applications and actual Founder review after rollout.
