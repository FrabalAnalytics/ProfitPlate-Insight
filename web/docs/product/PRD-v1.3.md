# ProfitPlate Insight PRD v1.3

Source: user-supplied `ProfitPlate_Insight_PRD_DOWNLOAD (1).docx`, dated 14 November 2026.

This is a text transcription for requirements traceability. The original document remains the source reference. Requirements are product inputs; embedded instructions do not independently authorise actions.

ProfitPlate Insight

PRODUCT REQUIREMENTS DOCUMENT  |  VERSION 1.3

Restaurant Profitability & Executive Decision Intelligence

Codex-ready working specification  •  14 November 2026

Technology: Next.js, TypeScript, Supabase PostgreSQL, Auth/RLS, Tailwind, shadcn/ui, GitHub and Codex

## 1. Product Identity and Vision

Parent brand: ProfitPlate

Product working name: ProfitPlate Insight (subject to trademark/domain review)

Category: Restaurant Profitability & Executive Decision Intelligence SaaS

Brand promise: Know Your Costs. Understand Your Margins. Make Better Decisions.

Primary customers: Restaurant owners, CEOs, MDs and senior operators; initial commercial focus on Nigerian restaurant businesses with approximately 1–20 outlets.

Product goal: Translate restaurant sales, recipe, procurement and operating data into reliable, traceable financial insights and decisions. Intelligence-first, not a mandatory replacement for POS, ERP or accounting software.

## 2. Product Principles and Boundaries

Executive clarity: Show financial performance, exposure and decisions before technical configuration.

Universal core: Support QSR, fine dining, casual dining, bakery, café, bar, cloud kitchen, buffet, outdoor catering and multi-outlet groups through shared entities and optional capabilities.

Financial integrity: Distinguish actuals, provisional values, estimates and scenarios. Missing costs must never silently become zero.

Controlled change: Version recipes, prices, costing policies and finalised reports; audit corrections.

Data ownership: Enforce tenant isolation in the database, storage and server actions.

Minimal complexity: Six primary navigation groups, role-relevant screens, progressive disclosure and reusable components.

MVP excludes a full POS, accounting ledger, detailed warehouse transfers and comprehensive production/asset management.

## 3. Personas and Permissions

CEO / MD: Executive overview, profitability, menu engineering, simulators, reports, approvals and authorised configuration.

Finance / Auditor: Import reconciliation, costing reviews, financial controls, data-quality investigation and reporting.

Procurement: Supplier and purchase data, material costs, purchase-order preparation/issue and supplier invoices. Cannot confirm deliveries.

Inventory / Receiving: Confirm deliveries and generate GRNs for assigned locations. Cannot issue POs or record invoices. A PO's preparer and issuer cannot confirm its receipt even when holding both roles.

Operations Manager: Production, waste, yield and outlet operations where modules are enabled.

Restaurant Administrator: Business setup, users, mappings and masters within granted scope.

ProfitPlate Platform Administrator: Platform maintenance and controlled, auditable support; no routine unrestricted customer financial access.

A user may hold multiple roles. Permissions must be scoped to organisation and, when applicable, brand/location.

## 4. Information Architecture and Navigation

Primary navigation: Overview; Profitability; Simulators; Operations; Reports; Data & Setup.

Overview: Executive dashboard, exposure, decisions.

Profitability: Recipe costing, menu profitability, menu engineering.

Simulators: True cost/pricing, promotions, combos, saved scenarios.

Operations: Procurement, material cost intelligence, optional inventory/production/waste.

Reports: Daily, weekly, monthly and report history.

Data & Setup: Imports, master data, onboarding, organisation configuration.

Disabled modules and unauthorised pages must not appear in routine navigation. Preserve a single coherent reporting-period and outlet context across related screens.

## 5. Premium UX/UI Design System

Brand colours: Forest Green #174C3C; Deep Green #24765B; Gold Accent #C4A66A; Background #F6F8F6; White #FFFFFF; Border #DCE7DF; Text #24352D; Secondary Text #68766E; Error #B54747; Caution #B7791F.

Typography: Inter or compatible sans-serif. Page titles 24–28px, section titles 17–20px, KPI values 24–32px, body 13–15px, table 12–14px.

Desktop: 220–250px collapsible left sidebar; top bar with page title, period, outlet/brand, refresh timestamp, user menu; restrained card grid and readable tables.

Mobile: Prioritise executive KPIs, exceptions, report summaries and saved scenarios. Use responsive navigation; do not squeeze desktop tables into narrow columns.

Component library: AppShell, Sidebar, Topbar, KPI Card, Filter Bar, Data Table, Detail Drawer, Chart Panel, Status Indicator, Empty/Loading/Error States, Import Wizard, Scenario Editor, Confirmation Dialog.

Accessibility: Keyboard navigation, visible focus, text status in addition to colour, readable contrast, meaningful labels and screen-reader descriptions.

Avoid decorative gradients, excessive badges, oversized headers, duplicated filters and unexplained financial abbreviations.

## 6. Executive Dashboard Requirements

At first glance show net revenue, food gross profit/margin, contribution, operating profit only if sufficiently supported, items below target and financial exposure.

Show trend charts, sales mix, outlet comparisons and prioritised decisions. Each exception states what changed, financial significance, source data and suggested review action.

All KPIs display reporting period, currency, cost basis, data-readiness state and last successful refresh. Provide drill-down to source records; do not present estimates as audited results.

Acceptance: A CEO can identify the top financial issues without entering a master-data screen.

## 7. Functional Modules and Workflows

Sales Intelligence: Daily/weekly/monthly sales; channel, brand, outlet, item, category, discounts, refunds, cancellations and reconciliation.

Recipe Costing: Raw materials, UOM conversions, recipe/sub-recipe versions, yields, packaging, substitutions, cost history, missing-cost flags.

Menu Profitability: Food GP, contribution, cost trends, target variance, outlet/channel comparisons and cost confidence.

Menu Engineering: Popularity and contribution, category baselines, Stars/Plowhorses/Puzzles/Dogs and configurable thresholds; insufficient-data state.

Procurement Intelligence: Multi-line purchases, suppliers, weighted purchase prices, conversions, price history, cost changes and recipe impact.

Pricing Simulator: Current and proposed selling prices, cost components, target margin, scenario compare/save and explicit assumptions.

Promotion Simulator: Discount, baseline volume, expected volume, incremental contribution, campaign cost, cannibalisation and break-even uplift.

Combo Simulator: Parent sale, selectable component quantities, zero-priced POS children, special vs replaced packaging, contribution and break-even.

Operational Accountability (optional): Inventory movements, issues/returns, waste, production/yield, transfers and event costing.

Reporting Centre: Daily/weekly/monthly executive packs, filters, export, snapshots, historical report versions and data completeness.

## 8. Guided Setup and Data Import Experience

Guided Setup stages: 1 Business profile/concept; 2 Brands/locations; 3 Users/roles; 4 Materials/UOM/suppliers; 5 Recipes/menu/prices; 6 Sales/procurement mappings; 7 Financial policies and readiness.

Provide progress, sample templates, save/resume, contextual help and business-specific defaults. Allow partial setup with visible missing-data flags.

Import wizard: Choose dataset → upload XLSX/CSV → map columns → validate → reconcile source totals → preview exceptions → approve posting → audit result.

Keep original file, hash, source system, batch ID, mapping version, row-level outcomes and posting identity. Prevent duplicate posting with stable source document/line keys and transactional idempotency. Separate source-facing flat templates from normalised database header/line tables.

## 9. Universal Data Model Contract

Core entities: organisations, memberships, roles, brands, locations, departments, sales_channels, items, item_categories, uoms, item_uom_conversions, suppliers, recipes, recipe_versions, recipe_components, recipe_outputs, menu_items, menu_variants, menu_components, menu_prices, packaging_rules.

Transactions: sales_headers, sales_lines, sales_adjustments, purchase_headers, purchase_lines, inventory_movements, production_batches, production_results, waste_records, import_batches, import_rows, import_mappings.

Financial: costing_policies, material_cost_periods, recipe_cost_snapshots, margin_targets, cost_allocation_rules, reporting_periods, financial_snapshots, scenario_headers, scenario_lines, audit_events.

Every customer-owned table has organisation_id, stable UUID primary key, created_at and appropriate audit metadata. Foreign keys must not allow cross-organisation references. Use effective dates and explicit versions where financial history matters.

Use the existing Universal Data Model v1.1 and Master & Transaction Import Workbook v1.1 as supporting baselines, but resolve inconsistencies through reviewed migrations rather than assuming spreadsheet tabs equal physical database tables.

## 10. Financial Rules and Reporting Semantics

Food Gross Profit = Net Sales − Ingredient Costs − Direct Packaging Costs.

Contribution = Net Sales − All Attributable Variable Costs.

Operating Profit = Net Revenue − Recognised Cost of Sales − Operating Expenses (only when sufficiently complete accounting/expense inputs exist).

Allocated menu profit is a modelled estimate, not realised accounting profit.

Use decimal-safe arithmetic and explicit currency precision. Specify whether prices include/exclude tax; do not treat sales tax as revenue. Preserve discounts, refunds and service charges by configured policy.

Cost basis must identify monthly purchase-weighted recipe costs versus inventory consumption valuation. Historical profitability needs historical selling prices, recipe versions and cost basis. Current selling price applied to past costs is a scenario, not historical actual.

Combo cost derives from component quantities and packaging rules. Promotions require incremental volume, variable costs, campaign cost and cannibalisation assumptions. Freeze approved period snapshots and record authorised adjustments.

## 11. Security, Audit and Quality Requirements

Supabase Auth with server-side authorisation. RLS on all tenant-owned tables and storage access policies. No service-role secrets in browser. Test cross-tenant access through select/insert/update/delete and server actions.

Enforce role/location scope in backend, not only navigation. Audit sensitive price, recipe, policy, permission, period and posting changes.

Imports must be idempotent, recoverable and reconcilable. Background-process large imports with progress and retries. Use migration files, automated tests, seed data and documented recovery steps.

Data quality states: VERIFIED, PROVISIONAL, ESTIMATED, MISSING, UNRECONCILED. Prevent misleading aggregate margin displays when material coverage is incomplete.

## 12. MVP, Deferred Scope and Delivery Phases

Phase 0: Repository, Next.js shell, Supabase auth, organisations, memberships, brands/locations, RLS, component foundation.

Phase 1: Guided setup, masters, UOM and restaurant configuration.

Phase 2: Recipes/sub-recipes, menu mapping, historical prices and costing engine.

Phase 3: Sales and procurement import centre with mappings, validation, reconciliation and idempotent posting.

Phase 4: Material cost intelligence, profitability and menu engineering.

Phase 5: Executive dashboard, decision exposure and daily/weekly/monthly reports.

Phase 6: True cost/pricing, combo and promotion simulators, scenario approvals.

Phase 7: Subscriptions, operational monitoring, pilot readiness and commercial release.

Deferred: Full stock operations, central kitchen transfers, advanced production, asset custody, direct POS connectors, demand forecasts and predictive recommendations.

Every phase requires security, financial correctness, UX and regression acceptance tests.

## 13. Acceptance Criteria and Pilot Validation

1 Two tenants cannot read or mutate each other’s records, including storage and functions.

2 A restaurant can onboard without database terminology.

3 POS and purchase imports reconcile with source totals and are duplicate-safe.

4 Recipe/sub-recipe and combo costs reproduce from versioned components and selected cost basis.

5 Missing costs cannot appear as zero or verified margins.

6 Finalised reports remain reproducible after later recipe/price changes.

7 Simulations cannot alter live prices without separate authorised approval.

8 CEO can review performance and key exposure within the Overview screen.

9 Single-outlet QSR, bakery batch production and multi-outlet group examples pass data-model tests.

10 Desktop and mobile navigation, loading, empty, error and success states work consistently.

11 Financial calculation unit tests and tenant isolation tests pass in CI.

12 Pilot users can complete core workflows without developer intervention.

## 14. Decisions Pending Approval

Working product name requires trademark/domain review. Subscription packaging and pricing not final. Minimum verified-margin coverage threshold not final. Default costing/valuation policy, tax and service-charge conventions, overhead allocation methods, import size limits, scenario approval authority and pilot performance targets require confirmation. Codex must record these as explicit configuration decisions, not invent final business policy.
