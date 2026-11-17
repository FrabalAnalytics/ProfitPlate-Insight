import { createClient } from "@/lib/supabase/server";
import { WorkspaceShellClient,type WorkspaceShellProps } from "./workspace-shell-client";
import type { NavigationAccess } from "@/lib/overview";
import { getUser } from "@/lib/auth";
import { workspaceNavigation } from "@/lib/workspace-home";

export async function WorkspaceShell(props:WorkspaceShellProps) {
 // Preserve the existing navigation until migration 012 is installed.
 let roleCodes:string[]=[];
 let navigation:NavigationAccess={overview:false,expenses:false,sales:false,purchases:false,menus:false,recipes:false,catalogue:false,team:false};
 if(props.organisationId&&!props.founder) {
  const client=await createClient();
  const result=await client.rpc("workspace_navigation_access",{p_organisation_id:props.organisationId});
  if(!result.error&&result.data&&typeof result.data==="object") navigation=result.data as NavigationAccess;
  else if(result.error?.code==="PGRST202") navigation={overview:false,expenses:false,sales:true,purchases:true,menus:true,recipes:true,catalogue:true,team:true};
  const user=await getUser();
  if(user) {
   const membership=await client.from("organisation_memberships").select("id").eq("organisation_id",props.organisationId).eq("user_id",user.id).eq("status","active").maybeSingle();
   if(membership.data) {
    const roles=await client.from("membership_roles").select("role_code,location_id").eq("organisation_id",props.organisationId).eq("membership_id",membership.data.id);
    if(roles.data){roleCodes=roles.data.map(role=>role.role_code);navigation=workspaceNavigation(roles.data,navigation);}
   }
  }
 }
 return <WorkspaceShellClient {...props} navigation={navigation} roleCodes={roleCodes}/>;
}
