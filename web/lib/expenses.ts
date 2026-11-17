import type { SalesSummary } from "./sales-imports";
export const expenseHeaders=["Organisation_Code","Source_System","Expense_Ref","Line_Ref","Category_Code","Scope","Location_Code","Expense_From","Expense_To","Recognition_Method","Payment_Date","Amount","Currency","Description"] as const;
export type ExpenseCategory={id:string;code:string;name:string;kind:"LABOUR"|"OPERATING";is_active:boolean};
export type ExpenseEntry={id:string;batch_id:string;source_system:string;expense_ref:string;line_ref:string;category_name:string;kind:string;location_name:string;location_id:string|null;expense_from:string;expense_to:string;recognition_method:string;payment_date:string|null;amount:string;period_amount:string|null;currency_code:string;description:string;voided_at:string|null;void_reason:string|null};
export type ExpenseReport={currency_code:string;labour_amount:string;operating_amount:string;central_amount:string;active_entries:number;daily_allocated_entries:number;labour_entries:number;operating_entries:number;excluded_central_entries:number;legacy_entries:number;categories:{code:string;name:string;kind:string;amount:string;entries:number}[];entries:ExpenseEntry[];entry_total:number;labour_coverage:{valid:boolean;reviewed_at:string|null};operating_coverage:{valid:boolean;reviewed_at:string|null};sales:SalesSummary|null;sales_error:string|null;estimated_prime_cost:string|null;prime_cost_percent:string|null;labour_cost_percent:string|null;refreshed_at:string};
export type ExpenseBatch={id:string;filename:string;state:"INVALID"|"REVIEW"|"POSTED";source_hash:string;report:{file_error:string|null;ready:number;duplicates:number;rejected:number;can_post:boolean;source_total:string|null;rows:{row:number;state:string;source:Record<string,string>;findings:string[];prepared:null|{category_name:string;kind:string;location_name:string;amount:string;currency_code:string;recognition_method:string;previously_voided:boolean}}[]}};
export type ExpenseHistory={total:number;batches:{id:string;filename:string;state:string;created_at:string}[]};
export type ExpenseState={error?:string;success?:string};
export const csvExpense=(values:string[])=>values.map(value=>'"'+value.replaceAll('"','""')+'"').join(',');
// Display rounding only. The ledger, cumulative allocations and source controls
// retain six decimal places and never pass financial arithmetic through Number.
export function expenseMoney(value:string,currency:string) {
 const negative=value.startsWith('-'),[whole,fraction='']=value.replace(/^-/,'').split('.');
 let cents=BigInt(whole)*BigInt(100)+BigInt(fraction.slice(0,2).padEnd(2,'0'));
 if((fraction[2]??'0')>='5')cents+=BigInt(1);
 return `${currency} ${negative&&cents?'-':''}${(cents/BigInt(100)).toString().replace(/\B(?=(\d{3})+(?!\d))/g,',')}.${(cents%BigInt(100)).toString().padStart(2,'0')}`;
}
