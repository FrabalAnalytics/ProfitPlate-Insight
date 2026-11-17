export const purchaseHeaders = ["Organisation_Code", "Source_System", "Purchase_Date", "Purchase_Ref", "Line_Ref", "Supplier_Code", "Item_Code", "Quantity", "Purchase_UOM", "Unit_Price", "Line_Discount", "Tax", "Location_Code", "Currency", "Status"] as const;
export type PurchaseMappings = { items: Record<string, string>; suppliers: Record<string, string>; locations: Record<string, string> };
export type PurchaseReport = {
 file_error: string | null; ready: number; duplicates: number; rejected: number; can_post: boolean;
 documents: { key: string; purchase_ref: string; source_system: string; supplier_name: string; location_name: string; currency_code: string; total: string; lines: number; duplicate: boolean }[];
 rows: { row: number; state: "READY" | "REJECTED" | "DUPLICATE"; source: Record<string, string>; findings: string[];
  prepared: null | { item_name: string; item_code: string; supplier_name: string; location_name: string; quantity: string; unit_code: string; base_quantity: string; base_unit_code: string; net_amount: string; tax: string; invoice_amount: string; currency_code: string } }[];
};
export type PurchaseBatch = {
 entry_method?: "CSV" | "MANUAL";
 id: string; filename: string; state: "INVALID" | "REVIEW" | "POSTED" | "CANCELLED";
 source_hash: string; source_organisation_code: string; price_basis: "EXCLUSIVE" | "INCLUSIVE";
 mappings: PurchaseMappings; contract_version: string; created_at: string; posted_at: string | null;
 report: PurchaseReport; controls: Record<string, string> | null;
};
export type PurchaseHistory = { total: number; batches: { id: string; filename: string; state: PurchaseBatch["state"]; created_at: string; posted_at: string | null; ready: number; duplicates: number; rejected: number }[] };

export function parsePurchaseMappings(text: string): PurchaseMappings {
 if (text.length > 32768) throw new Error("Use at most 100 code mappings per category.");
 const input = JSON.parse(text);
 if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("Check the code mappings.");
 const result: PurchaseMappings = { items: {}, suppliers: {}, locations: {} };
 for (const type of ["items", "suppliers", "locations"] as const) {
  const entries = input[type] ?? {};
  if (!entries || typeof entries !== "object" || Array.isArray(entries) || Object.keys(entries).length > 100) throw new Error("Check the code mappings.");
  for (const [source, target] of Object.entries(entries)) {
   if (source.length < 1 || source.length > 100 || typeof target !== "string" || target.trim().length > 40) throw new Error("Map source codes to existing catalogue codes (up to 40 characters).");
   if (target.trim()) Object.defineProperty(result[type], source, { value: target.trim(), enumerable: true, configurable: true, writable: true });
  }
 }
 return result;
}

export const purchaseStateLabel = (value: PurchaseBatch["state"]) => ({ INVALID: "Needs correction", REVIEW: "Ready for review", POSTED: "Recorded", CANCELLED: "Cancelled" })[value];

/** Generated entry records quote every data cell. Original imported files stay untouched. */
export function generatedPurchaseCsv(csv: string): string {
 return "\uFEFF" + csv.replace(/^\uFEFF/, "").replace(/"((?:""|[^"])*)"/g, (_cell, content: string) =>
  '"' + (/^[\s\u0000-\u001f]*[=+\-@]/.test(content) ? "'" : "") + content + '"');
}
