"use client";
import {useEffect} from 'react';
import {useRouter} from 'next/navigation';
import Link from 'next/link';
import {ArrowUpRight,CheckCircle2,RefreshCw} from 'lucide-react';
import {DataTable,StatusBadge} from './data-table';
import type {WelcomeTask} from '@/lib/workspace-welcome';
export function WelcomeAttention({rows,issues,label='Needs Attention'}:{rows:WelcomeTask[];issues:string[];label?:string}){
 const router=useRouter();
 useEffect(()=>{const refresh=()=>{if(document.visibilityState==='visible')router.refresh();};const id=setInterval(refresh,30000);document.addEventListener('visibilitychange',refresh);return()=>{clearInterval(id);document.removeEventListener('visibilitychange',refresh);};},[router]);
 const table=(items:WelcomeTask[],name:string)=><DataTable label={name} columns={[{label:'Needs attention'},{label:'Pending',numeric:true},{label:'Action'}]} rows={items.map(r=>({id:r.id,cells:[<span key="task" className="welcome-task-title">{r.label}<small>{r.detail||r.unit}</small></span>,<StatusBadge key="count" tone={r.priority===0?'danger':r.priority===1?'warning':'neutral'}>{r.count}</StatusBadge>,<Link key="action" className="welcome-task-action" href={r.href} aria-label={`${r.label} (${r.count} ${r.unit})`}>{r.action??'Review'}<ArrowUpRight size={14}/></Link>]}))}/>;
 return <section className="welcome-attention" aria-label={label}><header><div><h2>Needs Attention</h2><p>{rows.length?'Your outstanding work, in priority order.':'Your latest task status.'}</p></div><button type="button" className="welcome-refresh" aria-label="Refresh workspace" onClick={()=>router.refresh()}><RefreshCw size={15}/><span>Refresh</span></button></header>
 {issues.length>0&&<div className="welcome-issues" role="alert">{issues.map(issue=><p key={issue}>{issue}</p>)}</div>}
 {rows.length?<>{table(rows.slice(0,6),'Priority tasks')}{rows.length>6&&<details className="welcome-more"><summary>View {rows.length-6} more areas</summary>{table(rows.slice(6),'Other outstanding tasks')}</details>}</>:<p className="welcome-clear"><CheckCircle2 size={19}/>{issues.length?'Task status is incomplete. Refresh to check outstanding work.':'No outstanding tasks in your available records.'}</p>}
 </section>;
}
