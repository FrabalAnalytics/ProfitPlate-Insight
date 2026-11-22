export type ReportOptions={centres:{id:string;name:string}[];items:{id:string;name:string;code:string;category:string}[]};
export type StockStatement={centre:string;restaurant:string;currency:string;from:string;through:string;financial:boolean;generated_at:string;total:number;detail_total:number;known_estimated_value:string|null;unpriced:number|null;rows:{item_id:string;name:string;code:string;unit:string;opening:string;added:string;removed:string;adjusted:string;closing:string;breakdown:Record<string,string>;cost:null|{unit_cost:string|null;basis:string;source_note?:string;missing_reason?:string};estimated_value:string|null}[];entries:{id:number;document_id:string;reference:string;kind:string;occurred_on:string;created_at:string;quantity:string;running_balance:string}[]};
export type WeeklyRow={site_id:string;centre:string;day:string;count_id:string|null;state:string;expected:number;entered:number;cutoff:string;deadline:string;time_zone:string;owner:string|null;submitter:string|null;submitted_at:string|null;late:boolean|null;overdue:boolean;revision:number|null;can_record:boolean};
export type WeeklySummary={expected:number;submitted:number;overdue:number;late:number;reviewed:number};
export type WeeklyReport={centres:{id:string;name:string}[];manage:boolean;total:number;calendar_gaps:number;summary:WeeklySummary;rows:WeeklyRow[]};
export type CountLine={item_id:string;name:string;code:string;unit:string;book:string;physical:string|null;variance:string|null;variance_percent:string|null;note:string;unit_cost:string|null;estimated_variance_value:string|null;price_basis:unknown};
export type WeeklySheet={daily_boundary?:string|null;reporting_month?:string|null;scheduled_cutoff?:string|null;schedule_exception?:string|null;sales_reconciliations?:{item_id:string;book_delta:string;approved_at:string}[];monthly_date?:string|null;no_stock_confirmed?:boolean;id:string;organisation_id:string;site_id:string;centre:string;count_date:string;cutoff:string;deadline:string;time_zone:string;owner_name:string|null;state:string;revision:number;snapshot_at:string;submitter_name:string|null;submitted_by:string|null;submitted_at:string|null;submission_note:string|null;reviewed_by:string|null;reviewed_at:string|null;review_note:string|null;posted_at:string|null;stock_document_id:string|null;financial:boolean;currency:string;can_record:boolean;can_review:boolean;can_post:boolean;stale:boolean;cutoff_warnings:{id:string;reference:string}[];lines:CountLine[]};
export type CountScope={evidence:string;submission_hours:number;items:{id:string;name:string;code:string;unit:string;included:boolean;quantity:string}[]};
export const countLabels:Record<string,string>={UPCOMING:'Upcoming',NOT_STARTED:'Not started',DRAFT:'In progress',SUBMITTED:'Submitted for review',APPROVED:'Approved for adjustment',POSTED:'Adjustment posted',REVIEWED:'Reviewed without adjustment'};
export function countTime(value:string,zone:string){return new Intl.DateTimeFormat('en-GB',{timeZone:zone,dateStyle:'medium',timeStyle:'short'}).format(new Date(value));}
// Decimal subtraction stays exact even for twelve-place stock quantities.
export function quantityDifference(physical:string,book:string):string|null {
 const scale=BigInt('1000000000000');
 const parse=(source:string)=>{
  if(!/^-?\d+(\.\d{1,12})?$/.test(source))return null;
  const negative=source.startsWith('-');
  const [whole,fraction='']=source.replace('-','').split('.');
  const value=BigInt(whole)*scale+BigInt(fraction.padEnd(12,'0'));
  return negative?-value:value;
 };
 const actual=parse(physical),expected=parse(book);
 if(actual===null||expected===null)return null;
 const difference=actual-expected,negative=difference<BigInt(0),value=negative?-difference:difference;
 const fraction=String(value%scale).padStart(12,'0').replace(/0+$/,'');
 return(negative?'-':'')+String(value/scale)+(fraction?'.'+fraction:'');
}
