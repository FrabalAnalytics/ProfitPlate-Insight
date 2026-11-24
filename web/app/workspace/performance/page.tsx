import type {Metadata} from 'next';
import Link from 'next/link';
import {redirect} from 'next/navigation';
import {requireUser,getPlatformAccess,workspacePath} from '@/lib/auth';
import {createClient} from '@/lib/supabase/server';
import {workspaceNavigation} from '@/lib/workspace-home';
import type {NavigationAccess} from '@/lib/overview';
import type {WasteWorkspacePacket} from '@/lib/waste-accountability';
import type {WeeklyWorkspacePacket} from '@/app/components/weekly-count-status';
import {WorkspaceShell} from '@/app/components/workspace-shell';
import {ExecutiveBriefing} from '@/app/components/executive-briefing';
import {OperationsWorkspace} from '@/app/components/operations-workspace';
import '../workspace-home.css';import '../welcome.css';
export const metadata:Metadata={title:'Performance reports | ProfitPlate Insights'};
export const instant=false;
export default async function Page({searchParams}:{searchParams:Promise<{organisation?:string;from?:string;to?:string;location?:string}>}){
 const user=await requireUser(),platform=await getPlatformAccess();if(platform!=='member')redirect(workspacePath(platform));
 const p=await searchParams,client=await createClient(),orgs=await client.from('organisations').select('id,name,time_zone,currency_code').order('name'),org=p.organisation?orgs.data?.find(o=>o.id===p.organisation):orgs.data?.[0];
 if(!org)redirect('/workspace');
 const membership=await client.from('organisation_memberships').select('id').eq('organisation_id',org.id).eq('user_id',user.id).eq('status','active').maybeSingle();
 const [roleResult,nav]=await Promise.all([membership.data?client.from('membership_roles').select('role_code,location_id').eq('organisation_id',org.id).eq('membership_id',membership.data.id):null,client.rpc('workspace_navigation_access',{p_organisation_id:org.id})]);
 const roles=roleResult?.data??[],access=workspaceNavigation(roles,nav.data as NavigationAccess),operations=roles.some(r=>r.role_code==='operations')&&!roles.some(r=>r.role_code==='ceo'&&r.location_id===null);
 const shell={email:user.email,organisationId:org.id,restaurantName:org.name,sectionLabel:operations?'Operational overview':'Business performance'};
 if(!roles.length||nav.error||(!access.overview&&!operations))return <WorkspaceShell {...shell}><h1 className="workspace-title">Performance reports are restricted or unavailable.</h1><Link href={`/workspace?organisation=${org.id}`}>Back to workspace</Link></WorkspaceShell>;
 const [waste,weekly,monthly,locations]=await Promise.all([client.rpc('waste_compliance_workspace',{p_organisation_id:org.id}),client.rpc('weekly_counts_workspace',{p_organisation_id:org.id}),client.rpc('monthly_counts_workspace',{p_organisation_id:org.id}),client.from('locations').select('id,name').eq('organisation_id',org.id)]);
 const parts=new Intl.DateTimeFormat('en',{timeZone:org.time_zone,year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date()),today=['year','month','day'].map(k=>parts.find(v=>v.type===k)?.value).join('-');
 const packets={organisation:org.id,timeZone:org.time_zone,waste:waste.data as WasteWorkspacePacket|null,weekly:weekly.data as WeeklyWorkspacePacket|null,monthly:monthly.data as WeeklyWorkspacePacket|null,wasteError:!!waste.error,weeklyError:!!weekly.error,monthlyError:!!monthly.error};
 return <WorkspaceShell {...shell}><Link className="welcome-report-back" href={`/workspace?organisation=${org.id}`}>Back to workspace</Link><h1 className="workspace-title">{operations?'Operational overview':'Business performance'}</h1>{operations?<OperationsWorkspace {...packets} currency={org.currency_code}/>:<ExecutiveBriefing {...packets} from={p.from??today.slice(0,7)+'-01'} to={p.to??today} location={p.location??''} today={today} locations={locations.data??[]}/>}</WorkspaceShell>;
}
