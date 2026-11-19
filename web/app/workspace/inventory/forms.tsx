"use client";
import {ProcessingForm} from "./processing-form";
import {WasteForm} from "./waste-form";
import Link from "next/link";
import {useActionState,useId,useState,type ReactNode} from "react";
import {configureStock,requestStock,actOnStock,finishWasteRecord} from "./actions";
import {stockKinds,type StockPacket,type StockDocument,type StockActionState} from "@/lib/inventory";
import {ProcessingBatchFields} from "./processing-fields";
import {ProcessingOutputLink} from "../setup/production/output-link";
import {TableScroll} from "@/app/components/data-table";

function Feedback({state}:{state:StockActionState}){return <>{state.error&&<p className="auth-alert" role="alert">{state.error}</p>}{state.success&&<p className="stock-success" role="status">{state.success}</p>}</>;}
function Field({label,children}:{label:string;children:(id:string)=>ReactNode}){const id=useId();return <div className="setup-field"><label htmlFor={id}>{label}</label>{children(id)}</div>;}
function ConfigForm({organisation,kind,title,children}:{organisation:string;kind:string;title:string;children:ReactNode}){
 const [state,action,pending]=useActionState(configureStock,{});
 return <form action={action} className="stock-form"><input type="hidden" name="organisation" value={organisation}/><input type="hidden" name="configuration" value={kind}/><fieldset disabled={pending}><legend>{title}</legend>{children}<Feedback state={state}/><button className="secondary-button">{pending?"Saving...":title}</button></fieldset></form>;
}
export function StockConfiguration({organisation,packet}:{organisation:string;packet:StockPacket}){
 const sites=packet.locations.filter(s=>s.is_active);
 return <div className="stock-config-grid">
 <div className="stock-panel"><h2>Named stock centres</h2><p>Set up your storage centres and assign their responsible users.</p><Link className="secondary-button" href={`/workspace/setup/centres?organisation=${organisation}`}>Manage stock centres</Link></div>
 <ConfigForm organisation={organisation} kind="ROUTE" title="Save movement route">
  <Field label="From stock location">{id=><select id={id} name="source_id" required><option value="">Choose source</option>{sites.map(s=><option key={s.id} value={s.id}>{s.name}</option>)}</select>}</Field>
  <Field label="To stock location">{id=><select id={id} name="destination_id" required><option value="">Choose destination</option>{sites.map(s=><option key={s.id} value={s.id}>{s.name}</option>)}</select>}</Field>
  <Field label="Route movement type">{id=><select id={id} name="kind"><option value="TRANSFER">Store transfer</option><option value="ISSUE">Department issue</option></select>}</Field>
  <Field label="Source approval role">{id=><select id={id} name="approval_role"><option value="inventory_manager">Inventory Manager</option><option value="inventory">Inventory / source approver</option><option value="operations">Operations</option><option value="restaurant_admin">Restaurant Administrator</option></select>}</Field>
  <p className="stock-help">A different colleague approves the request. Source Inventory dispatches; a different destination Inventory colleague receives. Saving an existing route updates its approval role and reactivates it.</p>
 </ConfigForm>
 <StockOutputBinding organisation={organisation} packet={packet}/>
 </div>;
}
export function StockToggle({organisation,id,kind,active}:{organisation:string;id:string;kind:"LOCATION_STATE"|"ROUTE_STATE";active:boolean}){
 const [state,action,pending]=useActionState(configureStock,{});
 return <form action={action}><input type="hidden" name="organisation" value={organisation}/><input type="hidden" name="configuration" value={kind}/><input type="hidden" name="id" value={id}/><input type="hidden" name="active" value={String(!active)}/><button className="inline-link" disabled={pending}>{pending?"Saving...":active?"Deactivate":"Reactivate"}</button><Feedback state={state}/></form>;
}
export function AllowStockReturn({organisation,source,destination,sourceName,destinationName}:{organisation:string;source:string;destination:string;sourceName:string;destinationName:string}){
 const [state,action,pending]=useActionState(configureStock,{});
 return <form action={action}><input type="hidden" name="organisation" value={organisation}/><input type="hidden" name="configuration" value="ROUTE"/><input type="hidden" name="source_id" value={destination}/><input type="hidden" name="destination_id" value={source}/><input type="hidden" name="kind" value="TRANSFER"/><input type="hidden" name="approval_role" value="inventory_manager"/><button className="inline-link" disabled={pending} aria-label={`Allow return from ${destinationName} to ${sourceName}`}>{pending?"Saving...":"Allow reverse / excess return"}</button><Feedback state={state}/></form>;
}
export function StockRequest({organisation,packet,request,today,initialKind,fixedKind=false}:{organisation:string;packet:StockPacket;request:string;today:string;initialKind?:keyof typeof stockKinds;fixedKind?:boolean}){
 const [state,action,pending]=useActionState(requestStock,{}),[kind,setKind]=useState<keyof typeof stockKinds>(initialKind??"TRANSFER"),[lines,setLines]=useState([{key:0,item_id:"",quantity:""}]),[site,setSite]=useState("");
 const sites=packet.locations.filter(s=>s.is_active),incoming=["OPENING","GRN","DIRECT_RECEIPT"].includes(kind),production=kind==="PRODUCTION",hasLines=kind!=="GRN"&&!production;
 if(production)return <ProcessingForm organisation={organisation} packet={packet} submission={request} today={today} otherMovement={fixedKind?undefined:()=>setKind("TRANSFER")}/>;
 const selectable=sites.filter(s=>production?s.request&&s.processing_enabled:incoming?s.inventory&&s.request:s.request&&(kind!=="WASTE"||packet.processing?.waste_sites?.some(w=>w.id===s.id)===true));
 const update=(key:number,field:"item_id"|"quantity",value:string)=>setLines(lines.map(l=>l.key===key?{...l,[field]:value}:l));
 if(kind==="WASTE")return <WasteForm organisation={organisation} packet={packet} request={request} today={today} otherMovement={fixedKind?undefined:()=>setKind("TRANSFER")}/>;
 return <form action={action} onReset={e=>e.preventDefault()} className="stock-form stock-request"><input type="hidden" name="organisation" value={organisation}/><input type="hidden" name="request" value={request}/><input type="hidden" name="lines" disabled={production} value={JSON.stringify(lines.map(({item_id,quantity})=>({item_id,quantity})))}/><fieldset disabled={pending}>
  <legend>{fixedKind?(production?"Record material processing":"Record stock waste"):"Request a stock movement"}</legend>
  <div className="stock-field-grid"><Field label="Movement type">{id=><select id={id} name="kind" value={kind} onChange={e=>setKind(e.target.value as keyof typeof stockKinds)}>{Object.entries(stockKinds).filter(([code])=>!fixedKind||code===initialKind).map(([code,label])=><option key={code} value={code}>{label}</option>)}</select>}</Field>
  <Field label="Movement date">{id=><input id={id} name="date" type="date" required max={today} defaultValue={today}/>}</Field></div>
  {kind==="TRANSFER"||kind==="ISSUE"?<Field label="Permitted movement route">{id=><select id={id} name="route_id" required><option value="">Choose a configured route</option>{packet.routes.filter(r=>r.is_active&&r.kind===kind&&(sites.find(s=>s.id===r.destination_id)?.request||sites.find(s=>s.id===r.source_id)?.request)).map(r=><option key={r.id} value={r.id}>{sites.find(s=>s.id===r.source_id)?.name??"Source"} to {sites.find(s=>s.id===r.destination_id)?.name??"Destination"}</option>)}</select>}</Field>:<Field label={production?"Processing centre":incoming?"Receiving stock location":"Stock location"}>{id=><select id={id} name={incoming?"destination_id":"source_id"} required value={site} onChange={e=>setSite(e.target.value)}><option value="">Choose stock location</option>{selectable.map(s=><option key={s.id} value={s.id}>{s.name}</option>)}</select>}</Field>}
  {kind==="GRN"&&<><Field label="Accepted goods receipt">{id=><select id={id} name="receipt_id" required><option value="">Choose an unposted GRN</option>{packet.grns.map(g=><option key={g.id} value={g.id}>{g.reference} - {g.outlet} - {g.date}</option>)}</select>}</Field><p className="stock-help">All accepted quantities are taken from the GRN and the order’s saved unit conversions. Rejected goods are excluded. Post each GRN once. Exclude deliveries already included in your opening count.</p></>}
  {kind==="DIRECT_RECEIPT"&&<><Field label="Delivery supplier">{id=><select id={id} name="supplier_id" required><option value="">Choose supplier</option>{packet.suppliers.map(s=><option key={s.id} value={s.id}>{s.name}</option>)}</select>}</Field><Field label="Supplier delivery reference">{id=><input id={id} name="delivery_reference" maxLength={100} required/>}</Field><p className="stock-help">For deliveries without a GRN. Each supplier delivery reference can be recorded once. This records physical quantities; Procurement records the invoice separately. Do not also post a GRN for the same delivery.</p></>}
  {production&&<ProcessingBatchFields key={site} org={organisation} setup={packet.processing} site={site}/>}
  {hasLines&&<><p className="stock-help">Enter {kind==="COUNT"?"the physically counted quantity, including zero where appropriate":"positive movement quantities"} in each material’s base unit. Issues move stock; record consumption separately when materials are used.</p><TableScroll label="Stock request lines"><table className="data-table"><thead><tr><th>Material / base unit</th><th>Quantity</th><th>Action</th></tr></thead><tbody>{lines.map((line,n)=><tr key={line.key}><td><select aria-label={`Material ${n+1}`} value={line.item_id} required onChange={e=>update(line.key,"item_id",e.target.value)}><option value="">Choose material</option>{packet.items.map(i=><option key={i.id} value={i.id}>{i.code} - {i.name} ({i.unit})</option>)}</select></td><td><input aria-label={`Quantity ${n+1}`} inputMode="decimal" required value={line.quantity} onChange={e=>update(line.key,"quantity",e.target.value)}/></td><td><button type="button" className="inline-link" disabled={lines.length===1} onClick={()=>setLines(lines.filter(l=>l.key!==line.key))}>Remove line {n+1}</button></td></tr>)}</tbody></table></TableScroll><button type="button" className="secondary-button" disabled={lines.length>=100} onClick={()=>setLines([...lines,{key:Math.max(...lines.map(l=>l.key))+1,item_id:"",quantity:""}])}>Add material line</button></>}

  <Field label={production?"Batch reference / processing note":"Source reference and reason"}>{id=><textarea id={id} name="note" required maxLength={1000} rows={3} placeholder="Delivery note, count sheet, requisition reference, batch log or waste reason"/>}</Field>
  <label className="stock-confirm"><input name="confirmed" type="checkbox" required/>{"I checked the quantities, units and source. A separate authorised colleague will approve this request."}</label><Feedback state={state}/><button className="auth-button catalogue-add" disabled={production&&!packet.processing?.standards.length}>{pending?"Saving...":"Submit stock request"}</button>
 </fieldset></form>;
}
export function StockDecision({organisation,document}:{organisation:string;document:StockDocument}){
 const [state,action,pending]=useActionState(actOnStock,{}),[choice,setChoice]=useState(["approve","post","dispatch","receive","resolve"].find(k=>document.actions[k as keyof typeof document.actions])?.toUpperCase()??""),[received,setReceived]=useState(document.lines.map(l=>({item_id:l.item_id,quantity:l.quantity,reason:""})));
 const labels:Record<string,string>={APPROVE:"Approve request",POST:"Post stock quantities",DISPATCH:"Confirm dispatch",RECEIVE:"Accept transfer",REJECT:"Reject transfer",DECLINE:"Decline request",RESOLVE:"Resolve follow-up",CANCEL:"Cancel request"};
 if(document.kind==="WASTE")return <WasteRecordCompletion organisation={organisation} document={document}/>;
 if(!Object.values(document.actions).some(Boolean))return ["POSTED","RECEIVED","CANCELLED"].includes(document.state)?null:<p className="stock-help">No action is available to your account for this record.</p>;
 if(document.kind==="PRODUCTION")return ["REQUESTED","APPROVED"].includes(document.state)?<p className="stock-help">This older processing entry has not updated stock. Its original recorder can complete it in the <Link className="inline-link" href={`/workspace/inventory/processing?organisation=${organisation}&site=${document.source_id}&from=${document.document_date}&to=${document.document_date}`}>Material Processing Log</Link>.</p>:null;
 const primary=["approve","post","dispatch","receive","resolve"].some(k=>document.actions[k as keyof typeof document.actions]);
 const form=<form action={action} onReset={e=>e.preventDefault()} className="stock-form"><input type="hidden" name="organisation" value={organisation}/><input type="hidden" name="document" value={document.id}/><input type="hidden" name="received" value={JSON.stringify(received)}/><fieldset disabled={pending}><legend>Review and act</legend>
  <Field label="Stock decision">{id=><select id={id} name="decision" required value={choice} onChange={e=>setChoice(e.target.value)}><option value="" disabled>Choose an action</option>{Object.entries(document.actions).filter(([,allowed])=>allowed).map(([name])=><option key={name} value={name.toUpperCase()}>{labels[name.toUpperCase()]}</option>)}</select>}</Field>
  {choice==="RECEIVE"&&<><p className="stock-help">Confirm all lines. Only accepted quantities leave the source and enter this department. Rejected quantities stay in source stock and need a reason. Partial acceptance marks the requisition Incomplete; request a replacement separately if needed. Acceptance is dated today.</p><TableScroll label="Transfer receipt quantities"><table className="data-table"><thead><tr><th>Material</th><th>Dispatched</th><th>Accepted</th><th>Reason for rejected quantity</th></tr></thead><tbody>{document.lines.map((l,n)=><tr key={l.item_id}><th scope="row">{l.name} ({l.unit})</th><td>{l.quantity}</td><td><input aria-label={`Accepted ${l.name}`} inputMode="decimal" required value={received[n].quantity} onChange={e=>setReceived(received.map((r,i)=>i===n?{...r,quantity:e.target.value}:r))}/></td><td><input aria-label={`Reason for rejected ${l.name}`} maxLength={500} value={received[n].reason} onChange={e=>setReceived(received.map((r,i)=>i===n?{...r,reason:e.target.value}:r))}/></td></tr>)}</tbody></table></TableScroll></>}
  {document.manager_return&&(choice==="RECEIVE"||choice==="REJECT")&&<p className="stock-help">This is a department-originated return to Main Store. Your receiving decision is recorded separately from the dispatch authorisation.</p>}
  {choice==="DISPATCH"&&<p className="stock-help">Dispatch reserves stock for this requisition. Neither stock balance changes until the receiving side accepts.</p>}
  {choice==="REJECT"&&<p className="stock-help">Reject the entire transfer with a reason. No new stock deduction or addition will be posted; rejected stock remains reserved until the Inventory Manager confirms its physical return.</p>}
  {choice==="RESOLVE"&&<p className="stock-help">{document.dispatched_at?"Confirm rejected goods have physically returned to source and record the evidence or replacement reference. Resolving releases their reservation without changing on-hand balances.":"Record why this request was declined and any replacement reference. No stock quantity will change."}</p>}
  <Field label="Decision note">{id=><textarea id={id} name="note" required rows={2} maxLength={1000}/>}</Field><label className="stock-confirm"><input type="checkbox" name="confirmed" required/>I reviewed this record and confirm this stock decision.</label><Feedback state={state}/><button className="secondary-button" disabled={pending||!choice}>{pending?"Saving...":labels[choice]??"Choose an action"}</button>
 </fieldset></form>;
 return primary?form:<details className="stock-other-actions"><summary>Other actions</summary>{form}</details>;
}

export function StockOutputBinding({organisation,packet}:{organisation:string;packet:StockPacket}){return <ProcessingOutputLink organisation={organisation} packet={packet}/>;}

function WasteRecordCompletion({organisation,document}:{organisation:string;document:StockDocument}){
 const [state,action,pending]=useActionState(finishWasteRecord,{});
 if(document.state==="POSTED")return <p className="stock-help">Waste recorded. No approval required.</p>;
 if(!document.finish_waste)return <p className="stock-help">{["REQUESTED","APPROVED"].includes(document.state)?"This older record needs a submitter name. Its original recorder can complete it.":"This waste record is closed."}</p>;
 return <form action={action} className="stock-form"><input type="hidden" name="organisation" value={organisation}/><input type="hidden" name="document" value={document.id}/><fieldset disabled={pending}><legend>Complete waste recording</legend><p className="stock-help">Enter the submitter name to record this older entry and update stock once. No approval required.</p><Field label="Submitter name">{id=><input id={id} name="submitter_name" required maxLength={120} autoComplete="name"/>}</Field><Feedback state={state}/><button className="secondary-button">{pending?"Saving...":"Record waste"}</button></fieldset></form>;
}
