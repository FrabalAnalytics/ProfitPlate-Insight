import { getUser,getPlatformAccess } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { isUuid } from "@/lib/catalogue";
import { validBusinessDate } from "@/lib/recipes";
import { historicalRpc,historicalCsv,isPurchasingReport,purchasingRpc,purchasingView,purchasingStatus,type HistoricalOptions,type HistoricalReport,type HistoricalParams,type ReportExportContext } from "@/lib/operational-reports";
import { purchasingWorkbook } from "@/lib/report-workbook";

export async function GET(request:Request){
 const headers={"Cache-Control":"private, no-store","X-Content-Type-Options":"nosniff"};
 const fail=(message:string,status:number)=>Response.json({error:message},{status,headers});
 const user=await getUser();if(!user)return fail("Sign in to export historical reports.",401);
 if(await getPlatformAccess()!=="member")return fail("Restaurant membership is required.",403);
 const url=new URL(request.url),p=Object.fromEntries(url.searchParams) as HistoricalParams,format=url.searchParams.get("format")??"csv";
 if(!["csv","xlsx"].includes(format))return fail("Choose CSV or Excel export.",400);
 if(!p.organisation||!isUuid(p.organisation)||!p.from||!p.to||!validBusinessDate(p.from)||!validBusinessDate(p.to)||p.outlet&&!isUuid(p.outlet)||p.site&&!isUuid(p.site)||[p.supplier,p.material,p.user].some(id=>id&&!isUuid(id))||(p.q??"").length>80)return fail("Choose a valid business, dates and report filters.",400);
 const client=await createClient();
 const org=await client.from("organisations").select("id,name").eq("id",p.organisation).maybeSingle();
 if(org.error||!org.data)return fail("This business is unavailable.",403);
 const access=await client.rpc("operational_report_options",{p_organisation_id:p.organisation,p_type:p.type??null});
 if(access.error||!access.data)return fail("This historical report is unavailable for your current access.",403);
 let options=access.data as HistoricalOptions;
 const purchasing=isPurchasingReport(options.selected);
 if(purchasing){const extended=await client.rpc("purchasing_report_options",{p_organisation_id:p.organisation,p_type:options.selected});if(extended.error||!extended.data)return fail("The purchasing report is unavailable for your current access.",403);options=extended.data as HistoricalOptions;}
 if(format==="xlsx"&&!purchasing)return fail("Excel export is available for PO and GRN reports. Use CSV for this report.",400);
 const result=purchasing?await client.rpc("purchasing_history_report",purchasingRpc(p.organisation,options.selected,{...p,page:"1"},p.from,p.to,true)):await client.rpc("operational_report",historicalRpc(p.organisation,options.selected,{...p,page:"1"},p.from,p.to,true));
 if(result.error||!result.data)return fail(result.error?.code==="22023"?result.error.message:result.error?.code==="42501"?"The selected report or location is outside your current access.":"The export could not be created. Try again shortly.",result.error?.code==="22023"?400:result.error?.code==="42501"?403:503);
 const context:ReportExportContext={business:org.data.name,type:options.selected,from:p.from,to:p.to,outlet:options.outlets.find(o=>o.id===p.outlet)?.name??"All permitted outlets",site:options.stock_locations.find(s=>s.id===p.site)?.name??"All permitted stock locations",status:purchasing?purchasingStatus({...p,type:options.selected}).status:p.status??"ALL",search:p.q??"",view:purchasing?purchasingView(p):undefined,supplier:options.suppliers?.find(s=>s.id===p.supplier)?.name??"All permitted suppliers",material:options.materials?.find(m=>m.id===p.material)?.name??"All materials",user:options.users?.find(u=>u.id===p.user)?.name??"All permitted users",receiving:purchasingStatus({...p,type:options.selected}).receiving};
 const filename=`profitplate-${options.selected.toLowerCase()}${purchasing?`-${purchasingView(p).toLowerCase()}`:""}-${p.from}-${p.to}.${format}`;
 if(format==="xlsx")return new Response(new Uint8Array(purchasingWorkbook(result.data as HistoricalReport,context)),{headers:{...headers,"Content-Type":"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet","Content-Disposition":`attachment; filename="${filename}"`}});
 return new Response(historicalCsv(result.data as HistoricalReport,context),{headers:{...headers,"Content-Type":"text/csv; charset=utf-8","Content-Disposition":`attachment; filename="${filename}"`}});
}
