"use server";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { isUuid } from "@/lib/catalogue";
import { positiveDecimal, validBusinessDate } from "@/lib/recipes";
import { menuChannels, menuTaxSettings, validMenuTaxRate, type MenuRecipe } from "@/lib/menus";

export type MenuState = { error?: string };
async function session() {
 await requireUser(); const access = await getPlatformAccess();
 if (access !== "member") redirect(workspacePath(access));
 return createClient();
}
function failure(error: { code?: string; message?: string }): MenuState {
 return { error: error.code === "22023" ? error.message : error.code === "23505" ? "This menu code is already in use. Open that item to create another version." : error.code === "42501" ? "Your account cannot make this menu change, or the linked record is unavailable." : "We could not save this change. Your entries are still here; please try again." };
}
export async function findMenuRecipes(organisationId: string, search: string, page: number): Promise<{ options: MenuRecipe[]; more: boolean; error?: string }> {
 const client = await session();
 if (!isUuid(organisationId) || typeof search !== "string" || search.length > 80 || !Number.isInteger(page) || page < 0 || page > 100000) return { options: [], more: false, error: "Check your recipe search." };
 const { data, error } = await client.rpc("search_menu_recipes", { p_organisation_id: organisationId, p_search: search.trim(), p_page: page });
 if (error || !Array.isArray(data)) return { options: [], more: false, error: "Saved recipes are unavailable. Try another search or refresh the page." };
 return { options: data.slice(0, 25), more: data.length > 25 };
}
export async function publishMenu(_state: MenuState, form: FormData): Promise<MenuState> {
 const client = await session(), get = (key: string) => String(form.get(key) ?? "").trim();
 const org = get("organisation_id"), menuId = get("menu_id"), code = get("code").toUpperCase();
 if (!isUuid(org) || !isUuid(get("request_id")) || (menuId && !isUuid(menuId)) || !isUuid(get("brand_id")) || (get("recipe_version_id")&&!isUuid(get("recipe_version_id")))) return { error: "Choose your business, brand and saved recipe version." };
 if (!/^[A-Z0-9][A-Z0-9_-]{0,39}$/.test(code) || !get("name") || get("name").length > 120 || get("category").length > 60 || get("notes").length > 1000) return { error: "Check the menu code, name, category and notes." };
 if (get("recipe_version_id")&&(!positiveDecimal(get("recipe_quantity")) || !validBusinessDate(get("effective_from")))) return { error: "Enter a positive recipe quantity with up to six decimals and a valid effective date." };
 const values=Object.fromEntries([...form.entries()].map(([key,value])=>[key,String(value).trim()]));values.code=code;
 const {data:id,error}=await client.rpc("save_menu_setup",{p_organisation_id:org,p_request_id:get("request_id"),p_value:values});
 if(error)return failure(error);
 revalidatePath("/workspace/setup");revalidatePath("/workspace/setup/standards");revalidatePath("/admin");
 revalidatePath("/workspace/menus");
 redirect(`/workspace/menus?organisation=${org}&item=${id}&saved=${get("recipe_version_id")?"menu":"draft"}`);
}
export async function saveMenuPrice(_state: MenuState, form: FormData): Promise<MenuState> {
 const client = await session(), get = (key: string) => String(form.get(key) ?? "").trim();
 const org = get("organisation_id"), menuId = get("menu_id"), tax = get("tax_setting");
 if (![org, menuId, get("request_id"), get("location_id")].every(isUuid)) return { error: "Choose an available menu item and location." };
 if (!menuChannels.some(([code]) => code === get("channel")) || !menuTaxSettings.some(([code]) => code === tax) || !validMenuTaxRate(get("tax_percent")) || (tax === "NONE" && get("tax_percent") !== "0")) return { error: "Choose a sales channel and explicit tax setting. Tax rates must be from 0 to 100 with up to six decimal places." };
 if (!positiveDecimal(get("price")) || !validBusinessDate(get("effective_from")) || (get("effective_to") && (!validBusinessDate(get("effective_to")) || get("effective_to") < get("effective_from"))) || !get("notes") || get("notes").length > 300) return { error: "Enter a positive selling price, valid dates and a source note of up to 300 characters." };
 const { error } = await client.rpc("save_menu_selling_price", { p_organisation_id: org, p_menu_id: menuId, p_request_id: get("request_id"), p_location_id: get("location_id"), p_channel: get("channel"), p_price: get("price"), p_tax_setting: tax, p_tax_percent: get("tax_percent"), p_effective_from: get("effective_from"), p_effective_to: get("effective_to") || null, p_notes: get("notes") });
 if (error) return failure(error);
 revalidatePath("/workspace/setup");revalidatePath("/workspace/setup/standards");revalidatePath("/admin");
 revalidatePath("/workspace/menus");
 redirect(`/workspace/menus?organisation=${org}&item=${menuId}&saved=price&location=${get("location_id")}&channel=${get("channel")}${isUuid(get("view_version_id")) ? `&version=${get("view_version_id")}` : ""}`);
}
export async function toggleMenuActive(_state: MenuState, form: FormData): Promise<MenuState> {
 const client = await session(), org = String(form.get("organisation_id") ?? ""), id = String(form.get("menu_id") ?? ""), active = String(form.get("active") ?? "");
 if (!isUuid(org) || !isUuid(id) || !["true", "false"].includes(active)) return { error: "This menu item is unavailable." };
 const { error } = await client.rpc("set_menu_item_active", { p_organisation_id: org, p_menu_id: id, p_active: active === "true" });
 if (error) return failure(error);
 revalidatePath("/workspace/setup");revalidatePath("/workspace/setup/standards");revalidatePath("/admin");
 revalidatePath("/workspace/menus");
 redirect(`/workspace/menus?organisation=${org}&item=${id}&saved=status`);
}
