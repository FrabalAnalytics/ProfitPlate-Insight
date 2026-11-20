"use server";
import {requireUser} from '@/lib/auth';
import {createClient} from '@/lib/supabase/server';
import {isUuid} from '@/lib/catalogue';
import {validBusinessDate} from '@/lib/recipes';
import type {MaterialPlan,PlanOptions} from '@/lib/material-plans';
export type PlanState={error?:string;plan?:MaterialPlan};
export async function planOptions(org:string,site:string,date:string):Promise<{data?:PlanOptions;error?:string}>{
 await requireUser();if(!isUuid(org)||!isUuid(site)||!validBusinessDate(date))return{error:'Choose a centre and valid plan date.'};
 const client=await createClient(),r=await client.rpc('material_plan_options',{p_organisation_id:org,p_site_id:site,p_date:date});
 return r.error?{error:['22023','42501'].includes(r.error.code)?r.error.message:'Recipes could not be loaded. Check access and the material planning update.'}:{data:r.data};
}
export async function generatePlan(_state:PlanState,form:FormData):Promise<PlanState>{
 await requireUser();const org=String(form.get('organisation')??''),site=String(form.get('site')??''),date=String(form.get('date')??''),basis=String(form.get('basis')??'STOCK'),source=String(form.get('rows')??'');
 if(!isUuid(org)||!isUuid(site)||!validBusinessDate(date)||source.length>32768||!['STOCK','RECIPE'].includes(basis))return{error:'Check the centre, date and selected recipes.'};
 let rows:unknown;try{rows=JSON.parse(source);}catch{return{error:'Check the recipe targets.'};}
 const client=await createClient(),r=await client.rpc('generate_material_plan',{p_organisation_id:org,p_site_id:site,p_date:date,p_rows:rows,p_basis:basis});
 return r.error?{error:['22023','42501'].includes(r.error.code)?r.error.message:'The material plan could not be generated. Check setup and try again.'}:{plan:r.data};
}
