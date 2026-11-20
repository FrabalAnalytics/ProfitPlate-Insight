"use client";
import {useActionState} from 'react';
import {selectProcessingCentres} from '../production/actions';
import type {ProcessingSetup} from '@/lib/processing';
export function ProcessingUnitForm({org,setup}:{org:string;setup:ProcessingSetup}){
 const[state,action,pending]=useActionState(selectProcessingCentres,{});
 const eligible=setup.sites.filter(s=>s.is_active&&s.responsible_active!==false&&s.responsible_membership_id);
 return <form action={action} onReset={e=>e.preventDefault()} className="stock-form"><input type="hidden" name="organisation" value={org}/><input type="hidden" name="revision" value={setup.processing_centres_revision??0}/><fieldset disabled={pending||!!state.success}><legend>Centres allowed to process or produce</legend><p className="stock-help">Choose every centre that transforms materials, such as Main Store and Central Kitchen. Each batch consumes its inputs and adds one output SKU at the same centre. Transfers remain separate.</p><fieldset className="processing-sites"><legend>Enabled production centres</legend>{eligible.map(s=><label key={s.id} className="catalogue-checkbox"><input type="checkbox" name="centre" value={s.id} defaultChecked={s.processing_enabled}/>{s.name} / {s.responsible_name}</label>)}{!eligible.length&&<p>Save a centre with an active responsible member first.</p>}</fieldset><p className="stock-help">A baseline must also permit the selected centre, and the user still needs its stock task access. Finish or cancel pending batches before disabling their centre.</p>{state.error&&<p className="auth-alert" role="alert">{state.error}</p>}{state.success&&<p role="status">{state.success}</p>}<button className="secondary-button">{pending?'Saving...':'Save production centres'}</button></fieldset></form>;
}
