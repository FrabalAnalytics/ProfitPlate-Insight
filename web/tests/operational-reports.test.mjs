import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import ts from 'typescript';
const source=await readFile(new URL('../lib/operational-reports.ts',import.meta.url),'utf8');const {outputText}=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext}});const {historicalCsv,historicalCsvCell,historicalRpc}=await import(`data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`);
test('historical CSV preserves decimals, quoted notes, scope and spreadsheet safety',()=>{
 assert.equal(historicalCsvCell('\t=HYPERLINK("bad")'),'"\'\t=HYPERLINK(""bad"")"');assert.equal(historicalCsvCell('-2.000000000001'),'"-2.000000000001"');assert.equal(historicalCsvCell('@SUM(A1)'),'"\'@SUM(A1)"');
 const csv=historicalCsv({total:1,documents:1,refreshed_at:'2020-10-01T10:00:00Z',rows:[{reference:'=BAD',date:'2020-10-01',quantity:'2.000000000001',notes:'line one\nline "two"'}]},{business:'Restaurant',type:'WASTE',from:'2020-10-01',to:'2020-10-01',outlet:'Outlet',site:'Kitchen',status:'POSTED',search:'rice'});assert.ok(csv.startsWith('\uFEFF'));assert.match(csv,/"Kitchen"/);assert.match(csv,/2\.000000000001/);assert.match(csv,/"'=BAD"/);assert.match(csv,/line ""two""/);
});
test('export and screen RPC filters retain the same authorised scope',()=>{
 const screen=historicalRpc('org','WASTE',{outlet:'outlet',site:'kitchen',status:'POSTED',q:' rice ',page:'2'},'2020-01-01','2020-01-31');const exported=historicalRpc('org','WASTE',{outlet:'outlet',site:'kitchen',status:'POSTED',q:' rice ',page:'2'},'2020-01-01','2020-01-31',true);assert.deepEqual({...screen,p_export:true},exported);assert.equal(exported.p_search,'rice');
});
