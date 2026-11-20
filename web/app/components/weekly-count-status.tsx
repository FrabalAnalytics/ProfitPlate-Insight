import Link from 'next/link';
import {countLabels,type WeeklyRow,type WeeklySummary} from '@/lib/inventory-accountability';
import '@/app/workspace/inventory/stock-accountability.css';
export type WeeklyWorkspacePacket={summary:WeeklySummary;calendar_gaps:number;backlog:number;review_waiting:number;rows:WeeklyRow[]};
export function WeeklyCountStatus({organisation,packet,error}:{organisation:string;packet:WeeklyWorkspacePacket|null;error?:boolean}){
 if(!packet&&!error)return null;
 return <section className="weekly-workspace" aria-label="Weekly stock count status"><div><h2>Weekly stock counts</h2><Link href={`/workspace/inventory/counts?organisation=${organisation}`}>Open counts</Link></div>{error?<p role="alert">Count status could not be loaded. Refresh to try again.</p>:packet&&<><p>{packet.summary.submitted} / {packet.summary.expected} due counts submitted this cycle · {packet.backlog} overdue · {packet.review_waiting} awaiting review</p>{packet.calendar_gaps>0&&<p>Physical count day or cutoff is missing. Ask your administrator to finish the reporting calendar.</p>}<ul>{packet.rows.slice(0,4).map(r=><li key={r.site_id+r.day}><Link href={`/workspace/inventory/counts?${new URLSearchParams({organisation,site:r.site_id,from:r.day,to:r.day,...(r.count_id?{count:r.count_id}:{})})}`}>{r.centre} · {r.day} · {r.overdue?'Overdue':countLabels[r.state]}</Link></li>)}</ul></>}</section>;
}
