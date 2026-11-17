"use client";
import {DataTable} from "@/app/components/data-table";

import { useState,useTransition } from "react";
import { useRouter } from "next/navigation";
import { RefreshCw } from "lucide-react";
import { referenceAmount } from "@/lib/reference-prices";
import type { Overview } from "@/lib/overview";

export function RefreshOverview() {
 const router=useRouter(),[pending,start]=useTransition();
 return <button type="button" className="secondary-button" onClick={()=>start(()=>router.refresh())} disabled={pending}><RefreshCw size={14} aria-hidden="true"/>{pending?"Refreshing…":"Refresh overview"}</button>;
}
export function SalesTrend({daily,currency}:{daily:Overview["daily"];currency:string}) {
 const [selected,setSelected]=useState(()=>daily.reduce((last,point,index)=>point.lines>0?index:last,0));
 const point=daily[selected];if(!point)return null;
 // Floating point is used only for SVG geometry. Financial values remain decimal strings.
 const maximum=Math.max(...daily.map(day=>Number(day.net_revenue??0)),0);
 const x=(index:number)=>56+(daily.length===1?310:index/(daily.length-1)*620);
 const y=(value:string)=>174-(maximum?Number(value)/maximum*140:0);
 const paths:string[]=[];let path="";
 daily.forEach((day,index)=>{if(day.net_revenue===null){if(path)paths.push(path);path="";}else path+=`${path?" L":"M"}${x(index)},${y(day.net_revenue)}`;});if(path)paths.push(path);
 const compact=(value:number)=>new Intl.NumberFormat("en-NG",{notation:"compact",maximumFractionDigits:1}).format(value);
 return <><div className="overview-chart-control"><div><label htmlFor="inspect-sales-date">Inspect sales date</label><select id="inspect-sales-date" value={selected} onChange={event=>setSelected(Number(event.target.value))}>{daily.map((day,index)=><option key={day.date} value={index}>{day.date}{!day.lines?" · No records":""}</option>)}</select></div><p aria-live="polite"><strong>{point.net_revenue===null?"No records":referenceAmount(point.net_revenue,currency)}</strong><small>{point.date} · {point.lines?`${point.receipts} receipts`:"No sales rows recorded"}</small></p></div>
 <svg className="overview-trend" viewBox="0 0 720 216" role="img" aria-label={`Daily recorded net sales in ${currency}. Gaps indicate days without records. Use the date selector or daily figures for exact values.`}>
 {[0,.5,1].map(fraction=><g key={fraction}><line x1="56" x2="676" y1={174-fraction*140} y2={174-fraction*140} stroke="#dce7df" strokeDasharray="3 4"/><text x="48" y={178-fraction*140} textAnchor="end">{compact(maximum*fraction)}</text></g>)}
 {paths.map((value,index)=><path key={index} d={value} fill="none" stroke="#24765b" strokeWidth="2.5"/>)}
 {daily.map((day,index)=>day.net_revenue!==null&&<circle key={day.date} cx={x(index)} cy={y(day.net_revenue)} r={index===selected?5:2.5} fill="#174c3c"/>)}
 <line x1={x(selected)} x2={x(selected)} y1="25" y2="178" stroke="#c4a66a" strokeDasharray="4 4"/>
 <text x="56" y="204">{daily[0].date}</text><text x="676" y="204" textAnchor="end">{daily.at(-1)?.date}</text>
 </svg><div className="overview-chart-axis" aria-hidden="true"><span>{daily[0].date}</span><span>{daily.at(-1)?.date}</span></div><p className="overview-footnote">{currency} · Gaps mean no recorded data; they do not confirm zero sales.</p>
 <details className="workspace-disclosure"><summary>View daily figures</summary><DataTable label="Daily recorded sales" columns={[{label:"Date"},{label:"Net sales",numeric:true},{label:"Receipts",numeric:true}]} rows={daily.map(day=>({id:day.date,cells:[day.date,day.net_revenue===null?"No records":referenceAmount(day.net_revenue,currency),day.receipts]}))}/></details></>;
}
