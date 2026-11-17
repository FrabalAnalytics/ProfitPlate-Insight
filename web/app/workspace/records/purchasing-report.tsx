import Link from "next/link";
import { DataTable,StatusBadge } from "@/app/components/data-table";
import { displayQuantity } from "@/lib/recipes";
import { referenceAmount } from "@/lib/reference-prices";
import { historicalSource,historicalStatusLabels,receivingLabels,comparisonLabels,purchasingViewName,type HistoricalOptions,type HistoricalReport,type PurchasingView,type PurchasingRow } from "@/lib/operational-reports";

export function PurchasingFilters({options,supplier,material,user,receiving,type}:{options:HistoricalOptions;supplier?:string;material?:string;user?:string;receiving:string;type:string}){
 return <>
  <div><label htmlFor="history-supplier">Supplier</label><select id="history-supplier" name="supplier" defaultValue={supplier??""}><option value="">All permitted suppliers</option>{options.suppliers?.map(s=><option key={s.id} value={s.id}>{s.name}</option>)}</select></div>
  <div><label htmlFor="history-material">Material</label><select id="history-material" name="material" defaultValue={material??""}><option value="">All materials</option>{options.materials?.map(m=><option key={m.id} value={m.id}>{m.name} ({m.code})</option>)}</select></div>
  <div><label htmlFor="history-user">{type==="PO"?"Ordered by":"Received by"}</label><select id="history-user" name="user" defaultValue={user??""}><option value="">All permitted users</option>{options.users?.map(u=><option key={u.id} value={u.id}>{u.name}</option>)}</select></div>
  {type==="PO"&&<div><label htmlFor="history-receiving">Receiving progress</label><select id="history-receiving" name="receiving" defaultValue={receiving}>{Object.entries(receivingLabels).map(([key,label])=><option key={key} value={key}>{label}</option>)}</select></div>}
 </>;
}
export function PurchasingViewTabs({type,view,comparison,href}:{type:string;view:PurchasingView;comparison:boolean;href:(extra:Record<string,string>)=>string}){
 const views:PurchasingView[]=type==="PO"&&comparison?["REGISTER","DETAIL","COMPARISON"]:["REGISTER","DETAIL"];
 return <nav className="purchasing-view-tabs" aria-label="Purchasing report views">{views.map(v=><Link key={v} href={href({view:v})} aria-current={view===v?"page":undefined}>{v==="REGISTER"?`${type} register`:v==="DETAIL"?`${type} material detail`:"Ordered / received / invoiced"}</Link>)}</nav>;
}
export function PurchasingReportTable({organisation,type,view,report}:{organisation:string;type:string;view:PurchasingView;report:HistoricalReport}){
 const money=(row:PurchasingRow,value?:string|null)=>value==null?"Unavailable":referenceAmount(value,row.currency??"");
 const quantity=(value?:string|null)=>value==null?"—":displayQuantity(value);
 const doc=(row:PurchasingRow)=><span><Link className="inline-link" href={historicalSource(organisation,row)}>{row.reference}</Link><small>{row.date}</small></span>;
 const party=(row:PurchasingRow)=><span>{row.party}<small>{row.outlet}</small></span>;
 const item=(row:PurchasingRow)=><span>{row.item}<small>{row.item_code} · {row.unit}</small></span>;
 const status=(row:PurchasingRow)=><StatusBadge tone={row.state==="VOIDED"?"danger":row.state==="VOID_PENDING"?"warning":row.state==="DRAFT"?"neutral":"success"}>{historicalStatusLabels[row.state]??row.state}</StatusBadge>;
 const receiving=(row:PurchasingRow)=><StatusBadge tone={row.receiving_state==="COMPLETED"?"success":row.receiving_state==="NOT_ISSUED"?"neutral":"warning"}>{receivingLabels[row.receiving_state??""]??"Unavailable"}</StatusBadge>;
 const related=(row:PurchasingRow)=><Link className="inline-link" href={`/workspace/purchases/orders?${new URLSearchParams({organisation,order:row.params.order})}`}>{row.related_reference}</Link>;
 const columns:{label:string;numeric?:boolean}[]=view==="COMPARISON"?[
  {label:"PO / material"},{label:"Supplier / outlet"},{label:"Ordered",numeric:true},{label:"Accepted",numeric:true},{label:"Outstanding",numeric:true},{label:"Linked billed",numeric:true},{label:"Net price: PO / invoice",numeric:true},{label:"Net price impact",numeric:true},{label:"Review"}
 ]:type==="PO"?view==="REGISTER"?[
  {label:"PO / date"},{label:"Supplier / outlet"},{label:"Lines",numeric:true},{label:"Order status"},{label:"Receiving progress"},{label:"Quoted total",numeric:true},{label:"Ordered by"},{label:"Materials"}
 ]:[{label:"PO / date"},{label:"Supplier / outlet"},{label:"Material / unit"},{label:"Ordered",numeric:true},{label:"Accepted / outstanding",numeric:true},{label:"Quoted unit price",numeric:true},{label:"Discount / tax",numeric:true},{label:"Line total",numeric:true},{label:"Progress"}]:view==="REGISTER"?[
  {label:"GRN / received date"},{label:"PO"},{label:"Supplier / outlet"},{label:"Material lines",numeric:true},{label:"GRN status"},{label:"Received by"},{label:"Materials"}
 ]:[{label:"GRN / date"},{label:"PO / supplier"},{label:"Material / unit"},{label:"Accepted",numeric:true},{label:"Rejected",numeric:true},{label:"Rejection reason"},{label:"GRN status"},{label:"Received by"}];
 return <DataTable label={purchasingViewName(type,view)} columns={columns} rows={report.rows.map(row=>({id:row.id,cells:view==="COMPARISON"?[
  <span key="doc">{doc(row)}<small>{row.item} · {row.unit}</small></span>,party(row),quantity(row.quantity),quantity(row.accepted),quantity(row.remaining),<span key="billed">{quantity(row.billed)}<small>{row.billed==null?"Incomplete link coverage":`Billed − accepted: ${quantity(row.billing_gap)} ${row.unit}`}</small></span>,<span key="rate">{money(row,row.quoted_net_unit_price)}<small>{money(row,row.billed_net_unit_price)}</small></span>,money(row,row.price_impact),<span key="review"><StatusBadge tone={row.comparison_state==="ALIGNED"?"success":"warning"}>{comparisonLabels[row.comparison_state??""]??"Review required"}</StatusBadge>{row.invoices?.map(invoice=><Link className="purchasing-invoice-link" key={invoice.id} href={`/workspace/purchases/invoices?${new URLSearchParams({organisation,purchase:invoice.id})}`}>{invoice.reference}</Link>)}</span>
 ]:type==="PO"?view==="REGISTER"?[
  doc(row),party(row),row.material_lines,status(row),receiving(row),money(row,row.amount),row.actor,<Link key="detail" className="inline-link" href={historicalSource(organisation,row)}>View PO materials</Link>
 ]:[doc(row),party(row),item(row),quantity(row.quantity),<span key="qty">{quantity(row.accepted)} accepted<small>{quantity(row.remaining)} outstanding</small></span>,<span key="price">{money(row,row.unit_price)}<small>{row.price_basis==="INCLUSIVE"?"Tax-inclusive entry":"Tax-exclusive entry"}</small></span>,<span key="terms">Discount {money(row,row.discount)}<small>Tax {money(row,row.tax)}</small></span>,money(row,row.amount),<span key="progress">{status(row)}<small>{receivingLabels[row.receiving_state??""]}</small></span>]:view==="REGISTER"?[
  doc(row),related(row),party(row),row.material_lines,status(row),row.actor,<Link key="detail" className="inline-link" href={historicalSource(organisation,row)}>View GRN materials</Link>
 ]:[doc(row),<span key="po">{related(row)}<small>{row.party} · {row.outlet}</small></span>,item(row),quantity(row.accepted),quantity(row.rejected),row.rejection_reason||"—",status(row),row.actor]
 }))} empty={report.total?"No rows on this page. Return to the first page.":"No permitted purchasing records match these filters."}/>;
}
