"use client";
import {DataTable} from "@/app/components/data-table";


import { useActionState, useState } from "react";
import Link from "next/link";
import { ArrowRight, Download, Info } from "lucide-react";
import type { Unit } from "@/lib/catalogue";
import { displayQuantity } from "@/lib/recipes";
import { referenceAmount, type ReferenceMaterial } from "@/lib/reference-prices";
import { reviewReferencePrices, saveReferencePrices, type PriceReviewState, type PriceSaveState } from "./actions";

export function PriceEditor({ organisationId, material, units, businessDate, currency, requestId }: {
 organisationId: string; material?: ReferenceMaterial; units: Unit[]; businessDate: string; currency: string; requestId: string;
}) {
 const source = material ? "MANUAL" : "CSV";
 const [review, reviewAction, reviewing] = useActionState<PriceReviewState, FormData>(reviewReferencePrices, {});
 const [saved, saveAction, saving] = useActionState<PriceSaveState, FormData>(saveReferencePrices, {});
 const [revision, setRevision] = useState(0);
 const [csv, setCsv] = useState("");
 const [fileError, setFileError] = useState("");
 const [reading, setReading] = useState(false);
 const [filename, setFilename] = useState("");
 const [fields, setFields] = useState({ quantity: "", unit_code: material?.base_unit_code ?? "", total_price: "", price_date: businessDate, source_note: "" });
 const field = (key: keyof typeof fields) => ({ value: fields[key], onChange: (event: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => setFields(previous => ({ ...previous, [key]: event.target.value })) });
 const preview = review.revision === String(revision) ? review.preview : undefined;
 const busy = reviewing || saving || reading;
 const baseUnit = units.find(unit => unit.id === material?.base_uom_id);
 const choices = units.filter(unit => unit.dimension === "PACKAGE" || unit.dimension === baseUnit?.dimension);
 const back = `/workspace/materials/prices?organisation=${organisationId}`;
 return <section className="catalogue-editor reference-editor" aria-labelledby="price-editor-title">
  <p className="eyebrow form-eyebrow">OPTIONAL / ESTIMATED PRICES</p>
  <h2 id="price-editor-title">{material ? `Reference price for ${material.name}` : "Import initial material prices"}</h2>
  <p className="reference-intro">{material ? "Enter the total price for a known quantity. Include when the price was obtained and where it came from." : "Use existing material codes. Upload a CSV, review the converted prices, then save the whole batch together."} All amounts are in {currency}.</p>
  <form action={reviewAction} aria-busy={busy} className="setup-form" onReset={event => event.preventDefault()} onChange={() => setRevision(value => value + 1)}>
   <input type="hidden" name="organisation_id" value={organisationId}/><input type="hidden" name="source" value={source}/><input type="hidden" name="revision" value={revision}/>
   <fieldset disabled={busy} className="price-fieldset">
    {material ? <>
     <input type="hidden" name="material_code" value={material.code}/>
     <div className="setup-field-grid"><div className="setup-field"><label htmlFor="price-quantity">Quantity covered by this price</label><input id="price-quantity" name="quantity" inputMode="decimal" placeholder="e.g. 50" required maxLength={21} {...field("quantity")}/></div>
     <div className="setup-field"><label htmlFor="price-unit">Quantity unit</label><select id="price-unit" name="unit_code" {...field("unit_code")}>{choices.map(unit => <option key={unit.id} value={unit.code}>{unit.name} ({unit.code})</option>)}</select></div></div>
     <div className="setup-field-grid"><div className="setup-field"><label htmlFor="total-price">Total price ({currency})</label><input id="total-price" name="total_price" inputMode="decimal" placeholder="e.g. 90000" required maxLength={21} {...field("total_price")}/><small>For the full quantity above, up to six decimal places. No commas.</small></div>
     <div className="setup-field"><label htmlFor="price-date">Price date</label><input id="price-date" name="price_date" type="date" max={businessDate} {...field("price_date")} required/></div></div>
     <div className="setup-field"><label htmlFor="price-source">Source note</label><input id="price-source" name="source_note" placeholder="e.g. Last supplier invoice, 10 November" maxLength={300} required {...field("source_note")}/><small>State whether this is a recent purchase price, supplier quote or your estimate.</small></div>
     <p className="catalogue-form-note">Bags, cartons and other packages need a saved conversion effective on the price date. <Link className="record-edit" href={`/workspace/materials?organisation=${organisationId}&tab=conversions&item=${material.id}`}>Manage this material’s units</Link></p>
    </> : <>
     <a className="secondary-button price-template" href="/templates/initial-material-prices.csv" download><Download size={15}/> Download CSV template</a>
     <p className="reference-intro">Columns: material_code, quantity, unit_code, total_price, price_date, source_note. Dates use YYYY-MM-DD. Maximum 100 rows and 128 KB. Leave unpriced materials out.</p>
     <p className="reference-example">Example: RICE001,50,KG,90000,2026-11-10,Last supplier invoice</p>
     <div className="setup-field"><label htmlFor="price-file">Initial prices CSV</label><input id="price-file" type="file" accept=".csv,text/csv" onChange={async event => {
      const file = event.target.files?.[0]; setCsv(""); setFileError(""); setFilename("");
      if (!file) return;
      if (file.size > 131072) { setFileError("Keep the CSV under 128 KB."); return; }
      setReading(true);
      try { setCsv(await file.text()); setFilename(file.name); } catch { setFileError("We could not read this file. Choose it again."); } finally { setReading(false); }
     }}/><small>{reading ? "Reading file…" : filename ? `${filename} is ready to review.` : "You can export a completed template from Excel as CSV UTF-8."}</small></div>
     <input type="hidden" name="csv_text" value={csv}/>
    </>}
   </fieldset>
   {fileError && <p className="auth-alert" role="alert">{fileError}</p>}
   {review.revision === String(revision) && review.error && <p className="auth-alert" role="alert">{review.error}</p>}
   <div className="catalogue-editor-actions"><Link className="secondary-button" href={back}>Cancel</Link><button className="auth-button" type="submit" disabled={busy || (!material && !csv)}>{reviewing ? "Checking prices…" : "Review prices"}<ArrowRight size={15}/></button></div>
  </form>
  {preview && <section className="reference-review" aria-labelledby="price-review-title"><h3 id="price-review-title">Review before saving</h3><p>{preview.length} {preview.length === 1 ? "price" : "prices"} · Estimated · Business-wide reference</p>
   <DataTable label="Reviewed reference prices" columns={[{label:"Material"},{label:"Price date"},{label:"Quantity",numeric:true},{label:"Total price",numeric:true},{label:"Base quantity",numeric:true},{label:"Estimated unit cost",numeric:true},{label:"Source note"}]} rows={preview.map(row=>({id:`${row.item_id}-${row.price_date}`,cells:[<span key="material">{row.name}<small>{row.material_code}</small></span>,row.price_date,`${displayQuantity(row.quantity)} ${row.unit_code}`,referenceAmount(row.total_price,row.currency_code),`${displayQuantity(row.base_quantity)} ${row.base_unit_code}`,`${referenceAmount(row.cost_per_base_unit,row.currency_code)} / ${row.base_unit_code}`,row.source_note||"Not provided"]}))}/>
   <p className="setup-help"><Info size={16}/> This saves reference estimates only. It does not record a purchase, establish opening stock or verify a recipe margin. A new price preserves earlier entries.</p>
   <form action={saveAction} aria-busy={saving}><input type="hidden" name="organisation_id" value={organisationId}/><input type="hidden" name="request_id" value={requestId}/><input type="hidden" name="source" value={source}/><input type="hidden" name="rows" value={JSON.stringify(review.rows)}/><input type="hidden" name="preview" value={JSON.stringify(preview)}/>
    {saved.error && <p className="auth-alert" role="alert">{saved.error}</p>}
    <button type="submit" className="auth-button" disabled={busy}>{saving ? "Saving prices…" : "Save estimated prices"}<ArrowRight size={15}/></button>
   </form>
  </section>}
 </section>;
}
