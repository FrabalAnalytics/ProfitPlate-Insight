'use server';
import {redirect} from 'next/navigation';
import {revalidatePath} from 'next/cache';
import {requireUser,getPlatformAccess,workspacePath} from '@/lib/auth';
import {createClient} from '@/lib/supabase/server';
import {isUuid} from '@/lib/catalogue';
import {validBusinessDate} from '@/lib/recipes';
import {actionTopics,actionStates,reviewPeriods} from '@/lib/management-reviews';
export type ReviewState={error?:string};
async function clientFor(org:string){await requireUser();const access=await getPlatformAccess();if(access!=='member')redirect(workspacePath(access));if(!isUuid(org))return null;const client=await createClient(),permission=await client.rpc('management_review_access',{p_organisation_id:org});return !permission.error&&permission.data?client:null;}
export async function findActionOwners(org:string,site:string,outlet:string,topic:string):Promise<{manage:boolean;members:{id:string;name:string}[];error?:string}>{
 const client=await clientFor(org);if(!client||(site&&!isUuid(site))||(outlet&&!isUuid(outlet))||!actionTopics.some(t=>t===topic))return{manage:false,members:[],error:'Choose an available topic and scope.'};
 const {data,error}=await client.rpc('management_action_options',{p_organisation_id:org,p_site_id:site||null,p_outlet_id:outlet||null,p_topic:topic});return error?{manage:false,members:[],error:'This topic and scope are unavailable to your role. Choose a permitted centre or outlet.'}:data;
}
export async function saveFollowUp(_previous:ReviewState,form:FormData):Promise<ReviewState>{
 const get=(key:string)=>String(form.get(key)??''),org=get('organisation'),client=await clientFor(org);
 if(!client)return{error:'Follow-up is unavailable to your account.'};
 const id=get('id'),site=get('site_id'),outlet=get('outlet_id'),request=get('request_id'),revision=Number(get('revision'));
 if(!isUuid(request)||(id&&!isUuid(id))||(site&&!isUuid(site))||(outlet&&!isUuid(outlet))||!isUuid(get('assignee_id'))||!Number.isInteger(revision)||revision<0||!validBusinessDate(get('due_date'))||!actionTopics.some(v=>v===get('topic'))||!actionStates.some(v=>v===get('state')))return{error:'Check the owner, date and follow-up details.'};
 if(get('confirmed')!=='yes')return{error:'Confirm this follow-up update.'};
 const data=Object.fromEntries(['topic','site_id','outlet_id','title','description','assignee_id','due_date','priority','state','note'].map(key=>[key,get(key)]));
 const result=await client.rpc('save_management_action',{p_organisation_id:org,p_id:id||null,p_revision:revision,p_request_id:request,p_data:data});
 if(result.error)return{error:result.error.code==='22023'?result.error.message:result.error.code==='42501'?'You cannot make this follow-up change. Refresh and check your current assignment.':'Follow-up could not be saved. Reopen the record to check its status before retrying.'};
 revalidatePath('/workspace/reviews');revalidatePath('/workspace/reviews/actions');revalidatePath('/workspace');redirect(`/workspace/reviews/actions?${new URLSearchParams({organisation:org,id:result.data,saved:'1'})}`);
}
export async function saveReviewSnapshot(_previous:ReviewState,form:FormData):Promise<ReviewState>{
 const get=(key:string)=>String(form.get(key)??''),org=get('organisation'),client=await clientFor(org),period=get('period'),anchor=get('anchor'),outlet=get('outlet'),site=get('site');
 if(!client||!reviewPeriods.some(v=>v===period)||!validBusinessDate(anchor)||!isUuid(get('request'))||(outlet&&!isUuid(outlet))||(site&&!isUuid(site)))return{error:'Refresh the review and check its selection.'};
 const {data,error}=await client.rpc('save_management_review',{p_organisation_id:org,p_period:period,p_anchor:anchor,p_outlet_id:outlet||null,p_site_id:site||null,p_request_id:get('request')});
 if(error)return{error:error.code==='22023'?error.message:'The review could not be saved. Check your access and retry.'};
 revalidatePath('/workspace/reviews/history');redirect(`/workspace/reviews?${new URLSearchParams({organisation:org,snapshot:data,saved:'1'})}`);
}
