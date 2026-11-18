# Complete fictional restaurant test data - 18 November 2026

Start with the Excel workbook for the whole dataset. Use the Word guide for the step-by-step walkthrough. All figures and people are fictional. Use a separate training restaurant.

IMPORTANT: This is a testing pack, not a universal master-data importer. The XLSX workbook is for review/manual entry; do not upload it to a CSV screen. Files in manual-entry/ are populated collection sheets, not application upload formats. Only the four CSVs in upload-ready/ match implemented import screens, and they still need their prerequisite masters created first.

## Before testing
- Create Training Restaurant, brand Training Kitchen and first outlet Dining Room. Fresh onboarding assigns brand and outlet code PRIMARY; verify these codes in the actual workspace before uploading. Map/replace PRIMARY explicitly if using a different outlet.
- Owner rows in users.csv represent the same existing owner with two roles; do not invite or create the owner twice.
- Replace all example.test user emails with separate email addresses/aliases you control. They are not real logins. Register, verify and accept invitations; the pack contains no passwords.
- Test date: 2026-11-18. Use that date consistently in masters, prices, transactions and filters. If changing it, update all related dates together; do not enter future transactions.
- Week/count schedule in business.csv is a fictional choice. Replace it with the restaurant's actual schedule for a real pilot.

## Manual setup order
1. Business/calendar and named users.
2. Stock centres/owners; Kitchen as processing unit; role-to-centre permissions and transfer/return routes.
3. Suppliers, materials, packaging and conversions.
4. Starting prices (manual OR import the six initial-price rows).
5. SNAPPER_CUTTING processing baseline (40 KG whole fish -> 120 PCS cuts).
6. STEW_BASE sub-recipe, then SNAPPER_RICE_RECIPE final recipe and its component lines.
7. SNAPPER_RICE_MENU selling item, final recipe link and 1 PCS of recipe output per sale; set TAKEAWAY price 6000, NONE tax for this fictional arithmetic test only.
8. Opening stock. Positive rows need reviewed opening requests and posting. Zero rows need explicit zero-opening readiness confirmation, not zero-quantity stock requests. Opening quantities are per centre, not business-wide totals.
9. Transfer 40 KG whole fish Main Store -> Kitchen; manager approves/dispatches and Ada accepts before stock changes.
10. Record the sample processing batch and its 4 KG trim once; approve/post. Then record the separate 2 PCS spoilage; approve/post.

## Upload the four working CSVs
- initial-material-prices.csv: Initial material prices screen. Six rows; no Snapper Cut purchase price. Reference prices do not add stock.
- purchases-import.csv: Purchase imports screen. Source organisation code TRAINING; source unit-price tax basis EXCLUSIVE; NGN. Separate FISH_SUP and DRY_SUP invoices. Check totals 30000 and 9000 (39000 combined). File Status RECEIVED follows the source contract; invoice import does NOT create a GRN or receive/post physical stock. These invoices must not be posted again manually. If testing a manual PO/GRN/invoice cycle, use a separate reference/delivery.
- sales-import.csv: Sales CSV screen. Source organisation code TRAINING; EXCLUSIVE source tax format; NGN. This fictional file has zero tax/discount and one paid normal receipt: 3 servings, net/customer total 18000. The menu/final recipe versions and selling price must be effective first. Sales imports are not automatic ingredient-stock consumption postings.
- expense-import.csv: Expense CSV screen. Source organisation code TRAINING; existing WAGES and RENT categories; LOCATION scope, outlet PRIMARY, ON_DATE recognition. Review total 1100. Do not enter these same expenses manually too.

Preview every upload, correct unresolved codes and reconcile the app's source totals before confirmation. Current price/transaction CSV screens use reviewed, bounded batches; this pack contains only small samples. Repeat only as an explicit retry test, not as another new transaction.

## Expected results and boundaries
Use checks/expected-results.csv. The expected menu cost is 1680 per plate and food margin is 4320 (72%) at price 6000, before other costs. The illustrative processing batch achieves 110/120 = 91.67% of expected pieces and 36/40 = 90% usable weight; trim is already included in the input consumption. After independent spoilage Kitchen holds 108 cuts. Standard SKU recipe estimates are distinct from actual batch unit-cost performance.

The sample sales and expense files test financial records; they do not automatically reduce Kitchen stock to reflect the sold plates. Test recorded consumption/counts separately. Do not sum KG and PCS into one loss quantity. These food margins are estimates, not actual net profit or a complete contribution margin.

Suppliers, materials, conversions, recipe headers/components, menu items/prices, processing baselines and opening stock currently have no bulk upload screen. Their manual-entry sheets must remain labelled as such until the relevant importers are built.
