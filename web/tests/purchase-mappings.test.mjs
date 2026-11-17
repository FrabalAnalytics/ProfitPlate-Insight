import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import ts from "typescript";

const source = await readFile(new URL("../lib/purchase-imports.ts", import.meta.url), "utf8");
const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } });
const { parsePurchaseMappings, generatedPurchaseCsv } = await import(`data:text/javascript;base64,${Buffer.from(outputText).toString("base64")}`);

test('generated entry CSV neutralises formula references and preserves quoted newlines and decimal strings',()=>{
 const source='Reference,Amount,Note\n"=HYPERLINK(""x"")","123.450000","quoted ""note""\nnext line"\n" \t@SUM(1)","0.000001","ordinary"';
 const output=generatedPurchaseCsv(source);assert.ok(output.startsWith('\uFEFF'));assert.match(output,/"'=HYPERLINK\(""x""\)"/);assert.match(output,/"' \t@SUM\(1\)"/);assert.match(output,/"123.450000"/);assert.match(output,/"0.000001"/);assert.match(output,/quoted ""note""\nnext line/);
});
test("source code mappings preserve leading zeros and explicit codes without creating masters", () => {
 assert.deepEqual(parsePurchaseMappings('{"items":{"0001":" RICE001 ","0002":""}}'), { items: { "0001": "RICE001" }, suppliers: {}, locations: {} });
});
test("malformed or oversized code maps fail instead of entering form or RPC state", () => {
 for (const value of ['null', '[]', '{', '{"items":[]}', '{"items":{"A":42}}', '{"items":{"A":"' + "x".repeat(41) + '"}}', JSON.stringify({ suppliers: Object.fromEntries(Array.from({ length: 101 }, (_, i) => [String(i), "SUP001"])) }), "x".repeat(32769)]) assert.throws(() => parsePurchaseMappings(value));
});
test("special source keys are ordinary own properties and cannot change map prototypes", () => {
 const value = parsePurchaseMappings('{"items":{"__proto__":"RICE001","constructor":"RICE002"}}');
 assert.equal(Object.getPrototypeOf(value.items), Object.prototype);
 assert.equal(Object.hasOwn(value.items, "__proto__"), true);
 assert.equal(JSON.parse(JSON.stringify(value)).items.__proto__, "RICE001");
 assert.equal({}.polluted, undefined);
});
