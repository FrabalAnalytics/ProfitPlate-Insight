import {materialCostIssue,materialCostBasis,type MaterialCost} from "@/lib/material-costs";
import {DataTable,StatusBadge} from "@/app/components/data-table";
import type { Metadata } from "next";
import { randomUUID } from "node:crypto";
import Link from "next/link";
import { redirect } from "next/navigation";
import { ArrowLeft, ArrowRight, Info, Search, Upload } from "lucide-react";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { displayQuantity } from "@/lib/recipes";
import { isUuid, type Unit } from "@/lib/catalogue";
import { referenceAmount, type ReferencePricePage } from "@/lib/reference-prices";
import { WorkspaceShell } from "@/app/components/workspace-shell";
import { PriceEditor } from "./price-editor";
import "../catalogue.css";
import "./prices.css";

export const metadata: Metadata = { title: "Initial material prices | ProfitPlate Insights" };
export const instant = false;
type Params = { organisation?: string; q?: string; page?: string; item?: string; import?: string; saved?: string };

export default async function MaterialPricesPage({ searchParams }: { searchParams: Promise<Params> }) {
 const user = await requireUser();
 const access = await getPlatformAccess();
 if (access !== "member") redirect(workspacePath(access));
 const params = await searchParams;
 const supabase = await createClient();
 const { data: organisations, error: orgError } = await supabase.from("organisations").select("id,name,time_zone,currency_code").order("name");
 const org = params.organisation ? organisations?.find(entry => entry.id === params.organisation) : organisations?.[0];
 if (!org && !orgError && !organisations?.length) redirect("/onboarding");
 if (!org || orgError) return <WorkspaceShell email={user.email}><h1 className="workspace-title">This business is unavailable.</h1><Link className="auth-back" href="/workspace">Return to workspace</Link></WorkspaceShell>;
 const query = (values: Record<string, string> = {}) => `/workspace/materials/prices?${new URLSearchParams({ organisation: org.id, ...values })}`;
 const shell = { email: user.email, restaurantName: org.name, organisationId: org.id, sectionLabel: "Initial material prices" };
 const { data: permission, error: permissionError } = await supabase.rpc("reference_price_access", { p_organisation_id: org.id });
 if (permissionError) return <WorkspaceShell {...shell}><h1 className="workspace-title">Initial prices are not available yet.</h1><p className="workspace-description">The platform administrator needs to finish the initial-prices update, or access is temporarily unavailable. Your existing catalogue is still available.</p><Link className="auth-back" href={`/workspace/materials?organisation=${org.id}`}>Return to materials</Link></WorkspaceShell>;
 if (permission?.read !== true) return <WorkspaceShell {...shell}><h1 className="workspace-title">Business-wide price access is restricted.</h1><p className="workspace-description">An organisation-wide administrator, procurement manager, finance member or CEO can view these reference prices.</p><Link className="auth-back" href={`/workspace/materials?organisation=${org.id}`}>Return to materials</Link></WorkspaceShell>;
 const canEdit = permission.write === true;
 const q = (params.q ?? "").trim().slice(0, 80);
 const page = Math.min(100000, Math.max(1, Number.parseInt(params.page ?? "1", 10) || 1));
 const itemId = params.item && isUuid(params.item) ? params.item : null;
 const [result, unitsResult] = await Promise.all([
  supabase.rpc("list_material_reference_prices", { p_organisation_id: org.id, p_search: itemId ? "" : q, p_page: itemId ? 1 : page, p_item_id: itemId }),
  supabase.from("units_of_measure").select("id,code,name,dimension").eq("organisation_id", org.id).order("code"),
 ]);
 if (result.error || unitsResult.error) return <WorkspaceShell {...shell}><h1 className="workspace-title">We could not load reference prices.</h1><p className="workspace-description">Please refresh and try again. No missing or unavailable price is treated as zero.</p><a className="auth-back" href={query()}>Try again</a></WorkspaceShell>;
 const data = result.data as ReferencePricePage;
 const material = itemId ? data.items[0] : undefined;
 const dayParts = new Intl.DateTimeFormat("en", { timeZone: org.time_zone, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(new Date());
 const businessDate = ["year", "month", "day"].map(key => dayParts.find(part => part.type === key)?.value).join("-");
 const costsResult=await supabase.rpc("material_cost_estimates",{p_organisation_id:org.id,p_ids:data.items.map(i=>i.id),p_as_of:businessDate});
 const costs=(costsResult.data??{}) as Record<string,MaterialCost>,current=material?costs[material.id]:undefined,derived=current?.basis==='RECIPE_DERIVED';
 const editing=canEdit&&(params.import==='1'||(material?.is_active&&params.item&&!derived));
 return <WorkspaceShell {...shell}>
  <Link className="catalogue-back" href={`/workspace/materials?organisation=${org.id}`}><ArrowLeft size={14}/> Materials & suppliers</Link>
  <div className="page-heading-row"><div><p className="eyebrow form-eyebrow">DATA & SETUP / INITIAL PRICES</p><h1 className="workspace-title">A starting point for your costs.</h1><p className="workspace-description">Add the prices you know. Leave the rest visible as missing and complete them at your own pace.</p></div>{canEdit && !editing && <Link className="auth-button catalogue-add" href={query({ import: "1" })}><Upload size={16}/> Import initial prices</Link>}</div>
  <Link className="secondary-button" href={`/workspace/materials/prices/monthly?organisation=${org.id}`}>Monthly material price tracker</Link>
  <div className="reference-summary"><div><strong>{data.priced_materials} of {data.active_materials}</strong><span>active materials have initial price entries</span></div><div><strong>{data.active_materials - data.priced_materials}</strong><span>without initial price entries; some may use recipe costs</span></div><div><strong>Estimated</strong><span>business-wide · {org.currency_code}</span></div></div>
  <p className="catalogue-readonly"><Info size={16}/> Optional setup. These business-wide reference prices are separate from purchase transactions, stock balances and actual profit. Open a saved recipe to review estimated ingredient and packaging costs.</p>
  {costsResult.error&&<p className="auth-alert" role="alert">Current cost estimates are unavailable. Check the latest costing update.</p>}
  {!canEdit && <p className="catalogue-readonly">You have read-only price access. An organisation-wide restaurant administrator or procurement manager can add prices.</p>}
  {params.saved === "1" && <p className="welcome-message" role="status">Your estimated prices have been saved. Earlier entries remain in history.</p>}
  {params.item && !material && <p className="auth-alert" role="alert">This material is not available in this business.</p>}
  {editing && <PriceEditor key={material?.id ?? "import"} organisationId={org.id} material={params.import === "1" ? undefined : material} units={(unitsResult.data ?? []) as Unit[]} businessDate={businessDate} currency={org.currency_code} requestId={randomUUID()}/>}
  {material ? <section className="reference-history"><div className="section-heading"><h2>Price history · {material.name}</h2><Link className="record-edit" href={query()}>All material prices <ArrowRight size={14}/></Link></div>
   {derived&&<p className="reference-current">Estimated cost: <strong>{current.unit_cost?`${referenceAmount(current.unit_cost,current.currency_code)} / ${material.base_unit_code}`:materialCostIssue(current.missing_reason)}</strong>. This processed SKU gets its cost from its recipe, not a separately entered price. <Link className="inline-link" href={current.recipe_version_id?`/workspace/recipes?organisation=${org.id}&version=${current.recipe_version_id}`:`/workspace/setup/production?organisation=${org.id}`}>{current.recipe_name??'Link processing recipe'}</Link></p>}
   {material.latest && <p className="reference-current">Latest reference entry: <strong>{referenceAmount(material.latest.cost_per_base_unit, material.latest.currency_code)} / {material.base_unit_code}</strong> · {material.latest.price_date} · Estimated</p>}
   {!material.is_active && <p className="catalogue-readonly">This material is inactive. Its history remains available; reactivate it before adding a price.</p>}
   <p className="reference-intro">Latest 25 saved entries. The most recent price date takes priority; a correction on the same date uses the newest entry.</p>
   {data.history.length ? <DataTable label="Material reference price history" columns={[{label:"Entry / date"},{label:"Source"},{label:"Purchase quantity",numeric:true},{label:"Total price",numeric:true},{label:"Base quantity",numeric:true},{label:"Estimated unit cost",numeric:true},{label:"Source note"}]} rows={data.history.map(price=>({id:String(price.version),cells:[<span key="entry">Entry {price.version}<small>{price.price_date}</small></span>,price.source==="CSV"?"CSV import":"Manual entry",`${displayQuantity(price.quantity)} ${price.unit_code}`,referenceAmount(price.total_price,price.currency_code),`${displayQuantity(price.base_quantity)} ${material.base_unit_code}`,`${referenceAmount(price.cost_per_base_unit,price.currency_code)} / ${material.base_unit_code}`,price.source_note||"Not provided"]}))}/> : <p className="catalogue-readonly">{derived?"No manual reference entries. Its estimated cost comes from the linked processing recipe.":current?.unit_cost?"No manual reference entries. This material uses posted purchase history.":"No reference price yet. This material remains missing a price."}</p>}
  </section> : <>
   <form method="get" className="catalogue-filter"><input type="hidden" name="organisation" value={org.id}/><div><Search size={16}/><label className="sr-only" htmlFor="price-search">Search material prices</label><input id="price-search" name="q" defaultValue={q} maxLength={80} placeholder="Search materials by name or code"/></div><button className="secondary-button">Search</button></form>
   {data.items.length>0&&<DataTable label="Material reference prices" columns={[{label:"Material"},{label:"Base unit"},{label:"Estimated unit cost",numeric:true},{label:"Cost basis / date"},{label:"Status"},{label:"Action"}]} rows={data.items.map(item=>({id:item.id,cells:[<span key="material">{item.name}<small>{item.code}</small></span>,item.base_unit_code,costs[item.id]?.unit_cost?`${referenceAmount(costs[item.id].unit_cost!,costs[item.id].currency_code)} / ${item.base_unit_code}`:materialCostIssue(costs[item.id]?.missing_reason),<span key="basis">{materialCostBasis(costs[item.id]?.basis)}<small>{costs[item.id]?.price_date??"Not available"}</small></span>,<StatusBadge key="status" tone={!item.is_active?"neutral":costs[item.id]?.unit_cost?"success":"warning"}>{!item.is_active?"Inactive":costs[item.id]?.unit_cost?"Estimated":materialCostIssue(costs[item.id]?.missing_reason)}</StatusBadge>,<Link key="view" className="inline-link" href={query({item:item.id})} aria-label={`Reference prices for ${item.name}`}>{costs[item.id]?.basis==="RECIPE_DERIVED"?"Recipe cost / setup":canEdit&&item.is_active?item.latest?"Add price / history":"Add price":"View history"}<ArrowRight size={14}/></Link>]}))}/>}
   {!data.items.length && <section className="catalogue-empty"><h2>{q ? "No matching materials" : "Start with your materials"}</h2><p>{q ? "Try a different material name or code." : "Add ingredients and packaging in the catalogue. Prices are optional and can be added afterwards."}</p><Link className="auth-back" href={`/workspace/materials?organisation=${org.id}`}>Open catalogue</Link></section>}
   {(data.total > 25 || page > 1) && <div className="catalogue-pagination"><p>{data.total} materials · Page {page}</p><div>{page > 1 && <Link href={query({ q, page: String(page - 1) })}>Previous</Link>}{page * 25 < data.total && <Link href={query({ q, page: String(page + 1) })}>Next <ArrowRight size={14}/></Link>}</div></div>}
  </>}
 </WorkspaceShell>;
}
