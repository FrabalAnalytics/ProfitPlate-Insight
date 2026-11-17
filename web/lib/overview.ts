import type { SalesSummary } from "./sales-imports";
export type ReportingContext = {from?:string;to?:string;location?:string};
export type NavigationAccess = {overview:boolean;expenses:boolean;sales:boolean;purchases:boolean;orders?:boolean;inventory?:boolean;history?:boolean;menus:boolean;recipes:boolean;catalogue:boolean;team:boolean};
export type Overview = {
 summary:SalesSummary;
 daily:{date:string;lines:number;receipts:number;net_revenue:string|null}[];
 outlets:{id:string;name:string;code:string;net_revenue:string;quantity:string;receipts:number}[];
 channels:{code:string;net_revenue:string;quantity:string;share_percent:string|null}[];
 recent_receipts:{id:string;reference:string;source:string;date:string;location_name:string;batch_id:string;net_revenue:string;customer_total:string}[];
 negative_menus:SalesSummary["menus"];
 ranked_menus:SalesSummary["menus"];
 comparison:{from:string;to:string;reason:string|null;recorded_days:number;net_revenue:string|null;change_percent:string|null};
 refreshed_at:string;
};
export function contextQuery(organisation:string,context:ReportingContext={},extra:Record<string,string>={}) {
 return new URLSearchParams({organisation,...(context.from?{from:context.from}:{}),...(context.to?{to:context.to}:{}),...(context.location?{location:context.location}:{}),...extra}).toString();
}
