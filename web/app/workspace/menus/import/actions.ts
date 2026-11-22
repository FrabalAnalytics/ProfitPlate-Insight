"use server";
import {readOnboardingFile} from "@/lib/onboarding-file";
import {requireUser} from '@/lib/auth';import {createClient} from '@/lib/supabase/server';import {isUuid} from '@/lib/catalogue';import {parseMenuCsv,type MenuImportRow,type MenuImportPreview} from '@/lib/menu-imports';import {revalidatePath} from 'next/cache';
export type ImportState={error?:string;rows?:MenuImportRow[];preview?:MenuImportPreview;location?:string;done?:boolean;message?:string};
export async function reviewMenuImport(state:ImportState,form:FormData):Promise<ImportState>{
 await requireUser();const org=String(form.get('organisation')),site=String(form.get('location')),request=String(form.get('request'));if(![org,site,request].every(isUuid))return {...state,error:'Choose a restaurant and outlet.'};
 try{const client=await createClient();if(form.get('intent')==='post'){
  const rows=JSON.parse(String(form.get('rows'))),preview=JSON.parse(String(form.get('preview'))),r=await client.rpc('post_menu_catalogue_import',{p_organisation_id:org,p_location_id:site,p_request_id:request,p_rows:rows,p_preview:preview});if(r.error)throw new Error(r.error.code==='22023'?r.error.message:'Import could not be saved. Check permissions and update 048.');revalidatePath('/workspace/menus');revalidatePath('/workspace/menus/profitability');return {done:true,message:`Import saved. ${r.data} menu items created or updated. Unchanged items and repeated submissions are skipped.`};
 }
 const file=form.get('file');if(!(file instanceof File))throw new Error('Choose a CSV or XLSX with at most 100 menu items.');const text=await readOnboardingFile(file),rows=parseMenuCsv(text),r=await client.rpc('preview_menu_catalogue_import',{p_organisation_id:org,p_location_id:site,p_rows:rows});if(r.error)throw new Error(r.error.code==='22023'?r.error.message:'Review is unavailable. Check permissions and update 048.');return {rows,preview:r.data,location:site};
 }catch(e){return {...state,error:e instanceof Error?e.message:'Check your CSV and try again.'};}
}
