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
  const document=Object.fromEntries(["kind","date","note","submitter_name","source_id","destination_id","route_id","receipt_id","recipe_version_id","planned_output","actual_output","supplier_id","delivery_reference","processing_standard_id","variance_reason","usable_weight_kg"].map(key=>[key,String(form.get(key)??"").trim()]));
  if(document.kind==="WASTE"){
   const category=String(form.get("waste_category")??"");
   if(!['Spoilage','Expiry','Damage','Bad production','Other loss'].includes(category))throw new Error("Choose a waste category.");
   if(!document.submitter_name||document.submitter_name.length>120)throw new Error("Enter the submitter name (up to 120 characters).");
   document.waste_reason_code=({Spoilage:"SPOILAGE",Expiry:"EXPIRY",Damage:"DAMAGE","Bad production":"BAD_PRODUCTION","Other loss":"OTHER"} as Record<string,string>)[category];
   document.note=document.note?`${category}: ${document.note}`:category;
  }
  const result=await auth.client.rpc("request_stock_document",{p_organisation_id:org,p_request_id:request,p_document:{...document,...(document.kind==="PRODUCTION"?{processing_waste:parsed(form,"processing_waste"),waste_confirmed:form.get("waste_confirmed")==="on"}:{})},p_lines:parsed(form,"lines")});checked(result.error);id=result.data;
  revalidatePath("/workspace/inventory");revalidatePath("/workspace/inventory/processing");revalidatePath("/workspace/inventory/waste");revalidatePath("/workspace/inventory/waste/daily");revalidatePath("/workspace/inventory/waste/analysis");revalidatePath("/workspace/setup/centres");revalidatePath("/workspace/materials");revalidatePath("/workspace/setup");revalidatePath("/workspace/setup/standards");revalidatePath("/workspace");
 }catch(error){return failure(error);}
 redirect(`/workspace/inventory?${new URLSearchParams({organisation:org,view:"movements",document:id})}`);
}
export async function actOnStock(_state:StockActionState,form:FormData):Promise<StockActionState>{
 let org:string,document:string,decision:string;
 try{
  const auth=await access(form);org=auth.org;const client=auth.client;document=String(form.get("document")??"");
  if(!isUuid(document)||form.get("confirmed")!=="on")throw new Error("Confirm the stock decision before saving.");
  decision=String(form.get("decision")??"");if(!["APPROVE","POST","DISPATCH","RECEIVE","REJECT","DECLINE","RESOLVE","CANCEL"].includes(decision))throw new Error("Choose a stock action.");
  const result=await client.rpc("stock_document_action",{p_organisation_id:org,p_document_id:document,p_action:decision,p_note:String(form.get("note")??"").trim(),p_received:parsed(form,"received")});checked(result.error);
  revalidatePath("/workspace/inventory");revalidatePath("/workspace/inventory/processing");revalidatePath("/workspace/inventory/waste");revalidatePath("/workspace/inventory/waste/daily");revalidatePath("/workspace/inventory/waste/analysis");revalidatePath("/workspace/setup/centres");revalidatePath("/workspace/materials");revalidatePath("/workspace/setup");revalidatePath("/workspace/setup/standards");revalidatePath("/workspace");
 }catch(error){return failure(error);}
 redirect(`/workspace/inventory?${new URLSearchParams({organisation:org,view:"movements",document,result:decision.toLowerCase()})}`);
}
export async function saveDepartmentAccess(_state:StockActionState,form:FormData):Promise<StockActionState>{
 let org:string,member:string;
 try{
  const auth=await access(form);org=auth.org;member=String(form.get("membership")??"");
  if(!isUuid(member)||form.get("confirmed")!=="on")throw new Error("Review the member and confirm their department permissions.");
  const revision=Number(form.get("revision"));if(!Number.isInteger(revision)||revision<0)throw new Error("Refresh and review the latest permissions.");
  const result=await auth.client.rpc("save_stock_member_access",{p_organisation_id:org,p_membership_id:member,p_revision:revision,p_mode:String(form.get("mode")??""),p_assignments:parsed(form,"assignments")});
  if(result.error?.code==="PGRST202")return {error:"Department access needs migration 024. Ask your administrator to apply it after 023."};
  checked(result.error);revalidatePath("/workspace/inventory");revalidatePath("/workspace/inventory/processing");revalidatePath("/workspace/inventory/waste");revalidatePath("/workspace/inventory/waste/daily");revalidatePath("/workspace/inventory/waste/analysis");revalidatePath("/workspace/setup/centres");revalidatePath("/workspace/materials");revalidatePath("/workspace/setup");revalidatePath("/workspace/setup/standards");revalidatePath("/workspace");
 }catch(error){return failure(error);}
 redirect(`/workspace/inventory?${new URLSearchParams({organisation:org,view:"access",member,result:"access-saved"})}`);
}

export async function finishWasteRecord(_state:StockActionState,form:FormData):Promise<StockActionState>{
 try{
  const {org,client}=await access(form),doc=String(form.get("document")??""),name=String(form.get("submitter_name")??"").trim();
  if(!isUuid(doc)||!name||name.length>120)throw new Error("Enter the submitter name (up to 120 characters).");
  const result=await client.rpc("complete_waste_record",{p_organisation_id:org,p_document_id:doc,p_submitter_name:name});checked(result.error);
  revalidatePath("/workspace/inventory");revalidatePath("/workspace/inventory/waste");revalidatePath("/workspace/inventory/waste/daily");revalidatePath("/workspace/inventory/waste/analysis");revalidatePath("/workspace/records");revalidatePath("/workspace");return {success:"Waste recorded. Stock updated; no approval required."};
 }catch(error){return failure(error);}
}

export async function submitProcessing(_state:StockActionState,form:FormData):Promise<StockActionState>{
 let org:string,site:string,date:string;
 try{
  const auth=await access(form);org=auth.org;
  const submission=String(form.get('submission')??'');
  if(!isUuid(submission))throw new Error('Refresh before recording processing.');
  const value={source_id:String(form.get('source_id')??''),date:String(form.get('date')??''),submitter_name:String(form.get('submitter_name')??'').trim(),note:String(form.get('note')??'').trim(),rows:parsed(form,'rows')};
  if(!isUuid(value.source_id)||!value.submitter_name||value.submitter_name.length>120)throw new Error('Choose the processing centre and enter the submitter name.');
  const result=await auth.client.rpc('submit_material_processing',{p_organisation_id:org,p_submission_id:submission,p_value:value});
  if(result.error?.code==='PGRST202')throw new Error('Processing needs database migration 043. Ask your administrator to apply it.');
  checked(result.error);site=value.source_id;date=value.date;
  for(const path of ['/workspace/inventory','/workspace/inventory/processing','/workspace/inventory/waste','/workspace/records','/workspace/materials','/workspace'])revalidatePath(path);
 }catch(error){return failure(error);}
 redirect(`/workspace/inventory/processing?${new URLSearchParams({organisation:org,site,from:date,to:date,result:'recorded'})}`);
}
export async function completeProcessing(_state:StockActionState,form:FormData):Promise<StockActionState>{
 try{
  const {org,client}=await access(form),doc=String(form.get('document')??''),name=String(form.get('submitter_name')??'').trim();
  if(!isUuid(doc)||!name||name.length>120)throw new Error('Enter the submitter name (up to 120 characters).');
  const result=await client.rpc('complete_processing_record',{p_organisation_id:org,p_document_id:doc,p_submitter_name:name});checked(result.error);
  for(const path of ['/workspace/inventory','/workspace/inventory/processing','/workspace/inventory/waste','/workspace/records','/workspace'])revalidatePath(path);
  return {success:'Processing recorded. Input and output stock updated once; no approval needed.'};
 }catch(error){return failure(error);}
}
