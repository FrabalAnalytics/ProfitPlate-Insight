import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const source=await readFile(new URL('../lib/requisitions.ts',import.meta.url),'utf8');
const {outputText}=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}});
const {unacceptedQuantity}=await import(`data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`);
test('partial acceptance shows exact unaccepted quantities without floating-point residue',()=>{
 assert.equal(unacceptedQuantity('0.3','0.1'),'0.2');
 assert.equal(unacceptedQuantity('12.000000000000','12'),'0');
 assert.equal(unacceptedQuantity('5','0'),'5');
 assert.equal(unacceptedQuantity('999999999999.000000000001','999999999999'),'0.000000000001');
});
