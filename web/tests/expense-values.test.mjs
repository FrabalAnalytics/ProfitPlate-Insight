import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const source=await readFile(new URL('../lib/expenses.ts',import.meta.url),'utf8');
const {outputText}=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}});
const {expenseMoney}=await import(`data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`);
test('expense display rounds decimal strings without losing large-amount precision',()=>{
 assert.equal(expenseMoney('99999999999999.999999','NGN'),'NGN 100,000,000,000,000.00');
 assert.equal(expenseMoney('10000000000000.005000','NGN'),'NGN 10,000,000,000,000.01');
 assert.equal(expenseMoney('0.003334','NGN'),'NGN 0.00');
 assert.equal(expenseMoney('0.005000','NGN'),'NGN 0.01');
});
