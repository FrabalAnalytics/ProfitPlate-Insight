import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import ts from 'typescript';
import ExcelJS from 'exceljs';
import JSZip from 'jszip';

const transpile=async path=>ts.transpileModule(await readFile(new URL(path,import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022,esModuleInterop:true}}).outputText;
const parser=await import(`data:text/javascript;base64,${Buffer.from(await transpile('../lib/master-imports.ts')).toString('base64')}`);
await mkdir(new URL('../node_modules/.import-reader-tests/',import.meta.url),{recursive:true});
const readerUrl=new URL('../node_modules/.import-reader-tests/reader.mjs',import.meta.url);
await writeFile(readerUrl,await transpile('../lib/onboarding-file.ts'));
const {readOnboardingFile,checkWorkbookArchive}=await import(readerUrl.href);
const {parseMasterCsv,materialImportHeaders,recipeImportHeaders}=parser;
const csv=materialImportHeaders.join(',')+'\r\ncreate,fish,"Whole fish, large",raw,Fish,kg,TRUE,true,purchased,true,3000.123456,2026-11-22,main,0,2026-11-22';

test('master CSV preserves precision, quoted text and explicit zero; unknown is blank',()=>{
 const rows=parseMasterCsv('\uFEFF'+csv,'MATERIAL');assert.equal(rows[0].material_name,'Whole fish, large');assert.equal(rows[0].last_purchase_unit_price,'3000.123456');assert.equal(rows[0].opening_quantity,'0');assert.equal(rows[0].stock_tracked,'true');assert.equal(rows[0].centre_code,'MAIN');
 const blank=parseMasterCsv(csv.replace(',main,0,2026-11-22',',,,'),'MATERIAL');assert.equal(blank[0].opening_quantity,'');
});
test('master CSV rejects malformed schemas, quotes and oversized files',()=>{
 for(const bad of ['code,name\nA,B',materialImportHeaders.join(',')+'\nA,B',csv+'"',csv.repeat(10000)])assert.throws(()=>parseMasterCsv(bad,'MATERIAL'));
});
test('XLSX and CSV produce equivalent material rows including dates, booleans and zeros',async()=>{
 const book=new ExcelJS.Workbook(),sheet=book.addWorksheet('Import');sheet.addRow([...materialImportHeaders]);
 const row=parseMasterCsv(csv,'MATERIAL')[0];sheet.addRow(materialImportHeaders.map(h=>h==='last_purchase_date'||h==='opening_date'?new Date('2026-11-22T00:00:00Z'):h==='opening_quantity'?0:h==='stock_tracked'?true:row[h]));
 const file=new File([await book.xlsx.writeBuffer()],'materials.xlsx');assert.deepEqual(parseMasterCsv(await readOnboardingFile(file),'MATERIAL'),[row]);
});
test('XLSX refuses formulas, multiple data sheets, invalid archives and unsupported file types',async()=>{
 const book=new ExcelJS.Workbook(),sheet=book.addWorksheet('Import');sheet.addRow([...recipeImportHeaders]);sheet.addRow(['CREATE',{formula:'1+1',result:2}]);
 await assert.rejects(readOnboardingFile(new File([await book.xlsx.writeBuffer()],'recipe.xlsx')),/plain values/);
 book.addWorksheet('Another').addRow(['Not silently ignored']);await assert.rejects(readOnboardingFile(new File([await book.xlsx.writeBuffer()],'recipe.xlsx')),/one data sheet/);
 assert.throws(()=>checkWorkbookArchive(Buffer.from('not a workbook')));
 await assert.rejects(readOnboardingFile(new File(['x'],'test.xls')),/not supported/);
});
test('CSV and XLSX templates are schema-identical and use plain text values',async()=>{
 for(const[name,kind]of[['material-master-import','MATERIAL'],['recipe-components-import','RECIPE']]){
  const csvText=await readFile(new URL(`../public/templates/${name}.csv`,import.meta.url),'utf8');
  const file=new File([await readFile(new URL(`../public/templates/${name}.xlsx`,import.meta.url))],name+'.xlsx');
  assert.deepEqual(parseMasterCsv(await readOnboardingFile(file),kind),parseMasterCsv(csvText,kind));
 }
});
test('workbook preflight bounds expansion and refuses macro archives before the reader runs',async()=>{
 for(const payload of ['large','macro']){
  const zip=new JSZip();zip.file('[Content_Types].xml','types');zip.file('xl/workbook.xml','workbook');
  zip.file(payload==='macro'?'xl/vbaProject.bin':'xl/sharedStrings.xml',payload==='macro'?'macro':Buffer.alloc(8388609,65));
  const bytes=await zip.generateAsync({type:'nodebuffer',compression:'DEFLATE'});assert.ok(bytes.length<524288);assert.throws(()=>checkWorkbookArchive(bytes));
 }
});
