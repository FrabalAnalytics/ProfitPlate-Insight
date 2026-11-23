import Link from 'next/link';
import {createClient} from '@/lib/supabase/server';
import {reviewRoles,type FollowUpPacket} from '@/lib/management-reviews';
import '../workspace/reviews/reviews.css';
export async function ManagementReviewLinks({org,roles}:{org:string;roles:string[]}){
 if(!roles.some(r=>reviewRoles.includes(r)))return null;
 const client=await createClient(),result=await client.rpc('management_actions',{p_organisation_id:org,p_state:'ACTIVE',p_page:1,p_id:null}),packet=result.data as FollowUpPacket|null;
 return <nav className="review-links" aria-label="Management review shortcuts"><strong>Management review</strong>{['DAILY','WEEKLY','MONTHLY'].map(period=><Link key={period} href={`/workspace/reviews?${new URLSearchParams({organisation:org,period})}`}>{period[0]+period.slice(1).toLowerCase()}</Link>)}<Link href={`/workspace/reviews/actions?organisation=${org}`}>Action register{packet?.summary.overdue?` · ${packet.summary.overdue} overdue`:packet?.summary.resolved?` · ${packet.summary.resolved} awaiting closure`:packet?.summary.open?` · ${packet.summary.open} open`:''}</Link></nav>;
}
