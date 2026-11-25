import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const source=await readFile(new URL('../lib/requisitions.ts',import.meta.url),'utf8');
const {outputText}=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}});
const {unacceptedQuantity,requestRoutes}=await import(`data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`);
test('partial acceptance shows exact unaccepted quantities without floating-point residue',()=>{
 assert.equal(unacceptedQuantity('0.3','0.1'),'0.2');
 assert.equal(unacceptedQuantity('12.000000000000','12'),'0');
 assert.equal(unacceptedQuantity('5','0'),'5');
 assert.equal(unacceptedQuantity('999999999999.000000000001','999999999999'),'0.000000000001');
});

const site=(id,kind,request=true,is_active=true)=>({id,kind,request,is_active,department:''});
const route=(id,source_id,destination_id,kind='TRANSFER',is_active=true)=>({id,source_id,destination_id,kind,is_active});
test('requesting departments can choose their supplier without source-stock permission',()=>{
 const locations=[site('main','STORE',false),site('kitchen','KITCHEN')];
 assert.deepEqual(requestRoutes({locations,routes:[route('issue','main','kitchen','ISSUE')]}).map(r=>r.id),['issue']);
 assert.deepEqual(requestRoutes({locations:locations.map(s=>({...s,request:false})),routes:[route('issue','main','kitchen','ISSUE')]}),[]);
});
test('one centre pair is offered for legacy duplicate types and reverse directions remain separate',()=>{
 const locations=[site('main','STORE'),site('kitchen','KITCHEN')],routes=[route('transfer-in','main','kitchen'),route('issue-in','main','kitchen','ISSUE'),route('issue-return','kitchen','main','ISSUE'),route('transfer-return','kitchen','main')];
 assert.deepEqual(requestRoutes({locations,routes}).map(r=>r.id).sort(),['issue-in','transfer-return']);
 assert.deepEqual(requestRoutes({locations,routes:[...routes].reverse()}).map(r=>r.id).sort(),['issue-in','transfer-return']);
 // A single explicitly configured kind is always honoured.
 assert.equal(requestRoutes({locations,routes:[routes[0]]})[0].kind,'TRANSFER');
});
test('inactive, missing or same-centre connections cannot appear as request choices',()=>{
 const locations=[site('main','STORE'),site('kitchen','KITCHEN',true,false)];
 assert.deepEqual(requestRoutes({locations,routes:[route('off','main','kitchen'),route('missing','main','unknown'),route('self','main','main'),route('inactive','main','main','TRANSFER',false)]}),[]);
});
