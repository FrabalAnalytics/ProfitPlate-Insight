import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const source=await readFile(new URL('../lib/order-totals.ts',import.meta.url),'utf8');
const {outputText}=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2020}});
const {orderTotals}=await import(`data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`);
const line=(quantity,unit_price,discount='0',tax='0')=>({quantity,unit_price,discount,tax});

test('PO totals preserve decimal precision across lines, discounts and declared tax basis',()=>{
 assert.deepEqual(orderTotals([line('10','1000')],'EXCLUSIVE'),{total:'10000',lines:['10000']});
 assert.deepEqual(orderTotals([line('2','100','10','15'),line('0.1','0.2')],'EXCLUSIVE'),{total:'205.02',lines:['205','0.02']});
 assert.equal(orderTotals([line('2','100','10','15')],'INCLUSIVE').total,'190');
 assert.equal(orderTotals([line('0.000001','0.000001')],'EXCLUSIVE').total,'0.000000000001');
 assert.equal(orderTotals([line('9999999999999','9999999999999')],'EXCLUSIVE').total,'99999999999980000000000001');
});
test('incomplete or invalid PO lines do not produce misleading totals',()=>{
 for(const entry of [line('1',''),line('0','10'),line('1','10','11'),line('1','NaN'),line('1.0000001','1'),line('1','1','-1')]) assert.equal(orderTotals([entry],'EXCLUSIVE'),null);
 assert.equal(orderTotals([line('1','10','0','11')],'INCLUSIVE'),null);
 assert.equal(orderTotals([],'EXCLUSIVE'),null);
});
