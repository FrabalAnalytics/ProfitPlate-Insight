# Bulk onboarding: materials, recipes and selling menus

Release 057 adds reviewed CSV and Excel imports. Manual entry remains available. The restaurant must be Active; a Pending application cannot use imports to bypass Founder approval.

## Recommended order

1. Complete business setup, units and outlets. Add the responsible users, then open **Data & Setup → Centres & team access** to create stock centres before preparing opening-stock rows. Copy each centre's code from its stock-centre table. If you are importing only materials and purchase prices, centres can be created later; leave all three opening-stock fields blank.
2. Set up Food / Drink subcategories under Menu categories.
3. Open **Materials & suppliers → Import materials**.
4. Download the CSV or Excel template. Replace the fictional examples with your own data and actual centre codes. Dates in the examples are illustrative; use your real opening and purchase dates.
5. Choose **Business-wide** availability, or one outlet for this batch.
6. Upload the file and select **Review file**. Read the action and findings for every record. Correct errors and review again; an invalid batch cannot be saved partially.
7. Confirm the review and select **Save reviewed import**. Known last purchase prices become reference estimates; they do not create invoices. Opening quantities are prepared for Inventory review and do not change stock yet.
8. An authorised Inventory colleague opens **Inventory & movements → Review imported opening stock**. They check each centre/date batch and submit it. Positive quantities become a normal opening-stock record requiring a different authorised approver and normal posting. A verified zero is explicitly confirmed by an Inventory Manager; no quantity movement is created. The original import preparer and later submitter remain auditable.
9. Open **Recipes & scaling → Import recipes**. Use one row per ingredient or sub-recipe component. Sub-recipes and their final recipes may be in the same file; the importer resolves dependencies automatically.
10. Review and publish the recipes. Saved versions retain their precise child versions. Importing recipes does not create produced stock; stock-output links, processing baselines and daily production remain separate steps.
11. Open **Menu & prices → Menu catalogue → Import menu**, or follow **3. Selling menu** on the import screen. Select one outlet for its selling prices.
12. Supply Food/Drink, the restaurant's subcategory, final recipe code, quantity per sale and standard selling price together. Leave recipe_version blank to use the latest version effective by the menu date, or supply an explicit version.
13. Review and save. Standard prices apply without repeating a price for every sales channel. Channel-specific exceptions remain optional. A blank selling price preserves existing prices; a blank recipe link saves an incomplete item.
14. Check **Menu profitability**, **Materials** readiness and Inventory balances. Preparing or approving an opening is not the same as posting it. Blank opening quantities remain unknown; an explicit zero is a declaration that the centre held none.

## Templates

Both formats contain exactly the same columns and follow the same server validation:

- `/templates/material-master-import.csv` and `.xlsx`
- `/templates/recipe-components-import.csv` and `.xlsx`
- `/templates/menu-catalogue-import.csv` and `.xlsx`

CSV: UTF-8, comma-delimited, maximum 256 KB (menus: 128 KB after parsing). Excel: plain `.xlsx`, one data sheet, maximum 512 KB. Legacy `.xls`, formulas, error cells, rich text and cell links are rejected. Paste values before uploading. Keep the template headers and column order. Workbook archives and expanded contents are bounded before parsing.

Materials: maximum 100 unique materials / 500 rows per batch. Recipes: maximum 50 recipes / 500 component rows, with at most 100 components per recipe. Menus: maximum 100 rows per outlet batch. Dates use YYYY-MM-DD; numbers have no thousands separators and at most six decimal places. Stock quantities and prices are validated in the database.

## Material fields

| Field | What to enter |
| --- | --- |
| action | CREATE for a new code, UPDATE for an existing active material |
| material_code / material_name | Stable code and descriptive name |
| material_type | GENERAL, RAW, PACKAGING, RESALE, CONSUMABLE, SEMI_FINISHED or FINISHED |
| category | Your material category, such as Fish or Grains |
| base_unit | Existing unit code, such as KG, L or PCS; existing base units cannot be changed |
| stock_tracked | true or false |
| weekly_count_required | true for SKUs included in weekly physical counts |
| supply_source | PURCHASED, PROCESSED or BOTH |
| requires_processing | true if this input undergoes processing; false otherwise |
| last_purchase_unit_price / last_purchase_date | Optional known price per base unit and actual date, supplied together |
| centre_code / opening_quantity / opening_date | Optional opening quantity in the base unit, supplied together |

For a material held at multiple centres, repeat **identical master and purchase-price details** on separate rows, changing only centre code, opening quantity and opening date. The master and price are saved once. Enter 0 for a verified zero. If no opening is known, leave all three opening fields blank. Processed-only outputs receive their estimated cost from their linked production recipe; leave their purchase price blank.

An opening cannot be imported twice for the same material/centre, including one already declared zero, prepared, requested or posted. Corrections use the existing stock record or reviewed physical count workflow. This deliberately prevents a new upload from silently replacing stock history.

## Recipe fields

| Field | What to enter |
| --- | --- |
| action | CREATE or NEW_VERSION; a new version preserves older history |
| recipe_code / recipe_name | Stable code and descriptive name |
| recipe_type | SUB_RECIPE or FINAL |
| yield_quantity / yield_unit | Expected batch output and existing unit code |
| effective_from / notes | Version start date and optional note |
| component_kind / component_code | ITEM and a material code, or RECIPE and a sub-recipe code |
| component_version | Blank for latest eligible sub-recipe; explicit version when required; blank for ITEM |
| component_quantity / component_unit | Positive input quantity and unit code |

Repeat the same recipe header for all its component rows. Consolidate duplicate components. Children are published before parents even if the spreadsheet is unsorted. Cycles, missing/incompatible units, unavailable components and inconsistent headers block saving the entire batch. A failed child cannot be silently replaced by an invented component.

## Permissions and safe retries

Material editing follows existing catalogue permissions; recipe publication follows existing recipe permissions; selling menu editing follows existing menu permissions. Preparing material openings additionally requires stock setup authority. Submitting prepared openings requires the centre's Inventory/request permissions; zero declarations require Inventory Manager authority.

Uploads reference only the chosen restaurant. Foreign codes and incompatible outlet scopes are rejected. Reviews use a transactionally maintained revision token, so concurrent changes require another review without scanning all historical stock records. Preview uses the real save validations inside a rolled-back transaction, leaving no master records, price versions, opening declarations, stock entries or audits behind.

The save operation is atomic and keyed by its request. Retrying the same confirmed import does not duplicate records, recipe versions or stock movements. Reusing the request for different data is rejected. A new intentional NEW_VERSION import creates another recipe version; it does not rewrite an earlier one.

## Deployment

Apply `supabase/migrations/202611220057_reviewed_master_imports.sql` after 056 before deploying the matching app. The migration adds only import controls and prepared-opening records; it does not modify existing stock quantities or activate restaurants.
