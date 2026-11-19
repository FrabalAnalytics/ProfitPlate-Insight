import Link from "next/link";
import {redirect} from "next/navigation";
import {requireUser,getPlatformAccess,workspacePath} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {workspacePolicy} from "@/lib/workspace-policy-server";
import {WorkspaceShell} from "@/app/components/workspace-shell";
import {DataTable,StatusBadge} from "@/app/components/data-table";
import {displayQuantity} from "@/lib/recipes";
import {isUuid} from "@/lib/catalogue";
import type {ProcessingSetup,WasteRecord} from "@/lib/processing";
import "../inventory.css";
import "../../materials/catalogue.css";
import "./waste.css";
export const instant=false;
type Params={organisation?:string;site?:string;from?:string;to?:string;kind?:string;state?:string;page?:string};
export default async function WastePage({searchParams}:{searchParams:Promise<Params>}){
 const user=await requireUser(),access=await getPlatformAccess();if(access!=="member")redirect(workspacePath(access));
 const p=await searchParams,client=await createClient(),orgs=await client.from("organisations").select("id,name,time_zone").order("name"),org=p.organisation?orgs.data?.find(o=>o.id===p.organisation):orgs.data?.[0];
 if(!org)return <WorkspaceShell email={user.email}><h1>Business unavailable</h1></WorkspaceShell>;
 const [setupResult,policy]=await Promise.all([client.rpc("processing_setup",{p_organisation_id:org.id}),workspacePolicy(org.id)]),setup=setupResult.data as ProcessingSetup|null,centres=setup?.waste_sites??[],own=setup?.waste_own_centres===true;
 const parts=new Intl.DateTimeFormat("en",{timeZone:org.time_zone,year:"numeric",month:"2-digit",day:"2-digit"}).formatToParts(new Date()),today=["year","month","day"].map(k=>parts.find(x=>x.type===k)?.value).join("-");
 const site=p.site??(own?centres[0]?.id??"":""),from=p.from??`${today.slice(0,7)}-01`,to=p.to??today,kind=p.kind??(policy.financeOnly?"WASTE":"LOSSES"),state=p.state??"ALL",page=Number(p.page??1);
 const valid=(!site||isUuid(site))&&/^\d{4}-\d{2}-\d{2}$/.test(from)&&/^\d{4}-\d{2}-\d{2}$/.test(to)&&["WASTE","LOSSES","PROCESSING"].includes(kind)&&Number.isInteger(page)&&page>0&&page<=100000;
 const result=valid?await client.rpc("centre_waste_report",{p_organisation_id:org.id,p_site_id:site||null,p_from:from,p_to:to,p_kind:kind,p_page:page,p_state:state,p_export:false}):null,packet=result?.data as {total:number;processing_entries:number;standalone_entries:number;posted_entries:number;rows:WasteRecord[]}|null;
 const query=new URLSearchParams({organisation:org.id,site,from,to,kind,state}),href=(n:number)=>`?${query}&page=${n}`,canRecord=centres.some(s=>s.is_active&&s.can_record),extraFilters=kind!==(policy.financeOnly?"WASTE":"LOSSES")||state!=="ALL";
 return <WorkspaceShell email={user.email} restaurantName={org.name} organisationId={org.id} sectionLabel={policy.financeOnly?"Waste across centres":"Waste Log"}>
  <Link className="catalogue-back" href={`/workspace?organisation=${org.id}`}>Back to workspace</Link>
  <div className="page-heading-row"><div><h1 className="workspace-title">{policy.financeOnly?"Waste across centres":"Waste Log"}</h1><p className="workspace-description">{own?"Waste at your centres.":"Waste by centre, material and date."}</p></div>{canRecord&&<Link className="auth-button catalogue-add" href={`/workspace/inventory/waste/new?organisation=${org.id}${site?`&site=${site}`:""}`}>Record waste</Link>}</div>
  <form method="get" className="waste-filters"><input type="hidden" name="organisation" value={org.id}/><div className="waste-filter-main"><div className="setup-field"><label htmlFor="history-centre">Stock centre</label><select id="history-centre" name="site" defaultValue={site}>{!own&&<option value="">All permitted centres</option>}{own&&!centres.length&&<option value="">No responsible centre assigned</option>}{centres.map(s=><option key={s.id} value={s.id}>{s.name}</option>)}</select></div><div className="setup-field"><label htmlFor="processing-history-from">From</label><input id="processing-history-from" name="from" type="date" required defaultValue={from}/></div><div className="setup-field"><label htmlFor="processing-history-to">Through</label><input id="processing-history-to" name="to" type="date" required defaultValue={to}/></div><button className="secondary-button">Filter waste log</button></div>
   <details open={extraFilters}><summary>Source &amp; status</summary><div className="waste-filter-extra"><div className="setup-field"><label htmlFor="processing-history-kind">Waste source</label><select id="processing-history-kind" name="kind" defaultValue={kind}><option value="WASTE">Processing &amp; other waste</option><option value="LOSSES">Waste outside processing</option><option value="PROCESSING">Processing loss only</option></select></div><div className="setup-field"><label htmlFor="processing-history-state">Record state</label><select id="processing-history-state" name="state" defaultValue={state}>{["ALL","POSTED","REQUESTED","APPROVED","CANCELLED","REJECTED"].map(s=><option key={s} value={s}>{s==="ALL"?"All states":s==="POSTED"?"Recorded":["REQUESTED","APPROVED"].includes(s)?`Unposted (${s.toLowerCase()})`:s.toLowerCase()}</option>)}</select></div></div></details>
  </form>
  {own&&!centres.length?<p className="stock-help">Ask your administrator to assign your stock centre.</p>:!packet||result?.error?<p className="auth-alert" role="alert">Waste records could not be loaded. Check centre access, dates (up to 367 days) and the latest database update.</p>:<section className="stock-panel">
   <div className="waste-report-heading"><p>{packet.total} material {packet.total===1?"entry":"entries"} / {packet.posted_entries} recorded</p><Link className="secondary-button" href={`/workspace/inventory/waste/export?${query}`}>Export CSV</Link></div>
   <DataTable label="Centre waste log" columns={[{label:"Date / record"},{label:"Centre / material"},{label:"Quantity",numeric:true},{label:"Reason"},{label:"Submitter"},{label:"Source"},{label:"State"}]} rows={packet.rows.map((w,index)=>({id:`${w.id}:${w.item_id}:${index}`,cells:[<Link key="doc" className="inline-link" href={`/workspace/inventory?organisation=${org.id}&view=movements&document=${w.id}`}>{w.reference}<small>{w.document_date}</small></Link>,<span key="place">{w.material}<small>{w.site}</small></span>,`${displayQuantity(w.quantity)} ${w.unit}`,w.reason,w.submitter_name??"Not recorded on older entry",w.included_in_production?"Processing":"Other waste",<StatusBadge key="state" tone={w.state==="POSTED"?"success":"neutral"}>{w.state==="POSTED"?"Recorded":w.state.toLowerCase()}</StatusBadge>]}))} empty="No waste entries match these filters."/>
   <nav className="invoice-nav" aria-label="Waste history pages"><span>Page {page}</span>{page>1&&<Link href={href(page-1)}>Previous records</Link>}{page*10<packet.total&&<Link href={href(page+1)}>Next records</Link>}</nav>
   <details className="waste-basis"><summary>How to read this report</summary><p>Processing loss is included in its batch inputs and is not deducted again. Other waste has its own stock posting. Only recorded entries have affected stock; unposted and cancelled entries remain visible for history.</p><p>Quantities retain their material units. No waste value is inferred from quantities, and an empty report does not confirm that all waste was measured.</p></details>
  </section>}
 </WorkspaceShell>;
}
