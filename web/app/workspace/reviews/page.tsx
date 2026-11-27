import {randomUUID} from 'node:crypto';
import Link from 'next/link';
import {redirect} from 'next/navigation';
import {requireUser,getPlatformAccess,workspacePath} from '@/lib/auth';
import {createClient} from '@/lib/supabase/server';
import {isUuid} from '@/lib/catalogue';
import {validBusinessDate} from '@/lib/recipes';
import {reviewLabel,reviewPeriods,type ReviewPack,type ReviewAccess} from '@/lib/management-reviews';
import {WorkspaceShell} from '@/app/components/workspace-shell';
import {ReviewControls,ReviewFilters} from './controls';
import {ReviewContent} from './content';
import '../materials/catalogue.css';import './reviews.css';
export const instant=false;
export default async function Page({searchParams}:{searchParams:Promise<{organisation?:string;period?:string;anchor?:string;outlet?:string;site?:string;snapshot?:string;saved?:string}>}){
 const user=await requireUser(),platform=await getPlatformAccess();if(platform!=='member')redirect(workspacePath(platform));const p=await searchParams,client=await createClient(),orgs=await client.from('organisations').select('id,name,time_zone').order('name'),org=p.organisation?orgs.data?.find(o=>o.id===p.organisation):orgs.data?.[0];if(!org)redirect('/workspace');
 const accessResult=await client.rpc('management_review_access',{p_organisation_id:org.id}),access=accessResult.data as ReviewAccess|null;
 const shell={email:user.email,restaurantName:org.name,organisationId:org.id,sectionLabel:'Management review'};
 if(accessResult.error||!access)return <WorkspaceShell {...shell}><h1 className="workspace-title">Management review unavailable</h1><p role="alert">Check your role and the required database update, then refresh.</p></WorkspaceShell>;
 const period=p.period??'DAILY',valid=reviewPeriods.some(v=>v===period)&&(!p.anchor||validBusinessDate(p.anchor))&&(!p.outlet||isUuid(p.outlet))&&(!p.site||isUuid(p.site))&&(!p.snapshot||isUuid(p.snapshot));
 const result=valid?p.snapshot?await client.rpc('management_review_history',{p_organisation_id:org.id,p_id:p.snapshot,p_page:1}):await client.rpc('management_review_pack',{p_organisation_id:org.id,p_period:period,p_anchor:p.anchor||null,p_outlet_id:p.outlet||null,p_site_id:p.site||null}):null;
 const pack=(p.snapshot?result?.data?.payload:result?.data) as ReviewPack|null,c=pack?.context;
 const href=(extra:Record<string,string>)=>`/workspace/reviews?${new URLSearchParams({organisation:org.id,...extra})}`;
 return <WorkspaceShell {...shell} reportingContext={c?{from:c.from,to:c.to,location:c.outlet_id??''}:undefined}><div className="page-heading-row"><div><p className="eyebrow form-eyebrow">MANAGEMENT REVIEW</p><h1 className="workspace-title">{c?reviewLabel(c.period):'Management'} review</h1></div><div className="review-controls no-print"><Link className="secondary-button" href={`/workspace/reviews/actions?organisation=${org.id}`}>Action register</Link><Link className="secondary-button" href={`/workspace/reviews/history?organisation=${org.id}`}>Your saved reviews</Link></div></div>
 <section className="review-context no-print"><nav className="review-tabs" aria-label="Review periods">{reviewPeriods.map(v=><Link key={v} href={href({period:v,...(p.outlet?{outlet:p.outlet}:{}),...(p.site?{site:p.site}:{})})} aria-current={(c?.period??period)===v?'page':undefined}>{reviewLabel(v)}</Link>)}</nav><p>Daily defaults to yesterday; weekly and monthly default to the last completed business period. Select a date within another period to review it.</p><details><summary>Change date or scope</summary><ReviewFilters key={JSON.stringify(c??{period})} org={org.id} access={access} context={c} period={period}/></details></section>
 {p.saved==='1'&&pack&&<p role="status" className="stock-success">Review snapshot saved. Its figures are preserved at the save time.</p>}
 {!pack||result?.error?<p role="alert" className="auth-alert">{result?.error?.code==='22023'?result.error.message:'This review is unavailable. Check the date, permitted outlet/centre and current access.'}</p>:<><ReviewControls key={JSON.stringify(c)} org={org.id} pack={pack} request={randomUUID()} saved={!!p.snapshot}/><ReviewContent org={org.id} p={pack} saved={!!p.snapshot}/></>}
 </WorkspaceShell>;
}
