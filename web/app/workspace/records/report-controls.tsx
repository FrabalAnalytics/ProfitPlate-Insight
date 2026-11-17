"use client";
import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { historicalTypes,type HistoricalType } from "@/lib/operational-reports";

export function HistoricalTypeSelect({types,selected}:{types:HistoricalType[];selected:HistoricalType}){
 return <select id="history-type" name="type" defaultValue={selected} onChange={event=>{const form=event.currentTarget.form;if(!form)return;for(const name of["outlet","site","q","supplier","material","user"]){const field=form.elements.namedItem(name) as HTMLInputElement|HTMLSelectElement|null;if(field)field.value="";}for(const name of["view","receiving"]){const field=form.elements.namedItem(name) as HTMLInputElement|HTMLSelectElement|null;if(field)field.value=name==="view"?"REGISTER":"ALL";}const status=form.elements.namedItem("status") as HTMLSelectElement|null;if(status)status.value="ALL";form.requestSubmit();}}>{types.map(type=><option key={type} value={type}>{historicalTypes[type]}</option>)}</select>;
}
export function HistoricalActions(){const router=useRouter(),[pending,start]=useTransition();return <><button type="button" className="secondary-button" disabled={pending} onClick={()=>start(()=>router.refresh())}>{pending?"Refreshing…":"Refresh report"}</button><button type="button" className="secondary-button" onClick={()=>window.print()}>Print this page</button></>;}
