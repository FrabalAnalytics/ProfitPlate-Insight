import {DataTable,StatusBadge} from "@/app/components/data-table";
import Link from "next/link";
import { ArrowRight, Info } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { displayQuantity, positiveDecimal, validBusinessDate } from "@/lib/recipes";
import {materialCostIssue,materialCostBasis} from "@/lib/material-costs";
import { referenceAmount } from "@/lib/reference-prices";

type Estimate = {
 cost_state: "MISSING" | "ESTIMATED"; as_of: string; currency_code: string;
 batch_yield: string; yield_unit_code: string; output_quantity: string;
 missing_count: number; priced_count: number; batch_cost: string | null;
 cost_per_output_unit: string | null; target_cost: string | null; known_subtotal: string | null;
 lines: { item_id: string; name: string; code: string; item_type: string; quantity: string;
  quantity_below_precision: boolean; unit_code: string; price_date: string | null;
  cost_recipe_version_id?:string;cost_recipe_name?:string;price_basis?:string;price_month?:string;price_version: number | null; source_note: string | null; unit_cost: string | null;
  batch_cost: string | null; missing_reason: string | null }[];
};

export async function RecipeCostPreview({ organisationId, versionId, date, businessDate, effectiveFrom, outputQuantity, outputUnit }: {
 organisationId: string; versionId: string; date: string; businessDate: string; effectiveFrom: string; outputQuantity: string; outputUnit: string;
}) {
 const supabase = await createClient();
 const { data: access, error: accessError } = await supabase.rpc("reference_price_access", { p_organisation_id: organisationId });
 if (!accessError && access?.read !== true) return <section className="recipe-cost-preview"><h2>Estimated recipe cost</h2><p className="catalogue-readonly"><Info size={16}/> Business-wide financial access is required to view cost estimates. Recipe quantities remain available within your access.</p></section>;
 let estimate: Estimate | null = null, message = "";
 if (accessError) message = "Reference prices are unavailable. The platform administrator may need to finish the initial-prices update.";
 else if (!validBusinessDate(date) || !positiveDecimal(outputQuantity)) message = "Choose a valid cost date and positive target output with up to six decimal places.";
 else {
  const result = await supabase.rpc("recipe_reference_cost_estimate", { p_organisation_id: organisationId, p_version_id: versionId, p_as_of: date, p_output_quantity: outputQuantity });
  if (result.error) message = result.error.code === "22023" ? result.error.message : "The cost estimate is unavailable. Please try again; the platform administrator may need to apply the recipe-costing update.";
  else estimate = result.data as Estimate;
 }
 const money = (value: string) => referenceAmount(value, estimate!.currency_code);
 return <section className="recipe-cost-preview" aria-labelledby="recipe-cost-title">
  <div className="section-heading"><div><p className="eyebrow form-eyebrow">MATERIAL COSTS / ESTIMATE</p><h2 id="recipe-cost-title">Estimated recipe cost</h2></div>{estimate && <span className="recipe-missing-label">Cost readiness: {estimate.cost_state}</span>}</div>
  <p className="cost-explanation">Uses this saved recipe version, its saved sub-recipe versions and direct packaging. Input costs use business-wide monthly purchase averages, initial prices where needed, and linked processing recipes for produced SKUs.</p>
  <form method="get" className="recipe-scale-form"><input type="hidden" name="organisation" value={organisationId}/><input type="hidden" name="version" value={versionId}/><input type="hidden" name="scale" value={outputQuantity}/><div className="setup-field"><label htmlFor="recipe-cost-date">Cost date</label><input id="recipe-cost-date" name="cost_date" type="date" min={effectiveFrom} max={businessDate} defaultValue={date} required/></div><button className="secondary-button" type="submit">Update estimate <ArrowRight size={14}/></button></form>
  {message ? <p className="auth-alert" role="alert">{message}</p> : estimate && <>
   {estimate.cost_state === "MISSING" ? <div className="cost-incomplete" role="status"><h3>Cost incomplete — {estimate.missing_count} {estimate.missing_count === 1 ? "material needs" : "materials need"} a usable price.</h3><p>Batch, per-unit and target costs are unavailable until every material has a usable material price.</p>{estimate.known_subtotal !== null && <p>Known ingredient and packaging subtotal: <strong>{money(estimate.known_subtotal)}</strong>. This is a partial amount, not the full batch cost.</p>}</div> : <div className="cost-summary-grid">
    <article><span>Estimated batch cost</span><strong>{money(estimate.batch_cost!)}</strong><small>For {displayQuantity(estimate.batch_yield)} {estimate.yield_unit_code}</small></article>
    <article><span>{outputUnit === "PCS" ? "Estimated cost per portion / piece" : `Estimated cost per ${outputUnit}`}</span><strong>{money(estimate.cost_per_output_unit!)}</strong><small>Per 1 {estimate.yield_unit_code} of declared output</small></article>
    <article><span>Estimated target cost</span><strong>{money(estimate.target_cost!)}</strong><small>For {displayQuantity(estimate.output_quantity)} {estimate.yield_unit_code} · change target below</small></article>
   </div>}
   <DataTable label="Material costs for one standard batch" columns={[{label:"Material"},{label:"Batch quantity",numeric:true},{label:"Estimated unit cost",numeric:true},{label:"Price source"},{label:"Batch cost",numeric:true}]} rows={estimate.lines.map(line=>({id:line.item_id,cells:[<span key="material">{line.name}<small>{line.code}{line.item_type==="PACKAGING"?" - Direct packaging":""}</small></span>,`${line.quantity_below_precision?"<0.000000000001":displayQuantity(line.quantity)} ${line.unit_code}`,line.unit_cost===null?"Unavailable":`${money(line.unit_cost)} / ${line.unit_code}`,line.missing_reason?<StatusBadge key="missing" tone="warning">{materialCostIssue(line.missing_reason)}</StatusBadge>:<span key="source">{line.price_month ?? line.price_date} - {materialCostBasis(line.price_basis)}<small>{line.cost_recipe_version_id?<Link href={`/workspace/recipes?organisation=${organisationId}&version=${line.cost_recipe_version_id}`}>{line.cost_recipe_name}</Link>:line.source_note}</small></span>,line.batch_cost===null?<Link key="review" className="inline-link" href={`/workspace/materials/prices?organisation=${organisationId}&item=${line.item_id}`}>Review price <ArrowRight size={13}/></Link>:money(line.batch_cost)]}))}/>
   <p className="cost-explanation"><Info size={15}/> Live estimate as of {estimate.as_of}. Posted invoices and approved invoice corrections update monthly quantity-weighted costs. Initial prices are a fallback where that month has no invoice history. Earlier months carry forward when needed. This preview can change as source records change. It is not a finalised historical report. No additional labour, overhead or operating expenses are added; no actual profit or stock valuation is calculated.</p>
  </>}
 </section>;
}
