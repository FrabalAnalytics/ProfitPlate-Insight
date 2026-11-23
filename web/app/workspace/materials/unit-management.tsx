"use client";
import {useActionState,useState} from "react";
import {createUnit,deleteMaterial} from "./actions";

export function UnitCreator({organisationId}:{organisationId:string}) {
 const [state,action,pending]=useActionState(createUnit,{});
 const [dimension,setDimension]=useState("PACKAGE");
 const [fields,setFields]=useState({code:"",name:"",factor:""});
 const update=(key:"code"|"name"|"factor",value:string)=>setFields(old=>({...old,[key]:value}));
 const canonical=dimension==="MASS"?"KG":dimension==="VOLUME"?"L":"PCS";
 return <details className="catalogue-editor"><summary>Add a unit</summary><form action={action} className="setup-form" aria-busy={pending}>
 <input type="hidden" name="organisation_id" value={organisationId}/>
 {state.error&&<p className="auth-alert" role="alert">{state.error}</p>}
 <div className="setup-field-grid"><div className="setup-field"><label htmlFor="unit-code">Unit code</label><input id="unit-code" name="code" required maxLength={40} value={fields.code} onChange={e=>update("code",e.target.value.toUpperCase())} placeholder="e.g. CRATE"/>{state.errors?.code&&<p className="field-error">{state.errors.code}</p>}</div><div className="setup-field"><label htmlFor="unit-name">Unit name</label><input id="unit-name" name="name" required maxLength={80} value={fields.name} onChange={e=>update("name",e.target.value)} placeholder="e.g. Crate"/>{state.errors?.name&&<p className="field-error">{state.errors.name}</p>}</div></div>
 <div className="setup-field"><label htmlFor="unit-dimension">Measurement type</label><select id="unit-dimension" name="dimension" value={dimension} onChange={e=>{setDimension(e.target.value);update("factor","");}}><option value="PACKAGE">Packaging - size varies by material</option><option value="MASS">Weight</option><option value="VOLUME">Volume</option><option value="COUNT">Count</option></select></div>
 {dimension!=="PACKAGE"?<div className="setup-field"><label htmlFor="unit-factor">1 new unit equals how many {canonical}?</label><input key={dimension} id="unit-factor" name="factor" value={fields.factor} onChange={e=>update("factor",e.target.value)} inputMode="decimal" required placeholder={dimension==="COUNT"?"e.g. 12 for a dozen":"Enter the exact conversion"}/>{state.errors?.factor&&<p className="field-error">{state.errors.factor}</p>}<small>Up to six decimal places. Weight is measured against KG, volume against L, and count against PCS.</small></div>:<p className="catalogue-form-note">After saving, choose a material and add its package conversion. For example, 1 crate = 24 PCS of bottled water.</p>}
 <p className="catalogue-form-note">Saved unit definitions stay fixed to protect history. Use a different code for a different definition.</p>
 <button className="secondary-button" disabled={pending} type="submit">{pending?"Adding unit...":"Add unit"}</button>
 </form></details>;
}

export function MaterialDeletion({organisationId,itemId,code,name}:{organisationId:string;itemId:string;code:string;name:string}) {
 const [state,action,pending]=useActionState(deleteMaterial,{});
 return <details className="catalogue-editor"><summary>Delete unused material</summary><p>Delete {name} only if it was created by mistake. Materials with linked records must be marked inactive instead.</p><form action={action} className="setup-form" aria-busy={pending}>
 <input type="hidden" name="organisation_id" value={organisationId}/><input type="hidden" name="item_id" value={itemId}/>
 {state.error&&<p className="auth-alert" role="alert">{state.error}</p>}
 <div className="setup-field"><label htmlFor="delete-material-code">Type {code} to confirm</label><input id="delete-material-code" name="code" required autoComplete="off" maxLength={40}/></div>
 <label className="catalogue-checkbox"><input type="checkbox" name="confirmed" value="true" required/>I want to permanently delete this unused material.</label>
 <button type="submit" className="secondary-button" disabled={pending}>{pending?"Deleting...":"Delete material"}</button>
 </form></details>;
}
