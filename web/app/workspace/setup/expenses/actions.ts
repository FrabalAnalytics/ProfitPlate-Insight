'use server';
import {requireUser} from '@/lib/auth';import {createClient} from '@/lib/supabase/server';import {isUuid} from '@/lib/catalogue';import {parseExpenseCategories} from '@/lib/expense-categories';import {revalidatePath} from 'next/cache';
export type CategoryState={error?:string;success?:boolean;evidence?:string;savedCodes?:string[]};
export async function saveCategories(_state:CategoryState,form:FormData):Promise<CategoryState>{
 await requireUser();const org=String(form.get('organisation')??'');if(!isUuid(org))return{..._state,success:false,error:'Choose an available restaurant.'};let rows;try{rows=parseExpenseCategories(String(form.get('categories')??''));}catch(e){return{..._state,success:false,error:e instanceof Error?e.message:'Check categories.'};}
 const client=await createClient(),r=await client.rpc('save_expense_categories',{p_organisation_id:org,p_evidence:String(form.get('evidence')??''),p_categories:rows});if(r.error)return{..._state,success:false,error:['22023','42501'].includes(r.error.code)?r.error.message:'Categories could not be saved. Check your access and setup update.'};
 for(const path of ['/workspace/setup/expenses','/workspace/expenses','/workspace'])revalidatePath(path);return{success:true,evidence:r.data.evidence,savedCodes:rows.map(r=>r.code)};
}
