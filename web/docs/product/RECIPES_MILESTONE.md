# Versioned recipes and quantity scaling

## Delivered

- Customer navigation now includes the implemented Profitability → Recipes &
  scaling workflow, with the same organisation context as Data & Setup.
- Searchable, paginated recipe library; final recipes and sub-recipes have stable
  organisation-local codes. Editors search materials and saved sub-recipe versions
  in paginated result sets rather than relying on a truncated dropdown.
- Each publication saves a new version, effective date, name, batch output,
  component quantities, source-unit conversions, notes, identity and audit event.
  Recipe code/type stay fixed. There is one output per version in this milestone.
- Saving from an older version explicitly creates a new version; it does not
  overwrite the version being viewed. Previous versions remain selectable.
- Child recipes are specific saved SUB_RECIPE versions, not “latest” references.
  Child versions must already be effective by the parent's stated effective date.
- Active material inputs and packaging are normalised into their base units.
  Standard dimension conversions are exact decimal calculations in PostgreSQL.
  Package inputs require a saved item-specific conversion effective on the recipe
  date; its identity and normalised quantity are pinned in the saved component.
- Scaling unfolds pinned sub-recipe versions and aggregates material/packaging
  quantities for a requested output. It is a planning preview: no production,
  sales, inventory or purchase records are posted.
- No financial costs, selling prices, margins or profits are calculated. Readiness
  is explicitly MISSING until the financial cost sources and policy exist.

## User decision: costing policy deferred

On 14 November 2026 the user selected “Discuss the costing policy later.”
No default monthly purchase-weighted, inventory valuation or manual reference-price
policy is approved by this milestone. The recipe workflow must remain usable
independently, and it must not substitute zero for missing costs. Resolving the
financial policy and source data is a prerequisite for the future costing engine.

## Engineering contract

- Migration `202611140005_versioned_recipes.sql` runs once after 001–004.
  Existing founder, onboarding, catalogue and legacy recipe records are preserved.
  Legacy recipe_ingredients/menu_item relationships are not automatically turned
  into dated canonical recipe versions; their provenance requires explicit review.
- Tenant-owned recipes, versions, outputs and components use same-organisation
  foreign keys and UUIDs. Direct client insert/update/delete is unavailable.
- Active assigned members have read access. Organisation-wide restaurant_admin
  and operations roles can publish. Procurement-only, finance-only and scoped
  assignments do not implicitly grant shared recipe publication.
- The publication function serialises per organisation and uses a request UUID
  plus an input hash. An identical retry returns the same version; changing a
  previously successful request's contents is rejected. Publication is atomic.
- Exactly one component target (material or child recipe version) is required.
  Recursion rejects cycles by recipe identity, including a new version indirectly
  depending on an older version of the same recipe.
- Initial engineering limits: 100 direct component lines per recipe, 20 nesting
  levels including the root, and 10,000 expanded component occurrences. These
  limits protect interactive scaling and are not subscription limits.
- User-entered amounts have at most six decimal places. Normalised quantities
  retain twelve decimal places; scaling results are rounded to twelve. A positive
  result below display precision is flagged and shown with a less-than marker,
  rather than presented as a true zero requirement. No JS float arithmetic is used
  to calculate quantities or conversions.
- Version numbers represent publication sequence, not automatic effective-date
  precedence. The UI defaults to the latest saved version and displays its date;
  future reports must select and retain the intended version explicitly.

## Limits and next work

The recipe editor is not autosaved; publish to save a fixed version. Server-saved
recipe drafts, separate loss factors, substitutions, multiple outputs/co-product
allocation, recipe approval workflows, live menu mapping, financial costs and
exports are not delivered by this workflow. Enter the actual measured batch
quantities/yield; no unstated wastage assumption is applied.

Setup stages remain partially complete. A recipe existing does not establish
that the full menu, historical prices or financial readiness is complete.

## Verification

Database checks cover idempotency, immutable source versions, packaging and
ingredient scaling, exact dimensions, unsupported precision, missing package
factors, child-date and cycle rules, tenant isolation, read-only access and
positive quantities below display precision. Browser tests exercise creation,
new versions, pinning, scaling, read-only controls and mobile layout using real
PGlite functions/RLS with simulated Supabase Auth/REST transport.

The live Supabase migration is not applied by the agent. After applying it, use
the restaurant-owner account to create a small sub-recipe and final recipe and
verify their output quantities with a hand-calculated example.
