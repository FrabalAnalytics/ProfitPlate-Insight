"use client";
import Link from "next/link";
import {useEffect} from "react";
import {useRouter} from "next/navigation";
import {ArrowUpRight,CheckCircle2} from "lucide-react";
import {attentionLabels,type AttentionPacket} from "@/lib/workspace-attention";
import "./needs-attention.css";
export function NeedsAttention({organisation,packet,error}:{organisation:string;packet:AttentionPacket|null;error?:boolean}){
 const router=useRouter();useEffect(()=>{const refresh=()=>{if(document.visibilityState==="visible")router.refresh();};const id=setInterval(refresh,30000);document.addEventListener("visibilitychange",refresh);return()=>{clearInterval(id);document.removeEventListener("visibilitychange",refresh);};},[router]);
 const queues=[...(packet?.queues??[])].sort((a,b)=>Number(b.overdue>0)-Number(a.overdue>0)||b.count-a.count||a.queue.localeCompare(b.queue));
 return <section className="needs-attention" aria-label="Needs Attention"><div className="needs-attention-heading"><div><p className="eyebrow">YOUR NEXT ACTIONS</p><h2>Needs Attention</h2></div><button className="attention-refresh" onClick={()=>router.refresh()} type="button">Refresh</button></div>
  {error?<p role="alert">Your task counts could not be loaded. Refresh to try again.</p>:queues.length?<ul>{queues.map(q=><li key={q.queue}><Link href={`/workspace/tasks?${new URLSearchParams({organisation,queue:q.queue})}`}><span>{attentionLabels[q.queue]??q.queue}{q.overdue>0&&<small>{q.overdue} waiting over 24 hours</small>}</span><strong>{q.count}</strong><ArrowUpRight size={15} aria-hidden="true"/></Link></li>)}</ul>:<p className="attention-clear"><CheckCircle2 size={18}/>No outstanding tasks in your current queues.</p>}
  <p className="attention-footnote">Counts are distinct records per task. A record can appear in more than one queue. Updates every 30 seconds while this workspace is visible.</p>
 </section>;
}
