"use server";
import {revalidatePath} from "next/cache";
import {redirect} from "next/navigation";
import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {isUuid} from "@/lib/catalogue";
export async function reviewGrns(form:FormData){
 await requireUser();const org=String(form.get("organisation")??""),ids=form.getAll("receipt").map(String);
 if(!isUuid(org)||!ids.length||ids.length>10||ids.some(id=>!isUuid(id)))redirect("/workspace");
 const client=await createClient(),result=await client.rpc("mark_workspace_grns_reviewed",{p_organisation_id:org,p_receipts:ids});
 revalidatePath("/workspace");revalidatePath("/workspace/tasks");
 redirect(`/workspace/tasks?${new URLSearchParams({organisation:org,queue:"NEW_GRNS",result:result.error?"review-failed":"reviewed"})}`);
}
