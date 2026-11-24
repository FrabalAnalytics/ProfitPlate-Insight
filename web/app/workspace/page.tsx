import {type WeeklyWorkspacePacket} from '@/app/components/weekly-count-status';
import type {WasteWorkspacePacket} from "@/lib/waste-accountability";
import {pendingTeamInvitations} from "@/lib/team-invitation-server";
import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { WorkspaceShell } from "@/app/components/workspace-shell";
import { Button } from "@/app/components/ui/button";
import {MemberNameForm} from "./team/team-forms";
import type { NavigationAccess } from "@/lib/overview";
import { workspaceHome } from "@/lib/workspace-home";
import type {AttentionPacket} from "@/lib/workspace-attention";
import "./workspace-home.css";
import {WorkspaceWelcome} from "@/app/components/workspace-welcome";
import "./welcome.css";

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
  const [roles, navigation] = await Promise.all([
    membership.data ? client.from("membership_roles").select("role_code,location_id").eq("organisation_id", org.id).eq("membership_id", membership.data.id) : Promise.resolve({data: null, error: new Error("Membership unavailable")}),
    client.rpc("workspace_navigation_access", {p_organisation_id: org.id}),
  ]);
  const shell = { email: user.email, restaurantName: org.name, organisationId: org.id, sectionLabel: "Your workspace" };
  if (membership.error || roles.error || !roles.data?.length || navigation.error || !navigation.data) return <WorkspaceShell {...shell}><h1 className="workspace-title">Your workspace access couldn’t be loaded.</h1><p className="workspace-description">Refresh to try again. If this continues, ask your restaurant administrator to check your assigned roles.</p></WorkspaceShell>;
  const home = workspaceHome(roles.data, navigation.data as NavigationAccess);
  const executive=roles.data.some(r=>r.role_code==="ceo"&&r.location_id===null)&&(navigation.data as NavigationAccess).overview;
  const operations=!executive&&roles.data.some(r=>r.role_code==="operations");
  const parts=new Intl.DateTimeFormat("en",{timeZone:org.time_zone,year:"numeric",month:"2-digit",day:"2-digit"}).formatToParts(new Date());
  const today=["year","month","day"].map(key=>parts.find(p=>p.type===key)?.value).join("-");
  const attention=!executive&&!operations?await client.rpc("workspace_attention",{p_organisation_id:org.id,p_queue:null,p_page:1}):null;
  const [salesStock,waste,weekly,monthly]=await Promise.all([client.rpc("sales_stock_queue",{p_organisation_id:org.id,p_state:"PENDING",p_page:1}),client.rpc("waste_compliance_workspace",{p_organisation_id:org.id}),client.rpc("weekly_counts_workspace",{p_organisation_id:org.id}),client.rpc("monthly_counts_workspace",{p_organisation_id:org.id})]);
  return <WorkspaceShell {...shell}>
    <div className="welcome-page">
      <header className="welcome-header"><div><h1 className="welcome-greeting">{(()=>{const hour=Number(new Intl.DateTimeFormat("en-GB",{timeZone:org.time_zone,hour:"numeric",hourCycle:"h23"}).format(new Date()));return `${hour<12?"Good morning":hour<18?"Good afternoon":"Good evening"}${membership.data?.display_name?", "+membership.data.display_name:""}.`;})()}</h1><p className="welcome-role">{home.title} <span aria-hidden="true">/</span> {org.name}</p></div>{organisations.data.length > 1 && <form method="get" className="business-switcher"><label htmlFor="organisation">Business</label><select id="organisation" name="organisation" defaultValue={org.id}>{organisations.data.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select><Button variant="outline" type="submit">Switch</Button></form>}</header>
      {!membership.data?.display_name&&<details className="welcome-name"><summary>Add your name</summary><MemberNameForm organisation={org.id} member={{id:membership.data!.id,display_name:""}}/></details>}
      {params.message === "signout-failed" && <p className="auth-alert" role="alert">We could not sign you out. Please try again.</p>}
      <WorkspaceWelcome organisation={org.id} roles={roles.data} navigation={navigation.data as NavigationAccess} timeZone={org.time_zone} today={today} currency={org.currency_code} from={params.from??`${today.slice(0,7)}-01`} to={params.to??today} location={params.location??""} executive={!!executive} operations={operations} attention={attention?.data as AttentionPacket|null} attentionError={!!attention?.error} waste={waste.data as WasteWorkspacePacket|null} wasteError={!!waste.error&&waste.error.code!=="42501"} weekly={weekly.data as WeeklyWorkspacePacket|null} weeklyError={!!weekly.error&&weekly.error.code!=="42501"} monthly={monthly.data as WeeklyWorkspacePacket|null} monthlyError={!!monthly.error&&monthly.error.code!=="42501"} salesPending={salesStock.data?.pending??0} salesError={!!salesStock.error&&salesStock.error.code!=="42501"}/>
    </div>
  </WorkspaceShell>;
}
