import ExcelJS from "exceljs";
import { inflateRawSync } from "node:zlib";

// Check actual expanded bytes before handing an untrusted XLSX ZIP to the reader.
// Small onboarding files never need ZIP64, encryption, macros or external links.
export function checkWorkbookArchive(bytes: Buffer) {
 const fail = () => { throw new Error("Use a plain XLSX workbook under 512 KB, with one data sheet and no macros or external links."); };
 if (bytes.length < 22 || bytes.length > 524288) fail();
 let end = -1;
 for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 65557); i--) if (bytes.readUInt32LE(i) === 0x06054b50 && i + 22 + bytes.readUInt16LE(i + 20) === bytes.length) { end = i; break; }
 if (end < 0 || bytes.readUInt16LE(end + 4) !== 0 || bytes.readUInt16LE(end + 6) !== 0) fail();
 const count = bytes.readUInt16LE(end + 10), size = bytes.readUInt32LE(end + 12), start = bytes.readUInt32LE(end + 16);
 if (count < 1 || count > 128 || start + size !== end || bytes.readUInt16LE(end + 8) !== count) fail();
 let offset = start, total = 0;
 const names = new Set<string>();
 for (let i = 0; i < count; i++) {
  if (offset + 46 > end || bytes.readUInt32LE(offset) !== 0x02014b50) fail();
  const flags = bytes.readUInt16LE(offset + 8), method = bytes.readUInt16LE(offset + 10), compressed = bytes.readUInt32LE(offset + 20), expanded = bytes.readUInt32LE(offset + 24);
  const nameLength = bytes.readUInt16LE(offset + 28), extraLength = bytes.readUInt16LE(offset + 30), commentLength = bytes.readUInt16LE(offset + 32), local = bytes.readUInt32LE(offset + 42);
  if (offset + 46 + nameLength + extraLength + commentLength > end || local + 30 > start) fail();
  const name = bytes.subarray(offset + 46, offset + 46 + nameLength).toString("utf8").toLowerCase();
  if (names.has(name) || name.includes("..") || name.includes("\\") || name.startsWith("/") || name.includes("vbaproject") || name.includes("externallinks") || flags & 1 || ![0, 8].includes(method) || expanded > 8388608 || compressed > bytes.length || bytes.readUInt32LE(local) !== 0x04034b50) fail();
  names.add(name);
  const dataStart = local + 30 + bytes.readUInt16LE(local + 26) + bytes.readUInt16LE(local + 28);
  if (dataStart + compressed > start) fail();
  const data = bytes.subarray(dataStart, dataStart + compressed);
  let actual: number;
  try { actual = method === 0 ? data.length : inflateRawSync(data, { maxOutputLength: 8388608 }).length; } catch { fail(); }
  if (actual! !== expanded || (total += actual!) > 8388608) fail();
  offset += 46 + nameLength + extraLength + commentLength;
 }
 if (offset !== end || !names.has("[content_types].xml") || !names.has("xl/workbook.xml")) fail();
}

export async function readOnboardingFile(file: File): Promise<string> {
 const name = file.name.toLowerCase();
 if (!file.size || file.size > (name.endsWith(".xlsx") ? 524288 : 262144)) throw new Error("Use a CSV under 256 KB or XLSX under 512 KB.");
 const bytes = Buffer.from(await file.arrayBuffer());
 if (name.endsWith(".csv")) return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
 if (!name.endsWith(".xlsx")) throw new Error("Choose a CSV or XLSX file. Legacy XLS files are not supported.");
 checkWorkbookArchive(bytes);
 const book = new ExcelJS.Workbook();
 await book.xlsx.load(bytes as unknown as Parameters<typeof book.xlsx.load>[0]);
 const sheets = book.worksheets.filter(sheet => sheet.actualRowCount > 0);
 if (sheets.length !== 1 || sheets[0].rowCount > 501 || sheets[0].columnCount > 30) throw new Error("Use one data sheet, at most 500 data rows, and the original template columns.");
 const sheet = sheets[0], records: string[][] = [];
 sheet.eachRow({ includeEmpty: true }, row => {
  const values: string[] = [];
  for (let col = 1; col <= sheet.columnCount; col++) {
   const value = row.getCell(col).value;
   if (value === null || value === undefined) values.push("");
   else if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") values.push(String(value));
   else if (value instanceof Date && Number.isFinite(value.getTime())) values.push(value.toISOString().slice(0, 10));
   else throw new Error(`Row ${row.number}, column ${col}: paste plain values. Formulas, errors, rich text and links are not supported.`);
  }
  records.push(values);
 });
 return records.map(row => row.map(value => `"${value.replaceAll('"', '""')}"`).join(',')).join('\n');
}
