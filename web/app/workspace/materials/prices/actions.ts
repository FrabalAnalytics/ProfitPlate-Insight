"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { isUuid } from "@/lib/catalogue";
import { createClient } from "@/lib/supabase/server";
import { parseReferencePriceCsv, referencePriceHeaders, validateReferencePriceRows, type ReferencePriceInput, type ReferencePricePreview } from "@/lib/reference-prices";

export type PriceReviewState = { error?: string; revision?: string; rows?: ReferencePriceInput[]; preview?: ReferencePricePreview[] };
export type PriceSaveState = { error?: string };

async function access(organisationId: string) {
 await requireUser();
 const role = await getPlatformAccess();
 if (role !== "member") redirect(workspacePath(role));
 if (!isUuid(organisationId)) return null;
 const supabase = await createClient();
 const { data, error } = await supabase.rpc("reference_price_access", { p_organisation_id: organisationId });
 return !error && data?.write === true ? supabase : null;
}

export async function reviewReferencePrices(_state: PriceReviewState, form: FormData): Promise<PriceReviewState> {
 const organisationId = String(form.get("organisation_id") ?? "");
 const revision = String(form.get("revision") ?? "");
 const supabase = await access(organisationId);
 if (!supabase) return { revision, error: "Reference prices are unavailable or your account cannot change them." };
 let rows: ReferencePriceInput[];
 try {
  if (form.get("source") === "CSV") rows = parseReferencePriceCsv(String(form.get("csv_text") ?? ""));
  else rows = [Object.fromEntries(referencePriceHeaders.map(key => [key, String(form.get(key) ?? "").trim()])) as ReferencePriceInput];
 } catch (error) { return { revision, error: error instanceof Error ? error.message : "Check your CSV file." }; }
 const invalid = validateReferencePriceRows(rows);
 if (invalid) return { revision, error: invalid };
 const { data, error } = await supabase.rpc("preview_material_reference_prices", { p_organisation_id: organisationId, p_rows: rows });
 if (error) return { revision, error: error.code === "22023" ? error.message : "We could not review these prices. Check your access and try again." };
 return { revision, rows, preview: data as ReferencePricePreview[] };
}

export async function saveReferencePrices(_state: PriceSaveState, form: FormData): Promise<PriceSaveState> {
 const organisationId = String(form.get("organisation_id") ?? "");
 const supabase = await access(organisationId);
 if (!supabase) return { error: "Reference prices are unavailable or your account cannot change them." };
 const requestId = String(form.get("request_id") ?? "");
 if (!isUuid(requestId)) return { error: "Refresh the page before saving." };
 let rows: ReferencePriceInput[], preview: ReferencePricePreview[];
 const rawRows = String(form.get("rows") ?? ""), rawPreview = String(form.get("preview") ?? "");
 if (rawRows.length > 131072 || rawPreview.length > 262144) return { error: "The price batch is too large." };
 try { rows = JSON.parse(rawRows); preview = JSON.parse(rawPreview); } catch { return { error: "Review your prices again before saving." }; }
 const invalid = validateReferencePriceRows(rows);
 if (invalid) return { error: invalid };
 const source = String(form.get("source") ?? "");
 if (!["MANUAL", "CSV"].includes(source)) return { error: "Choose a valid price source." };
 const { error } = await supabase.rpc("save_material_reference_prices", { p_organisation_id: organisationId, p_request_id: requestId, p_source: source, p_rows: rows, p_preview: preview });
 if (error) return { error: error.code === "22023" ? error.message : "We could not save your prices. Your review is still here; please try again." };
 revalidatePath("/workspace/materials");
 revalidatePath("/workspace/materials/prices");
 revalidatePath("/workspace/recipes");
 revalidatePath("/workspace/menus");
 revalidatePath("/workspace/sales");
 redirect(`/workspace/materials/prices?organisation=${organisationId}&saved=1`);
}
