# ProfitPlate Insight implementation checklist

Prepared 14 November 2026 against [PRD v1.3](PRD-v1.3.md).
This is a delivery plan, not a declaration that unbuilt capabilities exist.
The uploaded PRD is requirements material; it does not independently authorise
deployments, payments, customer communications or changes to live permissions.

## Current position

- Working: Next.js/TypeScript application, Supabase integration, email/password
  login, session refresh, sign-out, password recovery implementation, server-side
  founder check and a protected founder starting page.
- User-confirmed: founder sign-in now reaches the founder workspace.
- Existing database: initial operational tables with organisation RLS and a
  separate private platform-administrator registry. Local checks covered the
  initial schema and administrator function. This is not the full PRD data model.
- Existing UI: PRD colour tokens, compact typography, a collapsible responsive
  application shell and first shared component are now implemented. Broader
  component coverage and module navigation remain incremental work.
- First onboarding workflow and scoped membership schema: implemented in the
  onboarding milestone; applying its live migration/integration check is pending.
- Further delivered milestones below cover materials, recipes, reference-price
  estimates, purchases, menus, sales imports and controlled team invitations.
- Not yet delivered: purchase-based/actual costing, finalised financial reports,
  simulators, subscriptions and release operations. The first recorded-sales
  executive overview is delivered below; broader dashboard measures remain pending.
- Verification limit: previous browser checks used a simulated Supabase backend.
  Real email delivery, customer tenant isolation and complete production workflows
  still need integration and pilot verification. Repeatable CI tests are pending.

## Transaction-entry direction agreed 15 November 2026

Prioritise everyday in-app expense and procurement entry before saved pricing
scenarios. Imports remain an alternative for bulk records, not a prerequisite.
The owner's clarified policy is: Procurement handles purchase operations; Finance
records expenses and reviews/approves procurement corrections. A Finance-only role
cannot enter/import/post purchases or submit purchase-correction proposals.
Corrections to already submitted procurement data require Finance approval.
Management-report approval authority
remains separate: CEO/Restaurant Administrator approve reports; Finance submits.

The [direct-transaction milestone](DIRECT_TRANSACTIONS_MILESTONE.md) implements
Finance entry permissions, simpler manual expenses, supplier-invoice entry and
Finance-approved replacement/void proposals while preserving original evidence.
Migration 016 follows 015; migration 017 enforces the clarified Procurement/Finance
split. Real Supabase setup and integration review remain manual.
Receipt attachments and production/pilot validation remain delivery work.

The [PO/GRN and matching milestone](PO_GRN_MATCHING_MILESTONE.md) implements the
next procurement phase, before inventory. The owner selected Procurement issuing
POs directly and Finance reviewing invoice exceptions. Migrations 018/019 add
draft/issued orders, partial GRNs, Finance-reviewed GRN voids, PO-backed versus
explicit no-PO bills, cumulative matching and source-sensitive exception reviews.
Direct bills remain supported. No payment or inventory posting is implemented.
Matching uses exact comparisons without silently selecting tolerance policies.

Inventory remains a future module. The existing inventory movement table references
legacy branches/ingredients, whereas current purchases use locations/items.
Reviewed additive migrations must connect the modern model, distinct goods
receipts, stock movements/counts/transfers and production/waste. Purchase recording
must not silently imply a new stock posting or an approved valuation policy.

## Delivery rules

1. Build complete workflows: interface, validation, server authorisation, database
   persistence, audit trail where applicable, meaningful tests and review steps.
2. Use incremental, reviewed migrations. Preserve founder access and existing data;
   never ask the user to rerun the original create-table migration.
3. Every tenant-owned entity must meet the PRD organisation, UUID, timestamp and
   audit requirements. Enforce same-organisation relationships in the database.
4. Missing costs remain missing. Display VERIFIED, PROVISIONAL, ESTIMATED, MISSING
   or UNRECONCILED as appropriate; never manufacture verified margins.
5. Platform administration provides controlled, audited support access. It does
   not automatically expose every restaurant's financial records.
6. Display only implemented, enabled and authorised customer navigation entries.
   Maintain shared reporting-period, brand and location context where applicable.
7. Agree unresolved business policies before presenting them as final defaults.
8. At each milestone report: delivered behaviour, validation evidence, database
   actions required, limitations and the next milestone.

## Phase 0: finish the foundation

- [x] Adopt PRD colour tokens: forest #174C3C, deep #24765B, gold #C4A66A,
  background #F6F8F6, white #FFFFFF, border #DCE7DF, text #24352D,
  secondary #68766E, error #B54747 and caution #B7791F.
- [x] Use Inter or compatible sans-serif. Titles 24–28px, sections 17–20px,
  KPIs 24–32px, body 13–15px, tables 12–14px. Remove decorative gradients
  and oversized product headings.
- [ ] Add shadcn/ui-based shared components alongside Tailwind, with keyboard,
  visible-focus and screen-reader support. Retain working auth behaviour.
- [ ] Build reusable AppShell, 220–250px collapsible Sidebar, Topbar, loading,
  empty/error/success states, form controls, tables and confirmation dialogs.
- [ ] Establish the six customer groups: Overview, Profitability, Simulators,
  Operations, Reports, Data & Setup. Keep founder administration separate.
- [ ] Design and migrate memberships with multiple roles per user, brands,
  locations and organisation/location-scoped permissions.
- [ ] Define and test CEO/MD, Finance/Auditor, Inventory/Procurement Manager,
  Operations Manager and Restaurant Administrator capabilities.
- [ ] Add audit foundations and storage policies; explicitly govern support access.
- [ ] Establish reproducible tests, seed fixtures and CI checks.

Acceptance: founder and restaurant roles stay separate; two tenants cannot read
or change each other's records through tables, storage, RPCs or server actions.

## Phase 1: guided setup, masters and configuration

- [ ] Implement signup/email verification and controlled team invitations.
- [x] Create organisation, first brand/location and initial owner membership
  together, with duplicate-safe retry behaviour.
- [ ] Build seven save/resume setup stages: business profile/concept;
  brands/locations; users/roles; materials/UOM/suppliers; recipes/menu/prices;
  sales/procurement mappings; financial policies/readiness.
- [ ] Implement material and supplier masters, UOMs and validated conversions,
  departments, sales channels and relevant business configuration.
- [ ] Provide contextual help, sample templates and visible missing-data progress.
- [ ] Keep later-stage configuration usable as its dependent modules arrive.

Acceptance: a restaurant can set up its business and first location, return later
without losing progress, and understand incomplete setup without database terms.

## Phase 2: versioned recipes and costing

- [ ] Migrate recipe/sub-recipe versions, components, outputs and yields; prevent
  cyclic sub-recipes and invalid conversions.
- [ ] Add menu mappings, variants, effective-dated prices, packaging rules,
  substitutions and material cost history.
- [ ] Replace the initial implicit zero-cost default with explicit cost/readiness
  handling. Review existing zeros; do not assume they mean verified free inputs.
- [ ] Implement decimal-safe costing and immutable cost snapshots with provenance.
- [ ] Distinguish ingredient/direct-packaging food GP from contribution and
  supported operating profit. Preserve tax, refunds and service-charge policy.
- [ ] Test single-outlet QSR, bakery batch/sub-recipe and multi-outlet fixtures.

Acceptance: versioned inputs reproduce a recipe cost; later changes preserve
history; missing costs cannot produce a verified margin.

## Phase 3: sales and procurement import centre

- [ ] Support XLSX/CSV upload, dataset choice, mapping and validation.
- [ ] Store original file, hash, source, batch, mapping version, row outcomes and
  posting identity with tenant-protected storage.
- [ ] Reconcile source totals, show exceptions and require authorised posting.
- [ ] Implement sales/purchase headers and lines, adjustments and stable source
  document/line keys; keep spreadsheet templates separate from physical tables.
- [ ] Make posting transactional and idempotent, including retries and recovery.
- [ ] Process large files in background jobs with progress and retry handling.
- [ ] Record discounts, refunds, cancellations, channel and outlet correctly.

Acceptance: valid imports reconcile, invalid rows have understandable outcomes,
and uploading/posting the same source again cannot duplicate transactions.

## Phase 4: material intelligence and profitability

- [ ] Calculate purchase-weighted prices and effective material cost periods
  under an explicitly selected costing policy.
- [ ] Show material changes and affected recipes; keep purchase-weighted recipe
  costs distinct from inventory-consumption valuation.
- [ ] Implement menu food GP/contribution, targets, trends, outlet/channel
  comparisons and cost coverage/confidence.
- [ ] Implement Stars/Plowhorses/Puzzles/Dogs using category baselines and
  configurable thresholds; include insufficient-data states.

Acceptance: profitability reconciles to its source/cost basis and incomplete
coverage prevents misleading aggregate margins.

## Phase 5: executive Overview and reporting

- [ ] Build prioritised KPIs, trends, sales mix, outlet comparisons and decisions.
- [ ] Attach period, currency, cost basis, readiness and last successful refresh
  to financial displays; provide drill-down to underlying records.
- [ ] Explain each exception's change, financial significance and review action.
- [ ] Show operating profit only when input completeness supports it; label
  modelled allocations as estimates.
- [ ] Build daily/weekly/monthly executive packs, export and report history.
- [ ] Freeze approved periods/reports and audit authorised adjustments.

Acceptance: an executive can identify key exposure from Overview; finalised
reports remain reproducible after later recipe, price and policy changes.

## Phase 6: pricing, promotion and combo scenarios

- [ ] Build saved scenarios with assumptions, versions, comparison and approvals.
- [ ] Pricing: component costs, current/proposed prices and target margins.
- [ ] Promotions: baseline/expected volume, incremental contribution, campaign
  cost, cannibalisation and break-even uplift.
- [ ] Combos: parent sale, selectable quantities, zero-priced POS children,
  packaging replacement rules, contribution and break-even.
- [ ] Keep scenario calculations isolated from live menu prices; require a
  separate authorised approval action to publish any live price change.

Acceptance: scenarios reproduce from saved assumptions and do not silently
change operational prices or historical results.

## Phase 7: pilot and commercial release

- [ ] Agree subscription packaging/pricing, then implement billing and entitlements.
- [ ] Add operational monitoring, error alerting, job visibility and support audit.
- [ ] Configure production hosting, email, secrets, backups and recovery procedures.
- [ ] Verify backup restoration and migration/deployment rollback procedures.
- [ ] Agree and measure pilot performance targets and import size limits.
- [ ] Test tenant isolation, financial correctness, browser workflows, accessibility
  and desktop/mobile regression paths in CI and a production-like environment.
- [ ] Pilot core workflows with restaurant users and resolve release blockers.

Acceptance: pilot users complete setup, imports, costing, profitability and
reports without developer intervention; release and support procedures work.

## Deferred scope

Full stock operations, central-kitchen transfers, advanced production, asset
custody, direct POS connectors, demand forecasts and predictive recommendations
are deferred by PRD section 12. Existing inventory tables do not make these
workflows complete or move them ahead of the intelligence/import foundations.
The MVP also excludes a full POS, accounting ledger and comprehensive asset system.

## Acceptance traceability

| PRD section 13 criterion | Main delivery phases |
| --- | --- |
| 1 Tenant isolation, storage and functions | 0, enforced throughout |
| 2 Onboarding without database terminology | 1 |
| 3 Reconcilable, duplicate-safe POS/purchase imports | 3 |
| 4 Reproducible recipe/sub-recipe/combo costs | 2, 4, 6 |
| 5 Missing costs never become verified zero margins | 2, 4, 5 |
| 6 Reproducible finalised historical reports | 2, 5 |
| 7 Scenarios isolated from live prices | 6 |
| 8 Executive Overview exposes key financial issues | 5 |
| 9 QSR, bakery and multi-outlet model tests | 0–4 |
| 10 Consistent responsive navigation and feedback states | Every phase |
| 11 Financial and isolation tests in CI | 0, expanded every phase |
| 12 Independent pilot workflow completion | 7 |

## Inputs and business decisions still needed

Both supporting baselines have now been supplied and reviewed:
[Universal Data Model v1.1](DATA_MODEL-v1.1.md) and the
[Master & Transaction Import Workbook inventory](IMPORT_WORKBOOK-v1.1.json).
The workbook contains 20 templates plus two documentation sheets. See the
[data contract review](DATA_CONTRACT_REVIEW.md) for source conflicts, field gaps,
logical destination mappings and migration prerequisites. These are proposed
contracts, not a deployed schema or a production-ready validation specification.
Safe UI foundation work can proceed while pending policies are resolved.

| Decision | Needed before |
| --- | --- |
| Product name/domain/trademark review | Public commercial launch |
| Role/location matrix and support approval model | Permission migration and invitation workflows |
| Canonical schema names, legacy transition and UOM dictionary ownership | Next foundation/master-data migrations |
| Required/conditional field rules and version-pinning extensions | Import validation contract |
| Recipe loss/yield semantics and multi-output policy | Recipe calculation acceptance |
| Default costing/valuation and effective-period policy | Costing engine and historical reporting |
| Tax, refunds and service-charge conventions | Sales import and revenue calculations |
| Overhead allocation methods | Estimated allocation-based profitability |
| Minimum verified-margin coverage | Verified aggregate margin displays |
| Import size limits and job expectations | Background import delivery |
| Scenario approval authority | Scenario approval and live-price workflows |
| Subscription packaging/pricing | Billing integration |
| Pilot performance targets | Pilot acceptance |

Record each decision's selected value, scope, approver, date and effective
version. The PRD's pending policies are not final business defaults.

## Next implementation milestone

Finish Phase 0 and deliver the first Phase 1 workflow: a PRD-aligned interface,
scoped membership foundation, and restaurant signup/setup creating a business,
first brand/location and owner membership. Include save/resume and cross-tenant
tests. This milestone does not claim all seven onboarding stages are functional
before their dependent costing/import modules exist.

### First onboarding workflow implemented

See [ONBOARDING_MILESTONE.md](ONBOARDING_MILESTONE.md) for delivered behaviour,
canonical naming/compatibility choices, the required migration, repeatable tests
and remaining limitations. The UI, private drafts, atomic restaurant/brand/outlet
creation and owner membership are implemented. Applying the migration and checking
real Supabase email confirmation remain deployment/integration tasks. Staff
invitations, broader role/action policies and the remaining setup modules are not
marked complete by this first workflow.

### Material catalogue implemented

The [catalogue milestone](CATALOGUE_MILESTONE.md) delivers material/supplier masters,
standard tenant-owned units, validated effective-dated conversions, audited writes,
read-only roles and paginated responsive screens. Migration 004 must be applied
to the live project. Financial costs, category/custom-unit editing, import mapping
and staff invitations remain pending; this does not complete all Phase 1 requirements.

### Recipe versions and quantity scaling implemented

The [recipe milestone](RECIPES_MILESTONE.md) delivers immutable recipe/sub-recipe
versions, single batch outputs, pinned source conversions and quantity scaling.
Migration 005 must be applied to the live project. The user explicitly deferred
the costing-policy decision; no financial cost engine is declared complete.
Menu mapping, historical prices, loss/substitution rules and other Phase 2 work
remain pending.

### Optional onboarding reference prices implemented

The [initial-prices milestone](INITIAL_PRICES_MILESTONE.md) adds manual and reviewed
CSV reference estimates, dated unit normalisation, append-only price history and
financial-access controls. Migration 006 must be applied in the live project.
Restaurants can continue setup with missing prices. Reference estimates do not
create purchases or stock, establish actual costs, or settle the deferred costing
and valuation policies. Recipe financial calculations remain the next milestone.

### Recipe reference-cost preview implemented

The [recipe estimate milestone](RECIPE_COST_ESTIMATES_MILESTONE.md) connects saved
composition and reference prices into estimated batch, per-output-unit and target
costs. Missing prices block full totals and expose a labelled partial subtotal.
Migration 007 must be applied after 006 in the live project. The preview is read-only
and can change when reference prices are corrected; it is not a finalised historical
report. Purchase-weighted costing, margins and actual financial reporting remain
pending their source data and business policies.

### Purchase invoice imports implemented

The [purchase import milestone](PURCHASE_IMPORTS_MILESTONE.md) delivers the supplied
purchase-sheet CSV contract, private staged source retention, row findings,
explicit code mappings, supplier-invoice controls, atomic recording, duplicate
protection and paginated history. Migration 008 follows 007. This records invoice
evidence without posting stock or changing reference prices. XLSX, background
jobs, posted corrections/returns and purchase-weighted costing remain separate
deliveries. Source tax inclusion is explicitly selected per import; tax
recoverability and accounting costing policies remain unselected.

### Menu links, selling prices and food-margin previews implemented

The [menu milestone](MENUS_AND_SELLING_PRICES_MILESTONE.md) extends the existing
menu catalogue with immutable final-recipe links, serving quantities, dated
location/channel prices, explicit tax treatment and reference-based food margins.
Migration 009 follows 008. Missing prices or ingredient costs block complete
margins; negative margins remain visible. Legacy static prices are preserved but
never inferred as dated prices. Combos, menu/sales imports, channel fees,
purchase-based cost policy and finalised financial reports remain pending.

### Standard paid sales imports and period food-margin previews implemented

The [sales milestone](SALES_IMPORTS_MILESTONE.md) adds source-tax declarations,
menu/location/channel mapping, receipt controls, immutable posted menu bindings,
duplicate-safe recording, private source/history and period/location summaries.
Migration 010 follows 009. Recorded revenue includes source discounts and declared
tax treatment; costs remain reference-based estimates with explicit coverage and
missing-cost blocking. Combos/refunds/voids and large/background reporting remain
deferred. This does not approve purchase-costing policy or finalised actual profit.

### Users, roles and controlled team invitations implemented

The [team milestone](TEAM_ACCESS_MILESTONE.md) adds private administrator-only
team management, seven-day email-bound invitation links, verified acceptance,
multiple scoped roles, protected owner/self access, optimistic member updates,
deactivation/reactivation and lifecycle audits. Migration 011 follows 010. No
invitation emails are sent automatically. Existing location-scoped financial
restrictions remain in force; live Supabase validation follows migration setup.

### Executive overview implemented for recorded sales

The [overview milestone](EXECUTIVE_OVERVIEW_MILESTONE.md) combines the existing
source-reconciled revenue and reference-cost estimate with daily trends, channel
mix, outlet revenue comparisons, source receipts and missing/negative-cost alerts.
Migration 012 follows 011. Role-relevant navigation and reporting context between
Overview and Sales are included. Actual profit, target policies and finalised
reports remain deferred; live validation follows migration setup.

### Labour and operating expense foundation implemented

The [expense milestone](EXPENSES_MILESTONE.md) adds explicit coverage/payment dates,
ON_DATE or chosen daily management recognition, central versus outlet scope,
reviewed labour/operating completeness and reference-based estimated prime cost.
Manual and CSV entries share atomic source review, duplicate protection, private
originals and audited voids. Migration 013 follows 012 and preserves legacy data
without guessing classifications. Full accounting profit, actual inventory COGS
and menu/outlet allocation policies remain deferred. Live setup remains manual.

### Labour and expenses connected to Executive overview

The overview now reuses the expense-report service for the exact selected period
and outlet. Recorded labour, operating expenses, estimated prime cost, exact-scope
coverage warnings and central-cost exclusions appear together with sales.
Read-only drill-down preserves reporting context. Migration 013 is reused;
no new SQL is required. Actual profit and allocation policies remain deferred.

### Downloadable executive management reports implemented

The [management-report milestone](MANAGEMENT_REPORTS_MILESTONE.md) adds daily,
last-seven-days, monthly and custom-period reports with source financial values,
coverage status, outlet/channel/menu details, same-view CSV download and a clean
browser print/PDF layout. Existing report permissions and migration 013 are reused.
No new SQL is needed. Saved report history and approved immutable snapshots remain
pending; these exports are explicitly live management estimates.

### Saved management-report history implemented

The [report-history milestone](REPORT_HISTORY_MILESTONE.md) adds named, immutable
management estimates, tenant-restricted paginated history, preserved figures and
coverage, and saved-copy CSV/print. Migration 014 follows 013. Saves generate their
own source figures in the database, audit creation and safely reuse retry IDs.
Source links open current records; these copies do not approve or close accounting
periods. Live migration and real Supabase integration review remain manual.

### Management-report review and approval implemented

The [report-review milestone](REPORT_REVIEW_MILESTONE.md) adds submission,
comments, changes requests, management approval and reasoned withdrawal, with
append-only events, revision conflict checks and retry-safe audit records.
As selected by the owner, organisation-wide CEO and Restaurant Administrator
approve; Finance submits and comments. Migration 015 follows 014. Saved source
figures remain immutable and no accounting period is closed. CSV/print preserve
the visible management decision and estimate basis. Live setup remains manual.
