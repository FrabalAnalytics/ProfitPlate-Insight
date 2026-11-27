import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const compile=source=>`data:text/javascript;base64,${Buffer.from(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext}}).outputText).toString('base64')}`;
const operational=compile(await readFile(new URL('../lib/operational-reports.ts',import.meta.url),'utf8'));
const report=compile(await readFile(new URL('../lib/management-report.ts',import.meta.url),'utf8'));
const source=(await readFile(new URL('../lib/management-reviews.ts',import.meta.url),'utf8')).replace("'./operational-reports'",JSON.stringify(operational)).replace("'./management-report'",JSON.stringify(report));
const {managementReviewCsv,reviewRate,reviewExportRows}=await import(compile(source));
const count={expected:0,submitted:0,overdue:0,review:0,posting:0};
const operating={waste:{centres:1,entries:0,known_value:null,unpriced:null,coverage:{complete:0,expected:0},materials:[{material:'=Fish',unit:'KG',quantity:'2.000000000001',entries:1}],reasons:[]},counts:{weekly:count,monthly:count,differences:{shortage_value:null}},production:{batches:0,exceptions:0,processes:[]},purchasing:{orders:0,grns:0}};
const pack={context:{period:'MONTHLY',from:'2024-03-01',to:'2024-03-31',previous_from:'2024-02-01',previous_to:'2024-02-29',time_zone:'Africa/Lagos',generated_at:'2024-04-02T10:00:00Z',site_id:'centre',outlet_id:'outlet'},access:{centres:[{id:'centre',name:'=Centre'}],outlets:[]},currency:'NGN',financial:{summary:{lines:1,net_revenue:'1234567890123456789.123456789012',estimated_food_margin:null,food_margin_percent:null}},financial_previous:null,current:operating,previous:operating,stock_now:null,expenses:null,menus:[]};
test('review exports retain exact source precision, calendar dates and scope without invented zeros',()=>{
 const rows=reviewExportRows(pack),csv=managementReviewCsv(pack);assert.ok(csv.startsWith('\uFEFF'));assert.ok(csv.includes('1234567890123456789.123456789012'));assert.ok(csv.includes('2024-02-29'));assert.ok(csv.includes('2.000000000001'));assert.equal(rows.find(r=>r[1]==='Estimated food contribution')[2],'Unavailable');assert.equal(rows.find(r=>r[1]==='Known estimated loss value')[2],'Unavailable');assert.equal(rows.find(r=>r[0]==='Scope')[1],'=Centre');assert.match(csv,/"'=Centre"/);assert.match(csv,/"'=Fish \/ KG"/);
});
test('zero obligations do not become perfect compliance',()=>{assert.equal(reviewRate(0,0),'Not scheduled');assert.equal(reviewRate(0,3),'0.0%');assert.equal(reviewRate(2,4),'50.0%');});


test('weekly/monthly review CSV includes standard ratios and keeps saved source values',()=>{
 const summary={lines:1,missing_lines:0,net_revenue:'10000.000000',estimated_food_cost:'3000.000000',estimated_food_margin:'7000',food_margin_percent:'70'};
 const expense={labour_coverage:{valid:true},labour_cost_percent:'20.000000',prime_cost_percent:'50.000000',labour_amount:'2000',categories:[]};
 for(const period of ['WEEKLY','MONTHLY']){const p={...pack,context:{...pack.context,period,site_id:null},access:{...pack.access,financial:true},financial:{summary},financial_previous:{...summary,estimated_food_cost:'4000'},expenses:expense};const rows=reviewExportRows(p).filter(r=>r[0]==='Cost ratios');assert.deepEqual(rows.map(r=>r[1]),['Food cost %','Labour cost %','Prime cost %']);assert.deepEqual(rows.map(r=>r[2]),['30.000000','20.000000','50.000000']);assert.equal(rows[0][3],'40.000000');assert.equal(rows[1][3],'Unavailable');assert.match(managementReviewCsv(p),/Labour cost %/);}
});
test('financial ratios stay outside centre and non-financial review exports',()=>{
 const p={...pack,access:{...pack.access,financial:true}};assert.equal(reviewExportRows(p).some(r=>r[0]==='Cost ratios'),false);assert.equal(reviewExportRows({...p,context:{...p.context,site_id:null},access:{...p.access,financial:false}}).some(r=>r[0]==='Cost ratios'),false);
});
