"use client";
import Link from "next/link";
import {useEffect} from "react";
import {useRouter} from "next/navigation";
import {Bell,ArrowUpRight,CheckCircle2} from "lucide-react";
import type {StockAlertsPacket} from "@/lib/inventory";
import "./stock-alerts.css";

export function StockAlerts({organisation,alerts,refresh=false}:{organisation:string;alerts:StockAlertsPacket;refresh?:boolean}){
 const router=useRouter();
 useEffect(()=>{if(!refresh)return;const update=()=>{if(document.visibilityState==="visible")router.refresh();};const timer=setInterval(update,30000);document.addEventListener("visibilitychange",update);return()=>{clearInterval(timer);document.removeEventListener("visibilitychange",update);};},[refresh,router]);
 const href=(extra:Record<string,string>={})=>`/workspace/inventory?${new URLSearchParams({organisation,view:"movements",...extra})}`;
 return <section className="stock-alert-centre" aria-label="Stock action alerts"><div className="stock-alert-heading"><div><p className="eyebrow">STOCK ACTION CENTRE</p><h2>{alerts.total?`${alerts.total} pending stock ${alerts.total===1?"action":"actions"}`:"Stock actions are up to date"}</h2></div>{alerts.total?<Bell size={22}/>:<CheckCircle2 size={22}/>}</div>
  <div className="stock-alert-totals"><Link href={href({status:"PENDING"})}><strong>{alerts.approval}</strong><span>To approve</span></Link><Link href={href({status:"AWAITING_RECEIPT"})}><strong>{alerts.incoming}</strong><span>To accept / reject</span></Link><Link href={href({status:"FOLLOW_UP"})}><strong>{alerts.follow_up}</strong><span>Need follow-up</span></Link><span><strong>{alerts.overdue}</strong><span>Over 24 hours</span></span></div>
  {alerts.items.length>0?<ul>{alerts.items.map(item=><li key={item.id}><Link href={href({document:item.id})}><span><strong>{item.reference}</strong><small>{item.label}{item.overdue?" · Over 24 hours":""}</small></span><ArrowUpRight size={16}/></Link></li>)}</ul>:<p className="stock-alert-empty">Requests, dispatches and receiving decisions will appear here when they need attention.</p>}
  <p className="stock-alert-foot">{refresh?"Updates every 30 seconds while this workspace is visible. ":""}Stock changes only after the receiving side accepts a transfer.</p>
 </section>;
}
