import Link from 'next/link';
import {redirect} from 'next/navigation';
import {requireUser,getPlatformAccess,workspacePath} from '@/lib/auth';
import {createClient} from '@/lib/supabase/server';
import {WorkspaceShell} from '@/app/components/workspace-shell';
import {DataTable} from '@/app/components/data-table';
import {reviewLabel,type ReviewContext} from '@/lib/management-reviews';
import '../../materials/catalogue.css';import '../reviews.css';
export const instant=false;
export default async function Page({searchParams}:{searchParams:Promise<{organisation?:string;page?:string}>}){
 const user=await requireUser(),platform=await getPlatformAccess();if(platform!=='member')redirect(workspacePath(platform));const p=await searchParams,client=await createClient(),orgs=await client.from('organisations').select('id,name').order('name'),org=p.organisation?orgs.data?.find(o=>o.id===p.organisation):orgs.data?.[0];if(!org)redirect('/workspace');const page=Math.max(1,Math.min(100000,Number.parseInt(p.page??'1',10)||1)),result=await client.rpc('management_review_history',{p_organisation_id:org.id,p_page:page}),packet=result.data as {total:number;rows:{id:string;created_at:string;context:ReviewContext}[]}|null;
 return <WorkspaceShell email={user.email} restaurantName={org.name} organisationId={org.id} sectionLabel="Saved management reviews"><div className="page-heading-row"><h1 className="workspace-title">Your saved reviews</h1><Link className="secondary-button" href={`/workspace/reviews?organisation=${org.id}`}>Back to live review</Link></div><p className="workspace-description">Personal snapshots preserve the server-generated figures at save time. Current access is checked whenever you reopen one.</p>{result.error||!packet?<p role="alert">Saved reviews could not be loaded. Check your access and refresh.</p>:<section className="review-panel"><DataTable label="Saved management review history" columns={[{label:'Review'},{label:'Period'},{label:'Saved at'},{label:'Open'}]} rows={packet.rows.map(r=>({id:r.id,cells:[reviewLabel(r.context.period),`${r.context.from} to ${r.context.to}`,r.created_at,<Link key="open" href={`/workspace/reviews?${new URLSearchParams({organisation:org.id,snapshot:r.id})}`}>Open saved review →</Link>]}))}/><nav className="catalogue-pagination"><span>{packet.total} saved reviews · Page {page}</span>{page>1&&<Link href={`?organisation=${org.id}&page=${page-1}`}>Previous</Link>}{page*20<packet.total&&<Link href={`?organisation=${org.id}&page=${page+1}`}>Next</Link>}</nav></section>}</WorkspaceShell>;
}
