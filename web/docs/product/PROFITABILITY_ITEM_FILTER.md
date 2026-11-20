# Same-page profitability item filter

Apply `supabase/migrations/202611200047_profitability_menu_recipe_filter.sql` before deploying the matching application.

The profitability toolbar has All, Menu and Recipes options. Menu is the default so an executive first sees selling items. Selecting a type and submitting Search updates the existing table. Outlet, channel, date and status remain available, and links, search and pagination retain the selected type. This replaces the previous dropdown that navigated to the recipe library.

Menu rows retain the existing per-channel selling-price and margin calculations. Recipe rows include final and sub-recipes within the selected outlet scope, each once regardless of channel. Their latest version effective on the selected date supplies the estimated cost per declared output unit. Unsold recipes have no selling price, food-cost percentage, target or contribution margin; those cells say Not applicable. A recipe with incomplete cost inputs stays incomplete rather than displaying a partial total as its cost.

All combines the two row types without summing or averaging their costs. Summary counts follow the selected type and search before status filtering and pagination. Recipes do not become missing-price or missing-target exceptions solely because they are not sold. Costed recipes have a separate summary count and status. The table remains paginated at 25 rows; a combined 5,000-row calculation limit requires a narrower search when exceeded. Recipe breakdown links return to the selected profitability filters.

The new read-only RPC uses the existing business-wide financial access gate and tenant, outlet, date and channel validation. Existing menu-only RPCs remain unchanged. No master records, prices, recipe versions or stock movements are created or changed by this report.
