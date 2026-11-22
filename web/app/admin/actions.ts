"use server";
import {requirePlatformAdmin} from '@/lib/auth';
import {createClient} from '@/lib/supabase/server';
import {isUuid} from '@/lib/catalogue';
import {redirect} from "next/navigation";
import {revalidatePath} from 'next/cache';
export async function changeRestaurantAccess(_state:{error?:string;success?:string},form:FormData):Promise<{error?:string;success?:string}>{
 await requirePlatformAdmin();
 const org=String(form.get('organisation')??''),state=String(form.get('state')??''),expected=String(form.get('expected')??''),reason=String(form.get('reason')??'').trim();
 if(!isUuid(org)||!['ACTIVE','INACTIVE'].includes(state)||!['PENDING','ACTIVE','INACTIVE'].includes(expected)||reason.length<3||reason.length>500||form.get('confirmed')!=='on')return{error:'Confirm the access change and provide a reason.'};
 const client=await createClient(),result=await client.rpc('set_restaurant_access',{p_organisation_id:org,p_expected_state:expected,p_state:state,p_reason:reason,p_confirmed:true});
 if(result.error)return{error:result.error.code==='40001'?'Access has changed. Refresh and review the current status.':'The access change could not be saved. Refresh and try again.'};
 revalidatePath('/admin');revalidatePath('/workspace');revalidatePath('/account-access');
 const message=state==='ACTIVE'?(expected==='PENDING'?'approved':'reactivated'):(expected==='PENDING'?'declined':'inactive');
 redirect(`/admin?business=${org}&message=${message}`);
}
