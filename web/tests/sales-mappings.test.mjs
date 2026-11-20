import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import ts from 'typescript';
const source=await readFile(new URL('../lib/sales-imports.ts',import.meta.url),'utf8');
const {outputText}=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}});
const {parseSalesMappings}=await import(`data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`);
test('sales mappings preserve source identities, strip target whitespace and keep channels explicit',()=>{
 assert.deepEqual(parseSalesMappings('{"menu_items":{"0001":" MENU001 "},"locations":{"B01":"PRIMARY"},"channels":{"IN STORE":"DINE_IN","EMPTY":""}}'),{menu_items:{'0001':'MENU001'},locations:{B01:'PRIMARY'},channels:{'IN STORE':'DINE_IN'}});
});
test('malformed, oversized and invalid channel-code mappings fail before validation',()=>{
 for(const text of ['null','[]','{','{"menu_items":[]}','{"menu_items":{"A":42}}','{"channels":{"X":"invalid code"}}',JSON.stringify({locations:Object.fromEntries(Array.from({length:101},(_,i)=>[String(i),'PRIMARY']))}),'x'.repeat(32769)]) assert.throws(()=>parseSalesMappings(text));
});
test('special source keys are ordinary data properties and cannot modify map prototypes',()=>{
 const value=parseSalesMappings('{"menu_items":{"__proto__":"MENU001","constructor":"MENU002"}}');
 assert.equal(Object.getPrototypeOf(value.menu_items),Object.prototype); assert.equal(Object.hasOwn(value.menu_items,'__proto__'),true);
 assert.equal(JSON.parse(JSON.stringify(value)).menu_items.__proto__,'MENU001'); assert.equal({}.polluted,undefined);
});

test('custom channel codes are preserved for restaurant-specific database validation',()=>{assert.equal(parseSalesMappings('{"channels":{"ROOM":"ROOM_SERVICE"}}').channels.ROOM,'ROOM_SERVICE');});
