"use server";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { readOnboardingFile } from "@/lib/onboarding-file";
import { isUuid } from "@/lib/catalogue";
import { parseMasterCsv, type MasterImportPreview, type MasterImportRow } from "@/lib/master-imports";

export type MasterImportState = { error?: string; rows?: MasterImportRow[]; preview?: MasterImportPreview; location?: string; done?: boolean; message?: string };
export async function reviewMasterImport(state: MasterImportState, form: FormData): Promise<MasterImportState> {
 await requireUser();
 const access = await getPlatformAccess(); if (access !== "member") redirect(workspacePath(access));
 const org = String(form.get("organisation")), kind = String(form.get("kind")), request = String(form.get("request")), location = String(form.get("location") ?? "");
 if (![org, request].every(isUuid) || (location && !isUuid(location)) || !["MATERIAL", "RECIPE"].includes(kind)) return { error: "Choose a restaurant and import type." };
 const posting = form.get("intent") === "post";
 try {
  const client = await createClient();
  if (posting) {
   const raw = String(form.get("rows")), rawPreview = String(form.get("preview"));
   if (raw.length > 524288 || rawPreview.length > 524288) throw new Error("Import is too large. Review a smaller file.");
   const result = await client.rpc("post_master_import", { p_organisation_id: org, p_kind: kind, p_location_id: location || null, p_request_id: request, p_rows: JSON.parse(raw), p_preview: JSON.parse(rawPreview) });
   if (result.error) throw new Error(result.error.code === "22023" ? result.error.message : "Import could not be saved. Check your access and database update 057.");
   for (const path of ["/workspace/materials", "/workspace/recipes", "/workspace/setup", "/workspace/menus", "/workspace/menus/profitability", "/workspace/inventory/openings", "/admin"]) revalidatePath(path);
   return { done: true, message: result.data === 0 ? "This import was already saved. No duplicate records were created." : kind === "MATERIAL" ? "Materials and supplied reference prices saved. Supplied openings are ready for Inventory review; stock has not been posted." : "Recipes published in dependency order. Existing versions and stock balances are unchanged." };
  }
  const file = form.get("file");
  if (!(file instanceof File)) throw new Error("Choose a CSV or XLSX file.");
  const rows = parseMasterCsv(await readOnboardingFile(file), kind as "MATERIAL" | "RECIPE");
  const result = await client.rpc("preview_master_import", { p_organisation_id: org, p_kind: kind, p_location_id: location || null, p_rows: rows });
  if (result.error) throw new Error(result.error.code === "22023" ? result.error.message : "Review is unavailable. Check your setup access and database update 057.");
  return { rows, preview: result.data, location };
 } catch (error) { return { ...(posting ? state : {}), error: error instanceof Error ? error.message : "Check the file and try again." }; }
}
