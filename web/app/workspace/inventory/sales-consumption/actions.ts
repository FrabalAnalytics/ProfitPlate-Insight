'use server';
import {requireUser} from '@/lib/auth';
import {createClient} from '@/lib/supabase/server';
import {revalidatePath} from 'next/cache';
import {redirect} from 'next/navigation';
import {isUuid} from '@/lib/catalogue';
export async function consumptionAction(_state:{error?:string},form:FormData):Promise<{error?:string}>{
 await requireUser();const org=String(form.get('organisation')??''),job=String(form.get('job')??''),client=await createClient();
 if(!isUuid(org))return{error:'Choose a business.'};
 const historical=form.get('intent')==='HISTORY';
 if(!historical&&!isUuid(job))return{error:'Choose a sales consumption record.'};
 const {error}=historical?await client.rpc('prepare_historical_sales_stock',{p_organisation_id:org,p_from:String(form.get('from')??''),p_to:String(form.get('to')??'')}):await client.rpc('resolve_sales_stock',{p_organisation_id:org,p_job_id:job,p_evidence:String(form.get('evidence')??''),p_reconcile:form.get('reconcile')==='on',p_note:String(form.get('note')??'')});
 if(error)return{error:['22023','42501'].includes(error.code)?error.message:'Unable to save. Refresh and review the consumption record.'};
 for(const path of ['/workspace','/workspace/sales','/workspace/inventory','/workspace/inventory/statements','/workspace/inventory/counts','/workspace/inventory/sales-consumption'])revalidatePath(path);
 redirect(`/workspace/inventory/sales-consumption?${new URLSearchParams({organisation:org,message:historical?'Historical sales prepared for review. No stock changed.':'Consumption processed. The current status is shown below.',...(!historical?{job}: {})})}`);
}
