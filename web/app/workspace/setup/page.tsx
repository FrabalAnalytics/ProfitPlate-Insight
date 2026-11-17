import {DataTable,StatusBadge} from "@/app/components/data-table";
import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { Building2, MapPin, Check, Circle, Users, FileSpreadsheet, ArrowRight } from "lucide-react";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { WorkspaceShell } from "@/app/components/workspace-shell";
import { createClient } from "@/lib/supabase/server";
import { Button } from "@/app/components/ui/button";

export const metadata: Metadata = { title: "Your workspace | ProfitPlate Insight" };
export const instant = false;

const laterStages = [
  ["Users & roles", "Account permissions are checked on the server. Restaurant administrators can invite colleagues and manage scoped roles."],
  ["Materials, units & suppliers", "Build a consistent catalogue of the things you buy."],
  ["Recipes, menu & prices", "Connect what you make to what you sell."],
  ["Sales & procurement mappings", "Import and reconcile purchases and standard paid sales."],
  ["Financial policies & readiness", "Confirm your costing assumptions before reviewing margins."],
];

export default async function WorkspacePage({ searchParams }: { searchParams: Promise<{ message?: string; organisation?: string; welcome?: string }> }) {
  const user = await requireUser();
  const access = await getPlatformAccess();
  if (access !== "member") redirect(workspacePath(access));
  const params = await searchParams;
  const supabase = await createClient();
  const { data: organisations, error } = await supabase.from("organisations")
    .select("id,name,currency_code,country_code,concept").order("name");
  if (error) return <WorkspaceShell email={user.email}><h1 className="workspace-title">Your workspace is temporarily unavailable.</h1><p className="workspace-description">We couldn’t load your business details. Please try again. The platform administrator may need to finish the setup update.</p><a href="/workspace" className="auth-back">Try again</a></WorkspaceShell>;
  if (!organisations?.length) redirect("/onboarding");
  const organisation = params.organisation ? organisations.find(org => org.id === params.organisation) : organisations[0];
  if (!organisation) return <WorkspaceShell email={user.email}><h1 className="workspace-title">This business isn’t available to your account.</h1><p className="workspace-description">Choose a business you have access to.</p><Link className="auth-back" href="/workspace">Return to your workspace</Link></WorkspaceShell>;
  const navigation = await supabase.rpc("workspace_navigation_access", { p_organisation_id: organisation.id });
  if (navigation.error || navigation.data?.team !== true) redirect(`/workspace?organisation=${organisation.id}`);
  const { data: locations, error: locationsError } = await supabase.from("locations")
    .select("id,name,timezone,address,is_active,brand_id").eq("organisation_id", organisation.id).order("name");
  const { data: brands, error: brandsError } = await supabase.from("brands")
    .select("id,name").eq("organisation_id", organisation.id).order("name");
  const savedBasics = !!organisation.concept && !!locations?.length && !!brands?.length;

  return <WorkspaceShell email={user.email} restaurantName={organisation.name} organisationId={organisation.id} sectionLabel="Data & Setup">
    <div className="page-heading-row"><div><p className="eyebrow form-eyebrow">DATA & SETUP</p><h1 className="workspace-title">A strong start for your business.</h1><p className="workspace-description">Your business details are in place. Here’s the path to a reliable financial picture.</p></div>{organisations.length > 1 && <form method="get" className="business-switcher"><label htmlFor="organisation">Business</label><select id="organisation" name="organisation" defaultValue={organisation.id}>{organisations.map(org => <option key={org.id} value={org.id}>{org.name}</option>)}</select><Button variant="outline" type="submit">Switch</Button></form>}</div>
    {params.welcome === "1" && <p className="welcome-message" role="status"><Check size={18} /> Your restaurant workspace is ready. Welcome to ProfitPlate.</p>}
    {params.message === "signout-failed" && <p className="auth-alert" role="alert">We couldn’t sign you out. Please check your connection and try again.</p>}
    <div className="business-summary-grid"><section className="business-card"><div className="summary-card-heading"><span className="summary-icon"><Building2 size={19} /></span><span>Business profile</span></div><h2>{organisation.name}</h2><p>{organisation.country_code} · {organisation.currency_code}</p><small>Reporting currency</small></section><section className="business-card"><div className="summary-card-heading"><span className="summary-icon"><MapPin size={19} /></span><span>Brands & locations</span></div><h2>{brands?.length ?? "—"} {brands?.length === 1 ? "brand" : "brands"} <span> / </span>{locations?.length ?? "—"} {locations?.length === 1 ? "location" : "locations"}</h2><p>{brands?.map(brand => brand.name).join(", ") || "No brands available"}</p><small>Visible within your account’s access</small></section></div>
    {(locationsError || brandsError) && <p className="auth-alert" role="alert">We couldn’t load all of your setup details. Please refresh to try again.</p>}
    <div className="business-work-grid"><section className="setup-checklist"><div className="section-heading"><h2>Your setup journey</h2><span>{savedBasics ? "2" : "0"} OF 7 STAGES READY</span></div><p className="section-description">Complete each stage as its features become available.</p><ol><li><span className={`checklist-dot ${savedBasics ? "complete" : ""}`}>{savedBasics ? <Check size={16} /> : <Circle size={16} />}</span><div><h3>Business profile & concept</h3><p>{savedBasics ? "Your business identity and reporting currency are saved." : "Existing business details may need review during a later setup update."}</p></div><span className="checklist-state">{savedBasics ? "Ready" : "Review needed"}</span></li><li><span className={`checklist-dot ${savedBasics ? "complete" : ""}`}>{savedBasics ? <Check size={16} /> : <Circle size={16} />}</span><div><h3>Brands & locations</h3><p>{locations?.map(location => location.name).join(", ") || "No locations available"}</p></div><span className="checklist-state">{savedBasics ? "Ready" : "Review needed"}</span></li>{laterStages.map(([title, text], index) => <li key={title}><span className="checklist-dot">{index + 3}</span><div><h3>{title}</h3><p>{text}</p>{index === 0 && <Link className="inline-link catalogue-stage-link" href={`/workspace/team?organisation=${organisation.id}`}>Open users & roles <ArrowRight size={14} aria-hidden="true" /></Link>}{index === 1 && <Link className="inline-link catalogue-stage-link" href={`/workspace/materials?organisation=${organisation.id}`}>Open catalogue <ArrowRight size={14} aria-hidden="true" /></Link>}{index === 2 && <Link className="inline-link catalogue-stage-link" href={`/workspace/recipes?organisation=${organisation.id}`}>Open recipes <ArrowRight size={14} aria-hidden="true" /></Link>}{index === 2 && <Link className="inline-link catalogue-stage-link" href={`/workspace/menus?organisation=${organisation.id}`}>Open menu & prices <ArrowRight size={14} aria-hidden="true" /></Link>}{index === 3 && <Link className="inline-link catalogue-stage-link" href={`/workspace/purchases?organisation=${organisation.id}`}>Open purchase imports <ArrowRight size={14} aria-hidden="true" /></Link>}{index === 3 && <Link className="inline-link catalogue-stage-link" href={`/workspace/sales?organisation=${organisation.id}`}>Open sales imports <ArrowRight size={14} aria-hidden="true" /></Link>}</div><span className="checklist-state pending">{index === 3 ? "Imports available" : index === 0 || index === 1 || index === 2 ? "Available" : "Coming next"}</span></li>)}</ol></section><aside className="readiness-card"><span className="summary-icon"><FileSpreadsheet size={21} /></span><h2>Good decisions start with trusted data.</h2><p>Your financial reports will become available as recipes, costs and sales are connected. Missing information will stay visible.</p><div className="readiness-state"><Circle size={12} /><span>Financial data not connected</span></div><div className="owner-access"><Users size={17} /><p>Permissions are checked on the server. You only see the locations available to your account.</p></div></aside></div>
    <section className="location-section"><div className="section-heading"><h2>Your locations</h2><span>{organisation.currency_code} · LOCAL BUSINESS TIME</span></div><DataTable label="Business locations" columns={[{label:"Location"},{label:"Brand"},{label:"Time zone"},{label:"Address"},{label:"Status"}]} rows={(locations??[]).map(location=>({id:location.id,cells:[location.name,brands?.find(brand=>brand.id===location.brand_id)?.name??"Unassigned",location.timezone,location.address||"Not provided",<StatusBadge key="state" tone={location.is_active?"success":"neutral"}>{location.is_active?"Active":"Inactive"}</StatusBadge>]}))} empty="No locations are available."/></section>
  </WorkspaceShell>;
}
