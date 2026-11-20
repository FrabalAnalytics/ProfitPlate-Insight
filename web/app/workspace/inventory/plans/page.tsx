import Link from 'next/link';
import {redirect} from 'next/navigation';
import {requireUser,getPlatformAccess,workspacePath} from '@/lib/auth';
import {createClient} from '@/lib/supabase/server';
import {WorkspaceShell} from '@/app/components/workspace-shell';
import type {PlanOptions} from '@/lib/material-plans';
import {MaterialPlanForm} from './plan-form';
import '../inventory.css';import '../../materials/catalogue.css';import './plans.css';
export const instant=false;
export default async function Page({searchParams}:{searchParams:Promise<{organisation?:string;site?:string}>}){
 const user=await requireUser(),access=await getPlatformAccess();if(access!=='member')redirect(workspacePath(access));
 const p=await searchParams,client=await createClient(),orgs=await client.from('organisations').select('id,name,time_zone').order('name'),org=p.organisation?orgs.data?.find(o=>o.id===p.organisation):orgs.data?.[0];if(!org)redirect('/workspace');
 const today=new Intl.DateTimeFormat('en-CA',{timeZone:org.time_zone,year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date()),result=await client.rpc('material_plan_options',{p_organisation_id:org.id,p_site_id:null,p_date:today}),options=result.data as PlanOptions|null;
 return <WorkspaceShell email={user.email} organisationId={org.id} restaurantName={org.name} sectionLabel="Material Plan"><Link className="catalogue-back" href={`/workspace?organisation=${org.id}`}>Back to workspace</Link><h1 className="workspace-title">Material Plan</h1><p className="workspace-description">Choose recipe targets. Review the combined materials before requesting or producing stock.</p>{result.error||!options?<p role="alert">Material planning is unavailable. Check your centre access and the latest planning update.</p>:!options.centres.length?<p className="stock-help">Your account needs stock request access at a centre to use material planning. Ask your administrator to review centre tasks.</p>:<MaterialPlanForm organisation={org.id} centres={options.centres} today={today} initialSite={p.site??''}/>}</WorkspaceShell>;
}
