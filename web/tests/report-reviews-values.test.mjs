import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const compile=source=>ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext}}).outputText;
const url=source=>`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`;
const financialUrl=url(compile(await readFile(new URL('../lib/management-report.ts',import.meta.url),'utf8')));
const {managementReportCsv,savedManagementReportRows}=await import(financialUrl);
const reviewsSource=compile(await readFile(new URL('../lib/report-reviews.ts',import.meta.url),'utf8')).replaceAll('"./management-report"',JSON.stringify(financialUrl));
const {reviewedManagementReportRows}=await import(url(reviewsSource));
const report={id:'report-id',title:'Saved report',format_version:'MANAGEMENT_SNAPSHOT_V1',created_at:'2026-11-15T12:00:00Z',payload:{
 context:{organisation:'Demo',organisationId:'org-id',from:'2020-04-15',to:'2020-04-15',location:'All',locationId:'',currency:'NGN',timeZone:'Africa/Lagos',generatedAt:'2026-11-15T12:00:00Z'},
 overview:{refreshed_at:'2026-11-15T12:00:00Z',summary:{lines:1,receipts:1,quantity:'1',priced_lines:0,missing_lines:1,net_revenue:'4350.123456',estimated_food_cost:null,estimated_food_margin:null,food_margin_percent:null,known_subtotal:'0',menus:[],missing:[]},daily:[],outlets:[],channels:[]},
 costs:{refreshed_at:'2026-11-15T12:00:00Z',labour_entries:1,operating_entries:0,labour_amount:'600.000000',operating_amount:'0',central_amount:'0',labour_coverage:{valid:false},operating_coverage:{valid:false},estimated_prime_cost:null,prime_cost_percent:null,labour_cost_percent:null,excluded_central_entries:0,legacy_entries:0,daily_allocated_entries:0}}};
const review={status:'APPROVED',revision:3,can_approve:true,decision:{action:'APPROVE',actor:'reviewer@example.test',at:'2026-11-15T12:30:00Z',note:'=unsafe, "note"\nnext line',revision:2},events:[]};
test('management approval adds decision provenance without changing missing financial values or claiming accounting approval',()=>{
 const original=structuredClone(report),rows=reviewedManagementReportRows(report,review),find=metric=>rows.find(r=>r.metric===metric);
 assert.equal(find('Recorded net sales').value,'4350.123456');assert.equal(find('Estimated food cost').value,null);assert.equal(find('Recorded labour').status,'PARTIAL');assert.equal(find('Estimated prime cost').value,null);
 assert.equal(find('Review status').value,'Approved for management use');assert.match(find('Review status').notes,/does not close/);assert.equal(find('Review revision').value,'3');assert.equal(find('Decision by').value,'reviewer@example.test');assert.equal(find('Decision at').value,review.decision.at);
 assert.equal(find('Format').value,'EXECUTIVE_MANAGEMENT_REVIEW_CSV_V1');assert.deepEqual(report,original);
 const csv=managementReportCsv(rows);assert.match(csv,/"'=unsafe, ""note""\nnext line"/);assert.match(csv,/not an approved accounting statement/);
});
test('unsubmitted downloads preserve V1 while unavailable review metadata never implies approval',()=>{
 assert.deepEqual(reviewedManagementReportRows(report,{status:'SAVED',revision:0,can_approve:false,decision:null,events:[]}),savedManagementReportRows(report));
 const rows=reviewedManagementReportRows(report,null);assert.equal(rows.find(r=>r.metric==='Review status').value,null);assert.match(rows.find(r=>r.metric==='Review status').notes,/No approval is inferred/);
});
test('withdrawn decisions retain changes-requested status and comment-only review retains saved state',()=>{
 const withdrawn=reviewedManagementReportRows(report,{...review,status:'CHANGES_REQUESTED',decision:{...review.decision,action:'WITHDRAW_APPROVAL'}});
 assert.equal(withdrawn.find(r=>r.metric==='Review status').value,'Changes requested');assert.equal(withdrawn.find(r=>r.metric==='Latest decision').value,'Approval withdrawn');
 const comment=reviewedManagementReportRows(report,{...review,status:'SAVED',revision:1,decision:null});assert.equal(comment.find(r=>r.metric==='Review status').value,'Not submitted');assert.equal(comment.some(r=>r.metric==='Decision by'),false);
});
