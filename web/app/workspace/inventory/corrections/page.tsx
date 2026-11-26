import Link from 'next/link';
import '@/app/components/workflow-guidance.css';
import {redirect} from 'next/navigation';
import {requireUser,getPlatformAccess,workspacePath} from '@/lib/auth';
import {createClient} from '@/lib/supabase/server';
import {WorkspaceShell} from '@/app/components/workspace-shell';
import {DataTable,StatusBadge} from '@/app/components/data-table';
import {workflowLink,type CorrectionQueue} from '@/lib/workflow-guidance';
import '../../materials/catalogue.css';import '../inventory.css';
export const instant=false;
export default async function Page({searchParams}:{searchParams:Promise<{organisation?:string;state?:string;page?:string}>}){
 const user=await requireUser(),access=await getPlatformAccess();if(access!=='member')redirect(workspacePath(access));const p=await searchParams,client=await createClient(),orgs=await client.from('organisations').select('id,name,time_zone').order('name'),org=p.organisation?orgs.data?.find(o=>o.id===p.organisation):orgs.data?.[0];if(!org)redirect('/workspace');
 const state=['ACTION','WAITING','ALL'].includes(p.state??'')?p.state!:'ACTION',page=Math.max(1,Math.min(100000,parseInt(p.page??'1')||1));
 const result=await client.rpc('stock_correction_queue',{p_organisation_id:org.id,p_state:state,p_page:page}),packet=result.data as CorrectionQueue|null;
 const href=(extra:Record<string,string>)=>workflowLink(org.id,'/workspace/inventory/corrections',{state,...extra});
 return <WorkspaceShell email={user.email} restaurantName={org.name} organisationId={org.id} sectionLabel="Balance reviews"><h1 className="workspace-title">Balance reviews</h1><p className="workspace-description">Review, approve and post verified stock corrections.</p>
 <form method="get" className="stock-filter workflow-filter"><input name="organisation" type="hidden" value={org.id}/><label>Tasks<select name="state" defaultValue={state}><option value="ACTION">Needs my action</option><option value="WAITING">My records awaiting a colleague</option><option value="ALL">All my pending records</option></select></label><button className="secondary-button">Show tasks</button></form>
 {result.error||!packet?<p role="alert">Balance tasks could not be loaded. Check your access and refresh.</p>:<><DataTable label="Balance review tasks" columns={[{label:'Record / centre'},{label:'Submitted'},{label:'Status'},{label:'Next step'},{label:'Action'}]} rows={packet.rows.map(r=>({id:r.id,cells:[<div key="name"><strong>{r.reference}</strong><small>{r.centre} / {r.kind==='COUNT'?'Balance correction':'Opening stock'}</small></div>,new Intl.DateTimeFormat('en-GB',{timeZone:org.time_zone,dateStyle:'medium',timeStyle:'short'}).format(new Date(r.created_at)),<StatusBadge key="status" tone="warning">{r.state==='APPROVED'?'Approved / not posted':r.kind==='OPENING'&&r.can_post?'Ready for Administrator recording':'Awaiting independent review'}</StatusBadge>,<div key="next">{r.next_action}{r.state==='REQUESTED'&&<small>{r.reviewers.length?r.reviewers.join(', '):'Administrator: assign another authorised management colleague'}</small>}</div>,<Link key="open" href={workflowLink(org.id,'/workspace/inventory',{view:'movements',document:r.id})}>{r.can_review?'Review correction':r.can_post?(r.kind==='OPENING'&&r.state==='REQUESTED'?'Record opening':'Post approved balance'):'View record'}</Link>]}))} empty="No balance records are waiting in this view."/><div className="stock-pagination"><span>{packet.total} records / Page {page}</span><nav>{page>1&&<Link href={href({page:String(page-1)})}>Previous</Link>}{page*20<packet.total&&<Link href={href({page:String(page+1)})}>Next</Link>}</nav></div></>}
 </WorkspaceShell>;
}
