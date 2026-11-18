import type { RecipeOption } from "./recipes";
export const menuChannels = [["DINE_IN", "Dine in"], ["TAKEAWAY", "Takeaway"], ["DELIVERY", "Delivery"]] as const;
export const menuTaxSettings = [["NONE", "No tax applied"], ["EXCLUSIVE", "Selling price excludes tax"], ["INCLUSIVE", "Selling price includes tax"]] as const;
export type MenuRecipe = RecipeOption & { effective_from: string };
export type MenuPacket = {
 item: { id: string; code: string; name: string; brand_id: string | null; location_id?:string|null; primary_category?:string|null; subcategory?:string; is_active: boolean };
 version: null | { id: string; version: number; name: string; category: string; recipe_version_id: string; recipe_quantity: string | number; effective_from: string; notes: string };
 recipe: MenuRecipe | null;
 versions: { id: string; version: number; name: string; effective_from: string }[];
 prices: { id: string; version: number; location_id: string; channel_code: string; currency_code: string; price: string; tax_setting: string; tax_percent: string; effective_from: string; effective_to: string | null; notes: string }[];
};
export type MenuEstimate = {
 cost_state: "MISSING" | "ESTIMATED"; as_of: string; currency_code: string; price_issue: string | null;
 price: null | { id: string; version: number; amount: string; tax_setting: string; tax_percent: string; effective_from: string; effective_to: string | null };
 net_revenue: string | null; tax_amount: string | null; customer_total: string | null; estimated_food_cost: string | null;
 estimated_food_margin: string | null; food_cost_percent: string | null; food_margin_percent: string | null;
 recipe_estimate: { cost_state: string; missing_count: number; lines: { item_id: string; name: string; code: string; missing_reason: string | null }[] };
};
export type MenuProfitability = {
 total: number; currency_code: string; unassigned_menu_count: number;
 rows: { id: string; code: string; name: string; version_id: string | null;
  primary_category?:string|null; target?:string|null; version: number | null; effective_from: string | null; recipe_quantity: string | null; estimate: MenuEstimate | null }[];
};
export function validMenuTaxRate(value: string) {
 return /^(?:0|[1-9]\d{0,2})(?:\.\d{1,6})?$/.test(value) && Number(value) <= 100;
}
