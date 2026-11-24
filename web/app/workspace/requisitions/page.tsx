import type {Metadata} from 'next';
import {randomUUID} from 'node:crypto';
import Link from 'next/link';
import {redirect} from 'next/navigation';
import {requireUser,getPlatformAccess,workspacePath} from '@/lib/auth';
import {createClient} from '@/lib/supabase/server';
import {isUuid} from '@/lib/catalogue';
import {displayQuantity} from '@/lib/recipes';
import {stockStates} from '@/lib/inventory';
import {stockProgress} from '@/lib/stock-progress';
import {requisitionQueues,requisitionFilters,unacceptedQuantity,type RequisitionPacket} from '@/lib/requisitions';
import {WorkspaceShell} from '@/app/components/workspace-shell';
import {DataTable,StatusBadge} from '@/app/components/data-table';
import {StockRequest,StockDecision} from '../inventory/forms';
import '../materials/catalogue.css';
import '../inventory/inventory.css';
import './requisitions.css';
export const metadata:Metadata={title:'Requisitions | ProfitPlate Insights'};
export const instant=false;
type Params={organisation?:string;location?:string;status?:string;queue?:string;q?:string;page?:string;document?:string;new?:string;result?:string};
export default async function RequisitionsPage({searchParams}:{searchParams:Promise<Params>}){
 const user=await requireUser(),access=await getPlatformAccess();if(access!=='member')redirect(workspacePath(access));
 const p=await searchParams,client=await createClient(),orgs=await client.from('organisations').select('id,name,time_zone').order('name').order('id'),org=p.organisation?orgs.data?.find(o=>o.id===p.organisation):orgs.data?.[0];
 if(!org)return <WorkspaceShell email={user.email}><h1 className="workspace-title">This business is unavailable.</h1><Link href="/workspace">Return to workspace</Link></WorkspaceShell>;
 const shell={email:user.email,restaurantName:org.name,organisationId:org.id,sectionLabel:'Requisitions'},page=Number(p.page??1),status=p.status??'ALL',queue=p.queue??'ALL',location=p.location??'',q=(p.q??'').trim().slice(0,80);
 const href=(extra:Record<string,string>={})=>`/workspace/requisitions?${new URLSearchParams({organisation:org.id,...(location?{location}:{}),...(status!=='ALL'?{status}:{}),...(queue!=='ALL'?{queue}:{}),...(q?{q}:{}),...extra})}`;
 if((location&&!isUuid(location))||(p.document&&!isUuid(p.document))||!Number.isInteger(page)||page<1||page>100000||!(status in requisitionFilters)||(queue!=='ALL'&&!(queue in requisitionQueues)))return <WorkspaceShell {...shell}><p role="alert" className="auth-alert">Choose valid requisition filters.</p><Link href={`/workspace/requisitions?organisation=${org.id}`}>Clear filters</Link></WorkspaceShell>;
 const r=await client.rpc('requisition_workspace',{p_organisation_id:org.id,p_location_id:location||null,p_page:page,p_status:status,p_search:q,p_document_id:p.document||null,p_queue:queue});
 if(r.error)return <WorkspaceShell {...shell}><h1 className="workspace-title">Requisitions are unavailable.</h1><p role="alert" className="auth-alert">{r.error.code==='PGRST202'?'The requisition update needs to be completed before this page is available.':'Check your centre access, then refresh.'}</p></WorkspaceShell>;
 const packet=r.data as RequisitionPacket,selected=packet.selected_document,canRequest=packet.routes.some(route=>route.is_active&&packet.locations.some(s=>s.is_active&&s.request&&(s.id===route.source_id||s.id===route.destination_id))),progress=selected?stockProgress(selected):null;
 const parts=new Intl.DateTimeFormat('en',{timeZone:org.time_zone,year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date()),today=['year','month','day'].map(k=>parts.find(x=>x.type===k)?.value).join('-');
 const context=new URLSearchParams({...(location?{location}:{}),status,queue,...(q?{q}:{}),page:String(page)}).toString();
 const stage=selected?({REQUESTED:0,APPROVED:1,DISPATCHED:2,RECEIVED:3,PARTIAL:3} as Record<string,number>)[selected.state]:undefined;
 return <WorkspaceShell {...shell}>
 <div className="page-heading-row"><div><h1 className="workspace-title">Requisitions</h1><p className="workspace-description">Request materials. Track dispatch. Confirm receipt.</p></div>{canRequest&&<Link className="secondary-button" href={href({new:'1'})+'#new-requisition'}>New requisition</Link>}</div>
 <nav className="requisition-queues" aria-label="Requisition task queues">{Object.entries(requisitionQueues).map(([key,label])=><Link key={key} href={href({queue:queue===key?'ALL':key,status:'ALL'})} aria-current={queue===key?'page':undefined}><span>{label}</span><strong>{packet.queues[key as keyof typeof requisitionQueues]}</strong></Link>)}</nav>
 <form method="get" className="stock-filter requisition-filter"><input type="hidden" name="organisation" value={org.id}/>{queue!=='ALL'&&<input type="hidden" name="queue" value={queue}/>}<div className="setup-field"><label htmlFor="req-search">Find requisition</label><input id="req-search" name="q" type="search" defaultValue={q} maxLength={80} placeholder="Reference or reason"/></div><div className="setup-field"><label htmlFor="req-centre">Centre</label><select id="req-centre" name="location" defaultValue={location}><option value="">All permitted centres</option>{packet.locations.filter(s=>s.read).map(s=><option key={s.id} value={s.id}>{s.name}</option>)}</select></div><div className="setup-field"><label htmlFor="req-status">Status</label><select id="req-status" name="status" defaultValue={status}>{Object.entries(requisitionFilters).map(([key,label])=><option key={key} value={key}>{label}</option>)}</select></div><button className="secondary-button">Apply filters</button><Link className="inline-link" href={`/workspace/requisitions?organisation=${org.id}`}>Clear</Link></form>
 {p.new==='1'&&!selected&&<section id="new-requisition">{canRequest?<><StockRequest requisitions returnContext={context} organisation={org.id} packet={packet} request={randomUUID()} today={today}/><Link className="inline-link" href={href()}>Cancel new requisition</Link></>:<p role="alert" className="auth-alert">No permitted request route is available. Ask your administrator to review centre access and routes.</p>}</section>}
 {p.document&&!selected&&<p className="auth-alert" role="alert">This requisition is unavailable or outside your centre access.</p>}
 {selected&&<section className="stock-panel" aria-label="Requisition detail"><div className="stock-detail-heading"><div><h2>{selected.reference}</h2><p className="stock-help">{selected.source_name} → {selected.destination_name} · {selected.document_date}</p><StatusBadge tone={selected.state==='RECEIVED'?'success':['PARTIAL','REJECTED'].includes(selected.state)?'danger':'neutral'}>{selected.state==='APPROVED'?'Ready to dispatch':stockStates[selected.state]}{selected.resolved_at?' / resolved':''}</StatusBadge></div><Link className="inline-link" href={href({page:String(page)})}>Close requisition</Link></div>
 <ol className="requisition-progress" aria-label="Requisition progress">{['Requested','Approved','Dispatched','Accepted'].map((label,n)=><li key={label} className={stage!==undefined&&n<=stage?'reached':''} aria-current={stage===n?'step':undefined}><span>{n+1}</span>{label}{n===3&&selected.state==='PARTIAL'?' in part':''}</li>)}</ol>
 {progress&&<div className="stock-progress" role="status"><strong>{progress.title}</strong><p>{progress.detail}</p></div>}
 <DataTable label="Requisition materials" columns={[{label:'Material'},{label:'Unit'},{label:'Requested',numeric:true},{label:'Accepted',numeric:true},{label:'Not accepted',numeric:true},{label:'Reason'}]} rows={selected.lines.map(l=>{const accepted=selected.received_lines?.find(a=>a.item_id===l.item_id);return{id:l.item_id,cells:[l.name,l.unit,displayQuantity(l.quantity),accepted?displayQuantity(accepted.quantity):'—',accepted?displayQuantity(unacceptedQuantity(l.quantity,accepted.quantity)):'—',accepted?.reason||'—']};})}/>
 <p className="stock-note">{selected.note}</p>
 <StockDecision key={`${selected.id}:${selected.state}:${selected.resolved_at??''}`} requisitions returnContext={context} organisation={org.id} document={selected}/>
 <details className="requisition-history"><summary>People & decision history</summary><dl className="stock-audit"><div><dt>Requested by</dt><dd>{selected.created_label}</dd></div><div><dt>Approved by</dt><dd>{selected.approved_label??'Pending'}</dd></div><div><dt>Dispatched by</dt><dd>{selected.dispatched_label??'—'}</dd></div><div><dt>Received by</dt><dd>{selected.completed_label??'—'}</dd></div><div><dt>Latest decision</dt><dd>{selected.decision_note??'—'}</dd></div></dl>{selected.resolution_note&&<p>{selected.resolution_note}</p>}</details>
 </section>}
 <section className="stock-panel"><div className="stock-detail-heading"><h2>{queue==='ALL'?'Requisition records':requisitionQueues[queue as keyof typeof requisitionQueues]}</h2><span className="stock-help">{packet.total} records</span></div><DataTable label="Requisition register" columns={[{label:'Requisition / date'},{label:'From'},{label:'To'},{label:'Materials',numeric:true},{label:'Status'},{label:'Action'}]} rows={packet.documents.map(d=>({id:d.id,cells:[<span key="ref">{d.reference}<small>{d.document_date}</small></span>,d.source_name??'—',d.destination_name??'—',String(d.lines.length),<StatusBadge key="state" tone={d.state==='RECEIVED'?'success':['PARTIAL','REJECTED'].includes(d.state)?'danger':'neutral'}>{d.state==='APPROVED'?'Ready to dispatch':stockStates[d.state]}{d.resolved_at?' / resolved':''}</StatusBadge>,<Link key="action" className="inline-link" aria-label={`Review ${d.reference}`} href={href({page:String(page),document:d.id})}>Open</Link>]}))} empty="No requisitions match these filters."/>
 <div className="stock-pagination"><span>{packet.total?`${(page-1)*10+1}–${Math.min(page*10,packet.total)} of ${packet.total}`:'0 records'} · Page {page}</span><nav aria-label="Requisition pages">{page>1&&<Link className="secondary-button" href={href({page:String(page-1)})}>Previous</Link>}{page*10<packet.total&&<Link className="secondary-button" href={href({page:String(page+1)})}>Next</Link>}</nav></div></section>
 </WorkspaceShell>;
}
