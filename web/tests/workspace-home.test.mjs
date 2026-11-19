import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const source=await readFile(new URL('../lib/workspace-home.ts',import.meta.url),'utf8');
const {outputText}=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext}});
const {workspaceHome,workspaceNavigation}=await import(`data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`);
const all={overview:true,expenses:true,sales:true,purchases:true,menus:true,recipes:true,catalogue:true,team:true};
const role=(role_code,location_id=null)=>({role_code,location_id});

test('Inventory Manager gets stock oversight and department access without financial or team tasks',()=>{
 const home=workspaceHome([role('inventory_manager')],{overview:false,expenses:false,sales:false,purchases:false,orders:true,inventory:true,menus:false,recipes:false,catalogue:false,team:false});
 assert.equal(home.title,'Inventory Manager workspace');
 assert.ok(home.tasks.some(task=>task.action==='Review stock requests'));
 assert.ok(home.tasks.some(task=>task.action==='Manage centres & team access'));
 assert.ok(home.tasks.some(task=>task.action==='Open Goods Received Notes'));
 assert.ok(!home.tasks.some(task=>task.path.includes('/expenses')||task.path.includes('/invoices')||task.path.includes('/team')));
});
test('Finance and Procurement get distinct work without crossing responsibilities',()=>{
 const finance=workspaceHome([role('finance')],{...all,team:false});
 const procurement=workspaceHome([role('procurement')],{...all,overview:false,expenses:false,team:false});
 assert.equal(finance.title,'Finance workspace');assert.equal(procurement.title,'Procurement workspace');
 assert.ok(finance.tasks.some(task=>task.action==='Review supplier invoices'));
 assert.ok(!finance.tasks.some(task=>task.action==='Record supplier invoice'));
 assert.ok(procurement.tasks.some(task=>task.action==='Record supplier invoice'));
 assert.ok(!procurement.tasks.some(task=>task.path==='/workspace/expenses'));
});

test('Procurement does not get stock requests; an independently assigned stock role retains its workspace',()=>{
 const access={...all,inventory:true,orders:true};
 assert.equal(workspaceNavigation([role('procurement')],access).inventory,false);
 assert.ok(!workspaceHome([role('procurement')],access).tasks.some(task=>task.path.startsWith('/workspace/inventory')));
 assert.equal(workspaceNavigation([role('procurement'),role('inventory_manager')],access).inventory,true);
});
test('combined roles retain both task groups and executive reporting comes first',()=>{
 const combined=workspaceHome([role('finance'),role('procurement')],all);
 assert.ok(combined.tasks.some(task=>task.action==='Record supplier invoice'));
 assert.ok(combined.tasks.some(task=>task.action==='Review supplier invoices'));
 assert.equal(workspaceHome([role('restaurant_admin'),role('ceo')],all).tasks[0].path,'/workspace/overview');
});

test('CEO home prioritises financial decisions even with other operational roles assigned',()=>{
 const home=workspaceHome([role('ceo'),role('restaurant_admin'),role('inventory_manager'),role('procurement')],{...all,inventory:true,orders:true});
 assert.match(home.description,/what changed/);
 assert.deepEqual(home.tasks.map(task=>task.path),['/workspace/overview','/workspace/reports']);
});
test('location-scoped roles never create organisation-wide purchasing or finance shortcuts',()=>{
 const home=workspaceHome([role('finance','outlet'),role('procurement','outlet')],{...all,overview:false,expenses:false,purchases:false,team:false});
 assert.ok(home.tasks.every(task=>!task.path.includes('/purchases')&&!task.path.includes('/expenses')&&!task.path.includes('/setup')));
});
test('disabled capabilities hide links even when roles include an administrator',()=>{
 const disabled=Object.fromEntries(Object.keys(all).map(key=>[key,false]));
 assert.deepEqual(workspaceHome([role('restaurant_admin')],disabled).tasks,[]);
 assert.equal(workspaceHome([role('operations')],disabled).title,'Operations workspace');
 assert.equal(workspaceHome([role('restaurant_admin')],all).title,'Administration workspace');
});
test('Inventory receives through its own workspace without purchasing or finance shortcuts',()=>{
 const access={overview:false,expenses:false,sales:false,purchases:false,orders:true,menus:false,recipes:false,catalogue:false,team:false};
 const home=workspaceHome([role('inventory','outlet')],access);
 assert.equal(home.title,'Inventory / Receiving workspace');
 assert.deepEqual(home.tasks.map(task=>task.path),['/workspace/purchases/receipts']);
 assert.match(home.tasks[0].description,/different colleague/);
 const combined=workspaceHome([role('inventory'),role('procurement')],{...access,purchases:true});
 assert.equal(combined.tasks.filter(task=>task.path==='/workspace/purchases/orders').length,1);
});

test('Finance has centre waste and financial work without setup or stock handling; extra roles retain their own tools',()=>{
 const access={...all,inventory:true,orders:true,history:true};const roles=[role('finance')],nav=workspaceNavigation(roles,access),home=workspaceHome(roles,access);
 assert.equal(nav.team,false);assert.equal(nav.catalogue,false);assert.equal(nav.recipes,false);assert.equal(nav.inventory,true);assert.ok(home.tasks.some(t=>t.action==='Review centre waste'));assert.ok(!home.tasks.some(t=>t.path.startsWith('/workspace/setup')||t.path==='/workspace/inventory'));assert.equal(home.tasks[0].action,'Review supplier invoices');
 const combined=workspaceHome([role('finance'),role('inventory_manager')],access);assert.ok(combined.tasks.some(t=>t.action==='Manage centres & team access'));assert.ok(combined.tasks.some(t=>t.action==='Review centre waste'));
});

test('Operations retains recipe and material tools, and explicitly combined executive roles retain navigation',()=>{
 const access={...all,inventory:true,orders:true};const ops=workspaceNavigation([role('operations')],access);assert.equal(ops.recipes,true);assert.equal(ops.catalogue,true);assert.equal(ops.sales,false);assert.equal(workspaceNavigation([role('ceo')],access).inventory,false);assert.equal(workspaceNavigation([role('ceo'),role('restaurant_admin')],access).inventory,true);
});
