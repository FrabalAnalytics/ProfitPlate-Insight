"use server";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireUser,getPlatformAccess } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { isUuid } from "@/lib/catalogue";
import { validBusinessDate } from "@/lib/recipes";
import { contextQuery } from "@/lib/overview";
import { expenseHeaders,csvExpense,type ExpenseState } from "@/lib/expenses";

async function authorised(form:FormData,write=true) {
 await requireUser();if(await getPlatformAccess()!=="member")throw new Error("Restaurant membership is required.");
 const org=String(form.get("organisation")??"");if(!isUuid(org))throw new Error("Choose an available business.");
 const client=await createClient(),permission=await client.rpc("expense_access",{p_organisation_id:org});
 if(permission.error||permission.data?.[write?"write":"read"]!==true)throw new Error(write?"An organisation-wide Finance member or Restaurant Administrator must record expenses.":"Expense access is restricted.");
 return {org,client};
}
function reportContext(form:FormData) {
 const from=String(form.get("report_from")??""),to=String(form.get("report_to")??""),location=String(form.get("report_location")??"");
 return {from:validBusinessDate(from)?from:undefined,to:validBusinessDate(to)?to:undefined,location:isUuid(location)?location:undefined};
}
const failure=(error:unknown):ExpenseState=>({error:error instanceof Error?error.message:"The request could not be completed. Try again."});
export async function stageExpenses(_state:ExpenseState,form:FormData):Promise<ExpenseState> {
 let org:string,batch:string;
 try {
  const auth=await authorised(form);org=auth.org;const request=String(form.get("request")??"");if(!isUuid(request))throw new Error("Refresh and try again.");
  let csv=String(form.get("csv")??""),source=String(form.get("source_org")??"").trim(),filename=String(form.get("filename")??"");
  if(form.get("mode")==="manual") {
   const row=Object.fromEntries(expenseHeaders.map(key=>[key,String(form.get(key)??"").trim()]));row.Organisation_Code="MANUAL";source="MANUAL";filename="manual-expense.csv";
   row.Source_System="MANUAL";row.Line_Ref="1";row.Expense_Ref=row.Expense_Ref||`EXP-${request}`;
   csv=csvExpense([...expenseHeaders])+"\n"+csvExpense(expenseHeaders.map(key=>row[key]));
  }
  const result=await auth.client.rpc("stage_expense_import",{p_organisation_id:org,p_request_id:request,p_filename:filename,p_csv:csv,p_source_org:source});
  if(result.error)return {error:result.error.code==="22023"?result.error.message:"The expense could not be reviewed. Check your access and try again."};
  batch=result.data;
 }catch(error){return failure(error);}
 redirect(`/workspace/expenses?${contextQuery(org,reportContext(form),{batch})}`);
}
export async function postExpenses(_state:ExpenseState,form:FormData):Promise<ExpenseState> {
 let org:string,batch:string,posted:boolean;
 try {
  const auth=await authorised(form);org=auth.org;batch=String(form.get("batch")??"");
  if(!isUuid(batch)||form.get("confirmed")!=="on")throw new Error("Review and confirm the expense details before recording.");
  const result=await auth.client.rpc("post_expense_import",{p_organisation_id:org,p_batch_id:batch,p_source_control:String(form.get("source_control")??"").trim()});
  if(result.error)return {error:result.error.code==="22023"?result.error.message:"Expenses could not be recorded. Refresh and try again."};posted=result.data.posted===true;
  revalidatePath("/workspace/expenses");
 }catch(error){return failure(error);}
 redirect(`/workspace/expenses?${contextQuery(org,reportContext(form),{batch,result:posted?"recorded":"review"})}`);
}
export async function voidExpense(_state:ExpenseState,form:FormData):Promise<ExpenseState> {
 try {
  const {org,client}=await authorised(form),entry=String(form.get("entry")??"");if(!isUuid(entry)||form.get("confirmed")!=="on")throw new Error("Confirm the void and provide its reason.");
  const result=await client.rpc("void_expense_entry",{p_organisation_id:org,p_entry_id:entry,p_reason:String(form.get("reason")??"").trim()});
  if(result.error)return {error:result.error.code==="22023"?result.error.message:"This expense could not be voided."};
  revalidatePath("/workspace/expenses");return {success:"Expense voided. Its source and audit history are retained."};
 }catch(error){return failure(error);}
}
export async function reviewCoverage(_state:ExpenseState,form:FormData):Promise<ExpenseState> {
 try {
  const {org,client}=await authorised(form);if(form.get("confirmed")!=="on")throw new Error("Explicitly confirm the coverage review.");
  const location=String(form.get("location")??"");if(location&&!isUuid(location))throw new Error("Choose a business location.");
  const result=await client.rpc("review_expense_coverage",{p_organisation_id:org,p_from:String(form.get("from")??""),p_to:String(form.get("to")??""),p_location_id:location||null,p_kind:String(form.get("kind")??""),p_confirmed:true});
  if(result.error)return {error:result.error.code==="22023"?result.error.message:"Coverage could not be reviewed. Check your access and try again."};
  revalidatePath("/workspace/expenses");return {success:"Coverage reviewed for this exact period and scope."};
 }catch(error){return failure(error);}
}
export async function createCategory(_state:ExpenseState,form:FormData):Promise<ExpenseState> {
 try {
  const {org,client}=await authorised(form),result=await client.rpc("create_expense_category",{p_organisation_id:org,p_code:String(form.get("code")??""),p_name:String(form.get("name")??""),p_kind:String(form.get("kind")??"")});
  if(result.error)return {error:result.error.code==="22023"?result.error.message:"The category could not be created."};revalidatePath("/workspace/expenses");return {success:"Expense category created. Its reporting type is fixed."};
 }catch(error){return failure(error);}
}
export async function downloadExpense(form:FormData) {
 const {org,client}=await authorised(form,false),batch=String(form.get("batch")??"");if(!isUuid(batch))return {error:"Choose an available source."};
 const result=await client.rpc("expense_import_source",{p_organisation_id:org,p_batch_id:batch});return result.error||!result.data?{error:"Source download is unavailable."}:{filename:result.data.filename as string,csv:result.data.csv as string};
}
