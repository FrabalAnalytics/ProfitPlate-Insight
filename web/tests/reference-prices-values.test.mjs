import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import ts from "typescript";

const source = await readFile(new URL("../lib/reference-prices.ts", import.meta.url), "utf8");
const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } });
const { parseReferencePriceCsv, validateReferencePriceRows, referenceAmount } = await import(`data:text/javascript;base64,${Buffer.from(outputText).toString("base64")}`);
const headers = "material_code,quantity,unit_code,total_price,price_date,source_note";

test("CSV preserves quoted notes and exact decimal strings from Excel exports", () => {
 const rows = parseReferencePriceCsv(`\uFEFF${headers}\r\nrice,50,kg,90000.000001,2020-01-01,"Invoice, supplier said ""revised""\nprice"\r\n`);
 assert.equal(rows[0].total_price, "90000.000001"); assert.equal(rows[0].material_code, "RICE");
 assert.equal(rows[0].source_note, 'Invoice, supplier said "revised"\nprice'); assert.equal(validateReferencePriceRows(rows), null);
});
test("CSV rejects malformed files and enforces bounded import size", () => {
 for (const text of [headers, "name,price\nRice,0", `${headers}\nRICE,50,KG,90000,2020-01-01,"unclosed`, `${headers}\nRICE,50,KG,90000,2020-01-01,"note"oops`, `${headers}\nRICE,50,KG,90000,2020-01-01,extra,note`, "x".repeat(131073), headers + "\n" + "RICE,50,KG,90000,2020-01-01,note\n".repeat(101)]) assert.throws(() => parseReferencePriceCsv(text));
});
test("zero, absent, formula and invalid calendar prices never become valid estimates", () => {
 const row = parseReferencePriceCsv(`${headers}\nRICE,50,KG,90000,2020-01-01,note`)[0];
 for (const changed of [{ total_price: "0" }, { total_price: "" }, { total_price: "=1+1" }, { quantity: "1e3" }, { quantity: "0.0000001" }, { price_date: "2020-02-31" }, { source_note: "" }]) assert.ok(validateReferencePriceRows([{ ...row, ...changed }]));
 assert.ok(validateReferencePriceRows(null));
 assert.equal(referenceAmount("0.000000000001", "NGN"), "NGN <0.01");
 assert.equal(referenceAmount("1800.000000000000", "NGN"), "NGN 1,800.00");
});

test("money displays two decimal places without changing source precision or losing large values",()=>{
 assert.equal(referenceAmount('5555.555555555556','NGN'),'NGN 5,555.56');
 assert.equal(referenceAmount('222222.222222222222','NGN'),'NGN 222,222.22');
 assert.equal(referenceAmount('1851.851851851852','NGN'),'NGN 1,851.85');
 assert.equal(referenceAmount('99999999999999.995000','NGN'),'NGN 100,000,000,000,000.00');
 assert.equal(referenceAmount('-12.345000','NGN'),'NGN -12.35');
 assert.equal(referenceAmount('0.000000','NGN'),'NGN 0.00');
 assert.equal(referenceAmount('-0.000001','NGN'),'NGN >-0.01');
});
