# Restaurant onboarding milestone — 14 November 2026

## Delivered

- Exact PRD semantic palette; compatible Geist sans-serif with compact page titles.
- Collapsible 240px sidebar and responsive navigation with keyboard dismissal,
  focus return, focus containment and background inertness on mobile.
- Shared shadcn-style Button using Radix Slot/CVA, semantic states and icon system.
- Email/password registration, email confirmation route and existing login/recovery.
- Three-step business, brand/location and review workflow, with private server-saved
  drafts and an atomic, idempotent finalisation function.
- Canonical brands, locations, memberships, multiple roles and location scope.
- Saved business/location workspace with two completed stages out of the seven
  PRD stages, missing-financial-data state and no fabricated KPI figures.
- Tenant audit event for completed onboarding; client audit writes are prohibited.
- Tracked PostgreSQL and production-browser tests rather than temporary-only checks.

## Engineering choices and compatibility

- Membership records are canonical `organisation_memberships` / `membership_roles`.
  The owner receives organisation-wide `ceo` and `restaurant_admin` roles.
- The shared, client-read-only `roles` dictionary is not a customer-owned table.
  Personal `restaurant_setup_drafts` belong to an auth user before a tenant exists.
  These two explicitly separate cases do not carry organisation_id.
- Legacy branches are backfilled to canonical `locations` with the same UUID.
  New outlet setup writes both records in the same transaction because existing
  sales/purchase foreign keys still reference branches. Do not independently edit
  legacy branches through old APIs: future location editing needs an explicit
  dual-write/transition operation. The first location type is OUTLET only.
- Each legacy organisation receives a PRIMARY brand using its existing name.
  This is a compatibility placeholder, not evidence of an actual brand portfolio.
  Legacy concept is left unknown; the workspace marks readiness for review.
- Owner and existing legacy member memberships are backfilled. Legacy managers
  map to restaurant_admin; analysts map to finance. This preserves the existing
  organisation-wide read/write split without inventing location assignments.
- The old organisation_members assignment API becomes read-only. New membership
  assignment management must use audited, authorised operations in a later milestone.
- New members must have active memberships. Scoped staff see only their permitted
  canonical locations/brands. They do not receive broad access to legacy operational
  tables, which do not yet have full per-action/per-location policies. A later
  operational milestone must implement those policies before exposing those screens.
- Financial, tax, UOM, valuation, allocation and subscription decisions remain
  pending; onboarding does not assign unapproved financial rules.
- Currency is selected explicitly. No foreign-exchange conversion is provided.
- Founder administration remains independent of restaurant membership. New-restaurant
  setup from a platform-admin account is rejected in both the UI and SQL functions.

## Deployment and verification limits

The new migration must be applied once by the Supabase project administrator.
The development agent has public app credentials, not database administrator
credentials; it has not applied this migration to the live project.

Database tests exercise real PostgreSQL migrations, RLS and RPCs through PGlite.
Browser tests exercise the production app against PGlite with simulated Auth and
REST transport. This verifies application flows, not delivery of real emails or
every production Supabase setting. Test with two separate restaurant-owner accounts
after applying the migration and configuring allowed confirmation URLs.

Staff invitations/assignment UI, business/location editing, the other five setup
stages, tenant storage features, full operational role/action permissions and CI
hosting integration remain open. This milestone completes the first onboarding
workflow, not all Phase 0/1 requirements.
