"use server";
import { requireUser } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { isUuid } from "@/lib/catalogue";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

export async function submitImportedOpening(_state: { error?: string }, form: FormData): Promise<{ error?: string }> {
 await requireUser();
 const org = String(form.get("organisation")), batch = String(form.get("batch"));
 if (![org, batch].every(isUuid)) return { error: "Refresh and choose an opening record." };
 const client = await createClient();
 const result = await client.rpc("submit_import_opening", { p_organisation_id: org, p_batch_id: batch });
 if (result.error) return { error: result.error.code === "22023" ? result.error.message : "Opening could not be submitted. Check your Inventory permissions for this centre." };
 revalidatePath("/workspace/inventory"); revalidatePath("/workspace/inventory/openings"); revalidatePath("/workspace/materials");
 redirect(result.data ? `/workspace/inventory?organisation=${org}&view=movements&document=${result.data}&result=requested` : `/workspace/inventory/openings?organisation=${org}&saved=zero`);
}
