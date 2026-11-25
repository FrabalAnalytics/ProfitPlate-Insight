"use server";
import { requireUser } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { isUuid } from "@/lib/catalogue";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

export async function submitImportedOpening(_state: { error?: string }, form: FormData): Promise<{ error?: string }> {
 await requireUser();
 const org = String(form.get("organisation")), batch = String(form.get("batch"));
 if (![org, batch].every(isUuid)||form.get("confirmed")!=="on") return { error: "Refresh and choose an opening record." };
 const client = await createClient();
 const direct=form.get("direct_opening")==="on";
 const result = await client.rpc(direct?"record_imported_opening":"submit_import_opening", { p_organisation_id: org, p_batch_id: batch });
 if (result.error) return { error: result.error.code === "22023" ? result.error.message : "Opening could not be submitted. Check your Inventory permissions for this centre." };
 for(const path of ["/workspace","/workspace/setup","/workspace/setup/standards","/workspace/inventory/value","/workspace/inventory/statements"])revalidatePath(path);
 revalidatePath("/workspace/inventory"); revalidatePath("/workspace/inventory/openings"); revalidatePath("/workspace/materials");
 redirect(result.data ? `/workspace/inventory?organisation=${org}&view=movements&document=${result.data}&result=${direct?"posted":"requested"}` : `/workspace/inventory/openings?organisation=${org}&saved=zero`);
}
