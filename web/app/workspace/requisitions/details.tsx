import Link from 'next/link';
import {DataTable} from '@/app/components/data-table';
import type {StockDocument} from '@/lib/inventory';
import {displayQuantity} from '@/lib/recipes';
import {unacceptedQuantity,type RequisitionAvailability} from '@/lib/requisitions';

export function RequisitionMaterials({document}:{document:StockDocument}){
 const original=document.requested_lines??document.lines;
 return <DataTable label="Requisition materials" columns={[{label:'Material'},{label:'Unit'},{label:'Requested',numeric:true},{label:'Approved',numeric:true},{label:'Received',numeric:true},{label:'Not received',numeric:true},{label:'Decision / reason'}]} rows={original.map(line=>{
  const review=document.approval_decisions?.find(a=>a.item_id===line.item_id),sent=document.lines.find(l=>l.item_id===line.item_id),received=document.received_lines?.find(l=>l.item_id===line.item_id),approved=review?.quantity??(document.state==='REQUESTED'?null:sent?.quantity??'0');
  const explanation=[review&&Number(review.quantity)===0?'Declined at approval':review&&Number(review.quantity)<Number(line.quantity)?'Reduced at approval':'',review?.reason,received?.reason].filter(Boolean).join(' / ');
  return{id:line.item_id,cells:[line.name,line.unit,displayQuantity(line.quantity),approved===null?'Awaiting review':displayQuantity(approved),received?displayQuantity(received.quantity):'—',received&&approved!==null?displayQuantity(unacceptedQuantity(approved,received.quantity)):'—',explanation||'—']};
 })}/>;
}

export function SourceAvailability({org,packet,open=false}:{org:string;packet:RequisitionAvailability;open?:boolean}){
 return <details className="stock-panel" open={open}><summary>Source stock availability: {packet.source}</summary><p className="stock-help">Live balances when this page loaded. Reserved elsewhere excludes this requisition. Dispatch rechecks availability before saving.</p><DataTable label="Requisition source availability" columns={[{label:'Material / unit'},{label:'On hand',numeric:true},{label:'Reserved elsewhere',numeric:true},{label:'Available for this request',numeric:true},{label:'Outstanding reservations'}]} rows={packet.items.map(i=>({id:i.item_id,cells:[<span key="name">{i.name}<small>{i.unit}</small></span>,displayQuantity(i.on_hand),displayQuantity(i.reserved),displayQuantity(i.available),<span key="reservations">{i.reservations.length?i.reservations.map((r,n)=><span key={r.id}>{n>0?' / ':''}<Link className="inline-link" href={`/workspace/requisitions?${new URLSearchParams({organisation:org,document:r.id})}`}>{r.reference}</Link></span>):Number(i.reserved)>0?'Reserved transfers outside this view':'None'}</span>]}))}/></details>;
}
