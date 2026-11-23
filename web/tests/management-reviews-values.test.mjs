import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const compile=source=>`data:text/javascript;base64,${Buffer.from(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext}}).outputText).toString('base64')}`;
const operational=compile(await readFile(new URL('../lib/operational-reports.ts',import.meta.url),'utf8'));
const source=(await readFile(new URL('../lib/management-reviews.ts',import.meta.url),'utf8')).replace("'./operational-reports'",JSON.stringify(operational));
const {managementReviewCsv,reviewRate,reviewExportRows}=await import(compile(source));
const count={expected:0,submitted:0,overdue:0,review:0,posting:0};
const operating={waste:{centres:1,entries:0,known_value:null,unpriced:null,coverage:{complete:0,expected:0},materials:[{material:'=Fish',unit:'KG',quantity:'2.000000000001',entries:1}],reasons:[]},counts:{weekly:count,monthly:count,differences:{shortage_value:null}},production:{batches:0,exceptions:0,processes:[]},purchasing:{orders:0,grns:0}};
const pack={context:{period:'MONTHLY',from:'2024-03-01',to:'2024-03-31',previous_from:'2024-02-01',previous_to:'2024-02-29',time_zone:'Africa/Lagos',generated_at:'2024-04-02T10:00:00Z',site_id:'centre',outlet_id:'outlet'},access:{centres:[{id:'centre',name:'=Centre'}],outlets:[]},currency:'NGN',financial:{summary:{lines:1,net_revenue:'1234567890123456789.123456789012',estimated_food_margin:null,food_margin_percent:null}},financial_previous:null,current:operating,previous:operating,stock_now:null,expenses:null,menus:[]};
test('review exports retain exact source precision, calendar dates and scope without invented zeros',()=>{
 const rows=reviewExportRows(pack),csv=managementReviewCsv(pack);assert.ok(csv.startsWith('\uFEFF'));assert.ok(csv.includes('1234567890123456789.123456789012'));assert.ok(csv.includes('2024-02-29'));assert.ok(csv.includes('2.000000000001'));assert.equal(rows.find(r=>r[1]==='Estimated food contribution')[2],'Unavailable');assert.equal(rows.find(r=>r[1]==='Known estimated loss value')[2],'Unavailable');assert.equal(rows.find(r=>r[0]==='Scope')[1],'=Centre');assert.match(csv,/"'=Centre"/);assert.match(csv,/"'=Fish \/ KG"/);
});
test('zero obligations do not become perfect compliance',()=>{assert.equal(reviewRate(0,0),'Not scheduled');assert.equal(reviewRate(0,3),'0.0%');assert.equal(reviewRate(2,4),'50.0%');});
