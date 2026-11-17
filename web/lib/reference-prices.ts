export const referencePriceHeaders = ["material_code", "quantity", "unit_code", "total_price", "price_date", "source_note"] as const;
export type ReferencePriceInput = Record<(typeof referencePriceHeaders)[number], string>;
export type ReferencePricePreview = ReferencePriceInput & { item_id: string; name: string; base_unit_code: string; base_quantity: string; cost_per_base_unit: string; currency_code: string; cost_state: "ESTIMATED" };
export type ReferenceMaterial = { id: string; code: string; name: string; base_uom_id: string; base_unit_code: string; is_active: boolean; latest: null | { cost_per_base_unit: string; currency_code: string; price_date: string; source_note: string; version: number; cost_state: "ESTIMATED" } };
export type ReferencePricePage = { total: number; active_materials: number; priced_materials: number; items: ReferenceMaterial[]; history: { version: number; quantity: string; unit_code: string; base_quantity: string; total_price: string; cost_per_base_unit: string; currency_code: string; price_date: string; source_note: string; created_at: string; source: string }[] };

// This small onboarding import is separate from transaction-import contracts.
// Strict CSV supports quoted commas, quotes, CRLF and newlines; never evaluates cells.
export function parseReferencePriceCsv(input: string): ReferencePriceInput[] {
 if (new TextEncoder().encode(input).length > 131072) throw new Error("Keep the CSV under 128 KB and at most 100 price rows.");
 const text = input.replace(/^\uFEFF/, "");
 const records: string[][] = [];
 let row: string[] = [], cell = "", quoted = false, closed = false;
 const endCell = () => { row.push(cell.trim()); cell = ""; closed = false; };
 const endRow = () => { endCell(); if (row.some(value => value !== "")) records.push(row); row = []; if (records.length > 101) throw new Error("Import at most 100 price rows at a time."); };
 for (let index = 0; index < text.length; index++) {
  const char = text[index];
  if (quoted) {
   if (char === '"' && text[index + 1] === '"') { cell += '"'; index++; }
   else if (char === '"') { quoted = false; closed = true; }
   else cell += char;
  } else if (char === ',') endCell();
  else if (char === '\n' || char === '\r') { if (char === '\r' && text[index + 1] === '\n') index++; endRow(); }
  else if (char === '"') { if (cell || closed) throw new Error("A CSV quote is misplaced. Export the file as CSV again."); quoted = true; }
  else { if (closed) throw new Error("Unexpected text after a quoted CSV value."); cell += char; }
 }
 if (quoted) throw new Error("The CSV contains an unclosed quote.");
 if (cell || row.length || closed) endRow();
 if (records.length < 2) throw new Error("Include the header and at least one price row.");
 if (records[0].join(",") !== referencePriceHeaders.join(",")) throw new Error(`Use the template headers in this order: ${referencePriceHeaders.join(", ")}.`);
 return records.slice(1).map((values, index) => {
  if (values.length !== referencePriceHeaders.length) throw new Error(`Row ${index + 1}: expected six columns. Quote any note containing commas.`);
  const row = Object.fromEntries(referencePriceHeaders.map((key, i) => [key, values[i]])) as ReferencePriceInput;
  row.material_code = row.material_code.toUpperCase(); row.unit_code = row.unit_code.toUpperCase();
  return row;
 });
}

export function validateReferencePriceRows(rows: ReferencePriceInput[]) {
 if (!Array.isArray(rows) || rows.length < 1 || rows.length > 100) return "Include between 1 and 100 price rows.";
 for (const [index, row] of rows.entries()) {
  const label = `Row ${index + 1}: `;
  if (!row || referencePriceHeaders.some(key => typeof row[key] !== "string")) return label + "check all six fields.";
  if (!/^[A-Z0-9][A-Z0-9_-]{0,39}$/.test(row.material_code)) return label + "enter an existing material code.";
  if (!/^[A-Z]{1,20}$/.test(row.unit_code)) return label + "enter a valid unit code.";
  for (const key of ["quantity", "total_price"] as const) {
   if (!/^(?:0|[1-9]\d{0,13})(?:\.\d{1,6})?$/.test(row[key]) || !/[1-9]/.test(row[key])) return label + "quantity and total price must be positive, with up to six decimal places and no commas.";
  }
  try {
   if (!/^\d{4}-\d{2}-\d{2}$/.test(row.price_date) || new Date(`${row.price_date}T00:00:00Z`).toISOString().slice(0, 10) !== row.price_date) throw new Error();
  } catch { return label + "enter a valid date in YYYY-MM-DD format."; }
  if (row.source_note.trim().length < 1 || row.source_note.length > 300) return label + "add a source note of 1 to 300 characters.";
 }
 return null;
}

// Preserve all stored decimal digits. Small positive prices must not display as zero.
export function referenceAmount(value: string, currency: string) {
 const [whole, fraction = ""] = value.split(".");
 return `${currency} ${whole.replace(/\B(?=(\d{3})+(?!\d))/g, ",")}.${fraction.replace(/0+$/, "").padEnd(2, "0")}`;
}
