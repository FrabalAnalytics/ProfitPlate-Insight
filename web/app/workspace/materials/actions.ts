"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { getPlatformAccess, requireUser, workspacePath } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { validateCatalogue } from "@/lib/catalogue";

export type CatalogueState = { error?: string; errors?: Record<string, string> };

export async function saveCatalogue(_state: CatalogueState, form: FormData): Promise<CatalogueState> {
  await requireUser();
  const access = await getPlatformAccess();
  if (access !== "member") redirect(workspacePath(access));
  const values = Object.fromEntries([...form.entries()].map(([key, value]) => [key, String(value).trim()]));
  values.code = (values.code ?? "").toUpperCase();
  const kind = values.kind;
  const errors = validateCatalogue(kind, values);
  if (Object.keys(errors).length) return { errors, error: "Please check the highlighted details." };
  const supabase = await createClient();
  const { data: permission, error: permissionError } = await supabase.rpc("can_manage_catalogue", { p_organisation_id: values.organisation_id });
  if (permissionError || permission !== true) return { error: "You don’t have permission to change this business’s catalogue, or access is temporarily unavailable." };
  const shared = { p_organisation_id: values.organisation_id, p_id: values.id || null, p_code: values.code, p_name: values.name, p_is_active: values.is_active === "true" };
  const result = kind === "material"
    ? await supabase.rpc("save_material_setup", {p_organisation_id:values.organisation_id,p_value:values})
    : kind === "supplier"
      ? await supabase.rpc("save_catalogue_supplier", { ...shared, p_email: values.email || "", p_phone: values.phone || "", p_address: values.address || "" })
      : await supabase.rpc("save_material_conversion", { p_organisation_id: values.organisation_id, p_item_id: values.item_id, p_from_uom_id: values.from_uom_id, p_factor: values.factor, p_effective_from: values.effective_from });
  if (result.error) {
    if (result.error.code === "23505") return { error: kind === "conversion" ? "A different conversion already exists for this material, source unit and date. Use a new effective date." : "This code is already in use in your business. Choose a different code." };
    if (result.error.code === "22023" && kind === "conversion") return { error: "Check the conversion: standard units must use the correct factor and match the material’s dimension. Package sizes must be positive." };
    if(result.error.code === "22023")return {error:result.error.message};
    return { error: "We couldn’t save your changes. Check your access and details, then try again. Your entries are still here." };
  }
  revalidatePath("/workspace/setup");revalidatePath("/workspace/setup/standards");revalidatePath("/admin");
 revalidatePath("/workspace/materials");
  const tab = kind === "supplier" ? "suppliers" : kind === "conversion" ? "conversions" : "materials";
  redirect(`/workspace/materials?organisation=${values.organisation_id}&tab=${tab}&saved=${kind}${kind === "conversion" ? `&item=${values.item_id}` : `&q=${encodeURIComponent(values.name)}`}`);
}
