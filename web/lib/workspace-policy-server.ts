import "server-only";
import {cache} from "react";
import {getUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {workspaceRolePolicy} from "@/lib/workspace-home";
export const workspacePolicy=cache(async(organisation:string)=>{
 const user=await getUser(),client=await createClient();
 const membership=user?await client.from('organisation_memberships').select('id').eq('organisation_id',organisation).eq('user_id',user.id).eq('status','active').maybeSingle():null;
 const result=membership?.data?await client.from('membership_roles').select('role_code,location_id').eq('organisation_id',organisation).eq('membership_id',membership.data.id):null;
 const roles=result?.data??[];return {...workspaceRolePolicy(roles),roles};
});
