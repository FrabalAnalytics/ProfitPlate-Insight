"use server";

import { revalidatePath } from "next/cache";
import { requireUser, getPlatformAccess } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { isUuid } from "@/lib/catalogue";
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
  const result=await client.rpc("invite_named_team_member",{p_organisation_id:org,p_request_id:request,p_email:email,p_name:String(form.get("display_name")??"").trim(),p_assignments:assignments(form)});
  if(result.error) return {error:result.error.code==="22023"?result.error.message:"We could not create this invitation. Check your access and try again."};
  revalidatePath("/workspace/team");
  return result.data.token ? {token:result.data.token,expires:result.data.expires_at,success:"Invitation created. Copy the link now and share it with the intended person."}
   : {success:"This invitation was already created. Its secret link is shown only once; revoke it and create another if you did not save it."};
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
