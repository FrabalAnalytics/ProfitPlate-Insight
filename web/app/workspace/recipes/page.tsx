import { MenuRecipeFilter } from "@/app/components/menu-recipe-filter";
import {DataTable} from "@/app/components/data-table";
import type { Metadata } from "next";
import { randomUUID } from "node:crypto";
import Link from "next/link";
import { redirect } from "next/navigation";
import { ArrowLeft, ArrowRight, BookOpen, Check, Clock3, Info, Layers3, Plus, Scale, Search } from "lucide-react";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { isUuid, type Unit } from "@/lib/catalogue";
import { displayQuantity, positiveDecimal, type RecipePacket } from "@/lib/recipes";
import { WorkspaceShell } from "@/app/components/workspace-shell";
import { RecipeEditor } from "./recipe-editor";
import { RecipeCostPreview } from "./cost-preview";
import "../materials/catalogue.css";
import "./recipes.css";

export const metadata: Metadata = { title: "Recipes & scaling | ProfitPlate Insight" };
export const instant = false;
type Params = { organisation?: string; recipe?: string; version?: string; new?: string; edit?: string; saved?: string; scale?: string; cost_date?: string; q?: string; page?: string };

export default async function RecipesPage({ searchParams }: { searchParams: Promise<Params> }) {
 const user = await requireUser();
 const access = await getPlatformAccess();
 if (access !== "member") redirect(workspacePath(access));
 const params = await searchParams;
 const supabase = await createClient();
 const { data: organisations, error: orgError } = await supabase.from("organisations").select("id,name,time_zone").order("name");
 if (orgError) return <WorkspaceShell email={user.email}><h1 className="workspace-title">We couldn’t load your business.</h1><p className="workspace-description">Please refresh and try again.</p></WorkspaceShell>;
 if (!organisations?.length) redirect("/onboarding");
 const org = params.organisation ? organisations.find(entry => entry.id === params.organisation) : organisations[0];
 if (!org) return <WorkspaceShell email={user.email}><h1 className="workspace-title">This business isn’t available to your account.</h1><Link className="auth-back" href="/workspace">Return to your workspace</Link></WorkspaceShell>;
 const query = (values: Record<string,string> = {}) => `/workspace/recipes?${new URLSearchParams({ organisation: org.id, ...values }).toString()}`;
 const [permission, unitsResult] = await Promise.all([
  supabase.rpc("can_manage_recipes", { p_organisation_id: org.id }),
  supabase.from("units_of_measure").select("id,code,name,dimension").eq("organisation_id",org.id).order("code"),
 ]);
 if (permission.error || unitsResult.error) return <WorkspaceShell email={user.email} restaurantName={org.name} organisationId={org.id} sectionLabel="Recipes & scaling"><p className="eyebrow form-eyebrow">PROFITABILITY / RECIPES</p><h1 className="workspace-title">Recipe setup is temporarily unavailable.</h1><p className="workspace-description">Please try again shortly. The platform administrator may need to finish the recipe update.</p><a className="auth-back" href={query()}>Try again</a></WorkspaceShell>;
 const canEdit = permission.data === true;
 const units = (unitsResult.data ?? []) as Unit[];
 const locationsResult=await supabase.from("locations").select("id,name").eq("organisation_id",org.id).eq("is_active",true).order("name");
 const isNew = params.new === "1";
 let packet: RecipePacket | null = null;
 let versions: { id: string; version: number; name: string; effective_from: string }[] = [];
 let detailError = false;
 if (params.version || params.recipe) {
  let id = params.version;
  if (!id && params.recipe && isUuid(params.recipe)) {
   const result = await supabase.from("recipe_versions").select("id,version,name,effective_from").eq("organisation_id",org.id).eq("recipe_id",params.recipe).order("version", { ascending: false });
   versions = result.data ?? [];
   id = versions[0]?.id;
  }
  if (id && isUuid(id)) {
   const result = await supabase.rpc("get_recipe_version", { p_organisation_id:org.id,p_version_id:id });
   if (!result.error && result.data) packet = result.data as RecipePacket;
   else detailError = true;
  } else detailError = true;
  if (packet && !versions.length) {
   const result = await supabase.from("recipe_versions").select("id,version,name,effective_from").eq("organisation_id",org.id).eq("recipe_id",packet.recipe.id).order("version",{ascending:false});
   versions = result.data ?? [];
  }
 }
 const showEditor = canEdit && (isNew || (params.edit === "1" && packet));
 const dayParts = new Intl.DateTimeFormat("en",{timeZone:org.time_zone,year:"numeric",month:"2-digit",day:"2-digit"}).formatToParts(new Date());
 const day = ["year","month","day"].map(key => dayParts.find(part=>part.type===key)?.value).join("-");
 const q = (params.q ?? "").trim().slice(0,80);
 const page = Math.min(100000,Math.max(1,Number.parseInt(params.page ?? "1",10)||1));
 let list: { id:string;code:string;name:string;recipe_type:string }[] = [], total=0, listError=false;
 if (!packet && !showEditor && !detailError) {
  let request = supabase.from("recipes").select("id,code,name,recipe_type",{count:"exact"}).eq("organisation_id",org.id).order("name").order("id");
  if(q)request=request.ilike("name",`%${q.replace(/[\\%_]/g,"\\$&")}%`);
  const result=await request.range((page-1)*25,page*25-1);
  list=result.data??[];total=result.count??0;listError=!!result.error;
 }
 let requirements: {item_id:string;name:string;code:string;item_type:string;quantity:string;below_precision?:boolean;uom_code:string}[]=[];
 let scaleError=false;
 const scale = params.scale ?? (packet ? displayQuantity(packet.output.quantity) : "1");
 if(packet && !showEditor && positiveDecimal(scale)){
  const result=await supabase.rpc("recipe_material_requirements",{p_organisation_id:org.id,p_version_id:packet.version.id,p_output_quantity:scale});
  requirements=Array.isArray(result.data)?result.data:[];scaleError=!!result.error;
 }else if(packet && !showEditor)scaleError=true;

 return <WorkspaceShell email={user.email} restaurantName={org.name} organisationId={org.id} sectionLabel="Recipes & scaling">
  <Link className="catalogue-back" href={`/workspace?organisation=${org.id}`}><ArrowLeft size={14}/> Back to workspace</Link>
  <div className="page-heading-row"><div><p className="eyebrow form-eyebrow">PROFITABILITY / RECIPES</p><h1 className="workspace-title">Recipes & scaling</h1></div>{canEdit && !showEditor && <Link className="auth-button catalogue-add" href={query({new:"1"})}><Plus size={16}/> Create recipe</Link>}</div>
  {!canEdit && <p className="catalogue-readonly"><Info size={16}/> You have read-only recipe access. An organisation-wide restaurant administrator or operations manager can publish versions.</p>}
  {params.saved==="1" && <p className="welcome-message" role="status"><Check size={16}/> Your recipe version has been published. Earlier versions remain unchanged.</p>}
  {showEditor ? <RecipeEditor organisationId={org.id} units={units} locations={locationsResult.data??[]} initial={isNew?undefined:packet??undefined} requestId={randomUUID()} businessDate={day}/> : detailError ? <section className="catalogue-empty"><BookOpen size={26}/><h2>This recipe version isn’t available in this business.</h2><Link className="auth-back" href={query()}>Return to your recipes</Link></section> : packet ? <>
   <div className="recipe-detail-toolbar"><Link className="catalogue-back" href={query()}><ArrowLeft size={14}/> All recipes</Link><form method="get"><input type="hidden" name="organisation" value={org.id}/><label htmlFor="recipe-version">Saved version</label><select id="recipe-version" name="version" defaultValue={packet.version.id}>{versions.map(version=><option key={version.id} value={version.id}>Version {version.version} · {String(version.effective_from).slice(0,10)}</option>)}</select><button className="secondary-button" type="submit">View</button></form>{canEdit && <Link className="secondary-button" href={query({version:packet.version.id,edit:"1"})}><Plus size={14}/> Create new version</Link>}</div>
   <div className="recipe-overview-grid"><section className="recipe-summary-card"><div className="summary-card-heading"><span className="summary-icon"><BookOpen size={19}/></span><span>{packet.recipe.code} · {packet.recipe.recipe_type==="SUB_RECIPE"?"Sub-recipe":"Final recipe"}</span></div><h2>{packet.version.name}</h2><div className="recipe-version-facts"><span><Layers3 size={14}/> Version {packet.version.version}</span><span><Clock3 size={14}/> Effective {String(packet.version.effective_from).slice(0,10)}</span></div><div className="recipe-batch-output"><span>STANDARD BATCH YIELD</span><strong>{displayQuantity(packet.output.quantity)} <small>{packet.output.uom_code}</small></strong></div>{packet.version.notes && <p className="recipe-version-notes">{packet.version.notes}</p>}</section><aside className="recipe-readiness"><Info size={20}/><h2>Composition saved.<br/>Ready to check your costs.</h2><p>Review estimated ingredient and packaging costs below. Missing prices remain visible; estimates do not establish actual profit.</p><span className="recipe-missing-label">Reference estimates</span></aside></div>
   <RecipeCostPreview organisationId={org.id} versionId={packet.version.id} date={params.cost_date ?? day} businessDate={day} effectiveFrom={String(packet.version.effective_from).slice(0,10)} outputQuantity={scale} outputUnit={packet.output.uom_code}/>
   <section className="recipe-saved-components"><div className="section-heading"><h2>What goes into this batch</h2><span>{packet.components.length} COMPONENT LINES</span></div><DataTable label="Saved recipe components" columns={[{label:"Component"},{label:"Code"},{label:"Source"},{label:"Quantity",numeric:true},{label:"Unit"}]} rows={packet.components.map(component=>({id:component.id,cells:[component.label,component.code,<span key="source">{component.kind==="RECIPE"?"Pinned sub-recipe version":component.target_type==="PACKAGING"?"Direct packaging":"Material"}{component.conversion_id&&<small>Package conversion pinned</small>}</span>,displayQuantity(component.quantity),component.uom_code]}))}/></section>
   <section className="recipe-scaling"><div className="section-heading"><div><span className="eyebrow form-eyebrow">QUANTITIES, WITHOUT THE GUESSWORK</span><h2>Scale this recipe</h2></div><Scale size={20}/></div><p>Expand the saved sub-recipes into material quantities for your target output. This preview does not post production or change stock.</p><form method="get" className="recipe-scale-form"><input type="hidden" name="organisation" value={org.id}/><input type="hidden" name="version" value={packet.version.id}/><input type="hidden" name="cost_date" value={params.cost_date ?? day}/><div className="setup-field"><label htmlFor="target-output">Target output ({packet.output.uom_code})</label><input id="target-output" name="scale" inputMode="decimal" defaultValue={scale} required/></div><button className="auth-button" type="submit">Calculate quantities <ArrowRight size={15}/></button></form>{scaleError?<p className="auth-alert" role="alert">We couldn?t calculate quantities. Check that the target output is positive with up to six decimal places, then try again.</p>:<DataTable label="Scaled material requirements" columns={[{label:"Material"},{label:"Code"},{label:"Type"},{label:"Required quantity",numeric:true},{label:"Unit"}]} rows={requirements.map(requirement=>({id:`${requirement.item_id}-${requirement.item_type}`,cells:[requirement.name,requirement.code,requirement.item_type==="PACKAGING"?"Packaging":"Ingredient",requirement.below_precision?"<0.000000000001":displayQuantity(requirement.quantity),requirement.uom_code]}))}/>}<small className="recipe-scaling-note">Calculated from this version’s saved quantities and conversions. Results are rounded to 12 decimal places; these are quantities, not financial costs.</small></section>
  </> : <>
   <MenuRecipeFilter organisation={org.id} selected="recipes"/>
   <form method="get" className="catalogue-filter"><input type="hidden" name="organisation" value={org.id}/><div><Search size={16}/><label className="sr-only" htmlFor="recipe-search">Search recipes</label><input id="recipe-search" type="search" name="q" defaultValue={q} maxLength={80} placeholder="Search recipes by name…"/></div><button className="secondary-button" type="submit">Search</button></form>
   {listError?<p className="auth-alert" role="alert">We couldn’t load your recipes. Please refresh and try again.</p>:list.length?<DataTable label="Recipe library" columns={[{label:"Recipe"},{label:"Code"},{label:"Type"},{label:"Action"}]} rows={list.map(recipe=>({id:recipe.id,cells:[recipe.name,recipe.code,recipe.recipe_type==="SUB_RECIPE"?"Sub-recipe / preparation":"Final recipe",<Link key="view" className="inline-link" href={query({recipe:recipe.id})} aria-label={`View ${recipe.name}`}>Versions & quantities <ArrowRight size={15}/></Link>]}))}/>:<section className="catalogue-empty"><span><BookOpen size={26}/></span><h2>{q?"No matching recipes":"Start with one standard batch"}</h2><p>{q?"Try a different recipe name.":"Create your base preparations first, then reuse their saved versions in final recipes. Add materials in your catalogue before building a recipe."}</p><Link className="auth-back" href={`/workspace/materials?organisation=${org.id}`}>Open material catalogue <ArrowRight size={14}/></Link></section>}
   {(total>25||page>1)&&<div className="catalogue-pagination"><p>{total} matching recipes · page {page}</p><div>{page>1&&<Link href={query({q,page:String(page-1)})}>Previous</Link>}{page*25<total&&<Link href={query({q,page:String(page+1)})}>Next</Link>}</div></div>}
   <p className="catalogue-bottom-note"><Info size={15}/> Recipes preserve their quantities and source versions. Open a saved version to review reference-price estimates. Menu pricing and purchase-based costing remain separate milestones.</p>
  </>}
 </WorkspaceShell>;
}
