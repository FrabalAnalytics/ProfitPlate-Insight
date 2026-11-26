import Link from 'next/link';
import {DataTable} from '@/app/components/data-table';
import {setupAreas,workflowLink,type SetupActions} from '@/lib/workflow-guidance';
export function SetupNextActions({org,packet,error,area,page}:{org:string;packet:SetupActions|null;error?:boolean;area:string;page:number}){
 const link=(changes:Record<string,string>)=>`?${new URLSearchParams({organisation:org,area,...changes})}#setup-actions`;
 return <section id="setup-actions" className="setup-checklist" aria-label="Complete setup"><div className="section-heading"><h2>Complete setup</h2><span>{packet?`${packet.remaining} tasks remaining`:'Status unavailable'}</span></div>
 {error||!packet?<p role="alert">Setup tasks could not be loaded. Refresh before relying on the readiness summary.</p>:<>
 {packet.next?<div className="setup-priority" aria-label="Next setup step"><div><small>Next step</small><h3>{packet.next.title}</h3><p>{packet.next.detail}</p><small>{packet.next.responsible}{packet.next.centre_owner?` · Centre owner: ${packet.next.centre_owner}`:''}</small></div><Link className="secondary-button" href={workflowLink(org,packet.next.path,packet.next.params)}>Complete this step</Link></div>:<p className="stock-success">No gaps found in the current setup checks. Verify your opening balances, menu mappings and team access before going live.</p>}
 <form method="get" className="setup-action-filter"><input type="hidden" name="organisation" value={org}/><label htmlFor="setup-area">Setup area</label><select name="area" id="setup-area" defaultValue={area}>{Object.entries(setupAreas).map(([key,label])=><option value={key} key={key}>{label}</option>)}</select><button className="secondary-button">Show tasks</button></form>
 <DataTable label="Setup tasks" columns={[{label:'Task / centre'},{label:'Responsible'},{label:'Action'}]} rows={packet.rows.map(row=>({id:row.id,cells:[<span key="task">{row.title}<small>{row.detail}</small></span>,<span key="owner">{row.responsible}{row.centre_owner&&<small>Centre owner: {row.centre_owner}</small>}</span>,<Link key="open" className="inline-link" href={workflowLink(org,row.path,row.params)}>Complete step</Link>]}))} empty="No tasks in this setup area."/>
 <nav className="invoice-nav" aria-label="Setup task pages"><span>{packet.total} matching tasks · Page {page}</span>{page>1&&<Link href={link({task_page:String(page-1)})}>Previous tasks</Link>}{page*20<packet.total&&<Link href={link({task_page:String(page+1)})}>Next tasks</Link>}</nav>
 </>}
 </section>;
}
