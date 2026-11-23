import {restaurantChannels} from "@/lib/channels-server";
import {DataTable,StatusBadge} from "@/app/components/data-table";
import type { Metadata } from "next";
import { randomUUID } from "node:crypto";
import Link from "next/link";
import { redirect } from "next/navigation";
import { ArrowLeft, ArrowRight, Upload } from "lucide-react";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { isUuid } from "@/lib/catalogue";
import { displayQuantity, validBusinessDate } from "@/lib/recipes";
import { referenceAmount } from "@/lib/reference-prices";
import { displayPercent } from "@/lib/display";
import { salesFormats, salesStateLabel, type SalesBatch, type SalesHistory, type SalesSummary } from "@/lib/sales-imports";
import { TransactionTable } from "@/app/components/transaction-table";
import { WorkspaceShell } from "@/app/components/workspace-shell";
import { SalesUpload, SalesApproval, CancelSalesImport, DownloadSalesSource } from "./import-forms";
import {SalesMenuReview} from './menu-matches';
import "../materials/catalogue.css";
import "../purchases/purchases.css";
import "./sales.css";

export const metadata: Metadata = { title: "Sales imports & summary | ProfitPlate Insights" };
export const instant = false;
type Params = { organisation?: string; batch?: string; new?: string; remap?: string; page?: string; result?: string; from?: string; to?: string; location?: string };

export default async function SalesPage({ searchParams }: { searchParams: Promise<Params> }) {
 const user = await requireUser(); const access = await getPlatformAccess();
 if (access !== "member") redirect(workspacePath(access));
 const params = await searchParams, client = await createClient();
 const { data: orgs, error: orgError } = await client.from("organisations").select("id,name,currency_code,time_zone").order("name");
 if (!orgError && !orgs?.length) redirect("/onboarding");
 const org = params.organisation ? orgs?.find(entry => entry.id === params.organisation) : orgs?.[0];
 if (!org || orgError) return <WorkspaceShell email={user.email}><h1 className="workspace-title">This business is unavailable.</h1><Link className="auth-back" href="/workspace">Return to workspace</Link></WorkspaceShell>;
 const shell = { email: user.email, restaurantName: org.name, organisationId: org.id, sectionLabel: "Sales & summary", reportingContext:{from:params.from,to:params.to,location:params.location} };
 const query = (values: Record<string, string> = {}) => `/workspace/sales?${new URLSearchParams({ organisation: org.id, ...values })}`;
 const { data: permission, error: permissionError } = await client.rpc("sales_import_access", { p_organisation_id: org.id });
 if (permissionError) return <WorkspaceShell {...shell}><h1 className="workspace-title">Sales imports are not available yet.</h1><p className="workspace-description">The platform administrator may need to finish the sales update, or access is temporarily unavailable.</p><Link className="auth-back" href={`/workspace?organisation=${org.id}`}>Return to workspace</Link></WorkspaceShell>;
 if (permission?.read !== true) return <WorkspaceShell {...shell}><h1 className="workspace-title">Business-wide sales access is restricted.</h1><p className="workspace-description">An organisation-wide CEO, finance member or restaurant administrator can view sales records and summaries.</p></WorkspaceShell>;
 const canEdit = permission.write === true;
 const parts = new Intl.DateTimeFormat("en", { timeZone: org.time_zone, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(new Date());
 const today = ["year", "month", "day"].map(key => parts.find(part => part.type === key)?.value).join("-");
 const from = params.from ?? `${today.slice(0,7)}-01`, to = params.to ?? today, location = params.location ?? "";
 const page = Math.min(100000, Math.max(1, Number.parseInt(params.page ?? "1", 10) || 1));
 const [historyResult, locationsResult] = await Promise.all([
  client.rpc("sales_import_history", { p_organisation_id: org.id, p_page: page }),
  client.from("locations").select("id,name,code,is_active").eq("organisation_id", org.id).order("name"),
 ]);
 const consumption=await client.rpc("sales_stock_queue",{p_organisation_id:org.id,p_page:1,p_state:"PENDING"});
 const history = historyResult.data as SalesHistory | null;
 let batch: SalesBatch | null = null, batchError = false;
 if (params.batch) {
  if (isUuid(params.batch)) {
   const result = await client.rpc("get_sales_import", { p_organisation_id: org.id, p_batch_id: params.batch });
   batch = result.data as SalesBatch | null; batchError = !!result.error || !batch;
  } else batchError = true;
 }
 let sourceCsv: string | undefined;
 const channels=await restaurantChannels(org.id);
 const remapping = canEdit && params.remap === "1" && batch && batch.state !== "POSTED";
 if (remapping) { const result = await client.rpc("sales_import_source", { p_organisation_id: org.id, p_batch_id: batch!.id }); if (!result.error) sourceCsv = result.data?.csv; }
 let summary: SalesSummary | null = null, summaryError = "";
 if (!validBusinessDate(from) || !validBusinessDate(to) || (location && !isUuid(location))) summaryError = "Choose valid summary dates and a business location.";
 else {
  const result = await client.rpc("sales_period_summary", { p_organisation_id: org.id, p_from: from, p_to: to, p_location_id: location || null });
  if (result.error) summaryError = result.error.code === "22023" ? result.error.message : "Sales summary is unavailable. Check your access and try again.";
  else summary = result.data as SalesSummary;
 }
 const weekStart = new Date(`${today}T00:00:00Z`); weekStart.setUTCDate(weekStart.getUTCDate() - 6);
 const periods = [["Today", today], ["Last 7 days", weekStart.toISOString().slice(0,10)], ["This month", `${today.slice(0,7)}-01`]];
 const money = (value: string) => referenceAmount(value, summary?.currency_code ?? org.currency_code);
 return <WorkspaceShell {...shell}><Link className="secondary-button" href={`/workspace/inventory/sales-consumption?organisation=${org.id}`}>Sales stock consumption</Link>
  <Link className="catalogue-back" href={`/workspace?organisation=${org.id}`}><ArrowLeft size={14}/> Back to workspace</Link>
  {!!consumption.data?.pending&&<p role="status" className="auth-alert">{consumption.data.pending} imported sales lines need stock-consumption review. Sales figures are recorded; stock usage is incomplete until resolved.</p>}
  <div className="page-heading-row"><div><p className="eyebrow form-eyebrow">SALES REPORTING</p><h1 className="workspace-title">Sales & margin</h1><p className="workspace-description">Recorded revenue and estimated food margins.</p></div>{canEdit && params.new !== "1" && !remapping && <Link className="auth-button catalogue-add" href={query({ new: "1" })}><Upload size={16}/> Import sales</Link>}</div>
  <p className="purchase-help">Reference-price estimates · Sales-date standard consumption</p>
  {!canEdit && <p className="catalogue-readonly">You have read-only sales access. An organisation-wide restaurant administrator can upload and save sales.</p>}
  {(params.new === "1" || remapping) && canEdit && <SalesUpload key={remapping ? batch!.id : "new"} organisationId={org.id} requestId={randomUUID()} currency={org.currency_code} initial={remapping && sourceCsv !== undefined ? batch! : undefined} sourceCsv={sourceCsv} channels={channels?.channels??[]}/>}
  {remapping && sourceCsv === undefined && <p role="alert" className="auth-alert">The original CSV could not be retrieved. Choose the corrected file again.</p>}
  {params.new === "1" && canEdit && <section className="purchase-code-help"><h2>Use POS menu names and your outlet codes</h2><p>File currency: <strong>{org.currency_code}</strong>. Available location codes:</p>{locationsResult.error ? <p>Location codes are unavailable.</p> : <DataTable label="Sales import location codes" columns={[{label:"Location code"},{label:"Location"},{label:"Availability"}]} rows={(locationsResult.data??[]).map(entry=>({id:entry.id,cells:[entry.code,entry.name,entry.is_active?"Active":"Inactive, historical records only"]}))}/>}<Link className="record-edit" href={`/workspace/menus?organisation=${org.id}`}>Review selling menus, recipe links and stock centres <ArrowRight size={13}/></Link><p>One receipt must have a consistent date and channel. A menu version must be effective on the sale date. Missing ingredient prices do not prevent recording otherwise valid sales.</p></section>}
  {batchError && <p role="alert" className="auth-alert">This sales import is unavailable in this business.</p>}
  {params.result === "recorded" && batch?.state === "POSTED" && <p className="welcome-message" role="status">Sales import recorded. Unchanged duplicates were skipped; earlier source transactions were preserved.</p>}
  {params.result === "review" && batch && <p className="auth-alert" role="alert">Menu links, catalogue details or duplicate findings changed. Review the updated results before saving again.</p>}
  {batch && <><section className="purchase-panel"><div className="purchase-batch-heading"><div><p className="eyebrow form-eyebrow">{salesStateLabel(batch.state)}</p><h2>{batch.filename}</h2><p className="purchase-intro">Source organisation {batch.source_organisation_code} · {batch.currency_code} · {salesFormats.find(([code]) => code === batch.net_basis)?.[1]}</p></div><DownloadSalesSource organisationId={org.id} batchId={batch.id}/></div>
   <div className="purchase-counts"><article><strong>{batch.report.ready}</strong><span>{batch.state === "POSTED" ? "New sales lines recorded" : "Ready rows"}</span></article><article><strong>{batch.report.duplicates}</strong><span>Duplicate lines · skipped</span></article><article><strong>{batch.report.rejected}</strong><span>Rows needing correction</span></article></div>
   {batch.report.file_error && <p role="alert" className="auth-alert">{batch.report.file_error}</p>}{batch.state === "INVALID" && <p className="purchase-help">No sales were recorded from this attempt. Fix all findings and validate a corrected attempt; ready rows are not partially posted.</p>}
   <TransactionTable key={batch.id} label="Sales import lines" amountLabel="Net sales" rows={batch.report.rows.map(row => ({
     id: String(row.row), date: row.source.Sale_Date, reference: `${row.source.Transaction_Ref} / ${row.source.Line_Ref}`,
     item: row.prepared?.menu_name ?? row.source.Menu_Name ?? row.source.Menu_Code,
     context: row.prepared ? `${row.prepared.location_name} · Saved menu version ${row.prepared.menu_version}` : row.source.Location_Code,
     quantity: row.source.Quantity,
     amount: row.prepared ? referenceAmount(row.prepared.net_revenue, row.prepared.currency_code) : "Unresolved",
     status: row.state === "READY" ? batch.state === "POSTED" ? "Recorded" : "Ready" : row.state === "DUPLICATE" ? "Already recorded" : "Needs correction",
     attention: row.state === "REJECTED" || row.warnings.length > 0,
     notices: row.findings.length || row.warnings.length ? <>{row.findings.map((finding,index) => <p key={`f-${index}`} className="field-error">{finding}</p>)}{row.warnings.map((warning,index) => <p key={`w-${index}`} className="sales-warning">{warning}</p>)}</> : null,
     details: <><p>Row {row.row} · Source {row.source.Source_System} · Menu {row.source.Menu_Name??row.source.Menu_Code} · Channel {row.source.Channel_Code}</p>{row.prepared && <dl><div><dt>Matched selling menu</dt><dd>{row.prepared.menu_name} / version {row.prepared.menu_version}</dd></div><div><dt>Recipe</dt><dd>{row.prepared.recipe_name??'See saved menu version'}</dd></div><div><dt>Stock centre on sale date</dt><dd>{row.prepared.stock_centre??'Not assigned - stock consumption needs review'}</dd></div>{row.prepared.consumption_mode&&<div><dt>Stock method</dt><dd>{row.prepared.consumption_mode==='FINISHED'?'Stocked finished item':'Recipe ingredients and stocked preparations'}</dd></div>}{row.prepared.menu_match_basis&&<div><dt>Menu match</dt><dd>{row.prepared.menu_match_basis}</dd></div>}<div><dt>Recorded net revenue, excluding tax</dt><dd>{referenceAmount(row.prepared.net_revenue,row.prepared.currency_code)}</dd></div><div><dt>Source discount / tax</dt><dd>{referenceAmount(row.prepared.discount,row.prepared.currency_code)} / {referenceAmount(row.prepared.tax,row.prepared.currency_code)}</dd></div><div><dt>Customer total</dt><dd>{referenceAmount(row.prepared.customer_total,row.prepared.currency_code)}</dd></div></dl>}</>,
   }))}/>
   {canEdit && batch.state !== "POSTED" && batch.state !== "CANCELLED" && <div className="purchase-batch-actions"><Link className="secondary-button" href={query({ batch: batch.id, remap: "1" })}>Correct file or match menus</Link><CancelSalesImport organisationId={org.id} batchId={batch.id}/></div>}
  </section>{batch.state!=="POSTED"&&<SalesMenuReview key={`review-${JSON.stringify(batch.report)}`} rows={batch.report.rows}/>} {canEdit && batch.state === "REVIEW" && batch.report.can_post && !remapping && <SalesApproval key={JSON.stringify(batch.report)} organisationId={org.id} batch={batch}/>}</>}
  <section className="purchase-panel sales-summary" aria-labelledby="sales-summary-title"><h2 id="sales-summary-title">Sales & estimated food margin</h2><p className="purchase-intro">Choose a period and location. Up to 93 days and 1,000 recorded lines per preview.</p>
   <nav className="sales-period-shortcuts" aria-label="Sales period shortcuts">{periods.map(([label,start]) => <Link key={label} href={query({from:start,to:today, ...(location ? {location} : {})})} aria-current={from === start && to === today ? "true" : undefined}>{label}</Link>)}</nav>
   <details className="sales-filter-panel"><summary><span><strong>{from} to {to}</strong><small>{locationsResult.data?.find(entry => entry.id === location)?.name ?? (location ? "Selected location" : "All business locations")}</small></span><span className="sales-filter-action">Change filters</span></summary>
   <form key={`${from}-${to}-${location}`} method="get" className="sales-summary-filters"><input type="hidden" name="organisation" value={org.id}/><div className="setup-field"><label htmlFor="sales-from">Sales from</label><input id="sales-from" type="date" name="from" defaultValue={from} max={today} required/></div><div className="setup-field"><label htmlFor="sales-to">Sales through</label><input id="sales-to" type="date" name="to" defaultValue={to} max={today} required/></div><div className="setup-field"><label htmlFor="sales-location">Sales location</label><select id="sales-location" name="location" defaultValue={location}><option value="">All business locations</option>{locationsResult.data?.map(entry => <option key={entry.id} value={entry.id}>{entry.name}{!entry.is_active && " (inactive)"}</option>)}</select></div><button className="secondary-button" type="submit">Update sales summary</button></form></details>
   {summaryError ? <p role="alert" className="auth-alert">{summaryError}</p> : summary && summary.lines === 0 ? <p className="catalogue-readonly">No recorded sales in this period and location.</p> : summary && <>
    <div className="sales-summary-cards"><article><span>Recorded net sales</span><strong>{money(summary.net_revenue)}</strong><small>After source discounts, excluding declared tax</small></article><article><span>Estimated food cost</span><strong>{summary.estimated_food_cost === null ? "Incomplete" : money(summary.estimated_food_cost)}</strong><small>{summary.priced_lines} of {summary.lines} sales lines have complete costs</small></article><article className={summary.estimated_food_margin?.startsWith("-") ? "sales-negative" : ""}><span>Estimated food margin</span><strong>{summary.estimated_food_margin === null ? "Unavailable" : money(summary.estimated_food_margin)}</strong><small>{summary.food_margin_percent !== null ? `${displayPercent(summary.food_margin_percent)}% of recorded net sales` : summary.estimated_food_margin !== null ? "Percentage is undefined for zero net sales" : "Requires complete cost coverage"}</small></article></div>
    <p className="sales-period-facts">{summary.receipts} receipts · {displayQuantity(summary.quantity)} menu units sold · Source discounts {money(summary.discounts)} · Declared tax {money(summary.tax)} · Customer totals {money(summary.customer_total)}</p>
    {summary.missing_lines > 0 && <div className="sales-missing" role="status"><p>{summary.missing_lines} {summary.missing_lines === 1 ? "sales line needs" : "sales lines need"} usable costs. The full period food cost and margin are unavailable.</p>{summary.known_subtotal !== null && <p>Known cost subtotal: {money(summary.known_subtotal)} — a partial amount.</p>}<DataTable label="Sales missing cost findings" columns={[{label:"Menu item"},{label:"Sale date"},{label:"Reason"},{label:"Action"}]} rows={summary.missing.slice(0,10).map((entry,index)=>({id:`${entry.menu_version_id}-${entry.sale_date}-${index}`,cells:[entry.menu_name,entry.sale_date,entry.reason,<Link key="review" className="inline-link" aria-label={`Review costs for ${entry.menu_name} on ${entry.sale_date}`} href={`/workspace/menus?organisation=${org.id}&item=${entry.menu_item_id}&version=${entry.menu_version_id}&date=${entry.sale_date}`}>Review menu costs <ArrowRight size={13}/></Link>]}))}/>{summary.missing.length > 10 && <p>Showing the first 10 missing-cost findings. Narrow the period to review more.</p>}</div>}
    <div className="sales-menu-breakdown"><h3>By menu item</h3><DataTable label="Sales by menu item" columns={[{label:"Menu item"},{label:"Units sold",numeric:true},{label:"Cost coverage"},{label:"Recorded net sales",numeric:true},{label:"Estimated food cost",numeric:true},{label:"Estimated food margin",numeric:true}]} rows={summary.menus.map(menu=>({id:menu.menu_item_id,cells:[<span key="menu">{menu.name}<small>{menu.code}</small></span>,displayQuantity(menu.quantity),`${menu.priced_lines}/${menu.lines} lines costed`,money(menu.net_revenue),menu.estimated_food_cost===null?"Incomplete":money(menu.estimated_food_cost),menu.estimated_food_margin===null?"Unavailable":money(menu.estimated_food_margin)]}))}/></div>
    <details className="workspace-disclosure"><summary>About these estimates</summary><p>Revenue is retained from reconciled source sales, not replaced by today’s menu price. Costs use the menu version saved on each sale line and reference prices dated on or before its sale date. Later reference-price corrections can change this live estimate. It is not a finalised historical report or actual profit; unresolved stock-consumption exceptions, waste, labour, overheads, service charges and channel fees are not calculated here.</p></details>
   </>}
  </section>
  <section className="purchase-history"><div className="section-heading"><h2>Sales import history</h2><span>Private to your business</span></div>{historyResult.error || !history ? <p role="alert" className="auth-alert">We could not load sales import history.</p> : history.batches.length ? <><DataTable label="Sales import history" columns={[{label:"Source file"},{label:"Created"},{label:"Ready",numeric:true},{label:"Duplicates",numeric:true},{label:"Needs correction",numeric:true},{label:"Status"},{label:"Action"}]} rows={history.batches.map(entry=>({id:entry.id,cells:[entry.filename,String(entry.created_at).slice(0,10),entry.ready,entry.duplicates,entry.rejected,<StatusBadge key="state" tone={entry.state==="POSTED"?"success":entry.rejected>0?"warning":"neutral"}>{salesStateLabel(entry.state)}</StatusBadge>,<Link key="view" className="inline-link" href={query({batch:entry.id})} aria-label={`Review sales import ${entry.filename}`}>Review <ArrowRight size={14}/></Link>]}))}/>{(history.total > 25 || page > 1) && <div className="catalogue-pagination"><p>{history.total} imports · Page {page}</p><div>{page > 1 && <Link href={query({ page: String(page-1) })}>Previous</Link>}{page*25 < history.total && <Link href={query({ page: String(page+1) })}>Next <ArrowRight size={14}/></Link>}</div></div>}</> : <section className="catalogue-empty"><h3>Your sales history starts here.</h3><p>Upload a source sales file, review the dated menu links and reconcile receipt totals before saving.</p></section>}</section>
 </WorkspaceShell>;
}
