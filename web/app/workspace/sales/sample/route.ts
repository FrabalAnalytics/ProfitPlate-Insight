import {requireUser} from '@/lib/auth';
import {createClient} from '@/lib/supabase/server';
import {isUuid} from '@/lib/catalogue';
import {historicalCsvCell} from '@/lib/operational-reports';
import {salesHeaders} from '@/lib/sales-imports';

export async function GET(request:Request){
 await requireUser();const org=new URL(request.url).searchParams.get('organisation')??'';
 if(!isUuid(org))return new Response('Choose your training restaurant.',{status:400});
 const client=await createClient(),{data,error}=await client.rpc('sales_training_sample',{p_organisation_id:org});
 if(error||!data)return new Response(error?.code==='22023'?error.message:'Training sample unavailable for this account.',{status:error?.code==='22023'?400:403});
 const prefix=`TRAINING-${String(data.date).replaceAll('-','')}`;
 const rows:unknown[][]=[[...salesHeaders],['TRAINING','PROFITPLATE_TRAINING',data.location,data.date,`${prefix}-01`,'L1',data.menu_name,'2','12000','0','0','12000',data.channel,'NORMAL','','PAID'],['TRAINING','PROFITPLATE_TRAINING',data.location,data.date,`${prefix}-02`,'L1',data.menu_name,'1','6000','150','0','5850',data.channel,'NORMAL','','PAID']];
 const csv='\uFEFF'+rows.map(row=>row.map(historicalCsvCell).join(',')).join('\r\n');
 return new Response(csv,{headers:{'Content-Type':'text/csv;charset=utf-8','Content-Disposition':`attachment; filename="ProfitPlate_training_sales_${data.date}.csv"`,'Cache-Control':'private, no-store'}});
}
