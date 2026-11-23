import {DataTable,StatusBadge} from "@/app/components/data-table";
import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { Building2, MapPin, Check, ArrowRight } from "lucide-react";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { WorkspaceShell } from "@/app/components/workspace-shell";
import { createClient } from "@/lib/supabase/server";
import { Button } from "@/app/components/ui/button";
import "./setup.css";

export const metadata: Metadata = { title: "Your workspace | ProfitPlate Insights" };
export const instant = false;

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
  const setupResult=await supabase.rpc("setup_workspace",{p_organisation_id:organisation.id});
  const progress=setupResult.data?.progress as {completed:number;total:number;stages:{name:string;ready:boolean;path:string;detail:string}[]}|undefined;


  const stageOrder = ["Business & locations", "Reporting calendar", "Users & roles", "Stock centres", "Suppliers", "Materials, prices & opening stock", "Processing baselines", "Recipes", "Food & beverage targets", "Menu mapping & selling prices"];
  const stages = [...(progress?.stages ?? [])].sort((a, b) => {
    const rank = (name: string) => { const index = stageOrder.indexOf(name); return index < 0 ? stageOrder.length : index; };
    return rank(a.name) - rank(b.name);
  });
  const tools = [
    ["Centres & team access", "centres"], ["Reporting calendar & targets", "standards"],
    ["Menu categories", "categories"], ["Expense categories", "expenses"],
    ["Sales channels", "channels"], ["Processed material setup", "production"],
  ];

  return <WorkspaceShell email={user.email} restaurantName={organisation.name} organisationId={organisation.id} sectionLabel="Data & Setup">
    <div className="page-heading-row"><div><p className="eyebrow form-eyebrow">DATA & SETUP</p><h1 className="workspace-title">Data & Setup</h1><p className="workspace-description">Manage your restaurant data and access.</p></div>{organisations.length > 1 && <form method="get" className="business-switcher"><label htmlFor="organisation">Business</label><select id="organisation" name="organisation" defaultValue={organisation.id}>{organisations.map(org => <option key={org.id} value={org.id}>{org.name}</option>)}</select><Button variant="outline" type="submit">Switch</Button></form>}</div>
    {params.welcome === "1" && <p className="welcome-message" role="status"><Check size={18} /> Your restaurant workspace is ready. Welcome to ProfitPlate.</p>}
    {params.message === "signout-failed" && <p className="auth-alert" role="alert">We couldn’t sign you out. Please check your connection and try again.</p>}
    <div className="business-summary-grid"><section className="business-card"><div className="summary-card-heading"><span className="summary-icon"><Building2 size={19} /></span><span>Business profile</span></div><h2>{organisation.name}</h2><p>{organisation.country_code} · {organisation.currency_code}</p><small>Reporting currency</small></section><section className="business-card"><div className="summary-card-heading"><span className="summary-icon"><MapPin size={19} /></span><span>Brands & locations</span></div><h2>{brands?.length ?? "—"} {brands?.length === 1 ? "brand" : "brands"} <span> / </span>{locations?.length ?? "—"} {locations?.length === 1 ? "location" : "locations"}</h2><p>{brands?.map(brand => brand.name).join(", ") || "No brands available"}</p><small>Visible within your account’s access</small></section></div>
    {(locationsError || brandsError) && <p className="auth-alert" role="alert">We couldn’t load all of your setup details. Please refresh to try again.</p>}
    <nav className="setup-tools" aria-label="Setup tools">{tools.map(([label, path]) => <Link key={path} href={`/workspace/setup/${path}?organisation=${organisation.id}`}>{label}<ArrowRight size={15} aria-hidden="true"/></Link>)}</nav>
    <section className="setup-checklist" aria-label="Your setup journey"><div className="section-heading"><h2>Your setup journey</h2><span>{progress?`${progress.completed} OF ${progress.total} STAGES READY`:"Setup status unavailable"}</span></div>{progress?<ol>{stages.map((stage,i)=><li key={stage.name}><span className={`checklist-dot ${stage.ready?'complete':''}`}>{stage.ready?<Check size={16}/>:i+1}</span><div><h3>{stage.name}</h3><p>{stage.name === "Stock centres" ? "Create centres and assign responsible members before importing opening stock." : stage.detail}</p><Link className="inline-link" href={`${stage.path}?organisation=${organisation.id}`}>Open {stage.name.toLowerCase()} <ArrowRight size={14}/></Link></div><span className={`checklist-state ${stage.ready ? "" : "pending"}`}>{stage.ready?'Ready':'Incomplete'}</span></li>)}</ol>:<p role="alert">Setup progress is unavailable. Refresh or contact platform support.</p>}</section>

    <section className="location-section"><div className="section-heading"><h2>Your locations</h2><span>{organisation.currency_code} · LOCAL BUSINESS TIME</span></div><DataTable label="Business locations" columns={[{label:"Location"},{label:"Brand"},{label:"Time zone"},{label:"Address"},{label:"Status"}]} rows={(locations??[]).map(location=>({id:location.id,cells:[location.name,brands?.find(brand=>brand.id===location.brand_id)?.name??"Unassigned",location.timezone,location.address||"Not provided",<StatusBadge key="state" tone={location.is_active?"success":"neutral"}>{location.is_active?"Active":"Inactive"}</StatusBadge>]}))} empty="No locations are available."/></section>
  </WorkspaceShell>;
}
