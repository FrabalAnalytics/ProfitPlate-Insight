"use server";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { isUuid } from "@/lib/catalogue";
import { parseSalesMappings, salesFormats } from "@/lib/sales-imports";
import { createClient } from "@/lib/supabase/server";
import {validBusinessDate} from '@/lib/recipes';
import type {SalesMenuChoice} from '@/lib/sales-imports';

export type SalesActionState = { error?: string };
export async function findSalesMenus(org:string,location:string,day:string,search:string,page:number):Promise<{options:SalesMenuChoice[];more:boolean;error?:string}>{
 const client=await access(org,true);
 if(!client||!location||location.length>40||!validBusinessDate(day)||search.length>80||!Number.isInteger(page)||page<0||page>100000)return{options:[],more:false,error:'Map the outlet and check the sales date first.'};
 const {data,error}=await client.rpc('sales_menu_choices',{p_organisation_id:org,p_location_code:location,p_day:day,p_search:search,p_page:page});
 return error?{options:[],more:false,error:error.code==='22023'?error.message:'Selling menus could not be loaded. Refresh and retry.'}:data;
}
async function access(org: string, write: boolean) {
 await requireUser(); const role = await getPlatformAccess();
 if (role !== "member") redirect(workspacePath(role));
 if (!isUuid(org)) return null;
 const client = await createClient();
 const { data, error } = await client.rpc("sales_import_access", { p_organisation_id: org });
 return !error && data?.[write ? "write" : "read"] === true ? client : null;
}
export async function stageSales(_state: SalesActionState, form: FormData): Promise<SalesActionState> {
 const get = (key: string) => String(form.get(key) ?? "");
 const org = get("organisation_id"), client = await access(org, true);
 if (!client) return { error: "Sales imports are unavailable or your account cannot upload them." };
 const csv = get("csv_text"), sourceOrg = get("source_org").trim(), basis = get("net_basis"), filename = get("filename");
 if (!isUuid(get("request_id")) || !csv || new TextEncoder().encode(csv).length > 131072 || csv.includes("\0") || !filename || filename.length > 180) return { error: "Choose a UTF-8 sales CSV under 128 KB with a filename of up to 180 characters." };
 if (!sourceOrg || sourceOrg.length > 40 || !salesFormats.some(([code]) => code === basis) || !/^[A-Z]{3}$/.test(get("currency"))) return { error: "Enter the source organisation code, choose the tax format and confirm the business currency." };
 let mappings;
 try { mappings = parseSalesMappings(get("mappings") || "{}"); } catch (error) { return { error: error instanceof Error ? error.message : "Check the source mappings." }; }
 const { data, error } = await client.rpc("stage_sales_import", { p_organisation_id: org, p_request_id: get("request_id"), p_filename: filename, p_csv: csv, p_source_org: sourceOrg, p_net_basis: basis, p_currency: get("currency"), p_mappings: mappings });
 if (error) return { error: error.code === "22023" ? error.message : "We could not validate these sales. Check your access and try again." };
 revalidatePath("/workspace/inventory");revalidatePath("/workspace/inventory/sales-consumption");revalidatePath("/workspace/inventory/statements");revalidatePath("/workspace/inventory/counts");revalidatePath("/workspace");revalidatePath("/workspace/sales"); redirect(`/workspace/sales?organisation=${org}&batch=${data}`);
}
export async function postSales(_state: SalesActionState, form: FormData): Promise<SalesActionState> {
 const org = String(form.get("organisation_id") ?? ""), id = String(form.get("batch_id") ?? ""), client = await access(org, true);
 if (!client || !isUuid(id)) return { error: "This sales import is unavailable to your account." };
 const raw = String(form.get("controls") ?? "{}"); let controls;
 if (raw.length > 32768) return { error: "The receipt controls are too large." };
 try { controls = JSON.parse(raw); } catch { return { error: "Check the source receipt totals." }; }
 if (form.get("confirmed") !== "yes") return { error: "Confirm the source currency, tax format, menu versions and receipt totals before saving." };
 const { data, error } = await client.rpc("post_sales_import", { p_organisation_id: org, p_batch_id: id, p_controls: controls });
 if (error) return { error: error.code === "22023" ? error.message : "We could not record the sales. Your review remains available; please try again." };
 revalidatePath("/workspace/inventory");revalidatePath("/workspace/inventory/sales-consumption");revalidatePath("/workspace/inventory/statements");revalidatePath("/workspace/inventory/counts");revalidatePath("/workspace");revalidatePath("/workspace/sales"); redirect(`/workspace/sales?organisation=${org}&batch=${id}&result=${data?.posted ? "recorded" : "review"}`);
}
export async function cancelSales(_state: SalesActionState, form: FormData): Promise<SalesActionState> {
 const org = String(form.get("organisation_id") ?? ""), id = String(form.get("batch_id") ?? ""), client = await access(org, true);
 if (!client || !isUuid(id)) return { error: "This sales import is unavailable to your account." };
 const { error } = await client.rpc("cancel_sales_import", { p_organisation_id: org, p_batch_id: id });
 if (error) return { error: error.code === "22023" ? error.message : "We could not cancel this import." };
 revalidatePath("/workspace/inventory");revalidatePath("/workspace/inventory/sales-consumption");revalidatePath("/workspace/inventory/statements");revalidatePath("/workspace/inventory/counts");revalidatePath("/workspace");revalidatePath("/workspace/sales"); redirect(`/workspace/sales?organisation=${org}&batch=${id}`);
}
export async function downloadSalesSource(org: string, batch: string): Promise<{ error: string } | { filename: string; csv: string }> {
 const client = await access(org, false);
 if (!client || !isUuid(batch)) return { error: "This source is unavailable to your account." };
 const { data, error } = await client.rpc("sales_import_source", { p_organisation_id: org, p_batch_id: batch });
 return error || !data ? { error: "The source file could not be retrieved." } : { filename: data.filename, csv: data.csv };
}
