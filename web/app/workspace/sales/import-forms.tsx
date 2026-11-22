"use client";
import {SalesMenuMatches} from "./menu-matches";
import { useActionState, useState } from "react";
import Link from "next/link";
import { ArrowRight, Download } from "lucide-react";
import { referenceAmount } from "@/lib/reference-prices";
import { salesFormats, type SalesBatch, type SalesMappings } from "@/lib/sales-imports";
import { stageSales, postSales, cancelSales, downloadSalesSource } from "./actions";

export function SalesUpload({ organisationId, requestId, currency, initial, sourceCsv, channels }: { organisationId: string; requestId: string; currency: string; initial?: SalesBatch; sourceCsv?: string;channels:import("@/lib/channels").SalesChannel[] }) {
 const [state, action, pending] = useActionState(stageSales, {});
 const [csv, setCsv] = useState(sourceCsv ?? ""), [filename, setFilename] = useState(initial?.filename ?? "");
 const [sourceOrg, setSourceOrg] = useState(initial?.source_organisation_code ?? ""), [basis, setBasis] = useState(initial?.net_basis ?? "");
 const [maps, setMaps] = useState<SalesMappings>(initial?.mappings ?? { menu_items: {}, locations: {}, channels: {} });
 const [reading, setReading] = useState(false), [fileError, setFileError] = useState("");
 const [samplePending,setSamplePending]=useState(false),[sampleError,setSampleError]=useState("");
 async function downloadSample(){
  setSamplePending(true);setSampleError("");const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),30000);
  try{
   const response=await fetch(`/workspace/sales/sample?organisation=${encodeURIComponent(organisationId)}`,{cache:'no-store',signal:controller.signal});
   if(response.redirected){setSampleError('Your session has expired. Sign in again, then retry the download.');return;}
   if(!response.ok){const result=await response.json().catch(()=>null);setSampleError(typeof result?.error==='string'?result.error:'The sample could not be downloaded. Please try again shortly.');return;}
   if(!response.headers.get('Content-Type')?.startsWith('text/csv')){setSampleError('The sample could not be downloaded. Refresh the page and try again.');return;}
   const blob=await response.blob(),url=URL.createObjectURL(blob),anchor=document.createElement('a');
   anchor.href=url;anchor.download=response.headers.get('Content-Disposition')?.match(/filename="(ProfitPlate_training_sales_\d{4}-\d{2}-\d{2}\.csv)"/)?.[1]??'ProfitPlate_training_sales.csv';
   document.body.append(anchor);anchor.click();anchor.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);setSourceOrg('TRAINING');
  }catch{setSampleError('The sample could not be downloaded. Check your connection and try again.');}
  finally{clearTimeout(timeout);setSamplePending(false);}
 }
 return <section className="purchase-panel"><p className="eyebrow form-eyebrow">UPLOAD → VALIDATE → RECONCILE → RECORD</p><h2>Upload sales records</h2><p className="purchase-intro">Use the menu names in your POS export and save the Sales_Import sheet as CSV UTF-8. Up to 100 data rows and 128 KB per file. Standard PAID / NORMAL lines are supported first; combos, refunds and voids are flagged.</p>
  <div className="purchase-template-links"><a className="secondary-button purchase-template" href="/templates/sales-import.csv" download><Download size={15}/> Download sales template</a><button type="button" className="secondary-button purchase-template" onClick={downloadSample} disabled={samplePending} aria-busy={samplePending}><Download size={15}/>{samplePending?'Preparing sample...':'Download restaurant training sample'}</button></div>
  {sampleError&&<p role="alert" className="auth-alert">{sampleError}</p>}
  <p className="purchase-intro">The training sample uses an existing menu name, outlet and configured sales channel, with a fictional unit price of {currency} 6,000 and zero tax. Use a training restaurant: saving it creates sales and may consume stock.</p><details className="purchase-mappings"><summary>Using an earlier code-based export?</summary><p>The Menu_Code format still works. Names are recommended; duplicate or unmatched names need your selection before saving.</p><a href="/templates/sales-import-codes.csv" download>Download code-based CSV template</a></details>
  <form action={action} onReset={event => event.preventDefault()} className="setup-form" aria-busy={pending || reading}><input type="hidden" name="organisation_id" value={organisationId}/><input type="hidden" name="request_id" value={requestId}/><input type="hidden" name="csv_text" value={csv}/><input type="hidden" name="filename" value={filename}/><input type="hidden" name="currency" value={currency}/><input type="hidden" name="mappings" value={JSON.stringify(maps)}/>
   <fieldset disabled={pending || reading} className="purchase-fieldset"><div className="setup-field"><label htmlFor="sales-file">Sales CSV</label><input id="sales-file" type="file" accept=".csv,text/csv" onChange={async event => {
    const file = event.target.files?.[0]; setCsv(""); setFilename(""); setFileError(""); if (!file) return;
    if (file.size > 131072 || file.name.length > 180) { setFileError("Use a CSV under 128 KB with a filename of up to 180 characters."); return; }
    setReading(true);
    try { const value = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(await file.arrayBuffer()); if (value.includes("\0")) throw new Error(); setCsv(value); setFilename(file.name); }
    catch { setFileError("Export the sales worksheet as CSV UTF-8 and choose it again."); } finally { setReading(false); }
   }}/><small>{reading ? "Reading…" : filename ? `${filename} is selected.` : "CSV only; direct XLSX workbook uploads are not supported in this delivery."}</small></div>
   <div className="setup-field-grid"><div className="setup-field"><label htmlFor="sales-source-org">Source organisation code</label><input id="sales-source-org" name="source_org" maxLength={40} required value={sourceOrg} onChange={event => setSourceOrg(event.target.value)} placeholder="e.g. ORG001"/><small>Every uploaded Organisation_Code must match. This alias maps to the selected business; it does not choose a different tenant.</small></div><div className="setup-field"><label htmlFor="sales-net-basis">Sales source tax format</label><select id="sales-net-basis" name="net_basis" value={basis} onChange={event => setBasis(event.target.value)} required><option value="">Choose the source format</option>{salesFormats.map(([code, label]) => <option key={code} value={code}>{label}</option>)}</select></div></div>
   <p className="purchase-help">{!basis ? "Choose the source tax format to validate the receipt arithmetic." : basis === "GROSS_INCLUSIVE" ? "Net_Sales = Gross_Sales − Discount − Tax. Customer total = Net_Sales + Tax." : basis === "INCLUSIVE" ? "Net_Sales = Gross_Sales − Discount. Net revenue excludes the declared Tax within Net_Sales." : "Net_Sales = Gross_Sales − Discount. Customer total = Net_Sales + Tax."} All money fields are whole-line amounts, not unit prices or percentages; enter explicit 0 values when absent.</p>
   <p className="purchase-help">All source amounts must be in <strong>{currency}</strong>; the worksheet has no currency column and no conversion is inferred. The review resolves and saves the menu version effective on each sale date. Historical inactive menus/locations are flagged for your review. Keep Source_System, Transaction_Ref and Line_Ref stable across repeated imports.</p>
   {initial && ([['locations','Location_Code','location'],['channels','Channel_Code','channel']] as const).map(([type, column, title]) => {
    const codes = [...new Set(initial.report.rows.map(row => row.source[column]).filter(Boolean))];
    return codes.length ? <details key={type} className="purchase-mappings"><summary>Map source {title} codes ({codes.length})</summary><p>Leave blank to use matching business codes. No menu items or locations are created automatically.</p>{codes.map(code => <div className="setup-field" key={code}><label htmlFor={`sales-${type}-${encodeURIComponent(code)}`}>Map {title} {code}</label>{type === "channels" ? <select id={`sales-${type}-${encodeURIComponent(code)}`} value={maps[type]?.[code] ?? ""} onChange={event => setMaps(previous => ({ ...previous, [type]: { ...previous[type], [code]: event.target.value } }))}><option value="">Use source value</option>{channels.filter(c=>c.is_active).map(c=><option key={c.code} value={c.code}>{c.name}</option>)}</select> : <input id={`sales-${type}-${encodeURIComponent(code)}`} value={maps[type]?.[code] ?? ""} maxLength={40} onChange={event => setMaps(previous => ({ ...previous, [type]: { ...previous[type], [code]: event.target.value } }))} placeholder="Existing business code"/>}</div>)}</details> : null;
   })}{initial&&<SalesMenuMatches org={organisationId} batch={initial} maps={maps} onChange={setMaps} disabled={pending||reading}/>}</fieldset>{fileError && <p role="alert" className="auth-alert">{fileError}</p>}{state.error && <p role="alert" className="auth-alert">{state.error}</p>}
   <div className="catalogue-editor-actions"><Link className="secondary-button" href={`/workspace/sales?organisation=${organisationId}`}>Back to sales</Link><button type="submit" className="auth-button" disabled={pending || reading || !csv}>{pending ? "Validating…" : "Validate sales file"}<ArrowRight size={15}/></button></div>
  </form>
 </section>;
}
export function SalesApproval({ organisationId, batch }: { organisationId: string; batch: SalesBatch }) {
 const [state, action, pending] = useActionState(postSales, {}), [controls, setControls] = useState<Record<string, string>>({});
 return <section className="purchase-panel"><h2>Reconcile and save sales</h2><p className="purchase-intro">Confirm the matched menus, recipes and stock centres, then enter each new receipt total. Confirmed POS-name matches are remembered when these sales are saved. Missing reference costs do not prevent recording sales.</p><form action={action} onReset={event => event.preventDefault()} className="setup-form" aria-busy={pending}><input type="hidden" name="organisation_id" value={organisationId}/><input type="hidden" name="batch_id" value={batch.id}/><input type="hidden" name="controls" value={JSON.stringify(controls)}/><fieldset disabled={pending} className="purchase-fieldset">
  {batch.report.receipts.map(receipt => <article key={receipt.key} className="invoice-control"><h3>{receipt.transaction_ref} · {receipt.location_name}</h3><p>{receipt.source_system} · {receipt.sale_date} · {receipt.lines} uploaded lines</p><p>Calculated customer total: <strong>{referenceAmount(receipt.total, receipt.currency_code)}</strong></p>{receipt.duplicate ? <span className="purchase-badge">Already recorded — will skip</span> : <div className="setup-field"><label htmlFor={`receipt-${receipt.key}`}>Customer total for {receipt.transaction_ref} ({receipt.location_name})</label><input id={`receipt-${receipt.key}`} inputMode="decimal" required maxLength={39} value={controls[receipt.key] ?? ""} onChange={event => setControls(previous => ({ ...previous, [receipt.key]: event.target.value }))} placeholder="Total from source receipt"/></div>}</article>)}
  <label className="catalogue-checkbox"><input type="checkbox" name="confirmed" value="yes" required/> I checked the currency, tax format, dated menu versions and source receipt totals. Save these sales.</label></fieldset>{state.error && <p role="alert" className="auth-alert">{state.error}</p>}<button className="auth-button" type="submit" disabled={pending}>{pending ? "Saving sales…" : "Save reviewed sales"}<ArrowRight size={15}/></button></form></section>;
}
export function CancelSalesImport({ organisationId, batchId }: { organisationId: string; batchId: string }) {
 const [state, action, pending] = useActionState(cancelSales, {});
 return <form action={action}><input type="hidden" name="organisation_id" value={organisationId}/><input type="hidden" name="batch_id" value={batchId}/>{state.error && <p role="alert" className="auth-alert">{state.error}</p>}<button className="secondary-button" type="submit" disabled={pending}>{pending ? "Cancelling…" : "Cancel unposted sales import"}</button></form>;
}
export function DownloadSalesSource({ organisationId, batchId }: { organisationId: string; batchId: string }) {
 const [pending, setPending] = useState(false), [error, setError] = useState("");
 return <div><button type="button" className="secondary-button" disabled={pending} onClick={async () => {
  setPending(true); setError("");
  try { const result = await downloadSalesSource(organisationId, batchId); if ("error" in result) { setError(result.error); return; }
   const url = URL.createObjectURL(new Blob([result.csv], { type: "text/csv;charset=utf-8" })), anchor = document.createElement("a");
   anchor.href = url; anchor.download = result.filename; document.body.append(anchor); anchor.click(); anchor.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000);
  } catch { setError("The source file could not be downloaded. Please try again."); } finally { setPending(false); }
 }}><Download size={14}/>{pending ? "Retrieving…" : "Download original sales CSV"}</button>{error && <p role="alert" className="field-error">{error}</p>}</div>;
}
