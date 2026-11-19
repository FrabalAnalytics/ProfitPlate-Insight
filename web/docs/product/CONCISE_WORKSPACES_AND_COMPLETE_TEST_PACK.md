# Concise workspaces and complete restaurant test data

Updated 19 November 2026 for invitation release 042. Presentation and sample files only; no new database migration.

## Presentation

- Role homes use compact, accessible shortcuts instead of cards repeating their title, explanation and action.
- Greetings, Needs Attention counts and CEO metrics remain visible. Count explanations and per-panel calculation notes expand on demand.
- Main records pages use functional names and fewer introductory descriptions. PO headings and supplier-invoice empty states are no longer repeated.
- Homepage capability/role copy is shorter. The repeated source-trace section is removed, FAQs are reduced to six, and outdated purchase-cost claims are corrected.
- Required inputs, permissions, financial basis labels, missing-data alerts and approval/receiving controls retain their existing behaviour.

## Test data

Download /templates/profitplate-complete-test-data-2026-11-19.zip. It contains a 23-sheet Excel workbook, 22 populated CSVs, the refreshed Word guide (including invitation email, centre selection and cross-browser recovery), START-HERE instructions, expected results and 44 acceptance cases with blank result fields.

The dataset covers business/calendar, named roles, storage centres, routes, suppliers, materials, conversions, starting prices, processing baselines, sub/final recipes, selling menu items, selling prices, opening counts, processing, independent waste, invoices, sales and expenses.

Only four upload-ready CSVs match current app import screens: initial prices, purchase invoices, sales and expenses. Manual-entry files and the XLSX workbook are preparation/review documents. Missing master-data importers remain an explicit product gap.

Use a separate training restaurant, replace example.test emails with accounts you control, and confirm that the first outlet code is PRIMARY. Source organisation code for transaction CSVs is TRAINING. Dates are 2026-11-19; keep dependent dates consistent if you change them. Use EXCLUSIVE source tax format for the fictional zero-tax transaction examples.

## Rebuild and validation

- python scripts/build_complete_test_pack.py regenerates files using only the standard library.
- node scripts/verify_complete_test_pack.mjs loads real migrations in an isolated local PostgreSQL database, creates prerequisite masters, validates/posts sample imports and checks recipe/menu/sales arithmetic. It does not access production.
- Expected menu serving cost is 1680; food cost 28%; estimated food margin 4320 / 72% at selling price 6000. The sales CSV totals 18000 for three servings and 5040 estimated food cost. Invoices total 39000 across two suppliers; expenses total 1100.
- The processing/count scenario is a separate physical-stock walkthrough. Sales/imported invoices do not automatically post ingredient depletion or delivery quantities. Do not duplicate opening stock, batch trim, invoices or expenses across routes.
