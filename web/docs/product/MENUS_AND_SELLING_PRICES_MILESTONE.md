# Menu items, selling prices and estimated food margins

This milestone implements the approved standard-menu workflow: connect a sold
item to a saved recipe version, add dated selling prices and review a clearly
labelled reference-based food margin. Sales imports and purchase-weighted costing
remain separate work.

## Delivered

- **Menu & prices** is available from the sidebar and Data & Setup checklist.
  List search and pagination show 25 menu items at a time, including inactive
  items. Creating an item assigns a stable business-scoped code and brand.
- Each immutable menu version stores its name, optional category label, effective
  date, notes, a specific final recipe version and the quantity of that recipe's
  output used by one sold item. For a recipe yielding 12 PCS, quantity 1 PCS means
  one portion. A recipe yielding KG can be sold as a measured fraction such as
  0.25 KG. Quantities are exact numeric strings, never JavaScript float results.
- The recipe's saved sub-recipes and direct packaging are included automatically.
  New recipe versions do not silently replace the menu's saved recipe link.
  A new menu version explicitly changes the link or serving quantity.
- Menu code and assigned brand stay fixed. Item activation/deactivation is
  reversible and audited; saved composition and price history remain visible.
- This first menu supports a single final-recipe link per sold item. Combos,
  nested menu components, resale-only menu items, modifiers and selectable options
  remain deferred. These are not silently flattened into incomplete recipes.

## Selling prices

Each immutable price entry records menu item, active location in the item's brand,
sales channel (DINE_IN / TAKEAWAY / DELIVERY), business reporting currency, positive
price, explicit tax setting/rate, effective start, optional inclusive last selling
date and required source/change note. Source prices support up to six decimals.
No currency conversion, legal tax-rate inference or silent zero tax is performed.

The user selects one of:

| Setting | Calculation |
| --- | --- |
| No tax applied | Net selling revenue = entered price; declared tax = 0 |
| Selling price excludes tax | Net selling revenue = price; customer total = price × (1 + declared rate / 100) |
| Selling price includes tax | Customer total = price; net selling revenue = price / (1 + declared rate / 100) |

Rates are explicitly entered from 0 to 100 with at most six decimals. The None
setting deliberately records 0; a missing rate on another setting is rejected.
These fields describe the restaurant's declared price treatment, not a tax-law
recommendation or a jurisdiction-specific accounting rule.

### Effective-price events and corrections

Prices are append-only effective events, rather than independently overlapping
intervals that all remain applicable. For the exact location/channel on a preview
date, choose the latest effective start on or before that date, then the newest
entry for same-date corrections. The chosen entry must not be expired and must
match the reporting currency. An older open price does not resume when a newer
price expires. A newer event supersedes an earlier event from its start date;
original entry data remains unchanged for provenance.

The latest 25 price entries are visible on each item. The selected price entry ID,
version, dates and declared tax treatment are also returned with the estimate.
Future prices can be scheduled and inspected in history, but future-date margin
previews are not calculated. Missing prices never fall back to a different outlet,
channel, currency or a legacy static price.

## Food-margin preview

Choose a saved menu version, active location in its brand, sales channel and
business reporting date. The method is `MENU_REFERENCE_MARGIN_V1`:

- Estimated ingredient and packaging cost comes from the existing recipe
  reference estimate for the menu's declared recipe output quantity.
- Estimated food margin = net selling revenue − estimated ingredient/packaging cost.
- Food margin percentage = estimated food margin ÷ net selling revenue × 100.
- Food cost percentage = estimated ingredient/packaging cost ÷ net selling revenue × 100.

Arithmetic runs in PostgreSQL numeric. Revenue/cost amounts use 12 decimals;
percentages round to six decimals. Price and recipe-reference inputs are returned
with IDs/versions. Negative margins remain visible, including negative percentages.
Unavailable ingredient costs block the full cost and full margin; missing, expired
or wrong-currency selling prices block net revenue and margin. Available individual
values remain visible without inventing zero for missing facts. Missing ingredient
prices link directly to the material's reference-price screen.

All complete margins remain **Estimated**, never actual, verified or operating
profit. Labour, overheads, discounts, service charges and channel fees are not
deducted by this basic food-margin view. It does not calculate contribution or
operating profit. Reference costs and source selling-price assumptions may be
corrected later, so this is a **live preview**, not a finalised historical report.
Reference prices remain business-wide even when the selling price is outlet-specific.

## Canonical schema and legacy compatibility

Migration 009 extends the existing `menu_items`; it does not create a competing
catalogue. Existing IDs, names, category references, recipe_ingredients and static
selling_price values remain stored. Old rows receive unique reviewable codes but
no invented brand, recipe-version link or effective/tax-declared price.

The legacy static selling_price is nullable for new canonical records, which leave
it null. It is never used by this preview. Name uniqueness is replaced by stable
organisation/code uniqueness so brands may have identically named dishes with
distinct codes. Legacy category tables remain intact; the new version stores a
category label snapshot. No master-category editor is introduced here.

New tables `menu_item_versions` and `menu_price_versions` use same-organisation
foreign keys. All mutations are audited, with idempotent request IDs and input
hashes for publication/price saves. Writes are serialised per organisation and
direct client edits/deletes are revoked. Legacy menu/category client writes are
revoked as part of the transition to these validated functions.

## Access

Active organisation-wide restaurant administrators can create menu versions,
change availability and save prices. Organisation-wide CEO, finance and procurement
roles can inspect records and estimates. Operations-only staff, scoped staff,
unrelated tenants, anonymous users and founders without restaurant membership
cannot read business-wide financial menu records. All public functions and table
RLS enforce these boundaries independently of the UI. A CEO wishing to edit needs
the separate restaurant-admin role, as the onboarded owner already has.

## Enable in Supabase and test

After migrations 001–008, run the complete new file once in the existing project:

`supabase/migrations/202611140009_menu_items_and_prices.sql`

The agent has not applied it remotely. Refresh ProfitPlate and open **Menu & prices**.

Using the existing fictional recipe costing NGN 900 per PCS:

1. Create menu code **MENU001**, name **Chicken Rice Plate**.
2. Select your brand and the saved final recipe version. Enter output quantity
   **1 PCS per menu item**, with an effective date on or after that recipe starts.
3. Publish the menu version. Cost can be shown, but margin remains incomplete
   until a matching selling price is added.
4. Add selling price **1500**, select the demo location and **Dine in**, explicitly
   choose **No tax applied** for this fictional test, and add a source note such
   as **Fictional test price**. Use today's date and save.
5. Expected net selling revenue: **NGN 1,500**; estimated ingredient/packaging cost:
   **NGN 900**; estimated food margin: **NGN 600 (40%)**; food cost: **60%**.

This no-tax fixture is a calculation example, not a recommendation for a real
restaurant's tax treatment. Real selling prices must use the business's declared
tax setting and applicable rate.

## Verification and boundaries

Database tests apply the migrations and test legacy preservation, immutable menu
links, idempotent publication/prices, tax arithmetic, scoped/date-based price
selection, expiry and corrections, missing costs/currency, negative margins,
availability, permission and tenant boundaries. Browser checks cover publication,
price entry, tax breakdown, saved menu versions, missing-cost links, negative
margins, mobile overflow and read-only finance access. Production build checks
Next.js compilation and TypeScript.

Direct workbook menu imports remain pending: the supplied Menu_Components needs
an explicit saved recipe-version binding, and Menu_Prices lacks tax settings/rates.
Those contracts must be extended before an importer can safely use them. Sales
mapping/imports, purchase-based cost policies, finalised financial snapshots,
discounts/fees and actual profit reports remain separate deliveries. The overall
setup-ready count is unchanged; available modules are not treated as completed
financial onboarding.
