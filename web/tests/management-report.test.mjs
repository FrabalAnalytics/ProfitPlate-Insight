import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const source=await readFile(new URL('../lib/management-report.ts',import.meta.url),'utf8');
const {outputText}=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext}});
const {managementReportRows,managementReportCsv,costPercent,savedManagementReportRows,standardCostRatios}=await import(`data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`);
const context={organisation:'Demo',organisationId:'org-id',from:'2020-05-15',to:'2020-05-15',location:'All business locations + central costs',locationId:'',currency:'NGN',timeZone:'Africa/Lagos',generatedAt:'2020-05-15T12:00:00Z'};
const overview={refreshed_at:context.generatedAt,summary:{lines:2,receipts:2,quantity:'3',priced_lines:2,missing_lines:0,net_revenue:'4350.000000',estimated_food_cost:'2700.000000',estimated_food_margin:'1650.000000',food_margin_percent:'37.931034',menus:[],missing:[]},daily:[{date:context.from,lines:2,receipts:2,net_revenue:'4350.000000'}],outlets:[],channels:[]};
const costs={refreshed_at:context.generatedAt,labour_entries:1,operating_entries:1,labour_amount:'600.000000',operating_amount:'100.000000',central_amount:'100.000000',labour_coverage:{valid:true},operating_coverage:{valid:true},estimated_prime_cost:'3300.000000',prime_cost_percent:'75.862069',labour_cost_percent:'13.793103',excluded_central_entries:0,legacy_entries:0,daily_allocated_entries:1};
const find=(rows,metric)=>rows.find(row=>row.metric===metric);

test('saved report exports retain source decimals, original context and saved-estimate identity',()=>{
 const report={id:'saved-id',title:'=Report name',created_at:context.generatedAt,format_version:'MANAGEMENT_SNAPSHOT_V1',payload:{context,overview,costs}};
 const rows=savedManagementReportRows(report),csv=managementReportCsv(rows);
 assert.equal(find(rows,'Recorded net sales').value,'4350.000000');
 assert.equal(find(rows,'Saved report ID').value,'saved-id');
 assert.match(find(rows,'Reporting basis').value,/Saved management estimate/);
 assert.match(csv,/EXECUTIVE_MANAGEMENT_SAVED_CSV_V1/);assert.match(csv,/"'=Report name"/);
 assert.doesNotMatch(csv,/Live management report|not a locked accounting|not a saved report history/);
 assert.throws(()=>savedManagementReportRows({...report,format_version:'UNKNOWN'}),/Unsupported/);
});
test('report preserves exact service values, metadata and financial basis without recomputing totals',()=>{
 const rows=managementReportRows(context,overview,costs);
 assert.equal(find(rows,'Recorded net sales').value,'4350.000000');assert.equal(find(rows,'Estimated prime cost').value,'3300.000000');assert.equal(find(rows,'Estimated prime cost percent').value,'75.862069');
 assert.equal(find(rows,'Labour coverage').value,'Reviewed');assert.equal(find(rows,'Location ID').value,'ALL');assert.equal(find(rows,'Daily management allocation entries').value,'1');assert.match(find(rows,'Reporting basis').value,/not actual inventory COGS/);
 const csv=managementReportCsv(rows);assert.match(csv,/"3300.000000"/);assert.ok(csv.startsWith('\uFEFF'));assert.match(csv,/EXECUTIVE_MANAGEMENT_CSV_V1/);
});
test('missing expense service and incomplete food costs retain revenue without manufactured zeros',()=>{
 const packet={...overview,summary:{...overview.summary,missing_lines:1,priced_lines:1,estimated_food_cost:null,estimated_food_margin:null,food_margin_percent:null,known_subtotal:'900.000000'}};
 const rows=managementReportRows(context,packet,null);
 assert.equal(find(rows,'Recorded net sales').value,'4350.000000');assert.equal(find(rows,'Estimated food margin').value,null);assert.equal(find(rows,'Recorded labour').value,null);assert.equal(find(rows,'Estimated prime cost').status,'UNAVAILABLE');assert.equal(find(rows,'Known food cost subtotal').status,'PARTIAL');assert.ok(rows.some(row=>row.section==='Exceptions'));
});
test('unreviewed empty costs remain missing, reviewed zero remains zero, and empty sales have no inferred revenue',()=>{
 const empty={...costs,labour_entries:0,labour_amount:'0.000000',labour_coverage:{valid:false},estimated_prime_cost:null,prime_cost_percent:null,labour_cost_percent:null};
 assert.equal(find(managementReportRows(context,overview,empty),'Recorded labour').value,null);
 assert.equal(find(managementReportRows(context,overview,{...empty,labour_coverage:{valid:true}}),'Recorded labour').value,'0.000000');
 const rows=managementReportRows(context,{...overview,summary:{...overview.summary,lines:0}},empty);
 assert.equal(find(rows,'Recorded net sales').value,null);assert.equal(find(rows,'Recorded net sales').status,'NO_RECORDS');
});
test('CSV neutralises text formulas, quotes multiline notes and preserves legitimate negative decimals',()=>{
 const csv=managementReportCsv([{section:'=HYPERLINK("bad")',metric:' \t@SUM(1)',value:'-900.123456',unit:'NGN',status:'ESTIMATED',notes:'A "quoted" note\nnext line'},{section:'safe',metric:'safe',value:'\r+cmd',unit:'',status:'CONTEXT',notes:'-unsafe text'}]);
 assert.match(csv,/"'=HYPERLINK\(""bad""\)"/);assert.match(csv,/"' \t@SUM\(1\)"/);assert.match(csv,/"-900.123456"/);assert.match(csv,/A ""quoted"" note\nnext line/);assert.match(csv,/"'\r\+cmd"/);assert.match(csv,/"'-unsafe text"/);
});

test('cost percentages use exact decimals and retain missing and zero-revenue states',()=>{
 assert.equal(costPercent('2700.000000','4350.000000'),'62.068966');
 assert.equal(costPercent('2700.00000000000000000000','4350.000000'),'62.068966');
 assert.equal(costPercent('0.12345678901234567890','0.24691357802469135780'),'50.000000');
 assert.equal(costPercent(null,'4350'),null);assert.equal(costPercent('900','0'),null);
 assert.equal(costPercent('0','4350'),'0.000000');assert.equal(costPercent('1','-3'),'-33.333333');
 assert.equal(costPercent('99999999999999.999999','99999999999999.999999'),'100.000000');
 assert.equal(costPercent('1','200000000'),'0.000001');
});


test('standard ratios share the report scope and retain exact server percentages',()=>{
 const values=standardCostRatios(overview.summary,costs);assert.deepEqual(values.map(r=>r.label),['Food cost %','Labour cost %','Prime cost %']);assert.deepEqual(values.map(r=>r.value),['62.068966','13.793103','75.862069']);assert.deepEqual(values.map(r=>r.status),['ESTIMATED','REVIEWED','ESTIMATED']);assert.match(values[2].formula,/food cost.*labour cost.*net sales/);
 const long={...overview.summary,net_revenue:'0.24691357802469135780',estimated_food_cost:'0.12345678901234567890'};assert.equal(standardCostRatios(long,null)[0].value,'50.000000');
});
test('missing food or labour cannot produce a reassuring partial prime cost',()=>{
 let values=standardCostRatios({...overview.summary,missing_lines:1},costs);assert.equal(values[0].value,null);assert.equal(values[1].value,'13.793103');assert.equal(values[2].value,null);
 values=standardCostRatios(overview.summary,{...costs,labour_coverage:{valid:false}});assert.equal(values[0].value,'62.068966');assert.equal(values[1].value,null);assert.equal(values[2].value,null);assert.match(values[1].note,/Review labour completeness/);
 const zero={...costs,labour_amount:'0.000000',labour_entries:0,labour_cost_percent:'0.000000',prime_cost_percent:'62.068966'};assert.equal(standardCostRatios(overview.summary,zero)[1].value,'0.000000');assert.equal(standardCostRatios(overview.summary,zero)[2].value,'62.068966');
});
test('zero and negative sales suppress ratios, including stale stored percentages',()=>{
 for(const net_revenue of ['0','0.000000','-1.000000'])assert.ok(standardCostRatios({...overview.summary,net_revenue},costs).every(r=>r.value===null));assert.ok(standardCostRatios({...overview.summary,lines:0},costs).every(r=>r.value===null));
});
test('separately refreshed sales and expenses cannot mix denominators or food bases',()=>{
 const source={...costs,sales:{...overview.summary,net_revenue:'4000.000000'}};let values=standardCostRatios(overview.summary,source);assert.equal(values[0].value,'62.068966');assert.equal(values[1].value,null);assert.equal(values[2].value,null);assert.match(values[1].note,/align sales and labour/);
 values=standardCostRatios(overview.summary,{...costs,sales:{...overview.summary,net_revenue:'4350.00000000',estimated_food_cost:'2700.00000000000'}});assert.equal(values[2].value,'75.862069');values=standardCostRatios(overview.summary,{...costs,sales:{...overview.summary,estimated_food_cost:'2600'}});assert.equal(values[1].value,'13.793103');assert.equal(values[2].value,null);
});

test('non-food retail sales and costs stay separate from food/beverage ratios',()=>{
 const summary={...overview.summary,lines:4,missing_lines:0,net_revenue:'2150',estimated_food_cost:'430',food_beverage_sales:'2000',food_beverage_cost:'400'};
 const expenses={...costs,sales:summary,labour_cost_percent:costPercent('100','2150'),prime_cost_percent:costPercent('500','2150')};
 assert.deepEqual(standardCostRatios(summary,expenses).map(r=>r.value),['20.000000','4.651163','23.255814']);
 const missingRetail={...summary,missing_lines:1,estimated_food_cost:null};
 assert.equal(standardCostRatios(missingRetail,{...expenses,sales:missingRetail})[0].value,'20.000000');
 const unknown={...summary,food_beverage_sales:null,food_beverage_cost:null};
 assert.equal(standardCostRatios(unknown,{...expenses,sales:unknown})[0].value,null);
 assert.equal(standardCostRatios(unknown,{...expenses,sales:unknown})[2].value,null);
});
