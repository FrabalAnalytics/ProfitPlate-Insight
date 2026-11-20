"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { isUuid } from "@/lib/catalogue";
import { parsePurchaseMappings } from "@/lib/purchase-imports";
import { createClient } from "@/lib/supabase/server";

export type PurchaseActionState = { error?: string };
async function access(organisationId: string, write: boolean) {
 await requireUser();
 const role = await getPlatformAccess();
 if (role !== "member") redirect(workspacePath(role));
 if (!isUuid(organisationId)) return null;
 const client = await createClient();
 const { data, error } = await client.rpc("purchase_import_access", { p_organisation_id: organisationId });
 return !error && data?.[write ? "write" : "read"] === true ? client : null;
}

export async function stagePurchases(_state: PurchaseActionState, form: FormData): Promise<PurchaseActionState> {
 const organisationId = String(form.get("organisation_id") ?? "");
 const client = await access(organisationId, true);
 if (!client) return { error: "Purchase imports are unavailable or your account cannot upload them." };
 const requestId = String(form.get("request_id") ?? "");
 if (!isUuid(requestId)) return { error: "Refresh the page before uploading." };
 const csv = String(form.get("csv_text") ?? ""), filename = String(form.get("filename") ?? "");
 if (new TextEncoder().encode(csv).length > 131072 || csv.includes("\0")) return { error: "Use a UTF-8 CSV under 128 KB without null characters." };
 if (!csv || !filename || filename.length > 180) return { error: "Choose a CSV file with a filename of up to 180 characters." };
 const sourceOrg = String(form.get("source_org") ?? "").trim(), basis = String(form.get("price_basis") ?? "");
 if (!sourceOrg || sourceOrg.length > 40 || !["EXCLUSIVE", "INCLUSIVE"].includes(basis)) return { error: "Enter the source organisation code and choose whether unit prices include tax." };
 let mappings;
 try { mappings = parsePurchaseMappings(String(form.get("mappings") ?? "{}")); }
 catch (error) { return { error: error instanceof Error ? error.message : "Check your mappings." }; }
 const { data, error } = await client.rpc("stage_purchase_import", { p_organisation_id: organisationId, p_request_id: requestId, p_filename: filename, p_csv: csv, p_source_org: sourceOrg, p_price_basis: basis, p_mappings: mappings });
 if (error) return { error: error.code === "22023" ? error.message : "We could not validate the file. Check your access and try again." };
 revalidatePath("/workspace/purchases");
 redirect(`/workspace/purchases?organisation=${organisationId}&batch=${data}`);
}

export async function postPurchases(_state: PurchaseActionState, form: FormData): Promise<PurchaseActionState> {
 const organisationId = String(form.get("organisation_id") ?? ""), batchId = String(form.get("batch_id") ?? "");
 const client = await access(organisationId, true);
 if (!client || !isUuid(batchId)) return { error: "This import is unavailable to your account." };
 const raw = String(form.get("controls") ?? "{}");
 if (raw.length > 32768) return { error: "The invoice controls are too large." };
 let controls;
 try { controls = JSON.parse(raw); } catch { return { error: "Check the invoice totals." }; }
 if (form.get("confirmed") !== "yes") return { error: "Confirm that you checked the supplier invoice totals before saving." };
 const { data, error } = await client.rpc("post_purchase_import", { p_organisation_id: organisationId, p_batch_id: batchId, p_controls: controls });
 if (error) return { error: error.code === "22023" ? error.message : "We could not save this import. Your review remains available; try again." };
 revalidatePath("/workspace");revalidatePath("/workspace/menus");revalidatePath("/workspace/menus/profitability");revalidatePath("/workspace/purchases");
 redirect(`/workspace/purchases?organisation=${organisationId}&batch=${batchId}&result=${data?.posted ? "recorded" : "review"}`);
}

export async function cancelPurchases(_state: PurchaseActionState, form: FormData): Promise<PurchaseActionState> {
 const organisationId = String(form.get("organisation_id") ?? ""), batchId = String(form.get("batch_id") ?? "");
 const client = await access(organisationId, true);
 if (!client || !isUuid(batchId)) return { error: "This import is unavailable to your account." };
 const { error } = await client.rpc("cancel_purchase_import", { p_organisation_id: organisationId, p_batch_id: batchId });
 if (error) return { error: error.code === "22023" ? error.message : "We could not cancel this import." };
 revalidatePath("/workspace/purchases");
 redirect(`/workspace/purchases?organisation=${organisationId}&batch=${batchId}`);
}

export async function downloadPurchaseSource(organisationId: string, batchId: string): Promise<{ error: string } | { filename: string; csv: string }> {
 const client = await access(organisationId, false);
 if (!client || !isUuid(batchId)) return { error: "This source file is unavailable to your account." };
 const { data, error } = await client.rpc("purchase_import_source", { p_organisation_id: organisationId, p_batch_id: batchId });
 if (error || !data) return { error: "We could not retrieve the source file. Please try again." };
 return { filename: data.filename, csv: data.csv };
}

export async function enterInvoice(_state: PurchaseActionState, form: FormData): Promise<PurchaseActionState> {
 const organisation = String(form.get("organisation") ?? ""), client = await access(organisation, true), request = String(form.get("request") ?? "");
 if (!client || !isUuid(request)) return { error: "Invoice entry is unavailable. Check your access and refresh." };
 const raw = String(form.get("lines") ?? "[]");
 if (raw.length > 65536) return { error: "Use up to 50 invoice lines." };
 let lines;
 try { lines = JSON.parse(raw); } catch { return { error: "Check the invoice lines." }; }
 const invoice = { supplier_id: String(form.get("supplier") ?? ""), location_id: String(form.get("location") ?? ""), date: String(form.get("date") ?? ""), reference: String(form.get("reference") ?? "").trim(), price_basis: String(form.get("basis") ?? ""), total: String(form.get("total") ?? "").trim(), route: String(form.get("route") ?? ""), order_id: String(form.get("order") ?? ""), direct_reason: String(form.get("direct_reason") ?? "").trim(), evidence: String(form.get("evidence") ?? "").trim() };
 const purchase = String(form.get("purchase") ?? "");
 const result = purchase ? await client.rpc("request_purchase_correction", { p_organisation_id: organisation, p_purchase_id: purchase, p_request_id: request, p_revision: Number(form.get("revision")), p_kind: String(form.get("kind") ?? "REPLACE"), p_reason: String(form.get("reason") ?? "").trim(), p_invoice: invoice, p_lines: lines }) : await client.rpc("stage_manual_purchase", { p_organisation_id: organisation, p_request_id: request, p_invoice: invoice, p_lines: lines });
 if (result.error) return { error: result.error.code === "PGRST202" ? "Direct transaction entry needs migration 016. Ask your administrator to complete setup." : result.error.code === "22023" ? result.error.message : "The invoice could not be saved. Check your entries, access and connection." };
 revalidatePath("/workspace/purchases");
 redirect(purchase ? `/workspace/purchases/invoices?${new URLSearchParams({ organisation, purchase, result: "requested" })}` : `/workspace/purchases?organisation=${organisation}&batch=${result.data}`);
}

export async function decideCorrection(_state: PurchaseActionState, form: FormData): Promise<PurchaseActionState> {
 const organisation = String(form.get("organisation") ?? ""), purchase = String(form.get("purchase") ?? ""), correction = String(form.get("correction") ?? ""), client = await access(organisation, false);
 const choice = String(form.get("decision") ?? "");
 if (!client || !isUuid(purchase) || !isUuid(correction) || !["APPROVE", "REJECT"].includes(choice) || form.get("confirmed") !== "on") return { error: "Review the proposed correction and confirm your decision." };
 const result = await client.rpc("decide_purchase_correction", { p_organisation_id: organisation, p_correction_id: correction, p_approve: choice === "APPROVE", p_note: String(form.get("note") ?? "").trim() });
 if (result.error) return { error: result.error.code === "22023" ? result.error.message : "Finance approval is required, or this decision could not be saved. Refresh to check its status." };
 revalidatePath("/workspace");revalidatePath("/workspace/menus");revalidatePath("/workspace/menus/profitability");revalidatePath("/workspace/purchases");revalidatePath("/workspace/purchases/invoices");
 redirect(`/workspace/purchases/invoices?${new URLSearchParams({ organisation, purchase, result: "decided" })}`);
}

function workflowError(error: { code?: string; message: string } | null) {
 return error?.code === "PGRST202" ? "PO and GRN workflows need migrations 018 and 019. Ask your administrator to complete setup." : error?.code === "22023" ? error.message : "The request could not be saved. Check your access and connection, then refresh to review its status.";
}
function refreshProcurement() { revalidatePath("/workspace");revalidatePath("/workspace/menus/profitability"); revalidatePath("/workspace/purchases");revalidatePath("/workspace/purchases/orders");revalidatePath("/workspace/purchases/invoices"); }
export async function saveOrder(_state: PurchaseActionState, form: FormData): Promise<PurchaseActionState> {
 const organisation=String(form.get("organisation")??""),client=await access(organisation,true),request=String(form.get("request")??""),id=String(form.get("order_id")??"");
 if(!client||!isUuid(request)||(id&&!isUuid(id)))return {error:"Procurement access and a valid order are required."};
 let lines;try{lines=JSON.parse(String(form.get("lines")??"[]"));}catch{return {error:"Check the order lines."};}
 const document={supplier_id:String(form.get("supplier")??""),location_id:String(form.get("location")??""),date:String(form.get("date")??""),reference:String(form.get("reference")??""),price_basis:String(form.get("basis")??""),total:String(form.get("total")??""),needed_by:String(form.get("needed_by")??""),notes:String(form.get("notes")??"")};
 const result=await client.rpc("save_purchase_order",{p_organisation_id:organisation,p_order_id:id||null,p_request_id:request,p_revision:Number(form.get("order_revision")??0),p_document:document,p_lines:lines});
 if(result.error)return {error:workflowError(result.error)};refreshProcurement();redirect(`/workspace/purchases/orders?${new URLSearchParams({organisation,order:result.data})}`);
}
export async function issueOrder(_state: PurchaseActionState, form: FormData): Promise<PurchaseActionState> {
 const organisation=String(form.get("organisation")??""),client=await access(organisation,true),order=String(form.get("order")??"");
 if(!client||!isUuid(order))return {error:"Procurement access and a valid order are required."};
 const result=await client.rpc("issue_purchase_order",{p_organisation_id:organisation,p_order_id:order,p_revision:Number(form.get("revision")),p_confirmed:form.get("confirmed")==="on"});
 if(result.error)return {error:workflowError(result.error)};refreshProcurement();redirect(`/workspace/purchases/orders?${new URLSearchParams({organisation,order,result:"issued"})}`);
}
export async function receiveOrder(_state: PurchaseActionState, form: FormData): Promise<PurchaseActionState> {
 const organisation=String(form.get("organisation")??""),order=String(form.get("order")??""),request=String(form.get("request")??"");
 const client=await orderAccess(organisation,order,"receive");
 if(!client||!isUuid(request))return {error:"Inventory / Receiving access is required. A different colleague must receive orders you prepared or issued."};
 let lines;try{lines=JSON.parse(String(form.get("receipt_lines")??"[]"));}catch{return {error:"Check accepted and rejected quantities."};}
 const result=await client.rpc("record_goods_receipt",{p_organisation_id:organisation,p_order_id:order,p_request_id:request,p_document:{date:String(form.get("received_on")??""),delivery_reference:String(form.get("delivery_reference")??""),notes:String(form.get("notes")??"")},p_lines:lines,p_confirmed:form.get("confirmed")==="on"});
 if(result.error)return {error:workflowError(result.error)};refreshProcurement();redirect(`/workspace/purchases/orders?${new URLSearchParams({organisation,order,result:"received",receipt:result.data})}`);
}
export async function reviewReceiptVoid(_state: PurchaseActionState, form: FormData): Promise<PurchaseActionState> {
 const organisation=String(form.get("organisation")??""),order=String(form.get("order")??""),receipt=String(form.get("receipt")??""),request=String(form.get("request")??"");
 const client=await orderAccess(organisation,order,form.get("decision")==="REQUEST"?"request_receipt_void":"approve_corrections");
 if(!client||!isUuid(order)||!isUuid(receipt)||!isUuid(request)||form.get("confirmed")!=="on")return {error:"Confirm the GRN correction request or Finance decision."};
 const result=await client.rpc("review_goods_receipt_void",{p_organisation_id:organisation,p_receipt_id:receipt,p_request_id:request,p_reason:String(form.get("reason")??""),p_decision:String(form.get("decision")??"REQUEST"),p_note:String(form.get("note")??"")});
 if(result.error)return {error:workflowError(result.error)};refreshProcurement();redirect(`/workspace/purchases/orders?${new URLSearchParams({organisation,order,result:"void-reviewed"})}`);
}
async function orderAccess(organisation: string, order: string, permission: "receive" | "request_receipt_void" | "approve_corrections") {
 await requireUser();
 const role=await getPlatformAccess();if(role!=="member")redirect(workspacePath(role));
 if(!isUuid(organisation)||!isUuid(order))return null;
 const client=await createClient();
 const result=await client.rpc("purchase_order_access",{p_organisation_id:organisation,p_order_id:order});
 return !result.error&&result.data?.read===true&&result.data?.[permission]===true?client:null;
}
export async function linkInvoice(_state: PurchaseActionState, form: FormData): Promise<PurchaseActionState> {
 const organisation=String(form.get("organisation")??""),client=await access(organisation,true),purchase=String(form.get("purchase")??""),request=String(form.get("request")??"");
 if(!client||!isUuid(purchase)||!isUuid(request))return {error:"Procurement must provide the invoice links."};
 let mappings;try{mappings=JSON.parse(String(form.get("mappings")??"[]"));}catch{return {error:"Check the invoice line links."};}
 const result=await client.rpc("set_invoice_procurement_context",{p_organisation_id:organisation,p_purchase_id:purchase,p_request_id:request,p_invoice_revision:Number(form.get("revision")),p_context:{route:String(form.get("route")??""),order_id:String(form.get("order")??""),reason:String(form.get("reason")??""),evidence:String(form.get("evidence")??"")},p_mappings:mappings});
 if(result.error)return {error:workflowError(result.error)};refreshProcurement();redirect(`/workspace/purchases/invoices?${new URLSearchParams({organisation,purchase,result:"linked"})}`);
}
export async function reviewInvoiceExceptions(_state: PurchaseActionState, form: FormData): Promise<PurchaseActionState> {
 const organisation=String(form.get("organisation")??""),client=await access(organisation,false),purchase=String(form.get("purchase")??""),request=String(form.get("request")??"");
 if(!client||!isUuid(purchase)||!isUuid(request))return {error:"Finance must review invoice exceptions."};
 const result=await client.rpc("review_invoice_exceptions",{p_organisation_id:organisation,p_purchase_id:purchase,p_request_id:request,p_fingerprint:String(form.get("fingerprint")??""),p_decision:String(form.get("decision")??""),p_note:String(form.get("note")??""),p_confirmed:form.get("confirmed")==="on"});
 if(result.error)return {error:workflowError(result.error)};refreshProcurement();redirect(`/workspace/purchases/invoices?${new URLSearchParams({organisation,purchase,result:"reviewed"})}`);
}

export async function lastPurchasePrice(organisation:string,item:string,unit:string,asOf:string):Promise<{value?:import('@/lib/procurement').LastPurchasePrice;error?:string}>{
 const client=await access(organisation,true);
 if(!client)return {error:'Price lookup is unavailable for this account.'};
 if(!isUuid(item)||!isUuid(unit)||asOf&&!/^\d{4}-\d{2}-\d{2}$/.test(asOf))return {error:'Choose a valid material, unit and order date.'};
 const result=await client.rpc('po_last_purchase_price',{p_organisation_id:organisation,p_item_id:item,p_uom_id:unit,p_as_of:asOf||null});
 if(result.error)return {error:result.error.code==='PGRST202'?'Price lookup needs database update 044.':'Price could not be loaded. Try again.'};
 return {value:result.data};
}
