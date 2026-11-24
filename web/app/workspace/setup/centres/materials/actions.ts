"use server";
import {redirect} from 'next/navigation';
import {revalidatePath} from 'next/cache';
import {requireUser} from '@/lib/auth';
import {createClient} from '@/lib/supabase/server';
import {isUuid} from '@/lib/catalogue';
export async function saveCentreMaterials(_state:{error?:string},form:FormData):Promise<{error?:string}>{
 await requireUser();const org=String(form.get('organisation')??''),site=String(form.get('site')??''),token=String(form.get('token')??''),revision=Number(form.get('revision'));
 if(!isUuid(org)||!isUuid(site)||!isUuid(token)||!Number.isInteger(revision)||revision<0||form.get('confirmed')!=='on')return{error:'Review the centre and confirm its material list.'};
 let items:unknown;try{items=JSON.parse(String(form.get('items')));}catch{return{error:'Choose valid materials.'};}
 if(!Array.isArray(items)||items.length>5000||items.some(i=>typeof i!=='string'||!isUuid(i)))return{error:'Choose valid materials.'};
 const client=await createClient(),r=await client.rpc('save_centre_materials',{p_organisation_id:org,p_site_id:site,p_revision:revision,p_request_id:token,p_items:items});
 if(r.error)return{error:r.error.code==='22023'?r.error.message:'This list could not be saved. Check centre administration access and the latest database update.'};
 for(const path of ['/workspace','/workspace/inventory','/workspace/inventory/waste','/workspace/inventory/processing','/workspace/inventory/counts','/workspace/materials','/workspace/setup'])revalidatePath(path);
 redirect(`/workspace/setup/centres/materials?${new URLSearchParams({organisation:org,site,saved:'1'})}`);
}
