export type RecipeOption = { id: string; label: string; code: string; uom_id: string; uom_code: string; dimension: string };
export type RecipeLine = { key: string; kind: "ITEM" | "RECIPE"; target: RecipeOption | null; quantity: string; uom_id: string };
export type RecipePacket = {
 recipe: { id: string; code: string; name: string; recipe_type: "FINAL" | "SUB_RECIPE" };
 version: { id: string; recipe_id: string; version: number; name: string; effective_from: string; notes: string; created_at: string };
 output: { quantity: string; uom_id: string; uom_code: string };
 components: { id: string; kind: "ITEM" | "RECIPE"; target_id: string; label: string; code: string; target_type: string; quantity: string; uom_id: string; uom_code: string; base_uom_id: string; base_uom_code: string; dimension: string; normalised_quantity: string; conversion_id: string | null }[];
 cost_state: "MISSING";
};
export const positiveDecimal = (text: string) => /^(?:0|[1-9]\d{0,13})(?:\.\d{1,6})?$/.test(text) && /[1-9]/.test(text);
export const displayQuantity = (value: string | number) => String(value).replace(/(\.\d*?)0+$/, "$1").replace(/\.$/, "");
export function validBusinessDate(value: string) {
 try { return /^\d{4}-\d{2}-\d{2}$/.test(value) && new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value; }
 catch { return false; }
}
