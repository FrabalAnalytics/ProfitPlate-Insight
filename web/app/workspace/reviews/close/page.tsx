import {randomUUID} from 'node:crypto';
import Link from 'next/link';
import '@/app/components/workflow-guidance.css';
import {redirect} from 'next/navigation';
import {requireUser,getPlatformAccess,workspacePath} from '@/lib/auth';
import {createClient} from '@/lib/supabase/server';
import {isUuid} from '@/lib/catalogue';
import {WorkspaceShell} from '@/app/components/workspace-shell';
import {DataTable,StatusBadge} from '@/app/components/data-table';
import {workflowLink,type ClosePacket} from '@/lib/workflow-guidance';
import {CloseForm} from './form';
import '../../materials/catalogue.css';import '../../inventory/inventory.css';import '../reviews.css';
export const instant=false;
export default async function Page({searchParams}:{searchParams:Promise<{organisation?:string;month?:string;site?:string;saved?:string}>}){
 const user=await requireUser(),access=await getPlatformAccess();if(access!=='member')redirect(workspacePath(access));const p=await searchParams,client=await createClient(),orgs=await client.from('organisations').select('id,name,time_zone').order('name'),org=p.organisation?orgs.data?.find(o=>o.id===p.organisation):orgs.data?.[0];if(!org)redirect('/workspace');
 const todayParts=new Intl.DateTimeFormat('en',{timeZone:org.time_zone,year:'numeric',month:'2-digit'}).formatToParts(new Date()),year=Number(todayParts.find(x=>x.type==='year')!.value),mon=Number(todayParts.find(x=>x.type==='month')!.value),previous=new Date(Date.UTC(year,mon-2,1)).toISOString().slice(0,7),month=p.month??previous,valid=/^\d{4}-(0[1-9]|1[0-2])$/.test(month)&&(!p.site||isUuid(p.site));
 const result=valid?await client.rpc('monthly_close_checklist',{p_organisation_id:org.id,p_month:month+'-01',p_site_id:p.site||null}):null,packet=result?.data as ClosePacket|null;
 const ready=packet?.saved?.current&&packet.saved.ready;
 return <WorkspaceShell email={user.email} restaurantName={org.name} organisationId={org.id} sectionLabel="Monthly close"><h1 className="workspace-title">Monthly close</h1><p className="workspace-description">Check stock, outstanding movements and source-data coverage before reviewing the month.</p>
 <form method="get" className="stock-filter workflow-filter"><input type="hidden" name="organisation" value={org.id}/><label>Month<input type="month" name="month" defaultValue={month} required/></label><label>Stock centre<select name="site" defaultValue={p.site??''}><option value="">All permitted centres</option>{packet?.centres.map(s=><option key={s.id} value={s.id}>{s.name}</option>)}</select></label><button className="secondary-button">Update checklist</button></form>
 {!packet||result?.error?<p className="auth-alert" role="alert">{result?.error?.code==='22023'?result.error.message:'Monthly close is unavailable. Check management access, month and centre, then refresh.'}</p>:<><section className="stock-panel"><div className="section-heading"><h2>{month} / {p.site?packet.centres.find(s=>s.id===p.site)?.name:'All permitted centres'}</h2><StatusBadge tone={ready?'success':'warning'}>{ready?'Operational review complete':packet.saved&&!packet.saved.current?'Records changed / refresh review':'Review in progress'}</StatusBadge></div><p>{packet.pending} pending checks. {!packet.ended?'This month has not ended. ':''}A saved review does not lock the accounting period or change stock.</p>{p.saved==='1'&&<p role="status" className="stock-success">Close review saved.</p>}{packet.saved&&<p>Last review: {packet.saved.name}, {new Intl.DateTimeFormat('en-GB',{timeZone:org.time_zone,dateStyle:'medium',timeStyle:'short'}).format(new Date(packet.saved.at))}. {!packet.saved.current?'Restaurant records have changed since that review. Check the updated figures and reconfirm coverage.':''}</p>}
 <DataTable label="Monthly close checks" columns={[{label:'Check'},{label:'Outstanding',numeric:true},{label:'Status'},{label:'Action'}]} rows={packet.checks.map(c=>({id:c.id,cells:[c.label,c.pending,<StatusBadge key="status" tone={c.pending?'warning':'success'}>{c.pending?'Needs attention':'Clear'}</StatusBadge>,c.path.startsWith('/workspace/setup')&&!packet.can_setup?<span key="action">Administrator action</span>:<Link key="action" href={workflowLink(org.id,c.path,{...c.params,...(p.site?{site:p.site}:{})})}>Review records</Link>]}))}/></section><CloseForm key={packet.evidence+String(packet.saved?.id)} org={org.id} packet={packet} request={randomUUID()}/></>}
 </WorkspaceShell>;
}
