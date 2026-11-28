import { randomUUID } from "node:crypto";
import Link from "next/link";
import { redirect } from "next/navigation";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { WorkspaceShell } from "@/app/components/workspace-shell";
import { workspacePolicy } from "@/lib/workspace-policy-server";
import { MasterImportForm } from "./form";
import "../materials/catalogue.css";
import "../menus/menus.css";
import "./imports.css";

export const instant = false;
export default async function Page({ searchParams }: { searchParams: Promise<{ organisation?: string; kind?: string }> }) {
 const user = await requireUser(), access = await getPlatformAccess(); if (access !== "member") redirect(workspacePath(access));
 const p = await searchParams, kind = p.kind === "RECIPE" ? "RECIPE" : "MATERIAL", client = await createClient();
 const orgs = await client.from("organisations").select("id,name").order("name");
 const org = p.organisation ? orgs.data?.find(o => o.id === p.organisation) : orgs.data?.[0]; if (!org) redirect("/workspace");
 const permission = await client.rpc(kind === "MATERIAL" ? "can_manage_catalogue" : "can_manage_recipes", { p_organisation_id: org.id });
 if (permission.data !== true) redirect(`/workspace?organisation=${org.id}`);
 const locations = await client.from("locations").select("id,name").eq("organisation_id", org.id).eq("is_active", true).order("name");
 const canSetUpCentres = kind === "MATERIAL" && (await workspacePolicy(org.id)).canStockSetup;
 const title = kind === "MATERIAL" ? "Import materials" : "Import recipes";
 return <WorkspaceShell email={user.email} restaurantName={org.name} organisationId={org.id} sectionLabel={title}><Link className="catalogue-back" href={`/workspace/${kind === "MATERIAL" ? "materials" : "recipes"}?organisation=${org.id}`}>Back to {kind === "MATERIAL" ? "materials" : "recipes"}</Link><h1 className="workspace-title">{title}</h1><p className="workspace-description">{kind === "MATERIAL" ? "Load materials, known last purchase prices and centre openings together." : "Load sub-recipes and final recipes together. Dependencies are resolved before publishing."}</p>
 {kind === "MATERIAL" && <section className="import-prerequisite" aria-label="Opening stock prerequisite"><div><h2>Before adding opening stock</h2><p>Create your stock centres first, then use their codes in the template. Materials and purchase prices can be imported now with the three opening-stock fields left blank.</p></div>{canSetUpCentres ? <Link className="secondary-button" href={`/workspace/setup/centres?organisation=${org.id}`}>Set up stock centres</Link> : <p>Ask your administrator to create centres and share their codes.</p>}</section>}
 <nav className="import-actions" aria-label="Import stages"><Link href={`/workspace/imports?organisation=${org.id}&kind=MATERIAL`}>1. Materials</Link><Link href={`/workspace/imports?organisation=${org.id}&kind=RECIPE`}>2. Recipes</Link><Link href={`/workspace/menus/import?organisation=${org.id}`}>3. Selling menu</Link></nav>
 <section className="menu-panel"><div className="import-template-actions"><a className="secondary-button" href={`/templates/${kind === "MATERIAL" ? "material-master" : "recipe-components"}-import.csv`} download>Download {kind === "MATERIAL" ? "material" : "recipe"} CSV template</a><a className="secondary-button" href={`/templates/${kind === "MATERIAL" ? "material-master" : "recipe-components"}-import.xlsx`} download>Download Excel template</a>{kind === "MATERIAL" && <a className="inline-link" href="/guides/material-naming.html" target="_blank" rel="noopener noreferrer">Material naming guide</a>}</div><details className="import-guide"><summary>How to prepare your file</summary>{kind === "MATERIAL" ? <><p>Use CREATE for new codes or UPDATE for existing active materials. Base units stay fixed after creation. Type, category, tracking and processing flags are included on each row.</p><p>Last purchase price is per base unit, with its date. It becomes a reference estimate, not an invoice. Leave both fields blank if unknown; processed-only SKUs get their cost from their linked recipe.</p><p>Opening quantities are in the base unit. Repeat identical material details for each centre, changing only centre code, quantity and opening date. Enter 0 for a verified zero; blank means unknown. Administrators can prepare openings for Inventory review, approval and posting.</p></> : <><p>Use one row per ingredient or sub-recipe component. Repeat the recipe header on each row. Use ITEM for material codes and RECIPE for sub-recipe codes. Maximum 50 recipes, 100 components per recipe and 500 rows per file.</p><p>CREATE adds a recipe. NEW_VERSION publishes a replacement version while preserving history. Files can contain nested sub-recipes and final recipes in any row order. Cycles and missing components stop the import.</p><p>Leave component_version blank to pin the latest sub-recipe effective by the parent date, including a child imported in the same file. Enter a version to pin it explicitly. Stock-output links and processing baselines remain separate setup steps.</p></>}<p>Use UTF-8 CSV under 256 KB, or a single-sheet XLSX under 512 KB with plain values. Dates: YYYY-MM-DD. No thousands separators. Your selected availability applies to the whole batch. Manual entry remains available.</p></details></section>
 {locations.error ? <p role="alert">Locations could not be loaded. Please refresh.</p> : <MasterImportForm key={`${org.id}:${kind}`} organisation={org.id} request={randomUUID()} kind={kind} locations={locations.data ?? []}/>}</WorkspaceShell>;
}
