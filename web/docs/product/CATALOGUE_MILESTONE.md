# Materials, units and suppliers milestone

## Delivered behaviour

- `/workspace/materials` is linked from customer navigation and setup stage 4.
- Materials include organisation-local codes, names, type, optional category,
  measurable base unit, quantity-tracking preference and active/inactive status.
- Supplier records include stable codes, names and optional email/phone/address.
  Phone numbers remain text, preserving leading zeros.
- Both master lists support name search, active/inactive filters and server-side
  pagination (25 rows). Mobile layouts use record cards instead of narrow tables.
- Existing records can be edited, made inactive and reactivated. Codes and material
  base units cannot change after creation. New canonical materials do not populate
  the legacy ingredients table; future recipes/imports will use canonical items.
- Each organisation has its own read-only unit dictionary: KG, G, L, ML, PCS,
  BAG, CARTON, PACK and BOTTLE. Package units have no assumed universal factor.
- Conversions belong to a specific material and always target its base unit.
  Standard dimensional factors are validated in PostgreSQL. Package factors are
  explicit inputs, using positive numeric(20,6) values without JS float conversion.
- Effective-date versions are immutable. Repeating the identical item/source/date/
  factor returns the existing version. Changing a factor requires a different date.
- Saving a material does not set a financial cost. The UI says “Not connected”;
  no recipe margin or zero cost is implied.

## Permissions

Active members with an assigned product role can read their own organisation's shared catalogue. Only an
organisation-wide restaurant_admin or procurement assignment can maintain it.
Scoped staff have read-only shared master access; they cannot make changes that
would affect other locations. Finance/CEO-only roles do not implicitly grant
configuration writes. The owner created by onboarding has both CEO/admin roles.
Platform administration does not grant customer catalogue access.

Every write function checks the caller's active membership and assignment.
Client table writes are denied. Updates verify organisation and record ID together;
parent/unit/category links use same-organisation foreign keys. Material/supplier
changes and conversion creation append audit events. The existing audit view is
restricted to owners; a review UI is a later capability.

## Migration and compatibility

Apply `202611140004_materials_and_suppliers.sql` ONCE, after 001–003, in the
Supabase SQL Editor. The app has no database administrator credential and has
not applied this migration to the live project.

- Existing organisations are seeded with unit dictionaries; a trigger seeds new
  organisations inside their onboarding transaction.
- Existing ingredients are copied to canonical items with preserved IDs and base
  quantities (g → G, ml → ML, each → PCS). Their old cost defaults are not copied
  into financial facts. Historical ingredient/recipe/purchase tables remain intact.
- Existing suppliers are preserved, assigned unique generated SUP codes and
  given audit metadata. Their legacy direct-write API is replaced by the audited
  supplier operation. Purchase foreign keys continue referencing the same IDs.
- Do not independently edit legacy ingredient masters to synchronise them with
  canonical items. Recipe/procurement migration will explicitly transition those
  consumers; there is no automatic dual write for ingredient changes.
- Category names resolve case-insensitively inside a tenant. Categories do not yet
  have a separate editing/import screen.

## Remaining work

Cost periods, historical valuation, recipe costing, import posting and operational
stock tracking are not implemented by this module. Conversion versions must be
pinned by the future costing/import workflows; lookup dates alone do not establish
historical financial reproducibility. Arbitrary custom UOM definitions, category
management, source-code aliases and correction/supersession UI are later work.
The setup roadmap remains 2/7 complete; starting a catalogue does not establish
that all materials or other setup stages are complete.

## Verification

`npm run test:db` includes catalogue tests for legacy preservation, duplicate
codes, immutable codes/base units, package/date versions, exact dimensions,
decimal precision, anonymous/tenant/role boundaries, cross-tenant foreign keys
and new-organisation dictionary seeding.

`npm run build` then `npm run test:e2e` exercise the production UI with real PGlite
tables/functions/RLS and simulated Supabase authentication/REST transport.
Live Supabase migration, email integration and real customer data still require
an integration check after applying the migration.
