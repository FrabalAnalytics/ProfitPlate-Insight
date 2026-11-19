import {DataTable,StatusBadge} from "@/app/components/data-table";
import type { Metadata } from "next";
import { randomUUID } from "node:crypto";
import Link from "next/link";
import { redirect } from "next/navigation";
import { ArrowLeft, ArrowRight, Upload } from "lucide-react";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { isUuid } from "@/lib/catalogue";
import { displayQuantity } from "@/lib/recipes";
import { referenceAmount } from "@/lib/reference-prices";
import { purchaseStateLabel, type PurchaseBatch, type PurchaseHistory } from "@/lib/purchase-imports";
import { TransactionTable } from "@/app/components/transaction-table";
import { WorkspaceShell } from "@/app/components/workspace-shell";
import { PurchaseUpload, PurchaseApproval, CancelPurchaseImport, DownloadPurchaseSource } from "./import-forms";
import "../materials/catalogue.css";
import "./purchases.css";

export const metadata: Metadata = { title: "Purchase imports | ProfitPlate Insight" };
export const instant = false;
type Params = { organisation?: string; batch?: string; new?: string; remap?: string; page?: string; result?: string };

export default async function PurchasesPage({ searchParams }: { searchParams: Promise<Params> }) {
 const user = await requireUser();
 const access = await getPlatformAccess();
 if (access !== "member") redirect(workspacePath(access));
 const params = await searchParams;
 const supabase = await createClient();
 const { data: orgs, error: orgError } = await supabase.from("organisations").select("id,name,currency_code").order("name");
 if (!orgError && !orgs?.length) redirect("/onboarding");
 const org = params.organisation ? orgs?.find(entry => entry.id === params.organisation) : orgs?.[0];
 if (!org || orgError) return <WorkspaceShell email={user.email}><h1 className="workspace-title">This business is unavailable.</h1><Link href="/workspace" className="auth-back">Return to workspace</Link></WorkspaceShell>;
 const shell = { email: user.email, restaurantName: org.name, organisationId: org.id, sectionLabel: "Purchase imports" };
 const query = (values: Record<string, string> = {}) => `/workspace/purchases?${new URLSearchParams({ organisation: org.id, ...values })}`;
 const { data: permission, error: permissionError } = await supabase.rpc("purchase_import_access", { p_organisation_id: org.id });
 if (permissionError) return <WorkspaceShell {...shell}><h1 className="workspace-title">Purchase imports are not available yet.</h1><p className="workspace-description">The platform administrator may need to finish the purchase-import update, or access is temporarily unavailable.</p><Link className="auth-back" href={`/workspace?organisation=${org.id}`}>Return to business setup</Link></WorkspaceShell>;
 if (permission?.read !== true) return <WorkspaceShell {...shell}><h1 className="workspace-title">Business-wide purchase access is restricted.</h1><p className="workspace-description">An organisation-wide administrator, procurement manager, CEO or finance member can view these purchase records.</p></WorkspaceShell>;
 const canEdit = permission.write === true;
 const page = Math.min(100000, Math.max(1, Number.parseInt(params.page ?? "1", 10) || 1));
 let batch: PurchaseBatch | null = null, batchError = false;
 if (params.batch) {
  if (isUuid(params.batch)) {
   const result = await supabase.rpc("get_purchase_import", { p_organisation_id: org.id, p_batch_id: params.batch });
   batch = result.data as PurchaseBatch | null; batchError = !!result.error || !batch;
  } else batchError = true;
 }
 const [historyResult, locationsResult] = await Promise.all([
  supabase.rpc("purchase_import_history", { p_organisation_id: org.id, p_page: page }),
  supabase.from("locations").select("id,name,code,is_active").eq("organisation_id", org.id).order("name"),
 ]);
 const history = historyResult.data as PurchaseHistory | null;
 let sourceCsv: string | undefined;
 const remapping = canEdit && params.remap === "1" && batch && batch.state !== "POSTED";
 if (remapping) {
  const source = await supabase.rpc("purchase_import_source", { p_organisation_id: org.id, p_batch_id: batch!.id });
  if (!source.error) sourceCsv = source.data?.csv;
 }
 return <WorkspaceShell {...shell}>
  <Link className="catalogue-back" href={`/workspace?organisation=${org.id}`}><ArrowLeft size={14}/> Back to workspace</Link>
  <div className="page-heading-row"><div><p className="eyebrow form-eyebrow">PURCHASING / IMPORTS</p><h1 className="workspace-title">Purchase imports</h1></div>{canEdit && params.new !== "1" && !remapping && <Link href={query({ new: "1" })} className="auth-button catalogue-add"><Upload size={16}/> Import purchases</Link>}</div>
  <nav className="invoice-nav" aria-label="Purchase entry options"><Link className="secondary-button" href={`/workspace/purchases/invoices?organisation=${org.id}`}>Supplier invoices</Link><Link className="secondary-button" href={`/workspace/purchases/orders?organisation=${org.id}`}>Purchase Orders</Link>{canEdit && <Link className="secondary-button" href={`/workspace/purchases/invoices?organisation=${org.id}&new=1`}>Record supplier invoice</Link>}</nav>
  <p className="purchase-help">Recording an invoice does not post stock or change reference prices. Purchase-based recipe costing will follow the approved costing policy.</p>
  {!canEdit && <p className="catalogue-readonly">Procurement handles purchase entry and imports. Finance can review records and approve or reject submitted corrections.</p>}
  {(params.new === "1" || remapping) && canEdit && <PurchaseUpload key={remapping ? batch!.id : "new"} organisationId={org.id} requestId={randomUUID()} initial={remapping && sourceCsv !== undefined ? batch! : undefined} sourceCsv={sourceCsv}/>}
  {remapping && sourceCsv === undefined && <p role="alert" className="auth-alert">We could not retrieve the original CSV. Choose the corrected file again.</p>}
  {params.new === "1" && canEdit && <section className="purchase-code-help"><h2>Use your existing business codes</h2><p>Reporting currency: <strong>{org.currency_code}</strong>. Location codes:</p>{locationsResult.error ? <p>Location codes are temporarily unavailable.</p> : <DataTable label="Purchase import location codes" columns={[{label:"Location code"},{label:"Location"}]} rows={(locationsResult.data??[]).filter(location=>location.is_active).map(location=>({id:location.id,cells:[location.code,location.name]}))}/>}<div><Link className="record-edit" href={`/workspace/materials?organisation=${org.id}`}>Find material codes <ArrowRight size={13}/></Link><Link className="record-edit" href={`/workspace/materials?organisation=${org.id}&tab=suppliers`}>Find supplier codes <ArrowRight size={13}/></Link></div><p>One invoice must belong to one supplier, location and date. Use RECEIVED status and explicit 0 values for absent discounts/tax. Orders, free lines, returns and credit notes are not supported in this first import.</p></section>}
  {batchError && <p className="auth-alert" role="alert">This import is unavailable in this business.</p>}
  {params.result === "recorded" && batch?.state === "POSTED" && <p className="welcome-message" role="status">Purchase import recorded. Duplicate source lines were skipped; existing purchases were not overwritten.</p>}
  {params.result === "review" && batch && <p className="auth-alert" role="alert">Purchase records or catalogue details changed. Review these updated findings before saving again.</p>}
  {batch && <>
   <section className="purchase-panel"><div className="purchase-batch-heading"><div><p className="eyebrow form-eyebrow">{purchaseStateLabel(batch.state)}</p><h2>{batch.entry_method === "MANUAL" ? "Supplier invoice review" : batch.filename}</h2><p className="purchase-intro">Unit prices {batch.price_basis === "EXCLUSIVE" ? "exclude" : "include"} tax.</p></div><DownloadPurchaseSource organisationId={org.id} batchId={batch.id} generated={batch.entry_method === "MANUAL"}/></div>
    {batch.state === "POSTED" && <p className="purchase-help">These are the original source values. See Supplier invoices for current figures and Finance-approved corrections.</p>}<div className="purchase-counts"><article><strong>{batch.report.ready}</strong><span>{batch.state === "POSTED" ? "New lines recorded" : "Ready rows"}</span></article><article><strong>{batch.report.duplicates}</strong><span>Duplicate lines · skipped</span></article><article><strong>{batch.report.rejected}</strong><span>Rows needing correction</span></article></div>
    {batch.report.file_error && <p className="auth-alert" role="alert">{batch.report.file_error}</p>}
    {batch.state === "INVALID" && <p className="purchase-help">No purchases were saved from this import. Correct every finding, then validate a new attempt. Accepted rows are not partially recorded.</p>}
    <TransactionTable key={batch.id} label="Purchase import lines" amountLabel="Invoice total" rows={batch.report.rows.map(row => ({
      id: String(row.row), date: row.source.Purchase_Date, reference: `${row.source.Purchase_Ref} / ${row.source.Line_Ref}`,
      item: row.prepared?.item_name ?? row.source.Item_Code,
      context: row.prepared ? `${row.prepared.supplier_name} · ${row.prepared.location_name}` : `${row.source.Supplier_Code} · ${row.source.Location_Code}`,
      quantity: `${row.source.Quantity} ${row.source.Purchase_UOM}`,
      amount: row.prepared ? referenceAmount(row.prepared.invoice_amount,row.prepared.currency_code) : "Unresolved",
      status: row.state === "READY" ? batch.state === "POSTED" ? "Recorded" : "Ready" : row.state === "DUPLICATE" ? "Already recorded" : "Needs correction",
      attention: row.state === "REJECTED",
      notices: row.findings.length ? <>{row.findings.map((finding,index) => <p key={index} className="field-error">{finding}</p>)}</> : null,
      details: <><p>Row {row.row} · Source {row.source.Source_System} · Material {row.source.Item_Code}</p>{row.prepared && <><p>Converted quantity: {displayQuantity(row.prepared.base_quantity)} {row.prepared.base_unit_code}</p><dl><div><dt>After discount, excluding tax</dt><dd>{referenceAmount(row.prepared.net_amount,row.prepared.currency_code)}</dd></div><div><dt>Source tax</dt><dd>{referenceAmount(row.prepared.tax,row.prepared.currency_code)}</dd></div><div><dt>Invoice line total</dt><dd>{referenceAmount(row.prepared.invoice_amount,row.prepared.currency_code)}</dd></div></dl></>}</>,
    }))}/>
    {batch.state === "POSTED" && <div className="purchase-recorded-totals"><h3>Reconciled supplier invoices</h3><DataTable label="Reconciled supplier invoice totals" columns={[{label:"Invoice number"},{label:"Supplier"},{label:"Total",numeric:true},{label:"Recording status"}]} rows={batch.report.documents.map(doc=>({id:doc.key,cells:[doc.purchase_ref,doc.supplier_name,referenceAmount(doc.total,doc.currency_code),doc.duplicate?"Already recorded lines":"Recorded"]}))}/></div>}
    {canEdit && batch.state !== "POSTED" && batch.state !== "CANCELLED" && <div className="purchase-batch-actions"><Link className="secondary-button" href={query({ batch: batch.id, remap: "1" })}>Correct file or map codes</Link><CancelPurchaseImport organisationId={org.id} batchId={batch.id}/></div>}
    <p className="purchase-source-hash">Source SHA-256: {batch.source_hash}</p>
   </section>
   {canEdit && batch.state === "REVIEW" && batch.report.can_post && !remapping && <PurchaseApproval key={JSON.stringify(batch.report)} organisationId={org.id} batch={batch}/>}
  </>}
  <section className="purchase-history"><div className="section-heading"><h2>Import history</h2><span>Private to your business</span></div>{historyResult.error || !history ? <p className="auth-alert" role="alert">We could not load import history. Please refresh and try again.</p> : history.batches.length ? <><DataTable label="Purchase import history" columns={[{label:"Source file"},{label:"Created"},{label:"Ready",numeric:true},{label:"Duplicates",numeric:true},{label:"Needs correction",numeric:true},{label:"Status"},{label:"Action"}]} rows={history.batches.map(entry=>({id:entry.id,cells:[entry.filename,String(entry.created_at).slice(0,10),entry.ready,entry.duplicates,entry.rejected,<StatusBadge key="state" tone={entry.state==="POSTED"?"success":entry.rejected>0?"warning":"neutral"}>{purchaseStateLabel(entry.state)}</StatusBadge>,<Link key="action" className="inline-link" href={query({batch:entry.id})} aria-label={`Review import ${entry.filename}`}>Review <ArrowRight size={14}/></Link>]}))}/>{(history.total > 25 || page > 1) && <div className="catalogue-pagination"><p>{history.total} imports · Page {page}</p><div>{page > 1 && <Link href={query({ page: String(page - 1) })}>Previous</Link>}{page * 25 < history.total && <Link href={query({ page: String(page + 1) })}>Next <ArrowRight size={14}/></Link>}</div></div>}</> : <div className="catalogue-empty"><h3>Your purchase history starts here.</h3><p>Upload and review your first supplier invoice file. Validation attempts are retained, including files needing correction.</p></div>}</section>
 </WorkspaceShell>;
}
