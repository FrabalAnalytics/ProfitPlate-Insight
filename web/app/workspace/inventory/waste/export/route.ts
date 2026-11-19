import {getUser,getPlatformAccess} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {isUuid} from "@/lib/catalogue";
import {historicalCsvCell} from "@/lib/operational-reports";
export async function GET(request:Request){
 const headers={"Cache-Control":"private, no-store"},user=await getUser();if(!user||await getPlatformAccess()!=="member")return new Response("Sign in to your restaurant.",{status:401,headers});
 const p=new URL(request.url).searchParams,organisation=p.get("organisation"),site=p.get("site"),from=p.get("from"),to=p.get("to");
 if(!organisation||!isUuid(organisation)||(site&&!isUuid(site))||!from||!to||!/^\d{4}-\d{2}-\d{2}$/.test(from)||!/^\d{4}-\d{2}-\d{2}$/.test(to))return new Response("Choose a business, centre and date range.",{status:400,headers});
 const client=await createClient(),result=await client.rpc("centre_waste_report",{p_organisation_id:organisation,p_site_id:site||null,p_from:from,p_to:to,p_kind:p.get("kind")??"WASTE",p_page:1,p_state:p.get("state")??"ALL",p_export:true});
 if(result.error)return new Response(result.error.code==="22023"?result.error.message:"Waste export unavailable for this access.",{status:result.error.code==="42501"?403:result.error.code==="22023"?400:503,headers});
 const packet=result.data as {rows:Record<string,unknown>[]},columns=["document_date","reference","site","material","quantity","unit","reason","submitter_name","recorded_by","source","state"];
 const csv="\uFEFF"+[columns,...packet.rows.map(row=>columns.map(k=>k==="source"?row.included_in_production?"Processing":"Other waste":row[k]))].map(row=>row.map(historicalCsvCell).join(",")).join("\r\n");
 return new Response(csv,{headers:{...headers,"Content-Type":"text/csv; charset=utf-8","Content-Disposition":`attachment; filename="waste-${from}-to-${to}.csv"`}});
}
