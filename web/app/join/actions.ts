"use server";
import { cookies,headers } from "next/headers";
import { redirect } from "next/navigation";
import { requireUser,getPlatformAccess } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import {isUuid} from "@/lib/catalogue";
import { invitationCookie,validInvitationToken,type TeamState } from "@/lib/team";

export async function rememberInvitation(_state:TeamState,form:FormData):Promise<TeamState> {
 const token=String(form.get("token")??"");
 if(!validInvitationToken(token))return {error:"This invitation link is incomplete. Ask the administrator for a new link."};
 const requestHeaders=await headers();
 const secure=requestHeaders.get("x-forwarded-proto")==="https" || requestHeaders.get("origin")?.startsWith("https://")===true;
 (await cookies()).set(invitationCookie,token,{httpOnly:true,sameSite:"lax",secure,path:"/",maxAge:7*24*60*60});
 redirect("/join");
}
export async function acceptInvitation(_state:TeamState,form:FormData):Promise<TeamState> {
 await requireUser();
 if(!["member","inactive"].includes(await getPlatformAccess()))return {error:"Platform administrator accounts cannot accept restaurant team invitations."};
 if(form.get("confirm")!=="on")return {error:"Review and confirm the business and permissions before joining."};
 const jar=await cookies(),token=jar.get(invitationCookie)?.value??"";
 const invitation=String(form.get("invitation")??"");
 if(!isUuid(invitation)&&!validInvitationToken(token))return {error:"Open your invitation or sign in to review pending invitations."};
 const client=await createClient();
 const password=String(form.get("password")??""),confirmation=String(form.get("confirmPassword")??"");
 if(password||confirmation){if(password.length<8||password!==confirmation)return {error:"Use at least 8 characters and matching passwords."};const saved=await client.auth.updateUser({password});if(saved.error)return {error:"Your password could not be saved. Try another password or leave it blank to join first."};}
 const result=isUuid(invitation)?await client.rpc("accept_pending_team_invitation",{p_invitation_id:invitation}):await client.rpc("accept_team_invitation",{p_token:token});
 if(result.error)return {error:result.error.code==="22023"?result.error.message:"The invitation could not be accepted. Try again shortly."};
 jar.delete(invitationCookie);
 redirect(`/workspace?organisation=${result.data}`);
}
export async function clearInvitation() {
 (await cookies()).delete(invitationCookie);redirect("/join");
}
