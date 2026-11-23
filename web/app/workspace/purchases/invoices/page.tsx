import Link from "next/link";
import {DataTable,StatusBadge} from "@/app/components/data-table";
import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { isUuid } from "@/lib/catalogue";
import { referenceAmount } from "@/lib/reference-prices";
import { displayQuantity } from "@/lib/recipes";
import type { InvoiceDetail, InvoiceList, InvoiceOptions, InvoiceValue, OrderChoice } from "@/lib/procurement";
import { WorkspaceShell } from "@/app/components/workspace-shell";
import { InvoiceForm, CorrectionDecision } from "../invoice-form";
import { invoiceMatchingLabels } from "@/lib/procurement";
import { InvoiceMatchingPanel } from "../invoice-matching-panel";
import "../../materials/catalogue.css";
import "../purchases.css";

export const metadata: Metadata = { title: "Supplier invoices | ProfitPlate Insights" };
export const instant = false;
type Params = { organisation?: string; purchase?: string; new?: string; correct?: string; page?: string; result?: string; po?: string; po_search?: string };
function InvoiceSummary({ value, title }: { value: InvoiceValue; title: string }) {
 const discount=value.lines.some(l=>Number(l.line_discount)!==0),tax=value.lines.some(l=>Number(l.tax)!==0);
 return <section className="invoice-summary"><h3>{title}</h3><div className="invoice-facts"><div><span>Invoice</span><strong>{value.header.reference}</strong></div><div><span>Supplier</span><strong>{value.header.supplier_name}</strong></div><div><span>Date / outlet</span><strong>{value.header.date}</strong><small>{value.header.location_name}</small></div><div><span>Total</span><strong>{referenceAmount(value.header.total,value.header.currency)}</strong>{value.voided&&<StatusBadge tone="danger">Voided</StatusBadge>}</div></div><DataTable label={`${title} lines`} columns={[{label:"Material"},{label:"Quantity",numeric:true},{label:"Unit price",numeric:true},...(discount?[{label:"Discount",numeric:true}]:[]),...(tax?[{label:"Tax",numeric:true}]:[]),{label:"Line total",numeric:true}]} rows={value.lines.map((line,index)=>({id:String(index),cells:[line.item_name,`${displayQuantity(line.quantity)} ${line.unit_code}`,referenceAmount(line.unit_price,value.header.currency),...(discount?[referenceAmount(line.line_discount,value.header.currency)]:[]),...(tax?[referenceAmount(line.tax,value.header.currency)]:[]),referenceAmount(line.invoice_amount,value.header.currency)]}))}/></section>;
}
export default async function InvoicesPage({ searchParams }: { searchParams: Promise<Params> }) {
 const user = await requireUser(), role = await getPlatformAccess();if (role !== "member") redirect(workspacePath(role));
 const params = await searchParams, client = await createClient();
 const orgs = await client.from("organisations").select("id,name,currency_code,time_zone").order("name");
 const org = params.organisation ? orgs.data?.find(item => item.id === params.organisation) : orgs.data?.[0];
 if (!org) return <WorkspaceShell email={user.email}><h1 className="workspace-title">This business is unavailable.</h1><Link href="/workspace">Return to workspace</Link></WorkspaceShell>;
 const shell = { email: user.email, restaurantName: org.name, organisationId: org.id, sectionLabel: "Supplier invoices" };
 const permission = await client.rpc("purchase_import_access", { p_organisation_id: org.id });
 const href = (extra: Record<string, string> = {}) => `/workspace/purchases/invoices?${new URLSearchParams({ organisation: org.id, ...extra })}`;
 const unavailable = (message: string) => <WorkspaceShell {...shell}><h1 className="workspace-title">Supplier invoices</h1><p role="alert" className="auth-alert">{message}</p><Link href={`/workspace/purchases?organisation=${org.id}`} className="secondary-button">Return to purchases</Link></WorkspaceShell>;
 if (permission.error || permission.data?.read !== true) return unavailable("Supplier invoice access is restricted or temporarily unavailable.");
 const failure = (code?: string, message?: string) => code === "PGRST202" ? "Supplier invoice entry needs migration 016. Ask your administrator to complete setup." : code === "22023" ? message ?? "Check your selection." : "Invoices could not be loaded. Check your access and try again.";
 let detail: InvoiceDetail | null = null;
 if (params.purchase) {
  if (!isUuid(params.purchase)) return unavailable("Choose an available invoice.");
  const result = await client.rpc("purchase_invoice_detail", { p_organisation_id: org.id, p_purchase_id: params.purchase });
  if (result.error || !result.data) return unavailable(failure(result.error?.code, result.error?.message));
  detail = result.data as InvoiceDetail;
 }
 const canWrite = permission.data.write === true, canApprove = permission.data.approve_corrections === true;
 const formatTime = (at: string) => new Intl.DateTimeFormat("en-GB", { timeZone: org.time_zone, dateStyle: "medium", timeStyle: "medium" }).format(new Date(at));
 const pending = detail?.corrections.some(change => change.state === "PENDING");
 let options: InvoiceOptions | null = null;
 if (canWrite && (params.new === "1" || (params.correct === "1" && detail && !pending))) {
  const [suppliers, locations, items, units, orders] = await Promise.all([
   client.from("suppliers").select("id,name").eq("organisation_id", org.id).eq("is_active", true).order("name").limit(1000),
   client.from("locations").select("id,name").eq("organisation_id", org.id).eq("is_active", true).order("name").limit(1000),
   client.from("items").select("id,name,base_uom_id").eq("organisation_id", org.id).eq("is_active", true).order("name").limit(1000),
   client.from("units_of_measure").select("id,name,code").eq("organisation_id", org.id).order("name").limit(1000),
   client.rpc("purchase_order_choices", { p_organisation_id: org.id, p_search: params.po_search ?? "", p_selected: params.po && isUuid(params.po) ? params.po : null }),
  ]);
  if ([suppliers, locations, items, units].some(result => result.error)) return unavailable("Supplier, material or unit details could not be loaded. Refresh before entering an invoice.");
  if (orders.error) return unavailable(orders.error.code === "PGRST202" ? "PO-backed and direct invoice entry need migrations 018 and 019 after 017." : orders.error.code === "22023" ? orders.error.message : "PO choices could not be loaded. Refresh before entering an invoice.");
  options = { suppliers: suppliers.data ?? [], locations: locations.data ?? [], items: items.data ?? [], units: units.data ?? [], orders: orders.data as OrderChoice[] };
 }
 let list: InvoiceList | null = null;const page = Number(params.page ?? "1");
 if (!detail && !options) {
  if (!Number.isInteger(page) || page < 1 || page > 100000) return unavailable("Choose a valid invoice page.");
  const result = await client.rpc("purchase_invoice_list", { p_organisation_id: org.id, p_page: page });
  if (result.error) return unavailable(failure(result.error.code, result.error.message));list = result.data as InvoiceList;
 }
 return <WorkspaceShell {...shell}><div className="page-heading-row"><div><p className="eyebrow form-eyebrow">SUPPLIER INVOICES</p><h1 className="workspace-title">{detail ? "Supplier invoice" : "Supplier invoices"}</h1></div><div className="invoice-nav">{canWrite&&<Link className="secondary-button" href={`/workspace/purchases?organisation=${org.id}`}>Purchase imports</Link>}{detail && <Link className="secondary-button" href={href()}>All supplier invoices</Link>}{canWrite && params.new !== "1" && !detail && <Link className="auth-button catalogue-add" href={href({ new: "1" })}>Record supplier invoice</Link>}</div></div>
  <nav className="invoice-nav" aria-label="Procurement workflows"><Link className="secondary-button" href={`/workspace/purchases/orders?organisation=${org.id}`}>Purchase Orders</Link></nav>
  <p className="purchase-help">{detail?"Review the bill, delivery match and any exceptions below.":"Supplier bills and their review status."}</p>
  {params.result === "requested" && pending && <p role="status" className="welcome-message">Correction submitted to Finance. Current figures stay unchanged until approval.</p>}
  {params.result === "decided" && <p role="status" className="welcome-message">Finance decision saved. Original invoice evidence is preserved.</p>}
  {options && !detail && <form method="get" className="purchase-panel procurement-no-print"><input type="hidden" name="organisation" value={org.id}/><input type="hidden" name="new" value="1"/><div className="setup-field"><label htmlFor="invoice-po-search">Find a PO by number or supplier before entering invoice figures</label><input id="invoice-po-search" name="po_search" maxLength={100} defaultValue={params.po_search ?? ""}/></div><button className="secondary-button">Find POs</button><p className="purchase-help">Up to 50 matching issued POs are offered. Search a specific PO number to find an older order.</p></form>}
  {options && <InvoiceForm organisation={org.id} request={crypto.randomUUID()} options={options} current={detail?.current} purchase={detail ? params.purchase : undefined} currency={org.currency_code} initialOrderId={params.po}/>}
  {detail && <><section className="purchase-panel invoice-current"><InvoiceSummary title="Current recorded invoice" value={detail.current}/><div className="invoice-nav">{canWrite && !pending && params.correct !== "1" && <Link className="secondary-button" href={href({ purchase: params.purchase!, correct: "1" })}>Request correction</Link>}{pending && <StatusBadge tone="warning">Correction awaiting Finance approval</StatusBadge>}</div></section>
   <InvoiceMatchingPanel organisation={org.id} purchase={params.purchase!} invoice={detail.current} canWrite={canWrite} canReview={canApprove} timeZone={org.time_zone} search={params.po_search}/>
   {detail.corrections.some(c=>c.state==="PENDING")&&<section className="purchase-panel"><h2>Correction awaiting review</h2>{detail.corrections.filter(c=>c.state==="PENDING").map(change=><article key={change.id} className="invoice-correction"><h3>{change.kind==="VOID"?"Void request":"Replacement invoice request"}</h3><p className="invoice-note">{change.reason}</p><small>Requested {formatTime(change.created_at)} / {change.created_label}</small><div className="invoice-comparison"><InvoiceSummary title="Before this request" value={change.before_value}/><InvoiceSummary title="Proposed values" value={change.proposal}/></div>{canApprove?<CorrectionDecision organisation={org.id} purchase={params.purchase!} correction={change.id}/>:<p className="purchase-help">Finance will review this correction.</p>}</article>)}</section>}
   <details className="purchase-panel invoice-audit"><summary>Source &amp; correction history ({detail.corrections.length})</summary><Link className="record-edit" href={`/workspace/purchases?organisation=${org.id}&batch=${detail.batch_id}`}>Review original source</Link><p className="purchase-help">{detail.current.revision} approved corrections. Original evidence is retained.</p>{!detail.corrections.length&&<p>No corrections requested.</p>}{detail.corrections.filter(c=>c.state!=="PENDING").map(change=><details key={change.id} className="invoice-correction"><summary>{change.kind==="VOID"?"Void request":"Replacement invoice request"} / {change.state.toLowerCase()} / {formatTime(change.created_at)}</summary><p className="invoice-note">Reason: {change.reason}</p><small>Requested by {change.created_label}</small><div className="invoice-comparison"><InvoiceSummary title="Before this request" value={change.before_value}/><InvoiceSummary title="Proposed values" value={change.proposal}/></div>{change.decided_at&&<p className="invoice-note">Finance decision: {change.state.toLowerCase()} / {formatTime(change.decided_at)} / {change.decided_label}{change.decision_note?` / ${change.decision_note}`:""}</p>}</details>)}</details></>}
  {list && <section className="purchase-panel"><p>{list.total} invoices · page {page}</p><DataTable label="Supplier invoice records" columns={[{label:"Invoice number"},{label:"Date"},{label:"Supplier"},{label:"Outlet"},{label:"Total",numeric:true},{label:"Review status"},{label:"Action"}]} rows={list.invoices.map(row=>({id:row.id,cells:[<Link key="reference" className="inline-link" href={href({purchase:row.id})}>{row.invoice.header.reference}</Link>,row.invoice.header.date,row.invoice.header.supplier_name,row.invoice.header.location_name,referenceAmount(row.invoice.header.total,row.invoice.header.currency),<div key="state" className="record-status-stack"><StatusBadge tone={row.invoice.voided?"danger":row.matching_status==="MATCHED"?"success":row.pending>0||row.matching_status==="NEEDS_FINANCE_REVIEW"?"warning":"neutral"}>{row.invoice.voided?"Voided":row.matching_status?invoiceMatchingLabels[row.matching_status]:"Recorded"}</StatusBadge>{row.pending>0&&<small>Awaiting Finance approval</small>}</div>,<Link key="action" className="inline-link" aria-label={`Open invoice ${row.invoice.header.reference}`} href={href({purchase:row.id})}>Open invoice</Link>]}))} empty="No invoices recorded on this page."/><nav className="invoice-nav" aria-label="Invoice pages">{page > 1 && <Link href={href({ page: String(page - 1) })}>Previous invoices</Link>}{page * 20 < list.total && <Link href={href({ page: String(page + 1) })}>Next invoices</Link>}</nav></section>}
 </WorkspaceShell>;
}
