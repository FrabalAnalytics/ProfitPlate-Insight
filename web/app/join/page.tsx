import {pendingTeamInvitations} from "@/lib/team-invitation-server";
import type { Metadata } from "next";
import Link from "next/link";
import { cookies } from "next/headers";
import { getUser } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { invitationCookie,roleName,type Assignment } from "@/lib/team";
import { Brand } from "@/app/components/brand";
import { InvitationCapture,AcceptInvitationForm } from "./join-forms";
import { clearInvitation } from "./actions";
import { signOut } from "@/app/auth/actions";
import "../workspace/team/team.css";
export const instant=false;
export const metadata:Metadata={title:"Join your restaurant team | ProfitPlate Insight",robots:{index:false,follow:false},referrer:"no-referrer"};
export default async function JoinPage() {
 const token=(await cookies()).get(invitationCookie)?.value,user=await getUser();
 const pending=user?await pendingTeamInvitations():{invitations:[],error:null};
 const result=token&&user?await (await createClient()).rpc("inspect_team_invitation",{p_token:token}):null;
 const invitation=result?.data as {organisation_name:string;email:string;assignments:Assignment[];expires_at:string;stock_centres?:string[]}|null;
 return <main className="join-card"><Brand/><InvitationCapture>{(!token||!invitation)&&user&&pending.invitations.length?<><h1>Your team invitation{pending.invitations.length>1?"s":""}</h1>{pending.invitations.map(invite=><section key={invite.id} className="join-pending"><h2>Join {invite.organisation_name}</h2><p>{invite.email}</p><ul>{invite.assignments.map((a,index)=><li key={index}>{roleName(a.role_code)}</li>)}</ul>{!!invite.stock_centres?.length&&<p><strong>Stock centres:</strong> {invite.stock_centres.join(", ")}</p>}<AcceptInvitationForm invitation={invite.id} emailLink/></section>)}</>:!token&&user&&pending.error?<><h1>Invitations could not be loaded.</h1><p>Refresh to try again. Your restaurant access has not changed.</p></>:!token?<><h1>Join your restaurant team</h1><p>Open the complete invitation link shared by your restaurant administrator.</p>{user?<Link href="/dashboard" className="inline-link">Open my workspace</Link>:<Link href="/login" className="inline-link">Sign in</Link>}</>:!user?<><h1>Sign in to review your invitation</h1><p>Use the email address your administrator invited. Your account’s email must be verified before joining.</p><div className="join-actions"><Link className="auth-button" href="/login">Sign in</Link><Link className="secondary-button" href="/signup">Create an account</Link></div></>:invitation?<><h1>Join {invitation.organisation_name}</h1><p>Invited email: <strong>{invitation.email}</strong></p><ul>{invitation.assignments.map((assignment,index)=><li key={index}>{roleName(assignment.role_code)} · {assignment.location_name??"All business locations"}</li>)}</ul>{invitation.assignments.some(a=>a.location_id)&&<p>Each location-scoped role applies only to its selected location. Organisation-wide roles still grant their own business-wide permissions.</p>}{!!invitation.stock_centres?.length&&<p><strong>Stock centres:</strong> {invitation.stock_centres.join(", ")}</p>}<p>Expires {invitation.expires_at.slice(0,10)}. Accepting adds this business to your account.</p><AcceptInvitationForm/></>:<><h1>Invitation unavailable</h1><p>This link may be expired, revoked or intended for a different verified email. Signed in as {user.email}. Ask the restaurant administrator to check the invitation.</p><form action={signOut}><button className="secondary-button">Sign out to use another account</button></form></>}{token&&<form action={clearInvitation}><button className="secondary-button">Discard invitation</button></form>}</InvitationCapture></main>;
}
