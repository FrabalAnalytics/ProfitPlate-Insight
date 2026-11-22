'use server';
import {redirect} from 'next/navigation';
import {revalidatePath} from 'next/cache';
import {requireUser} from '@/lib/auth';
import {createClient} from '@/lib/supabase/server';
import {isUuid} from '@/lib/catalogue';
export type CountState={error?:string};
export async function countAction(_state:CountState,form:FormData):Promise<CountState>{
 await requireUser();const org=String(form.get('organisation')??''),site=String(form.get('site')??''),count=String(form.get('count')??''),intent=String(form.get('intent')??''),revision=Number(form.get('revision')),token=String(form.get('token')??'');
 if(!isUuid(org)||!isUuid(site))return{error:'Choose a permitted centre.'};
 const frequency=form.get('frequency')==='MONTHLY'?'MONTHLY':'WEEKLY',monthly=frequency==='MONTHLY';
 const client=await createClient();let result;let message='';
 if(intent==='START'){result=await client.rpc(monthly?'start_monthly_count_actual':'start_weekly_count',{p_organisation_id:org,p_site_id:site,p_day:String(form.get('day')??''),...(monthly?{p_reporting_month:form.get('reporting_month')?String(form.get('reporting_month'))+'-01':null,p_actual:String(form.get('actual')??form.get('day')??''),p_boundary:String(form.get('boundary')??'AFTER_CLOSING'),p_reason:String(form.get('schedule_reason')??'')}:{})});message='Count sheet opened. Enter every expected material, including zero stock.';}
 else if(intent==='SCOPE'){result=await client.rpc('save_weekly_count_scope',{p_organisation_id:org,p_site_id:site,p_item_ids:form.getAll('item').map(String),p_submission_hours:Number(form.get('hours')),p_evidence:String(form.get('evidence')??'')});message='Count scope saved for future cutoffs from tomorrow. Existing sheets are unchanged.';}
 else {
  if(!isUuid(count)||!isUuid(token)||!Number.isInteger(revision))return{error:'Refresh this count before saving.'};
  if(intent==='SAVE'||intent==='SUBMIT'){
   const source=String(form.get('rows')??'');if(source.length>256000)return{error:'This count sheet is too large.'};let rows;try{rows=JSON.parse(source);}catch{return{error:'Check the count quantities.'};}
   result=await client.rpc(monthly?'save_monthly_count':'save_weekly_count',{p_organisation_id:org,p_count_id:count,p_revision:revision,p_request_id:token,p_rows:rows,p_submit:intent==='SUBMIT',p_submitter:String(form.get('name')??''),p_note:String(form.get('note')??''),...(monthly?{p_no_stock:form.get('no_stock')==='on'}:{})});message=intent==='SUBMIT'?'Count submitted for independent review. Stock has not changed.':'Draft saved. Stock has not changed.';
  }else if(intent==='BOUNDARY'){result=await client.rpc('clarify_count_sales_boundary',{p_organisation_id:org,p_count_id:count,p_boundary:String(form.get('boundary')??''),p_reason:String(form.get('note')??'')});message='Daily sales boundary confirmed. No stock changed.';}else if(['APPROVE','REVIEW_ONLY','REOPEN','RECOUNT','POST'].includes(intent)){
   result=await client.rpc('weekly_count_action',{p_organisation_id:org,p_count_id:count,p_revision:revision,p_request_id:token,p_action:intent,p_reason:String(form.get('note')??'')});message={APPROVE:'Review saved. Stock has not changed.',REVIEW_ONLY:'Review completed without a stock adjustment.',REOPEN:'Count reopened for correction.',RECOUNT:'Cutoff snapshot refreshed. Enter physical counts again.',POST:'Count variance posted once. Later movements are preserved.'}[intent]??'';
  }else return{error:'Choose a valid count action.'};
 }
 if(result.error)return{error:['22023','42501','23505'].includes(result.error.code)?result.error.message:'Unable to save. Refresh and check the stock-count update and your access.'};
 if(monthly&&intent==='POST'){const check=await client.rpc('monthly_count_detail',{p_organisation_id:org,p_count_id:count});if(check.data?.no_stock_confirmed&&!check.data.lines?.length)message='No-stock declaration reviewed. No stock adjustment was needed.';}
 for(const path of ['/workspace','/workspace/inventory','/workspace/inventory/counts','/workspace/inventory/statements'])revalidatePath(path);
 const id=intent==='START'?String(result.data):count;
 redirect(`/workspace/inventory/counts?${new URLSearchParams({organisation:org,site,...(monthly?{frequency}:{}),...(id?{count:id}:{}),message})}`);
}
