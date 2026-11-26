'use server';
import {redirect} from 'next/navigation';
import {revalidatePath} from 'next/cache';
import {requireUser,getPlatformAccess,workspacePath} from '@/lib/auth';
import {createClient} from '@/lib/supabase/server';
import {isUuid} from '@/lib/catalogue';
import {validBusinessDate} from '@/lib/recipes';
export async function saveClose(_previous:{error?:string},form:FormData):Promise<{error?:string}>{
 await requireUser();const access=await getPlatformAccess();if(access!=='member')redirect(workspacePath(access));const get=(k:string)=>String(form.get(k)??''),org=get('organisation'),site=get('site'),month=get('month'),request=get('request');
 if(!isUuid(org)||(site&&!isUuid(site))||!isUuid(request)||!validBusinessDate(month)||!month.endsWith('-01')||get('confirmed')!=='yes')return{error:'Refresh the checklist, check the month and confirm your review.'};
 const client=await createClient(),result=await client.rpc('save_monthly_close_review',{p_organisation_id:org,p_month:month,p_site_id:site||null,p_request_id:request,p_evidence:get('evidence'),p_confirmations:Object.fromEntries(['sales','invoices','expenses'].map(k=>[k,get(k)==='yes'])),p_note:get('note')});
 if(result.error)return{error:result.error.code==='22023'?result.error.message:result.error.code==='42501'?'This review requires management access to the selected scope.':'The review could not be saved. Refresh and check its status before retrying.'};
 revalidatePath('/workspace/reviews/close');revalidatePath('/workspace');redirect(`/workspace/reviews/close?${new URLSearchParams({organisation:org,month:month.slice(0,7),...(site?{site}:{}),saved:'1'})}`);
}
