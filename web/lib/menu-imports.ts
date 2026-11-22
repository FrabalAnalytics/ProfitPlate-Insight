export const menuImportHeaders=["action", "menu_code", "menu_name", "major_category", "subcategory", "recipe_code", "recipe_version", "recipe_quantity", "selling_price", "tax_setting", "tax_percent", "effective_from", "stock_centre_code", "consumption_mode"] as const;
export type MenuImportRow=Record<(typeof menuImportHeaders)[number],string>;
export type MenuImportPreview={valid:boolean;rows:{row:number;code:string;name:string;major:string;subcategory:string;price:string;action:string;error:string|null;warning:string|null}[]};
export function parseMenuCsv(input: string): MenuImportRow[] {
 if (new TextEncoder().encode(input).length > 131072) throw new Error("Keep the CSV under 128 KB and at most 100 menu rows.");
 const text = input.replace(/^\uFEFF/, "");
 const records: string[][] = [];
 let row: string[] = [], cell = "", quoted = false, closed = false;
 const endCell = () => { row.push(cell.trim()); cell = ""; closed = false; };
 const endRow = () => { endCell(); if (row.some(value => value !== "")) records.push(row); row = []; if (records.length > 101) throw new Error("Import at most 100 menu rows at a time."); };
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
 if (records.length < 2) throw new Error("Include the header and at least one menu row.");
 const legacy=records[0].join(",")===menuImportHeaders.slice(0,12).join(",");
 if (!legacy&&records[0].join(",") !== menuImportHeaders.join(",")) throw new Error(`Use the template headers in this order: ${menuImportHeaders.join(", ")}.`);
 return records.slice(1).map((values, index) => {
  if (values.length !== (legacy?12:menuImportHeaders.length)) throw new Error(`Row ${index + 1}: check the template columns. Quote any note containing commas.`);
  const row = Object.fromEntries(menuImportHeaders.map((key, i) => [key, values[i]??""])) as MenuImportRow;
  row.action=row.action.toUpperCase();row.menu_code=row.menu_code.toUpperCase();row.major_category=row.major_category.toUpperCase();row.recipe_code=row.recipe_code.toUpperCase();
  return row;
 });
}
