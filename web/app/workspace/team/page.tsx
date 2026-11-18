import {DataTable,StatusBadge} from "@/app/components/data-table";
import type { Metadata } from "next";
import { randomUUID } from "node:crypto";
import Link from "next/link";
import { redirect } from "next/navigation";
import { requireUser,getPlatformAccess,workspacePath } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { roleName,type Assignment,type TeamDirectory } from "@/lib/team";
import { WorkspaceShell } from "@/app/components/workspace-shell";
import { MemberNameForm, InvitationForm,MemberForm,RevokeInvitation } from "./team-forms";
import "../materials/catalogue.css";
import "../purchases/purchases.css";
import "./team.css";

export const metadata:Metadata={title:"Users & roles | ProfitPlate Insight"};
export const instant=false;
type Params={organisation?:string;search?:string;page?:string;invite_page?:string;invite?:string};
export default async function TeamPage({searchParams}:{searchParams:Promise<Params>}) {
 const user=await requireUser(),access=await getPlatformAccess();if(access!=="member")redirect(workspacePath(access));
 const params=await searchParams,client=await createClient();
 const {data:orgs}=await client.from("organisations").select("id,name").order("name");
 const org=params.organisation?orgs?.find(org=>org.id===params.organisation):orgs?.[0];
 if(!org)return <WorkspaceShell email={user.email}><h1 className="workspace-title">This business is unavailable.</h1><Link href="/workspace">Return to workspace</Link></WorkspaceShell>;
 const shell={email:user.email,restaurantName:org.name,organisationId:org.id,sectionLabel:"Users & roles"};
 const permission=await client.rpc("team_access",{p_organisation_id:org.id});
 if(permission.error)return <WorkspaceShell {...shell}><h1 className="workspace-title">Team management is not available yet.</h1><p className="workspace-description">The platform administrator may need to finish the team-access update. Existing permissions remain in place.</p></WorkspaceShell>;
 if(permission.data!==true)return <WorkspaceShell {...shell}><h1 className="workspace-title">Team administration is restricted.</h1><p className="workspace-description">An organisation-wide restaurant administrator manages users and permissions.</p></WorkspaceShell>;
 const page=Math.min(100000,Math.max(1,parseInt(params.page??"1",10)||1)),invitePage=Math.min(100000,Math.max(1,parseInt(params.invite_page??"1",10)||1)),search=(params.search??"").slice(0,120);
 const [directoryResult,locationResult]=await Promise.all([client.rpc("team_directory",{p_organisation_id:org.id,p_search:search,p_page:page,p_invite_page:invitePage}),client.from("locations").select("id,name,is_active").eq("organisation_id",org.id).order("name")]);
 const directory=directoryResult.data as TeamDirectory|null,locations=locationResult.data??[];
 const query=(values:Record<string,string>)=>`/workspace/team?${new URLSearchParams({organisation:org.id,search,page:String(page),invite_page:String(invitePage),...values})}`;
 const grants=(assignments:Assignment[])=>assignments.map(entry=>`${roleName(entry.role_code)} · ${entry.location_name??(entry.location_id?locations.find(l=>l.id===entry.location_id)?.name??"Saved location":"All business locations")}`).join("; ");
 return <WorkspaceShell {...shell}><div className="page-heading-row"><div><p className="eyebrow form-eyebrow">BUSINESS SETUP / TEAM</p><h1 className="workspace-title">Users & roles</h1><p className="workspace-description">Give each colleague the access they need.</p></div>{params.invite!=="1"&&<Link className="auth-button catalogue-add" href={query({invite:"1"})}>Invite colleague</Link>}</div>
  <p className="purchase-help">Invitations expire after 7 days and require the invited, verified email. Share links yourself; no invitation email is sent.</p>
  {params.invite==="1"&&<section className="purchase-panel"><div className="section-heading"><h2>Invite a colleague</h2><Link className="record-edit" href={query({})}>Close</Link></div><InvitationForm organisation={org.id} request={randomUUID()} locations={locations}/><details className="workspace-disclosure"><summary>Understand the roles</summary><p>Permissions from multiple roles combine. Organisation-wide Restaurant Administrators can manage the team. CEO and Finance are read-only in the current configuration screens. Location scopes restrict access; business-wide modules remain unavailable to scoped-only staff.</p></details></section>}
  {directoryResult.error||!directory?<p className="auth-alert" role="alert">Team details could not be loaded. Refresh and try again.</p>:<>
  <section className="purchase-panel"><div className="section-heading"><h2>Team members</h2><span>{directory.member_total} accounts</span></div><form className="catalogue-filter" method="get"><input type="hidden" name="organisation" value={org.id}/><div><input name="search" type="search" aria-label="Search team by email" placeholder="Search by email" defaultValue={search} maxLength={120}/></div><button className="secondary-button">Search</button></form>
   <div className="team-list"><DataTable label="Team members" columns={[{label:"Member"},{label:"Roles / location scopes"},{label:"Status"},{label:"Access management"}]} rows={directory.members.map(member=>({id:member.id,cells:[<span key="member">{member.display_name||member.email}<small>{member.display_name?member.email+" / ":""}{member.is_owner?"Business owner":member.is_self?"Your account":"Team member"}</small></span>,<div key="roles">{grants(member.assignments)}<details><summary>Edit name</summary><MemberNameForm organisation={org.id} member={member}/></details></div>,<StatusBadge key="state" tone={member.status==="active"?"success":"neutral"}>{member.status==="active"?"Active":"Inactive"}</StatusBadge>,member.is_owner||member.is_self?<span key="protected">{member.is_owner?"Owner permissions are protected.":"Another administrator must manage your access."}</span>:<details key="manage" className="workspace-disclosure team-access-editor"><summary>Manage access for {member.email}</summary><MemberForm organisation={org.id} member={member} locations={locations}/></details>]}))} empty="No team members match this search."/></div>
   <div className="catalogue-pagination"><p>Page {page}</p><div>{page>1&&<Link href={query({page:String(page-1)})}>Previous members</Link>}{page*25<directory.member_total&&<Link href={query({page:String(page+1)})}>Next members</Link>}</div></div>
  </section><section className="purchase-panel"><div className="section-heading"><h2>Invitation history</h2><span>{directory.invitation_total} invitations</span></div><DataTable label="Team invitation history" columns={[{label:"Invited email"},{label:"Roles / location scopes"},{label:"Status"},{label:"Created"},{label:"Expires"},{label:"Action"}]} rows={directory.invitations.map(invite=>({id:invite.id,cells:[invite.email,grants(invite.assignments),<StatusBadge key="status" tone={invite.state==="ACCEPTED"?"success":invite.state==="PENDING"?"warning":"neutral"}>{invite.state}</StatusBadge>,invite.created_at.slice(0,10),invite.expires_at.slice(0,10),invite.state==="PENDING"?<RevokeInvitation key="revoke" organisation={org.id} id={invite.id}/>:"Not applicable"]}))} empty="No invitations yet."/><div className="catalogue-pagination"><p>Page {invitePage}</p><div>{invitePage>1&&<Link href={query({invite_page:String(invitePage-1)})}>Previous invitations</Link>}{invitePage*25<directory.invitation_total&&<Link href={query({invite_page:String(invitePage+1)})}>Next invitations</Link>}</div></div></section></>}
 </WorkspaceShell>;
}
