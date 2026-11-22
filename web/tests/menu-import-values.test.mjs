import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import ts from 'typescript';
const {outputText}=ts.transpileModule(await readFile(new URL('../lib/menu-imports.ts',import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}});
const {parseMenuCsv,menuImportHeaders}=await import(`data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`);
test('menu import preserves quoted names, subcategories and exact decimal prices',()=>{
 const csv=menuImportHeaders.join(',')+'\r\ncreate,plate,"Rice, fish",food,Mains,recipe,1,1,6000.123456,NONE,0,2026-11-19,KITCHEN,RECIPE';const r=parseMenuCsv('\uFEFF'+csv)[0];assert.equal(r.menu_name,'Rice, fish');assert.equal(r.major_category,'FOOD');assert.equal(r.recipe_code,'RECIPE');assert.equal(r.selling_price,'6000.123456');assert.equal(r.action,'CREATE');
});
test('menu CSV rejects extra cells, malformed quotes, wrong schemas and oversized batches',()=>{
 const header=menuImportHeaders.join(',');for(const csv of ['menu_code,name\nA,B',header+'\nCREATE,A,B',header+'\nCREATE,A,"Unclosed'])assert.throws(()=>parseMenuCsv(csv));assert.throws(()=>parseMenuCsv(header+'\n'+('CREATE,A,B,FOOD,Mains,,,,,,,2026-11-19\n').repeat(101)));assert.throws(()=>parseMenuCsv('a'.repeat(131073)));
});

test('earlier twelve-column menu files remain usable without a stock mapping',()=>{
 const csv=menuImportHeaders.slice(0,12).join(',')+'\nCREATE,OLD,Old plate,FOOD,Mains,R,1,1,6000,NONE,0,2026-11-19';const row=parseMenuCsv(csv)[0];assert.equal(row.stock_centre_code,'');assert.equal(row.consumption_mode,'');
});
