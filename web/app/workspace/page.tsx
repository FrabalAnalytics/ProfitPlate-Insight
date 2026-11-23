import {OperationsWorkspace} from "@/app/components/operations-workspace";
import {CurrentStockCard} from "@/app/components/current-stock-card";
import {WeeklyCountStatus,type WeeklyWorkspacePacket} from '@/app/components/weekly-count-status';
import {ManagementReviewLinks} from '@/app/components/management-review-links';
import type {WasteWorkspacePacket} from "@/lib/waste-accountability";
import {pendingTeamInvitations} from "@/lib/team-invitation-server";
import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { ArrowRight } from "lucide-react";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { WorkspaceShell } from "@/app/components/workspace-shell";
import { Button } from "@/app/components/ui/button";
import {MemberNameForm} from "./team/team-forms";
import { roleName } from "@/lib/team";
import type { NavigationAccess } from "@/lib/overview";
import { workspaceHome } from "@/lib/workspace-home";
import {NeedsAttention} from "@/app/components/needs-attention";
import type {AttentionPacket} from "@/lib/workspace-attention";
import { ExecutiveBriefing } from "@/app/components/executive-briefing";
import "./workspace-home.css";

export const metadata: Metadata = { title: "Your workspace | ProfitPlate Insights" };
export const instant = false;

export default async function WorkspacePage({ searchParams }: { searchParams: Promise<{ organisation?: string; message?: string;from?:string;to?:string;location?:string }> }) {
  const user = await requireUser();
  const access = await getPlatformAccess();
  if (access !== "member") redirect(workspacePath(access));
  const params = await searchParams;
  const client = await createClient();
  const organisations = await client.from("organisations").select("id,name,time_zone,currency_code").order("name").order("id");
  if (organisations.error) return <WorkspaceShell email={user.email}><h1 className="workspace-title">Your workspace is temporarily unavailable.</h1><p>Please refresh to try again.</p></WorkspaceShell>;
  if (!organisations.data?.length){const pending=await pendingTeamInvitations();if(pending.invitations.length)redirect("/join");if(pending.error)return <WorkspaceShell email={user.email}><h1>Team invitations could not be loaded.</h1><p>Refresh to try again.</p></WorkspaceShell>;redirect("/onboarding");}
  const org = params.organisation ? organisations.data.find(item => item.id === params.organisation) : organisations.data[0];
  if (!org) return <WorkspaceShell email={user.email}><h1 className="workspace-title">This business isn’t available to your account.</h1><Link href="/workspace">Return to your workspace</Link></WorkspaceShell>;
  const membership = await client.from("organisation_memberships").select("id,display_name").eq("organisation_id", org.id).eq("user_id", user.id).eq("status", "active").maybeSingle();
  const [roles, navigation, locations] = await Promise.all([
    membership.data ? client.from("membership_roles").select("role_code,location_id").eq("organisation_id", org.id).eq("membership_id", membership.data.id) : Promise.resolve({data: null, error: new Error("Membership unavailable")}),
    client.rpc("workspace_navigation_access", {p_organisation_id: org.id}),
    client.from("locations").select("id,name").eq("organisation_id", org.id),
  ]);
  const shell = { email: user.email, restaurantName: org.name, organisationId: org.id, sectionLabel: "Your workspace" };
  if (membership.error || roles.error || !roles.data?.length || navigation.error || !navigation.data) return <WorkspaceShell {...shell}><h1 className="workspace-title">Your workspace access couldn’t be loaded.</h1><p className="workspace-description">Refresh to try again. If this continues, ask your restaurant administrator to check your assigned roles.</p></WorkspaceShell>;
  const home = workspaceHome(roles.data, navigation.data as NavigationAccess);
  const executive=roles.data.some(r=>r.role_code==="ceo"&&r.location_id===null)&&(navigation.data as NavigationAccess).overview;
  const operations=!executive&&roles.data.some(r=>r.role_code==="operations");
  const Greeting=executive?"h1":"p";
  const parts=new Intl.DateTimeFormat("en",{timeZone:org.time_zone,year:"numeric",month:"2-digit",day:"2-digit"}).formatToParts(new Date());
  const today=["year","month","day"].map(key=>parts.find(p=>p.type===key)?.value).join("-");
  const attention=!executive&&!operations?await client.rpc("workspace_attention",{p_organisation_id:org.id,p_queue:null,p_page:1}):null;
  const [salesStock,waste,weekly,monthly]=await Promise.all([client.rpc("sales_stock_queue",{p_organisation_id:org.id,p_state:"PENDING",p_page:1}),client.rpc("waste_compliance_workspace",{p_organisation_id:org.id}),client.rpc("weekly_counts_workspace",{p_organisation_id:org.id}),client.rpc("monthly_counts_workspace",{p_organisation_id:org.id})]);
  return <WorkspaceShell {...shell}><div className={executive?"owner-workspace":undefined}>
    <div className="page-heading-row"><div><Greeting className="workspace-greeting">{(()=>{const hour=Number(new Intl.DateTimeFormat("en-GB",{timeZone:org.time_zone,hour:"numeric",hourCycle:"h23"}).format(new Date()));return `${hour<12?"Good morning":hour<18?"Good afternoon":"Good evening"}${membership.data?.display_name?", "+membership.data.display_name:""}.`;})()}</Greeting>{!executive&&<h1 className="workspace-title">{home.title}</h1>}</div>{organisations.data.length > 1 && <form method="get" className="business-switcher"><label htmlFor="organisation">Business</label><select id="organisation" name="organisation" defaultValue={org.id}>{organisations.data.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select><Button variant="outline" type="submit">Switch</Button></form>}</div>
    <ManagementReviewLinks org={org.id} roles={roles.data.map(r=>r.role_code)}/>
    {!!salesStock.data?.pending&&<p className="auth-alert"><Link href={`/workspace/inventory/sales-consumption?organisation=${org.id}`}>{salesStock.data.pending} sales consumption records need attention</Link>. Stock balances are incomplete until these are resolved.</p>}
    {!membership.data?.display_name&&<details className="workspace-access-disclosure"><summary>Set the name shown in your workspace</summary><MemberNameForm organisation={org.id} member={{id:membership.data!.id,display_name:""}}/></details>}
    {params.message === "signout-failed" && <p className="auth-alert" role="alert">We couldn’t sign you out. Please check your connection and try again.</p>}
    {!executive&&!operations&&(navigation.data as NavigationAccess).inventory&&<CurrentStockCard org={org.id} timeZone={org.time_zone}/>}
    {!executive&&!operations&&<NeedsAttention organisation={org.id} packet={attention?.data as AttentionPacket|null} error={!!attention?.error} waste={waste.data as WasteWorkspacePacket|null} wasteError={!!waste.error} extraPending={!!monthly.error||!!monthly.data?.backlog||!!monthly.data?.review_waiting||!!monthly.data?.posting_waiting||!!monthly.data?.rows?.some((r:{state:string})=>['NOT_STARTED','DRAFT'].includes(r.state))||!!weekly.error||!!weekly.data?.backlog||!!weekly.data?.review_waiting||!!weekly.data?.posting_waiting||!!weekly.data?.rows?.some((r:{state:string})=>['NOT_STARTED','DRAFT'].includes(r.state))}/>}
    {!executive&&!operations&&<WeeklyCountStatus organisation={org.id} packet={weekly.data as WeeklyWorkspacePacket|null} error={!!weekly.error}/>}
    {!executive&&!operations&&<WeeklyCountStatus monthly organisation={org.id} packet={monthly.data as WeeklyWorkspacePacket|null} error={!!monthly.error}/>}
    {operations?<OperationsWorkspace organisation={org.id} timeZone={org.time_zone} currency={org.currency_code} waste={waste.data as WasteWorkspacePacket|null} weekly={weekly.data as WeeklyWorkspacePacket|null} wasteError={!!waste.error} weeklyError={!!weekly.error} monthly={monthly.data as WeeklyWorkspacePacket|null} monthlyError={!!monthly.error}/>:executive?<>
      <ExecutiveBriefing organisation={org.id} from={params.from??`${today.slice(0,7)}-01`} to={params.to??today} location={params.location??""} today={today} timeZone={org.time_zone} locations={locations.data??[]} waste={waste.data as WasteWorkspacePacket|null} weekly={weekly.data as WeeklyWorkspacePacket|null} wasteError={!!waste.error} weeklyError={!!weekly.error} monthly={monthly.data as WeeklyWorkspacePacket|null} monthlyError={!!monthly.error}/>
      <nav className="management-overview-actions" aria-label="Executive reporting links">{home.tasks.map(task=><Link className="secondary-button" key={task.path} href={`${task.path}?organisation=${org.id}&${new URLSearchParams({from:params.from??`${today.slice(0,7)}-01`,to:params.to??today,...(params.location?{location:params.location}:{})})}`}>{task.action} <ArrowRight size={14} aria-hidden="true"/></Link>)}</nav>
      <details className="executive-access"><summary>Your assigned access</summary><p>{roles.data.map(role=>roleName(role.role_code)).join(" · ")}. Other assigned responsibilities remain available through navigation.</p></details>
    </>:<>
    <details className="workspace-access-disclosure"><summary>Your assigned access</summary><h2>Your access at {org.name}</h2>{roles.data.map((role, index) => <p key={index}>{roleName(role.role_code)} · {role.location_id ? locations.data?.find(location => location.id === role.location_id)?.name ?? "Assigned location" : "All business locations"}</p>)}</details>
    <section className="location-section"><div className="section-heading"><h2>Your daily work</h2></div><nav className="workspace-home-tasks" aria-label="Daily work shortcuts">{home.tasks.slice(0,6).map(task => <Link key={task.path} href={`${task.path}${task.path.includes("?") ? "&" : "?"}organisation=${org.id}`}>{task.action}<ArrowRight size={16} aria-hidden="true" /></Link>)}</nav>{home.tasks.length>6&&<details className="workspace-access-disclosure"><summary>More records &amp; tools</summary><nav className="workspace-home-tasks" aria-label="Additional workspace tools">{home.tasks.slice(6).map(task=><Link key={task.path} href={`${task.path}${task.path.includes("?")?"&":"?"}organisation=${org.id}`}>{task.action}<ArrowRight size={16} aria-hidden="true"/></Link>)}</nav></details>}{!home.tasks.length && <p className="workspace-description">No shortcuts available. Ask your administrator to check your access.</p>}</section>
    </>}
  </div></WorkspaceShell>;
}
