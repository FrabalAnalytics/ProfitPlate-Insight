"use client";

import { useActionState, useState } from "react";
import Link from "next/link";
import { ArrowRight, Download } from "lucide-react";
import { referenceAmount } from "@/lib/reference-prices";
import type { PurchaseBatch, PurchaseMappings } from "@/lib/purchase-imports";
import { generatedPurchaseCsv } from "@/lib/purchase-imports";
import { stagePurchases, postPurchases, cancelPurchases, downloadPurchaseSource, type PurchaseActionState } from "./actions";

const emptyMaps: PurchaseMappings = { items: {}, suppliers: {}, locations: {} };
export function PurchaseUpload({ organisationId, requestId, initial, sourceCsv }: {
 organisationId: string; requestId: string; initial?: PurchaseBatch; sourceCsv?: string;
}) {
 const [state, action, pending] = useActionState<PurchaseActionState, FormData>(stagePurchases, {});
 const [csv, setCsv] = useState(sourceCsv ?? "");
 const [filename, setFilename] = useState(initial?.filename ?? "");
 const [sourceOrg, setSourceOrg] = useState(initial?.source_organisation_code ?? "");
 const [basis, setBasis] = useState(initial?.price_basis ?? "");
 const [maps, setMaps] = useState<PurchaseMappings>(initial?.mappings ?? emptyMaps);
 const [reading, setReading] = useState(false), [fileError, setFileError] = useState("");
 const fields = [["items", "Item_Code", "material"], ["suppliers", "Supplier_Code", "supplier"], ["locations", "Location_Code", "location"]] as const;
 return <section className="purchase-panel" aria-labelledby="purchase-upload-title"><p className="eyebrow form-eyebrow">UPLOAD → VALIDATE → REVIEW → RECORD</p><h2 id="purchase-upload-title">{initial ? "Correct codes and validate a new attempt" : "Upload purchase records"}</h2>
  <p className="purchase-intro">Export the Purchases_Import worksheet from your workbook as CSV UTF-8, or use this template. Up to 100 data rows and 128 KB per file.</p>
  <div className="purchase-template-links"><a className="secondary-button purchase-template" href="/templates/purchases-import.csv" download><Download size={15}/> Download purchase template</a><a className="secondary-button purchase-template" href="/templates/fictional-purchases.csv" download><Download size={15}/> Download fictional NGN sample</a></div>
  <p className="purchase-intro">The fictional sample uses supplier SUP001 and location PRIMARY. Confirm your existing codes or map them during review.</p>
  <form className="setup-form" action={action} onReset={event => event.preventDefault()} aria-busy={pending || reading}>
   <input type="hidden" name="organisation_id" value={organisationId}/><input type="hidden" name="request_id" value={requestId}/><input type="hidden" name="csv_text" value={csv}/><input type="hidden" name="filename" value={filename}/><input type="hidden" name="mappings" value={JSON.stringify(maps)}/>
   <fieldset disabled={pending || reading} className="purchase-fieldset">
    <div className="setup-field"><label htmlFor="purchase-file">Purchases CSV</label><input id="purchase-file" type="file" accept=".csv,text/csv" onChange={async event => {
     const file = event.target.files?.[0]; setCsv(""); setFilename(""); setFileError("");
     if (!file) return;
     if (file.size > 131072 || file.name.length > 180) { setFileError("Use a CSV under 128 KB with a filename of up to 180 characters."); return; }
     setReading(true);
     try {
      const text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(await file.arrayBuffer());
      if (text.includes("\0")) throw new Error();
      setCsv(text); setFilename(file.name);
     } catch { setFileError("The file is not a supported UTF-8 text CSV. Export the purchase sheet as CSV UTF-8 and try again."); } finally { setReading(false); }
    }}/><small>{reading ? "Reading file…" : filename ? `${filename} is selected.` : "CSV only; uploading the entire XLSX workbook is not supported in this first importer."}</small></div>
    <div className="setup-field-grid"><div className="setup-field"><label htmlFor="source-org">Source organisation code</label><input id="source-org" name="source_org" value={sourceOrg} onChange={event => setSourceOrg(event.target.value)} maxLength={40} required placeholder="e.g. ORG001"/><small>Enter the Organisation_Code used in this file. Every row must match. It maps to your current business and cannot grant access to another business.</small></div>
    <div className="setup-field"><label htmlFor="purchase-price-basis">Unit price tax setting</label><select id="purchase-price-basis" name="price_basis" value={basis} onChange={event => setBasis(event.target.value)} required><option value="">Choose the source format</option><option value="EXCLUSIVE">Unit_Price excludes tax</option><option value="INCLUSIVE">Unit_Price includes tax</option></select><small>Line_Discount and Tax must be explicit amounts for each complete line, not percentages. Enter 0 when none applies.</small></div></div>
    <p className="purchase-help">{basis === "INCLUSIVE" ? "Invoice line = Quantity × Unit_Price − Line_Discount. Tax is separated from that amount." : basis === "EXCLUSIVE" ? "Invoice line = Quantity × Unit_Price − Line_Discount + Tax." : "Choose the source format so invoice arithmetic is explicit."} Freight, tax recoverability and inventory valuation are not inferred. Keep Source_System, Purchase_Ref and Line_Ref stable across repeated imports.</p>
    {initial && fields.map(([type, column, title]) => {
     const codes = [...new Set(initial.report.rows.map(row => row.source[column]).filter(Boolean))];
     return codes.length ? <details className="purchase-mappings" key={type}><summary>Map source {title} codes ({codes.length})</summary><p>Leave blank when the source code already matches. Enter an existing code from this business; this does not create master records.</p>{codes.map(code => <div className="setup-field" key={code}><label htmlFor={`map-${type}-${encodeURIComponent(code)}`}>Map {title} {code}</label><input id={`map-${type}-${encodeURIComponent(code)}`} value={maps[type]?.[code] ?? ""} maxLength={40} placeholder="Existing business code" onChange={event => setMaps(previous => ({ ...previous, [type]: { ...previous[type], [code]: event.target.value } }))}/></div>)}</details> : null;
    })}
   </fieldset>
   {fileError && <p className="auth-alert" role="alert">{fileError}</p>}{state.error && <p className="auth-alert" role="alert">{state.error}</p>}
   <div className="catalogue-editor-actions"><Link href={`/workspace/purchases?organisation=${organisationId}`} className="secondary-button">Back to imports</Link><button type="submit" className="auth-button" disabled={pending || reading || !csv}>{pending ? "Validating…" : "Validate purchase file"}<ArrowRight size={15}/></button></div>
  </form>
 </section>;
}

export function PurchaseApproval({ organisationId, batch }: { organisationId: string; batch: PurchaseBatch }) {
 const [state, action, pending] = useActionState<PurchaseActionState, FormData>(postPurchases, {});
 const [controls, setControls] = useState<Record<string, string>>(batch.entry_method === "MANUAL" ? batch.controls ?? {} : {});
 return <section className="purchase-panel"><h2>Reconcile and save purchases</h2><p className="purchase-intro">Enter the total from each supplier invoice independently. Include all invoice lines in this upload. Exact matches are required; no amounts are silently rounded.</p>
  <form action={action} onReset={event => event.preventDefault()} className="setup-form" aria-busy={pending}><input type="hidden" name="organisation_id" value={organisationId}/><input type="hidden" name="batch_id" value={batch.id}/><input type="hidden" name="controls" value={JSON.stringify(controls)}/>
   <fieldset disabled={pending} className="purchase-fieldset">{batch.report.documents.map(doc => <article className="invoice-control" key={doc.key}><div><h3>{doc.purchase_ref} · {doc.supplier_name}</h3><p>{doc.source_system} · {doc.location_name} · {doc.lines} uploaded lines</p><p>Calculated uploaded total: <strong>{referenceAmount(doc.total, doc.currency_code)}</strong></p></div>{doc.duplicate ? <span className="purchase-badge">Already recorded — will skip</span> : <div className="setup-field"><label htmlFor={`control-${doc.key}`}>Invoice total for {doc.purchase_ref} ({doc.supplier_name})</label><input id={`control-${doc.key}`} inputMode="decimal" value={controls[doc.key] ?? ""} onChange={event => setControls(previous => ({ ...previous, [doc.key]: event.target.value }))} required maxLength={39} placeholder="Total from supplier invoice"/></div>}</article>)}
    <label className="catalogue-checkbox"><input type="checkbox" name="confirmed" value="yes" required/> I checked the source format and supplier invoice totals. Save these purchase records.</label>
   </fieldset>{state.error && <p className="auth-alert" role="alert">{state.error}</p>}<button type="submit" className="auth-button" disabled={pending}>{pending ? "Saving purchases…" : "Save reviewed purchases"}<ArrowRight size={15}/></button>
  </form>
 </section>;
}

export function CancelPurchaseImport({ organisationId, batchId }: { organisationId: string; batchId: string }) {
 const [state, action, pending] = useActionState<PurchaseActionState, FormData>(cancelPurchases, {});
 return <form action={action}><input type="hidden" name="organisation_id" value={organisationId}/><input type="hidden" name="batch_id" value={batchId}/>{state.error && <p className="auth-alert" role="alert">{state.error}</p>}<button className="secondary-button" type="submit" disabled={pending}>{pending ? "Cancelling…" : "Cancel unposted import"}</button></form>;
}

export function DownloadPurchaseSource({ organisationId, batchId, generated = false }: { organisationId: string; batchId: string; generated?: boolean }) {
 const [pending, setPending] = useState(false), [error, setError] = useState("");
 return <div><button className="secondary-button" disabled={pending} type="button" onClick={async () => {
  setPending(true); setError("");
  try {
   const result = await downloadPurchaseSource(organisationId, batchId);
   if ("error" in result) { setError(result.error); return; }
   const url = URL.createObjectURL(new Blob([generated ? generatedPurchaseCsv(result.csv) : result.csv], { type: "text/csv;charset=utf-8" }));
   const anchor = document.createElement("a"); anchor.href = url; anchor.download = result.filename; document.body.append(anchor); anchor.click(); anchor.remove();
   setTimeout(() => URL.revokeObjectURL(url), 1000);
  } catch { setError("We could not download the source. Please try again."); } finally { setPending(false); }
 }}><Download size={14}/>{pending ? "Retrieving…" : generated ? "Download entry record" : "Download original CSV"}</button>{error && <p role="alert" className="field-error">{error}</p>}</div>;
}
