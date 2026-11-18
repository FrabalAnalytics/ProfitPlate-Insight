"use server";
import {revalidatePath} from "next/cache";
import {redirect} from "next/navigation";
import {requireUser,getPlatformAccess} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {isUuid} from "@/lib/catalogue";
import type {StockActionState} from "@/lib/inventory";

async function access(form:FormData){
 await requireUser();
 if(await getPlatformAccess()!=="member")throw new Error("Restaurant membership is required.");
 const org=String(form.get("organisation")??"");
 if(!isUuid(org))throw new Error("Choose a valid business.");
 return {org,client:await createClient()};
}
function failure(error:unknown):StockActionState{return {error:error instanceof Error?error.message:"Stock could not be saved. Refresh and try again."};}
function checked(error:{code?:string;message:string}|null){
 if(error)throw new Error(error.code==="PGRST202"?"Inventory setup needs database migration 023. Ask your administrator to apply it.":error.code==="22023"||error.code==="42501"?error.message:"Stock could not be saved. Check your entries and connection, then refresh to check its status.");
}
function parsed(form:FormData,name:string){const raw=String(form.get(name)??"[]");if(raw.length>65536)throw new Error("Use at most 100 stock lines.");return JSON.parse(raw);}
export async function configureStock(_state:StockActionState,form:FormData):Promise<StockActionState>{
 try{
  const {org,client}=await access(form),kind=String(form.get("configuration")??"");
  const value=Object.fromEntries(["code","name","kind","outlet_id","department","source_id","destination_id","approval_role","recipe_version_id","item_id","id","active"].map(key=>[key,String(form.get(key)??"").trim()]));
  const result=await client.rpc("save_stock_configuration",{p_organisation_id:org,p_kind:kind,p_value:value});checked(result.error);
  revalidatePath("/workspace/inventory");revalidatePath("/workspace/setup/production");revalidatePath("/workspace/materials");revalidatePath("/workspace/materials/prices");revalidatePath("/workspace/materials/prices/monthly");revalidatePath("/workspace/recipes");revalidatePath("/workspace/menus");revalidatePath("/workspace");return {success:"Inventory configuration saved."};
 }catch(error){return failure(error);}
}
export async function requestStock(_state:StockActionState,form:FormData):Promise<StockActionState>{
 let org:string,id:string;
 try{
  const auth=await access(form);org=auth.org;
  const request=String(form.get("request")??"");if(!isUuid(request)||form.get("confirmed")!=="on")throw new Error("Review and confirm the stock request.");
  const document=Object.fromEntries(["kind","date","note","source_id","destination_id","route_id","receipt_id","recipe_version_id","planned_output","actual_output","supplier_id","delivery_reference"].map(key=>[key,String(form.get(key)??"").trim()]));
  const result=await auth.client.rpc("request_stock_document",{p_organisation_id:org,p_request_id:request,p_document:document,p_lines:parsed(form,"lines")});checked(result.error);id=result.data;
  revalidatePath("/workspace/inventory");revalidatePath("/workspace");
 }catch(error){return failure(error);}
 redirect(`/workspace/inventory?${new URLSearchParams({organisation:org,view:"movements",document:id})}`);
}
export async function actOnStock(_state:StockActionState,form:FormData):Promise<StockActionState>{
 try{
  const {org,client}=await access(form),document=String(form.get("document")??"");
  if(!isUuid(document)||form.get("confirmed")!=="on")throw new Error("Confirm the stock decision before saving.");
  const result=await client.rpc("stock_document_action",{p_organisation_id:org,p_document_id:document,p_action:String(form.get("decision")??""),p_note:String(form.get("note")??"").trim(),p_received:parsed(form,"received")});checked(result.error);
  revalidatePath("/workspace/inventory");revalidatePath("/workspace");return {success:"Stock decision saved. Balances and movement history are updated."};
 }catch(error){return failure(error);}
}
export async function saveDepartmentAccess(_state:StockActionState,form:FormData):Promise<StockActionState>{
 let org:string,member:string;
 try{
  const auth=await access(form);org=auth.org;member=String(form.get("membership")??"");
  if(!isUuid(member)||form.get("confirmed")!=="on")throw new Error("Review the member and confirm their department permissions.");
  const revision=Number(form.get("revision"));if(!Number.isInteger(revision)||revision<0)throw new Error("Refresh and review the latest permissions.");
  const result=await auth.client.rpc("save_stock_member_access",{p_organisation_id:org,p_membership_id:member,p_revision:revision,p_mode:String(form.get("mode")??""),p_assignments:parsed(form,"assignments")});
  if(result.error?.code==="PGRST202")return {error:"Department access needs migration 024. Ask your administrator to apply it after 023."};
  checked(result.error);revalidatePath("/workspace/inventory");revalidatePath("/workspace");
 }catch(error){return failure(error);}
 redirect(`/workspace/inventory?${new URLSearchParams({organisation:org,view:"access",member,result:"access-saved"})}`);
}
