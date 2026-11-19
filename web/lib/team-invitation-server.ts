import "server-only";
import {cache} from "react";
import {createClient} from "@/lib/supabase/server";
import type {PendingTeamInvitation} from "@/lib/team";
export const pendingTeamInvitations=cache(async()=>{
 const result=await(await createClient()).rpc("pending_team_invitations");
 return {invitations:(Array.isArray(result.data)?result.data:[]) as PendingTeamInvitation[],error:result.error};
});
