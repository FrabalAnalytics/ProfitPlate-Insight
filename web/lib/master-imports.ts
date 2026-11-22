export const materialImportHeaders = ["action", "material_code", "material_name", "material_type", "category", "base_unit", "stock_tracked", "weekly_count_required", "supply_source", "requires_processing", "last_purchase_unit_price", "last_purchase_date", "centre_code", "opening_quantity", "opening_date"] as const;
export const recipeImportHeaders = ["action", "recipe_code", "recipe_name", "recipe_type", "yield_quantity", "yield_unit", "effective_from", "notes", "component_kind", "component_code", "component_version", "component_quantity", "component_unit"] as const;
export type MasterImportKind = "MATERIAL" | "RECIPE";
export type MasterImportRow = Record<string, string>;
export type MasterImportPreview = { valid: boolean; revision: string; rows: { row: number; code: string; name: string; action: string; detail: string; error: string | null; warning: string | null }[] };

export function parseMasterCsv(input: string, kind: MasterImportKind): MasterImportRow[] {
 if (new TextEncoder().encode(input).length > 262144) throw new Error("Keep the CSV under 256 KB and 500 data rows.");
 const headers = kind === "MATERIAL" ? materialImportHeaders : recipeImportHeaders;
 const text = input.replace(/^\uFEFF/, ""), records: string[][] = [];
 let row: string[] = [], cell = "", quoted = false, closed = false;
 const endCell = () => { row.push(cell.trim()); cell = ""; closed = false; };
 const endRow = () => { endCell(); if (row.some(v => v !== "")) records.push(row); row = []; if (records.length > 501) throw new Error("Import at most 500 data rows at a time."); };
 for (let i = 0; i < text.length; i++) {
  const char = text[i];
  if (quoted) {
   if (char === '"' && text[i + 1] === '"') { cell += '"'; i++; }
   else if (char === '"') { quoted = false; closed = true; }
   else cell += char;
  } else if (char === ',') endCell();
  else if (char === '\n' || char === '\r') { if (char === '\r' && text[i + 1] === '\n') i++; endRow(); }
  else if (char === '"') { if (cell || closed) throw new Error("A CSV quote is misplaced. Export the file as CSV again."); quoted = true; }
  else { if (closed) throw new Error("Unexpected text after a quoted CSV value."); cell += char; }
 }
 if (quoted) throw new Error("The CSV contains an unclosed quote.");
 if (cell || row.length || closed) endRow();
 if (records.length < 2 || records[0].join(',') !== headers.join(',')) throw new Error("Use the downloaded template headers, in their original order, and at least one data row.");
 const upper = new Set(["action", "material_code", "material_type", "base_unit", "supply_source", "centre_code", "recipe_code", "recipe_type", "yield_unit", "component_kind", "component_code", "component_unit"]);
 const bools = new Set(["stock_tracked", "weekly_count_required", "requires_processing"]);
 return records.slice(1).map((values, index) => {
  if (values.length !== headers.length) throw new Error(`Data row ${index + 1}: check the template columns. Quote names or notes containing commas.`);
  return Object.fromEntries(headers.map((key, i) => [key, upper.has(key) ? values[i].toUpperCase() : bools.has(key) ? values[i].toLowerCase() : values[i]]));
 });
}
