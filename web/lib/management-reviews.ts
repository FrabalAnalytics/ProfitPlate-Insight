import type {ExecutiveBriefing} from './executive-briefing';
import type {Overview} from './overview';
import type {ExpenseReport} from './expenses';
import type {StockValue} from './stock-value';
import type {SalesSummary} from './sales-imports';
import {historicalCsvCell} from './operational-reports';
export const reviewPeriods=['DAILY','WEEKLY','MONTHLY'] as const;
export const actionTopics=['WASTE','COUNT','PRODUCTION','STOCK','PURCHASING','MENU','DATA'] as const;
export const actionStates=['OPEN','IN_PROGRESS','RESOLVED','CLOSED','CANCELLED'] as const;
export const reviewRoles=['ceo','finance','restaurant_admin','operations','inventory_manager','inventory','procurement','kitchen_manager','bar_lead','stock_department'];
export type ReviewAccess={member:string;financial:boolean;reference_financial:boolean;menu:boolean;purchasing:boolean;manage:boolean;outlets:{id:string;name:string}[];centres:{id:string;name:string;outlet_id:string|null;waste:boolean}[]};
export type ReviewContext={period:string;anchor:string;from:string;to:string;previous_from:string;previous_to:string;today:string;time_zone:string;complete:boolean;days:number;previous_days:number;generated_at:string;outlet_id:string|null;site_id:string|null};
export type CountReview={expected:number;submitted:number;overdue:number;review:number;posting:number};
export type OperatingReview={
 waste:{centres:number;entries:number;known_value:string|null;unpriced:number|null;coverage:{expected:number;complete:number;due:number;on_time:number;overdue:number};daily:{day:string;entries:number;value:string|null;expected:number;complete:number}[];reasons:{reason:string;entries:number;value:string|null}[];materials:{material:string;unit:string;quantity:string;entries:number;value:string|null}[]};
 counts:{weekly:CountReview;monthly:CountReview;differences:{lines:number;shortage_value:string|null;surplus_value:string|null;unpriced:number};rows:{frequency:string;count:{count_id:string|null;site_id:string;centre:string;day:string;state:string}}[]};
 production:{batches:number;exceptions:number;processes:{process:string;unit:string;output_item_id:string;batches:number;exceptions:number;expected:string;actual:string;achievement:string|null}[];rows:{document_id:string;reference:string;document_date:string;centre:string;process:string;unit:string;expected:string;actual:string;variance:string;responsible_name:string;variance_reason:string}[]};
 purchasing:{orders:number;issued:number;grns:number};movement_documents:number;
};
export type ReviewPack={context:ReviewContext;access:ReviewAccess;financial:Pick<ExecutiveBriefing,'summary'|'food_cost_percent'|'prior_from'|'prior_to'|'prices'|'po_exposure'>|null;financial_previous:SalesSummary|null;overview:Overview|null;expenses:ExpenseReport|null;stock_now:StockValue|null;current:OperatingReview;previous:OperatingReview;live:{open_transfers:number;last_sale_date:string|null;pending_consumption:number|null};menus:{id:string;outlet:string;summary:{at_risk:number;incomplete:number;within_target:number;targets_missing?:number}}[];warnings:string[];currency:string};
export type FollowUp={id:string;organisation_id:string;topic:string;site_id:string|null;outlet_id:string|null;title:string;description:string;assignee_id:string;assignee:string;due_date:string;priority:string;state:string;revision:number;created_by:string;created_at:string;updated_at:string;centre:string|null;outlet:string|null;can_manage:boolean;can_progress:boolean;overdue:boolean};
export type FollowUpPacket={access:ReviewAccess;today:string;total:number;summary:{open:number;overdue:number;resolved:number;closed:number};rows:FollowUp[];events:{revision:number;note:string;state:string;due_date:string;assignee:string;at:string;actor:string}[]};
export const reviewLabel=(value:string)=>value.toLowerCase().replaceAll('_',' ').replace(/^./,c=>c.toUpperCase());
export const reviewRate=(part:number,total:number)=>total>0?`${(part/total*100).toFixed(1)}%`:'Not scheduled';
export function reviewExportRows(p:ReviewPack){
 const c=p.context,cur=p.current,previous=p.previous;
 const rows:unknown[][]=[['ProfitPlate Insights',`${reviewLabel(c.period)} management review`],['Period',c.from,c.to],['Comparison',c.previous_from,c.previous_to],['Scope',p.access.centres.find(s=>s.id===c.site_id)?.name??p.access.outlets.find(o=>o.id===c.outlet_id)?.name??'All permitted locations'],['Outlet ID',c.outlet_id??'All permitted'],['Centre ID',c.site_id??'All permitted'],['Timezone',c.time_zone],['Generated at',c.generated_at],['Basis','Recorded evidence; reference-cost estimates; not accounting net profit'],[],['Area','Metric','Selected period','Previous period','Basis']];
 const add=(area:string,metric:string,value:unknown,prior:unknown,basis='Recorded evidence')=>rows.push([area,metric,value??'Unavailable',prior??'Unavailable',basis]);
 if(p.financial){const a=p.financial.summary,b=p.financial_previous;add('Sales','Net sales',a.lines?a.net_revenue:null,b?.lines?b.net_revenue:null);add('Margins','Estimated food contribution',a.lines?a.estimated_food_margin:null,b?.lines?b.estimated_food_margin:null,'Ingredient and packaging basis; excludes unconnected costs');add('Margins','Estimated gross profit margin %',a.lines?a.food_margin_percent:null,b?.lines?b.food_margin_percent:null);}
 for(const row of p.overview?.daily??[])add('Daily sales',row.date,row.lines?row.net_revenue:null,null,'No recorded rows do not confirm zero trading');
 if(cur.waste.centres>0){
  add('Waste','Recorded loss entries',cur.waste.entries,previous.waste.entries,'Entries, not quantities across different units');add('Waste','Known estimated loss value',cur.waste.known_value,previous.waste.known_value,'Unpriced entries excluded; missing reports are not zero waste');add('Compliance','Waste centre-days complete',cur.waste.coverage.complete,previous.waste.coverage.complete);add('Compliance','Waste centre-days expected',cur.waste.coverage.expected,previous.waste.coverage.expected);
  for(const row of cur.waste.materials)add('Waste materials',`${row.material} / ${row.unit}`,row.quantity,null,'Recorded quantities in their own units');
  for(const row of cur.waste.reasons)add('Waste reasons',row.reason,row.entries,null,'Recorded entries; no quantities combined across units');
  for(const row of cur.waste.daily??[]){add('Daily waste reporting',row.day,`${row.complete} / ${row.expected}`,null,'Centre-days confirmed / expected');add('Daily recorded loss',row.day,row.value,null,'Known estimated value; missing/unpriced loss is not zero');}
 }
 if(p.access.centres.length){
  for(const frequency of ['weekly','monthly'] as const){const a=cur.counts[frequency],b=previous.counts[frequency];add('Counts',`${frequency} counts expected`,a.expected,b.expected);add('Counts',`${frequency} counts submitted`,a.submitted,b.submitted);add('Counts',`${frequency} awaiting review`,a.review,b.review,'Current status of obligations scheduled in each period');add('Counts',`${frequency} approved awaiting posting`,a.posting,b.posting);}
  add('Production','Posted batches',cur.production.batches,previous.production.batches);add('Production','Outside tolerance',cur.production.exceptions,previous.production.exceptions);
  for(const row of cur.production.processes)add('Yield',`${row.process} / ${row.unit}`,row.achievement,null,'Expected output achieved %; not measured mass yield');
  add('Count observations','Known estimated shortage',cur.counts.differences.shortage_value,null,'Submitted/reviewed observations; overlapping count cycles are not additive losses');
 }
 if(p.access.purchasing&&!c.site_id){add('Purchasing','POs dated in period',cur.purchasing.orders,previous.purchasing.orders);add('Purchasing','Active GRNs received in period',cur.purchasing.grns,previous.purchasing.grns);}
 if(p.stock_now)add('Stock now','Known estimated value',p.stock_now.known_value,null,`Current snapshot ${p.stock_now.as_of}; not a historical closing valuation`);
 for(const row of p.expenses?.categories??[])add('Expenses',`${row.kind} / ${row.name}`,row.amount,null,'Recorded expense allocation; review coverage before interpreting totals');
 for(const row of p.menus){add('Menu targets',`${row.outlet} / Above target or loss`,row.summary.at_risk,null,`Menu setup effective ${c.to}, not sales-weighted performance`);add('Menu targets',`${row.outlet} / Costing incomplete`,row.summary.incomplete,null);}
 for(const row of p.stock_now?.centres??[])add('Centre stock value',row.name,row.known_value,null,`Snapshot ${p.stock_now!.as_of}; ${row.unpriced} unpriced balances excluded`);
 return rows;
}
export const managementReviewCsv=(p:ReviewPack)=>'\uFEFF'+reviewExportRows(p).map(row=>row.map(historicalCsvCell).join(',')).join('\r\n');
