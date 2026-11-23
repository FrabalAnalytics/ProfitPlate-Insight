import {randomUUID} from 'node:crypto';
import Link from 'next/link';
import {redirect} from 'next/navigation';
import {requireUser,getPlatformAccess,workspacePath} from '@/lib/auth';
import {createClient} from '@/lib/supabase/server';
import {isUuid} from '@/lib/catalogue';
import {reviewLabel,type FollowUpPacket} from '@/lib/management-reviews';
import {WorkspaceShell} from '@/app/components/workspace-shell';
import {DataTable,StatusBadge} from '@/app/components/data-table';
import {FollowUpForm} from './form';
import '../../materials/catalogue.css';import '../reviews.css';
export const instant=false;
export default async function Page({searchParams}:{searchParams:Promise<{organisation?:string;state?:string;page?:string;id?:string;new?:string;saved?:string;topic?:string;site?:string;outlet?:string}>}){
 const user=await requireUser(),platform=await getPlatformAccess();if(platform!=='member')redirect(workspacePath(platform));const p=await searchParams,client=await createClient(),orgs=await client.from('organisations').select('id,name').order('name'),org=p.organisation?orgs.data?.find(o=>o.id===p.organisation):orgs.data?.[0];if(!org)redirect('/workspace');
 const page=Math.max(1,Math.min(100000,Number.parseInt(p.page??'1',10)||1)),state=p.state??'ACTIVE',result=!p.id||isUuid(p.id)?await client.rpc('management_actions',{p_organisation_id:org.id,p_state:state,p_page:page,p_id:p.id||null}):null,packet=result?.data as FollowUpPacket|null;
 const href=(extra:Record<string,string>={})=>`/workspace/reviews/actions?${new URLSearchParams({organisation:org.id,...extra})}`,record=p.id?packet?.rows[0]:undefined;
 return <WorkspaceShell email={user.email} restaurantName={org.name} organisationId={org.id} sectionLabel="Action register"><div className="page-heading-row"><div><p className="eyebrow form-eyebrow">MANAGEMENT FOLLOW-UP</p><h1 className="workspace-title">Action register</h1></div><div className="review-controls"><Link className="secondary-button" href={`/workspace/reviews?organisation=${org.id}`}>Management review</Link><Link className="auth-button" href={href({new:'1'})}>Create follow-up</Link></div></div>
 {!packet||result?.error?<p role="alert" className="auth-alert">{result?.error?.code==='22023'?result.error.message:'Follow-up is unavailable. Check your current access and refresh.'}</p>:<>
 <div className="review-grid"><article className="review-card"><span>Open / in progress</span><strong>{packet.summary.open}</strong></article><article className="review-card"><span>Overdue, not closed</span><strong>{packet.summary.overdue}</strong></article><article className="review-card"><span>Resolved, awaiting closure</span><strong>{packet.summary.resolved}</strong></article></div>
 {p.saved==='1'&&record&&<p role="status" className="stock-success">Follow-up saved · {reviewLabel(record.state)} · Revision {record.revision}</p>}
 {p.new==='1'||record?<section className="review-panel"><h2>{record?record.title:'New follow-up'}</h2><FollowUpForm key={`${record?.id??'new'}:${record?.revision??0}`} org={org.id} access={packet.access} request={randomUUID()} existing={record} topic={p.topic} site={p.site} outlet={p.outlet} today={packet.today}/>{record&&<><h2>Update history</h2><ul className="review-action-history">{packet.events.map(e=><li key={e.revision}><strong>{reviewLabel(e.state)} · Revision {e.revision}</strong><p>{e.note}</p><small>Assigned: {e.assignee} · Due: {e.due_date}<br/>{e.actor} · {e.at}</small></li>)}</ul></>}<Link className="inline-link" href={href()}>Return to action list</Link></section>:<>
 <form method="get" className="review-controls"><input type="hidden" name="organisation" value={org.id}/><label htmlFor="follow-up-filter">Follow-up status</label><select id="follow-up-filter" name="state" defaultValue={state}>{['ACTIVE','OVERDUE','OPEN','IN_PROGRESS','RESOLVED','CLOSED','CANCELLED','ALL'].map(v=><option key={v} value={v}>{reviewLabel(v)}</option>)}</select><button className="secondary-button">Filter follow-up</button></form>
 <section className="review-panel"><DataTable label="Management follow-up register" columns={[{label:'Follow-up'},{label:'Scope'},{label:'Assigned colleague'},{label:'Due'},{label:'Status'}]} rows={packet.rows.map(r=>({id:r.id,cells:[<Link key="title" href={href({id:r.id})}>{r.title}<small>{reviewLabel(r.topic)} · {reviewLabel(r.priority)} priority</small></Link>,r.centre??r.outlet,r.assignee,r.due_date,<StatusBadge key="status" tone={r.overdue?'warning':r.state==='CLOSED'?'success':'neutral'}>{reviewLabel(r.state)}{r.overdue?' · Overdue':''}</StatusBadge>]}))}/><nav className="catalogue-pagination"><span>{packet.total} follow-up records · Page {page}</span>{page>1&&<Link href={href({state,page:String(page-1)})}>Previous</Link>}{page*20<packet.total&&<Link href={href({state,page:String(page+1)})}>Next</Link>}</nav></section></>}
 <p className="review-basis">The assigned colleague records progress and evidence. Authorised managers assign, close or reopen follow-up. Closing an action does not post stock, approve a count, change a price or alter any source document.</p>
 </>}
 </WorkspaceShell>;
}
