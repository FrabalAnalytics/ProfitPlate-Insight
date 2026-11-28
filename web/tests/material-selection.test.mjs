import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const {outputText}=ts.transpileModule(await readFile(new URL('../lib/material-selection.ts',import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}});
const {materialChoices,materialMatches,materialGroup}=await import('data:text/javascript;base64,'+Buffer.from(outputText).toString('base64'));
const raw={id:'raw',name:'Beef — Whole',code:'BEEF_WHOLE',unit:'KG',item_type:'RAW'};
const cut={id:'cut',name:'Beef — Cut',code:'BEEF_CUT',unit:'PCS',item_type:'SEMI_FINISHED'};
test('names, codes and units can be searched with multiple words and punctuation',()=>{
 assert.equal(materialMatches(raw,'beef whole'),true);
 assert.equal(materialMatches(raw,'BEEF_WHOLE'),true);
 assert.equal(materialMatches(cut,'beef pcs'),true);
 assert.equal(materialMatches(cut,'beef whole'),false);
 assert.equal(materialMatches({id:'x',name:'Purée'},'puree'),true);
});
test('a search never replaces a previously chosen ingredient or mutates its source name',()=>{
 const list=[raw,cut];assert.deepEqual(materialChoices(list,'whole','cut').map(i=>i.id),['cut','raw']);
 assert.equal(list[0],raw);assert.equal(raw.name,'Beef — Whole');
});
test('only the caller-supplied catalogue is searchable, even when a stale id is supplied',()=>{
 assert.deepEqual(materialChoices([raw],'cut','cut'),[]);
 assert.deepEqual(materialChoices([],'','cut'),[]);
});
test('equal names retain separate records with deterministic ordering',()=>{
 const a={id:'a',name:'Beef',code:'B01'},b={id:'b',name:'Beef',code:'B02'};
 assert.deepEqual(materialChoices([b,a],'','').map(i=>i.id),['a','b']);
});
test('groups use recorded classification rather than guessing from names',()=>{
 assert.equal(materialGroup(raw),'Raw ingredients');assert.equal(materialGroup(cut),'Prepared ingredients');
 assert.equal(materialGroup({id:'x',name:'Beef Processed'}),'Materials');
 assert.equal(materialGroup({id:'x',name:'Bottle',item_type:'PACKAGING'}),'Packaging');
});
test('alphabetical selection does not hide zero-stock or unpriced assigned materials',()=>{
 assert.deepEqual(materialChoices([raw,cut],'','').map(i=>i.id),['cut','raw']);
});
