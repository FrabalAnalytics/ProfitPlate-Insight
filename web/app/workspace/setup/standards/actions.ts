"use server";
import {requireUser} from '@/lib/auth';import {createClient} from '@/lib/supabase/server';import {isUuid} from '@/lib/catalogue';import {redirect} from 'next/navigation';
import {revalidatePath} from 'next/cache';
export type SetupState={error?:string;success?:string};
export async function saveTargets(_state:SetupState,form:FormData):Promise<SetupState>{await requireUser();const org=String(form.get('organisation')??''),location=String(form.get('location_id')??'');const food=String(form.get('food')??'').trim(),beverage=String(form.get('beverage')??'').trim();if(!isUuid(org)||(location&&!isUuid(location))||[food,beverage].some(v=>v!==''&&(!/^\d{1,3}(?:\.\d{1,6})?$/.test(v)||Number(v)>100)))return{error:'Enter targets from 0 to 100, or leave blank.'};const client=await createClient();const result=await client.rpc('save_cost_targets',{p_organisation_id:org,p_location_id:location||null,p_food:food||null,p_beverage:beverage||null});if(result.error)return{error:result.error.code==='22023'?result.error.message:'You cannot update these targets.'};revalidatePath('/workspace/setup');revalidatePath('/workspace/setup/standards');revalidatePath('/workspace/menus/profitability');revalidatePath('/workspace');return{success:'Targets saved.'};}
export async function confirmOpening(_state:SetupState,form:FormData):Promise<SetupState>{await requireUser();const org=String(form.get('organisation')??''),item=String(form.get('item')??''),site=String(form.get('site')??'');if(![org,item,site].every(isUuid)||form.get('confirmed')!=='on')return{error:'Select the material, stock location and confirm the zero balance.'};const client=await createClient();const result=await client.rpc('confirm_zero_opening',{p_organisation_id:org,p_item_id:item,p_site_id:site,p_date:String(form.get('date')??''),p_note:String(form.get('note')??'')});if(result.error)return{error:result.error.code==='22023'?result.error.message:'You cannot confirm this opening balance.'};revalidatePath('/workspace/setup');revalidatePath('/workspace/setup/standards');revalidatePath('/workspace/materials');return{success:'Zero opening confirmed. No quantities were posted.'};}

export async function saveCalendar(_state:SetupState,form:FormData):Promise<SetupState>{
 await requireUser();const org=String(form.get('organisation')??''),week=String(form.get('week_start')??''),day=String(form.get('count_day')??''),cutoff=String(form.get('cutoff')??''),timezone=String(form.get('timezone')??'');
 if(!isUuid(org)||!(/^[0-6]$/.test(week)&&/^[0-6]$/.test(day))||!/^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(cutoff))return{error:'Choose the reporting week and physical count schedule.'};
 const client=await createClient(),result=await client.rpc('save_reporting_calendar',{p_organisation_id:org,p_timezone:timezone,p_week_start:Number(week),p_count_day:Number(day),p_cutoff:cutoff});
 if(result.error)return{error:'The reporting calendar could not be saved. Check your access and timezone.'};
 revalidatePath('/workspace/setup');revalidatePath('/workspace/setup/standards');return{success:'Reporting calendar saved.'};
}

export async function saveMonthlyCalendar(_state:SetupState,form:FormData):Promise<SetupState>{
 await requireUser();const org=String(form.get('organisation')??''),day=Number(form.get('day')),hours=Number(form.get('hours')),cutoff=String(form.get('cutoff')??'');
 if(!isUuid(org)||!Number.isInteger(day)||day<0||day>31||!Number.isInteger(hours)||hours<1||hours>168||!/^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(cutoff))return{error:'Choose a valid monthly day, cutoff and submission window.'};
 const client=await createClient(),result=await client.rpc('save_monthly_count_calendar',{p_organisation_id:org,p_day:day,p_cutoff:cutoff,p_hours:hours,p_evidence:String(form.get('evidence')??'')});
 if(result.error)return{error:result.error.code==='22023'?result.error.message:'Monthly schedule could not be saved. Check administrator access and update 058.'};
 for(const path of ['/workspace','/workspace/setup/standards','/workspace/inventory/counts'])revalidatePath(path);
 redirect(`/workspace/setup/standards?organisation=${org}&message=monthly-schedule-saved`);
}
