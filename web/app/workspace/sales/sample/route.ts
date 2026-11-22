import {getUser} from '@/lib/auth';
import {createClient} from '@/lib/supabase/server';
import {isUuid} from '@/lib/catalogue';
import {historicalCsvCell} from '@/lib/operational-reports';
import {salesHeaders} from '@/lib/sales-imports';

export async function GET(request:Request){
 const failure=(error:string,status:number)=>Response.json({error},{status,headers:{'Cache-Control':'private, no-store'}});
 try {
 if(!await getUser())return failure('Your session has expired. Sign in again, then retry the download.',401);
 const org=new URL(request.url).searchParams.get('organisation')??'';
 if(!isUuid(org))return failure('Choose your training restaurant.',400);
 const client=await createClient(),{data,error}=await client.rpc('sales_training_sample',{p_organisation_id:org});
 if(error?.code==='22023')return failure(error.message,400);
 if(error?.code==='42501')return failure('Your account does not have sales-import access to this restaurant.',403);
 if(error||!data)return failure('The training sample service is unavailable. Please try again shortly.',503);
 const prefix=`TRAINING-${String(data.date).replaceAll('-','')}`;
 const rows:unknown[][]=[[...salesHeaders],['TRAINING','PROFITPLATE_TRAINING',data.location,data.date,`${prefix}-01`,'L1',data.menu_name,'2','12000','0','0','12000',data.channel,'NORMAL','','PAID'],['TRAINING','PROFITPLATE_TRAINING',data.location,data.date,`${prefix}-02`,'L1',data.menu_name,'1','6000','150','0','5850',data.channel,'NORMAL','','PAID']];
 const csv='\uFEFF'+rows.map(row=>row.map(historicalCsvCell).join(',')).join('\r\n');
 return new Response(csv,{headers:{'Content-Type':'text/csv;charset=utf-8','Content-Disposition':`attachment; filename="ProfitPlate_training_sales_${data.date}.csv"`,'Cache-Control':'private, no-store'}});
 }catch{return failure('The training sample service could not be reached. Please try again shortly.',503);}
}
