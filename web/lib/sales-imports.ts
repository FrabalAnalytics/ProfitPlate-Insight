export const salesHeaders = ["Organisation_Code", "Source_System", "Location_Code", "Sale_Date", "Transaction_Ref", "Line_Ref", "Menu_Code", "Quantity", "Gross_Sales", "Discount", "Tax", "Net_Sales", "Channel_Code", "Line_Type", "Parent_Line_Ref", "Status"] as const;
export const salesFormats = [
 ["EXCLUSIVE", "Gross_Sales and Net_Sales both exclude tax"],
 ["INCLUSIVE", "Gross_Sales and Net_Sales both include tax"],
 ["GROSS_INCLUSIVE", "Gross_Sales includes tax; Net_Sales excludes tax"],
] as const;
export type SalesMappings = { menu_items: Record<string, string>; locations: Record<string, string>; channels: Record<string, string> };
export function parseSalesMappings(text: string): SalesMappings {
 if (text.length > 32768) throw new Error("The source mappings are too large.");
 const input = JSON.parse(text);
 if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("Check the source mappings.");
 const result: SalesMappings = { menu_items: {}, locations: {}, channels: {} };
 for (const type of ["menu_items", "locations", "channels"] as const) {
  const entries = input[type] ?? {};
  if (!entries || typeof entries !== "object" || Array.isArray(entries) || Object.keys(entries).length > 100) throw new Error("Use at most 100 mappings per category.");
  for (const [source, target] of Object.entries(entries)) {
   if (!source || source.length > 100 || typeof target !== "string" || target.trim().length > 40) throw new Error("Map source codes to existing business codes (up to 40 characters).");
   if (type === "channels" && target.trim() && !["DINE_IN", "TAKEAWAY", "DELIVERY"].includes(target.trim())) throw new Error("Map channels to DINE_IN, TAKEAWAY or DELIVERY.");
   if (target.trim()) Object.defineProperty(result[type], source, { value: target.trim(), enumerable: true, configurable: true, writable: true });
  }
 }
 return result;
}
export type SalesReport = {
 file_error: string | null; ready: number; duplicates: number; rejected: number; can_post: boolean;
 receipts: { key: string; transaction_ref: string; source_system: string; location_name: string; sale_date: string; channel_code: string; currency_code: string; total: string; net_revenue: string; lines: number; duplicate: boolean }[];
 rows: { row: number; state: "READY" | "REJECTED" | "DUPLICATE"; source: Record<string, string>; findings: string[]; warnings: string[];
  prepared: null | { menu_name: string; menu_code: string; menu_version: number; menu_version_id: string; location_name: string; quantity: string; gross_sales: string; discount: string; tax: string; net_revenue: string; customer_total: string; currency_code: string } }[];
};
export type SalesBatch = { id: string; filename: string; source_hash: string; state: "INVALID" | "REVIEW" | "POSTED" | "CANCELLED"; source_organisation_code: string; net_basis: string; currency_code: string; mappings: SalesMappings; report: SalesReport; created_at: string };
export type SalesHistory = { total: number; batches: { id: string; filename: string; state: SalesBatch["state"]; created_at: string; ready: number; rejected: number; duplicates: number }[] };
export const salesStateLabel = (state: SalesBatch["state"]) => ({ INVALID: "Needs correction", REVIEW: "Ready for review", POSTED: "Recorded", CANCELLED: "Cancelled" })[state];
export type SalesSummary = {
 currency_code: string; lines: number; receipts: number; priced_lines: number; missing_lines: number; quantity: string;
 net_revenue: string; tax: string; discounts: string; customer_total: string; known_subtotal: string | null;
 estimated_food_cost: string | null; estimated_food_margin: string | null; food_margin_percent: string | null;
 menus: { menu_item_id: string; code: string; name: string; lines: number; priced_lines: number; quantity: string; net_revenue: string; estimated_food_cost: string | null; estimated_food_margin: string | null }[];
 missing: { menu_version_id: string; menu_item_id: string; menu_name: string; sale_date: string; reason: string }[];
};
