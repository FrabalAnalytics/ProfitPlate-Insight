# Product specification gap assessment and phased plan

Reviewed 18 November 2026 against the application and migrations 001-031. This is a planning document, not an implementation or a change to the live service. It responds to both parts of the supplied Product Improvement Specifications.

## Overall assessment

The five-node restaurant model fits the existing configurable stock-location model. Requests, independent receiving, department returns, recipe versions, stored sub-recipes and single-output production already have foundations. The full specification is not yet delivered. The biggest missing connections are multi-output processing, sales-driven theoretical consumption, scheduled weekly reconciliation, broader imports, configurable targets, and founder-controlled restaurant activation.

Commercial outlets and stock departments must remain separate concepts. Five departments at one restaurant should not become five sales outlets merely to track stock. A central node serving several outlets can be business-wide; department locations can belong to their actual outlet. Department-level cost-center reporting needs explicit attribution beyond today's outlet reporting.

## Requirement-by-requirement assessment

| Requirement | Current capability | Gap / proposed extension |
|---|---|---|
| Back navigation | Browser history and contextual links exist on many pages. | Consistent in-app back action with a known fallback; preserve search, filters, selected outlet and pagination. Avoid history loops after saves or auth redirects. |
| Concise product copy and homepage | Refreshed homepage, grouped sidebar, task queues and progressive report filters. | Audit operational screens for repeated paragraphs. Retain units, dates, missing-data indicators, confirmation consequences and financial basis, using compact labels or expandable details. |
| CSV/Excel imports | CSV for purchases, sales, expenses and initial reference prices; purchasing history exports CSV/XLSX. | Supplier, material, menu and recipe master-data imports; XLSX input support; stock document imports. XLSX export does not mean XLSX input already exists. |
| Founder approval and activation | Read-only restaurant directory, onboarding drafts and access review. | Pending / Active / Inactive restaurant lifecycle, founder decisions and audit trail, enforced in server/database permissions and direct RPC access. Existing restaurant memberships alone currently determine access. |
| Setup progress | Owner checklist and founder visibility into incomplete setup drafts. | Real stage completion per onboarded business. Owner checklist currently reports basic setup as 2 of 7; it does not measure all completed operational data. |
| Food/beverage cost targets | CEO uses an explicitly labelled fixed 40% food-cost review guide. | Configurable business defaults and outlet overrides; separate food and beverage targets; consistent use across menus, briefing and weekly report. |
| Selling menu completeness | Catalogue items can exist without a published mapped version or current selling price; profitability flags missing readiness. | Unified draft/incomplete workflow; capture available selling prices in entry/import; Food/Drink/Packaging primary category plus business subcategories; explicit business/location availability. Publishing a menu version currently requires a final recipe. |
| Dynamic serving cost and mapping | Final-recipe mapping and reference-price serving estimates with dated breakdowns. | Clear incomplete status until mapping and costs are usable; cost-driver ranking; new scope rules. Do not permit incomplete records to masquerade as costed sale items. |
| Raw material completeness | Base UOM, stock flag, types/categories and separate dated last-known reference-price entry/import. | Unified material readiness, location availability, displayed last purchase price, missing-data flags and opening-stock checklist. Current material creation requires core identity and UOM; supporting drafts without UOM needs an explicit draft model. |
| Opening stock | Manual, controlled opening documents, including base-unit quantities, with first-posting safeguards. | Per-material/per-stock-location readiness, opening date and explicit zero confirmation; optional bulk opening upload. A business-wide material cannot have one ambiguous shared physical opening balance. |
| Weekly stock counts | Manual physical counts; posting records book-to-physical adjustment and rejects stale counts. | Count-required flags, reporting calendar, due/missing submissions, frozen count context, variance classification and weekly reporting. Sales do not automatically consume stock today. |
| Sub/final recipe hierarchy | Versioned sub-recipes and final recipes, pinned child versions, yields and cycle/date checks. Production consumes stocked child output once. | CSV/XLSX loading in dependency order, explicit recipe availability by location, draft completeness. Only recipes depending on a sub-recipe need that child first; raw-material-only final recipes remain valid. |
| Menu profitability | Cost/serving, net selling price, food cost %, food profit/serving, gross food margin %, readiness and recipe breakdown. | Food/beverage targets, threshold status, category/scope filters and fuller cost-driver view. True contribution margin needs the relevant additional variable-cost inputs; the existing column correctly says unavailable. |
| Transaction date and scope | Dated manual/CSV sales, purchases and expenses. Manual stock documents carry date and physical locations. Central expenses remain unallocated. | Consistent entry/import experience and batch scope. Physical stock must retain a stock location, and sales/purchases generally need a meaningful outlet; do not invent physical business-wide stock or silently allocate central costs. |
| Weekly margin review | Selectable-period overview, saved management reports, price-pressure/waste/accountability briefing, historical reports. A week can already be selected manually. | Purpose-built weekly default and week-on-week comparisons; Food/Drink and subcategory sales; department attribution; count coverage and material variances; preserved reviewed weekly snapshot. |
| Purchased and processed stock | Several material types, including semi-finished and finished; direct receipts and recipe-based production. | Explicit purchased/processed grouping and clearer material taxonomy including General. Keep origin separate from material classification. |
| Bulk raw processing into several SKUs | Current production consumes recipe inputs and adds one stock output per batch. | A single processing batch producing multiple SKUs, with measured input, output quantities/units, yield, trim/waste and traceability. A financial cost allocation policy is also required before assigning actual monetary output costs. |

## Five-node configuration

| Operational node | Proposed stock-location setup | Role in the flow |
|---|---|---|
| Central Inventory Store | STORE or WAREHOUSE; outlet-linked if local, central scope if serving several outlets | Supplier receiving, purchased/processed stocks, processing and dispatch. |
| Central Kitchen | PRODUCTION | Receives ingredients, requests/records production, holds prepared output, supplies Front Kitchen. |
| Front Kitchen | KITCHEN | Requests and accepts prepared output; completes service or finishes dishes. |
| Back Kitchen | KITCHEN | Requests and accepts ingredients, produces its own dishes. |
| Bar Department | BAR | Requests and accepts drinks/ingredients, records usage and waste. |

Configure physical routes from Central Store to Central Kitchen, Back Kitchen and Bar; Central Kitchen to Front Kitchen; and reverse routes where excess returns are allowed. Add Central Store to Front Kitchen only if that movement is allowed in the restaurant's real plan. The Front Kitchen's requisition travels to the supplying team; the physical stock route still runs Central Kitchen to Front Kitchen.

The Inventory Manager remains responsible for approval and dispatch. Each receiving department accepts or rejects its incoming movement. Dispatch reserves stock; acceptance posts the accepted source deduction and destination addition atomically. Department production/usage/count/waste requests remain subject to the current authorised posting process. No new staff account is required for each dispatch step.

Sub-recipes held in stock need their own stock-tracked output SKU. A batch of sauce is produced before a parent batch consumes that sauce. A parent must not deduct both the stocked sauce and the sauce's raw ingredients.

### Critical processing example

Receiving 20 kg of whole beef and producing small cuts, large cuts and trim is one input-to-many-output event. Record the actual measured input, each output SKU's quantity and unit, and identified waste/by-products. Piece-based outputs need a defined weight/yield relationship; kilograms and pieces cannot be reconciled by adding their numbers. Whether trim is reusable stock or waste must be recorded explicitly.

This cannot be accurately represented as one current single-output batch. Separate existing batches may represent genuinely separate input portions, but they are not a substitute for one accountable multi-output cutting record.

### Critical weekly reconciliation distinction

Current book stock comes from posted openings, accepted receipts/transfers, production, waste, counts and manually recorded usage. It is not yet sales-driven theoretical stock.

For the requested stronger reconciliation, connect sales to a dated recipe and the correct selling department. A stocked finished product consumes its finished SKU when sold. A made-to-order dish consumes the relevant materials/prepared components once. Corrected, voided or re-imported sales must not double-deplete stock.

Keep these measures distinct:

- Physical-count variance: counted stock versus expected book stock at the controlled cutoff.
- Sales-theoretical usage variance: actual ingredient/component usage versus the expected usage of recorded sales, with production/yield context.
- Recorded waste and processing loss: already explained movements, not a second unexplained loss deduction.

Automatically create an exception when a count shows a gap. The existing controlled posting process should authorise any stock adjustment. Preserve surplus as well as shortage, and label unexplained differences as variance until classified. A missing count is missing coverage, never a zero balance or an assumed loss.

## Recommended implementation phases

### Phase 1: Setup, scopes and completeness

Establish stable business/location availability, primary/subcategories, material classifications, draft/incomplete states, business food/beverage targets and location overrides. Add measured setup readiness and material opening-stock requirements. Keep existing records usable, preserving IDs, versions and histories.

Acceptance: incomplete master records save with visible gaps; operational posting still requires usable units, locations and quantities; targets resolve correctly at each location; setup progress follows real data rather than a fixed label.

### Phase 2: Bulk data onboarding

Add shared CSV/XLSX parsing and review infrastructure. Deliver supplier and material imports first, then dated prices/openings, sub-recipes in dependency order, final recipes, menu mapping and selling prices. Follow with stock-document uploads using the same posting rules as manual entry.

Each upload chooses business-wide scope or one permitted location. Location-specific menu population handles one selected location per batch. Show row-level errors and incomplete warnings, reject cross-business references and duplicate/replayed transactions, and show an explicit create/update preview. An uploaded stock file must not bypass manager or receiver controls.

Acceptance: a representative restaurant can load a checked initial dataset without manually retyping every master record; repeated imports do not create duplicate business records or ledger movements; CSV and XLSX produce equivalent reviewed values.

### Phase 3: Founder lifecycle and onboarding control

Add Pending / Active / Inactive status, approval controls, real setup progress and decision history. Existing restaurants should remain Active during rollout; newly completed registrations can default to Pending. Pending owners should be able to finish permitted setup, while operational posting requires activation. Inactive tenant access must be centrally enforced, not merely hidden in the sidebar.

These are recommended transition rules, not yet agreed business policy. Confirm whether Pending restaurants may import setup data and whether Inactive means full tenant lockout or read-only access before implementing the gates.

Acceptance: founder decisions are audited; ordinary restaurant administrators cannot activate themselves; direct database functions honour status; disabling one restaurant does not affect another or destroy its data; reactivation restores authorised access.

### Phase 4: Processing and production accountability

Add multi-output processing, measured inputs and outputs, units/portion weights, yield and explained loss. Support the whole-beef-to-cuts flow and prepared stock between Central Kitchen and Front Kitchen. Keep batch quantities and any monetary valuation policy separate until the latter is selected.

Acceptance: input stock is consumed once; all outputs are created atomically; shortage prevents partial posting; output SKUs transfer and receive normally; processing loss is recorded once and remains traceable to the batch.

### Phase 5: Weekly counts and sales-driven theoretical usage

Add weekly-count flags, the business reporting calendar, location-specific count sheets, reminders and missing-count queues. Connect sales to versioned recipes/departments or stocked finished products, with correction/idempotency safeguards and no double counting of production consumption. Add book-versus-count and theoretical-versus-actual exceptions.

Acceptance: explicit zero counts are valid; missing counts remain incomplete; movement cutoff and stale counts are controlled; accepted transfers, production, sales and waste reconcile once; corrections retain an audit trail and do not duplicate depletion.

### Phase 6: Weekly margin review, profitability and final UX pass

Build the weekly executive review around preceding-week comparisons, business/outlet/category sales, configured target exceptions, supplier price inflation, waste, yield and material variances, with owner/location/source drill-down. Expand menu costing and contribution only as supported by connected cost inputs. Finish consistent back navigation and concise copy across the completed workflows; existing basic navigation/copy issues can also be corrected alongside earlier phases.

Acceptance: every reported figure has a clear week, scope and basis; unavailable inputs stay visible; waste and count/production losses are not added twice; saved reviews preserve their figures; threshold statuses match setup; back actions retain working context.

## Business decisions before dependent work

1. Lifecycle: keep existing restaurants active; decide what pending/inactive restaurants may read or enter.
- We can set demo test restaurant as Inactive inorder to decluster the schema, we can set an onboarded restaurant due to payment issues, meaning will not be able to sign in to their workspace

2. Reporting calendar: choose week start, business timezone and physical count cutoff. Do not assume Monday-Sunday suits every restaurant.
- This should form part of the initial setup

3. Cost basis: decide how dated starting prices and later posted invoices update recipe estimates. New invoices currently do not automatically replace reference prices. Multi-output monetary valuation and complete contribution margin need explicit cost definitions.
- Every new material price should be averaged & tracks under monthly material price tracker, and should be used t recalculate the recipe cost

4. Production: provide one measured processing example with input weight, cut sizes/weights, output counts and trim/waste. This is needed to validate unit conversion and yield expectations.
-Central Inventory receives Whole Snapper Fish 40kg (SKU1)
-Processed into 120 Pices of Snapper fish_Cut (SKU2)
- I beleived proceesed material data should form part of the master data provided at set up stage

No application code or live records were changed for this assessment. PO approval remains outside scope, as previously instructed. Existing manager dispatch and independent department acceptance remain the baseline.
