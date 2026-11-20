"use client";
import Link from "next/link";
import {WasteWorkspaceStatus} from "./waste-workspace-status";
import type {WasteWorkspacePacket} from "@/lib/waste-accountability";
import {useEffect} from "react";
import {useRouter} from "next/navigation";
import {ArrowUpRight,CheckCircle2} from "lucide-react";
import {attentionLabels,type AttentionPacket} from "@/lib/workspace-attention";
import "./needs-attention.css";
export function NeedsAttention({organisation,packet,error,waste,wasteError,extraPending}:{organisation:string;packet:AttentionPacket|null;error?:boolean;waste?:WasteWorkspacePacket|null;wasteError?:boolean;extraPending?:boolean}){
 const router=useRouter();useEffect(()=>{const refresh=()=>{if(document.visibilityState==="visible")router.refresh();};const id=setInterval(refresh,30000);document.addEventListener("visibilitychange",refresh);return()=>{clearInterval(id);document.removeEventListener("visibilitychange",refresh);};},[router]);
 const queues=[...(packet?.queues??[])].sort((a,b)=>Number(b.overdue>0)-Number(a.overdue>0)||b.count-a.count||a.queue.localeCompare(b.queue));
 return <section className="needs-attention" aria-label="Needs Attention"><div className="needs-attention-heading"><div><h2>Needs Attention</h2></div><button className="attention-refresh" onClick={()=>router.refresh()} type="button">Refresh</button></div>
  {error?<p role="alert">Your task counts could not be loaded. Refresh to try again.</p>:queues.length?<ul>{queues.map(q=><li key={q.queue}><Link href={`/workspace/tasks?${new URLSearchParams({organisation,queue:q.queue})}`}><span>{attentionLabels[q.queue]??q.queue}{q.overdue>0&&<small>{q.overdue} waiting over 24 hours</small>}</span><strong>{q.count}</strong><ArrowUpRight size={15} aria-hidden="true"/></Link></li>)}</ul>:waste?.open||wasteError||extraPending?null:<p className="attention-clear"><CheckCircle2 size={18}/>No tasks waiting.</p>}
  <WasteWorkspaceStatus organisation={organisation} packet={waste??null} error={wasteError}/>
  <details className="attention-footnote"><summary>About these counts</summary><p>A record can appear in several queues. Counts refresh every 30 seconds.</p></details>
 </section>;
}
