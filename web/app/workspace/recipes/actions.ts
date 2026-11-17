"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { isUuid } from "@/lib/catalogue";
import { positiveDecimal, validBusinessDate, type RecipeOption } from "@/lib/recipes";

export async function findRecipeComponents(organisationId: string, kind: string, search: string, page: number): Promise<{ options: RecipeOption[]; more: boolean; error?: string }> {
 await requireUser();
 if (typeof organisationId !== "string" || !isUuid(organisationId) || !["ITEM", "RECIPE"].includes(kind) || typeof search !== "string" || search.length > 80 || !Number.isInteger(page) || page < 0 || page > 100000) return { options: [], more: false, error: "Check your search." };
 const supabase = await createClient();
 const { data, error } = await supabase.rpc("search_recipe_components", { p_organisation_id: organisationId, p_kind: kind, p_search: search.trim(), p_page: page });
 if (error || !Array.isArray(data)) return { options: [], more: false, error: "We couldn’t load these components. Please try again." };
 return { options: data.slice(0, 25) as RecipeOption[], more: data.length > 25 };
}

export type RecipeState = { error?: string; errors?: Record<string, string> };
export async function publishRecipe(_state: RecipeState, form: FormData): Promise<RecipeState> {
 await requireUser();
 const access = await getPlatformAccess();
 if (access !== "member") redirect(workspacePath(access));
 const get = (key: string) => String(form.get(key) ?? "").trim();
 const org = get("organisation_id"), code = get("code").toUpperCase(), name = get("name");
 const errors: Record<string, string> = {};
 if (!isUuid(org) || !isUuid(get("request_id")) || (get("recipe_id") && !isUuid(get("recipe_id")))) errors.record = "This recipe isn’t available. Refresh and try again.";
 if (!/^[A-Z0-9][A-Z0-9_-]{0,39}$/.test(code)) errors.code = "Use up to 40 letters, numbers, hyphens or underscores.";
 if (!name || name.length > 120) errors.name = "Enter a recipe name of up to 120 characters.";
 if (!["FINAL", "SUB_RECIPE"].includes(get("recipe_type"))) errors.recipe_type = "Choose a recipe type.";
 if (!validBusinessDate(get("effective_from"))) errors.effective_from = "Choose a valid effective date.";
 if (!positiveDecimal(get("yield_quantity"))) errors.yield_quantity = "Enter a positive batch yield with up to six decimal places.";
 if (!isUuid(get("yield_uom_id"))) errors.yield_uom_id = "Choose a yield unit.";
 if (get("notes").length > 2000) errors.notes = "Use 2000 characters or fewer.";
 let components: { kind: string; target_id: string; quantity: string; uom_id: string }[] = [];
 try {
  const parsed = JSON.parse(get("components"));
  if (!Array.isArray(parsed) || parsed.length < 1 || parsed.length > 100) throw new Error();
  components = parsed.map((line, index) => {
   if (!line || !["ITEM", "RECIPE"].includes(line.kind) || !isUuid(String(line.target_id)) || !isUuid(String(line.uom_id)) || typeof line.quantity !== "string" || !positiveDecimal(line.quantity)) errors.components = `Complete the component and positive quantity on line ${index + 1}.`;
   return { kind: String(line?.kind), target_id: String(line?.target_id), quantity: String(line?.quantity), uom_id: String(line?.uom_id) };
  });
 } catch { errors.components = "Add between 1 and 100 valid component lines."; }
 if (Object.keys(errors).length) return { error: "Please check the recipe details.", errors };
 const supabase = await createClient();
 const { data: id, error } = await supabase.rpc("publish_recipe_version", {
  p_organisation_id: org, p_recipe_id: get("recipe_id") || null, p_request_id: get("request_id"),
  p_code: code, p_name: name, p_recipe_type: get("recipe_type"), p_effective_from: get("effective_from"),
  p_yield_quantity: get("yield_quantity"), p_yield_uom_id: get("yield_uom_id"), p_notes: get("notes"), p_components: components,
 });
 if (error || typeof id !== "string") return { error: error?.code === "23505" ? "This recipe code already exists. Open that recipe and create a new version."
  : error?.code === "22023" ? error.message
  : "We couldn’t publish this version. Check your access and that all source materials are active, then try again. Your entries are still here." };
 revalidatePath("/workspace/recipes");
 redirect(`/workspace/recipes?organisation=${org}&version=${id}&saved=1`);
}
