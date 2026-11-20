import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const source=await readFile(new URL('../lib/inventory-accountability.ts',import.meta.url),'utf8');
const {outputText}=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}});
const {quantityDifference}=await import(`data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`);
test('count variance distinguishes missing input, explicit zero and exact fractional shortages',()=>{
 assert.equal(quantityDifference('','80.000000000000'),null);
 assert.equal(quantityDifference('0','0.000000000000'),'0');
 assert.equal(quantityDifference('0','5.25'),'-5.25');
 assert.equal(quantityDifference('0.3','0.1'),'0.2');
 assert.equal(quantityDifference('999999999999999999999.000000000001','999999999999999999999'),'0.000000000001');
 assert.equal(quantityDifference('12','-3'),'15');
 assert.equal(quantityDifference('1e3','1'),null);
});
