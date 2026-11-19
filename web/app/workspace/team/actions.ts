"use server";

import { revalidatePath } from "next/cache";
import { requireUser, getPlatformAccess } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { isUuid } from "@/lib/catalogue";
import {createClient as createEmailClient} from "@supabase/supabase-js";
import {getSupabaseConfig} from "@/lib/supabase/config";
import {siteUrl} from "@/lib/site-url";
import type { TeamState } from "@/lib/team";

async function teamClient(form: FormData) {
 await requireUser();
 if (await getPlatformAccess() !== "member") throw new Error("Restaurant administrator access is required.");
 const org = String(form.get("organisation") ?? "");
 if (!isUuid(org)) throw new Error("Choose an available business.");
 const client = await createClient();
 const permission = await client.rpc("team_access",{p_organisation_id:org});
 if (permission.error || permission.data !== true) throw new Error("Team administration is restricted.");
 return {client,org};
}
function assignments(form: FormData) {
 const text=String(form.get("assignments")??"");
 if(text.length>8192) throw new Error("Use at most 20 role assignments.");
 const input=JSON.parse(text);
 if(!Array.isArray(input)||input.length<1||input.length>20) throw new Error("Choose between 1 and 20 role assignments.");
 return input;
}
const failure = (error: unknown): TeamState => ({error:error instanceof Error ? error.message : "Team access could not be updated. Try again."});
export async function inviteTeam(_state:TeamState,form:FormData):Promise<TeamState> {
 try {
  if(form.get("confirm")!=="on") throw new Error("Review and confirm the invitation permissions.");
  const {client,org}=await teamClient(form), request=String(form.get("request")??"");
  if(!isUuid(request)) throw new Error("Refresh and try again.");
  const email=String(form.get("email")??"").trim();
  const result=await client.rpc("invite_team_member_with_centres",{p_organisation_id:org,p_request_id:request,p_email:email,p_name:String(form.get("display_name")??"").trim(),p_assignments:assignments(form),p_stock_access:stockAccess(form)});
  if(result.error) return {error:result.error.code==="22023"?result.error.message:"We could not create this invitation. Check your access and try again."};
  revalidatePath("/workspace/team");
  if(!result.data.token)return {success:"This invitation already exists. Resend its email from invitation history, or revoke it to generate a new shareable link."};
  const delivery=await sendInvitationEmail(client,org,result.data.id);
  return {token:result.data.token,expires:result.data.expires_at,...delivery};
 } catch(error) {return failure(error);}
}
export async function updateTeam(_state:TeamState,form:FormData):Promise<TeamState> {
 try {
  if(form.get("confirm")!=="on") throw new Error("Review and confirm the access change.");
  const {client,org}=await teamClient(form), member=String(form.get("member")??"");
  if(!isUuid(member)) throw new Error("Choose an available member.");
  const result=await client.rpc("update_team_member",{p_organisation_id:org,p_membership_id:member,p_expected_updated_at:String(form.get("updated")??""),p_active:form.get("active")==="true",p_assignments:form.get("active")==="true"?assignments(form):[]});
  if(result.error) return {error:["22023","42501"].includes(result.error.code)?result.error.message:"Team access could not be updated. Refresh and try again."};
  revalidatePath("/workspace/team"); revalidatePath("/workspace");
  return {success:"Team access updated. Pending invitations created by this member were revoked."};
 } catch(error) {return failure(error);}
}
export async function revokeInvite(_state:TeamState,form:FormData):Promise<TeamState> {
 try {
  const {client,org}=await teamClient(form), id=String(form.get("invitation")??"");
  if(!isUuid(id)) throw new Error("Choose an available invitation.");
  const result=await client.rpc("revoke_team_invitation",{p_organisation_id:org,p_invitation_id:id});
  if(result.error) return {error:result.error.code==="22023"?result.error.message:"Invitation could not be revoked. Refresh and try again."};
  revalidatePath("/workspace/team");return {success:"Invitation revoked."};
 } catch(error) {return failure(error);}
}

export async function saveMemberName(_state:TeamState,form:FormData):Promise<TeamState> {
 try {
  await requireUser();const org=String(form.get("organisation")??""),member=String(form.get("member")??"");
  if(!isUuid(org)||!isUuid(member))throw new Error("Choose an available business and member.");
  const client=await createClient(),result=await client.rpc("save_member_name",{p_organisation_id:org,p_membership_id:member,p_name:String(form.get("display_name")??"").trim()});
  if(result.error)return {error:["22023","42501"].includes(result.error.code)?result.error.message:"The name could not be saved."};
  for(const path of ["/workspace","/workspace/team","/workspace/setup/centres"])revalidatePath(path);
  return {success:"Name saved."};
 }catch(error){return failure(error);}
}

function stockAccess(form:FormData){const text=String(form.get("stock_access")??"[]");if(text.length>32768)throw new Error("Choose up to 100 centres.");const input=JSON.parse(text);if(!Array.isArray(input)||input.length>100)throw new Error("Choose valid stock centres.");return input;}
async function sendInvitationEmail(client:Awaited<ReturnType<typeof createClient>>,org:string,invitation:string):Promise<TeamState>{
 const attempt=await client.rpc("team_invitation_email",{p_organisation_id:org,p_invitation_id:invitation,p_status:"REQUESTED"});
 if(attempt.error)return {error:attempt.error.code==="22023"?attempt.error.message:"Invitation saved, but email delivery could not start. Copy the link or try again."};
 let sent=false,deliveryCode="";
 try{const origin=siteUrl();if(!origin)throw new Error("Site URL missing");const {url,key}=getSupabaseConfig();
  // An isolated client avoids replacing the administrator's session or using their PKCE verifier.
  const mail=createEmailClient(url,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false,flowType:"implicit"}});
  const result=await mail.auth.signInWithOtp({email:attempt.data.email,options:{shouldCreateUser:true,emailRedirectTo:`${origin}/join`}});sent=!result.error;deliveryCode=result.error?.code??"";
 }catch{sent=false;}
 await client.rpc("team_invitation_email",{p_organisation_id:org,p_invitation_id:invitation,p_status:sent?"SENT":"FAILED"});revalidatePath("/workspace/team");
 const hint=deliveryCode==="email_address_not_authorized"?" Configure custom SMTP in Supabase to send to restaurant staff.":deliveryCode.includes("rate_limit")?" Supabase email limits were reached; wait before resending.":" Check Supabase email delivery settings if this continues.";
 return sent?{success:"Invitation saved and email link requested. Your colleague can open the email to sign in and join. A shareable link is also available below."}:{error:"Invitation saved, but Supabase could not send its email. Copy the link below, or retry from invitation history."+hint};
}
export async function resendInvitation(_state:TeamState,form:FormData):Promise<TeamState>{try{const {client,org}=await teamClient(form),id=String(form.get("invitation")??"");if(!isUuid(id))throw new Error("Choose an invitation.");return await sendInvitationEmail(client,org,id);}catch(error){return failure(error);}}
