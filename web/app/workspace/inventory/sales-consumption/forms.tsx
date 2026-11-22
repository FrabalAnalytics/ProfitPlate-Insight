'use client';
import {useActionState} from 'react';
import {consumptionAction} from './actions';
export function ConsumptionForm({org,job,evidence,reconcile=false,historical=false}:{org:string;job?:string;evidence?:string;reconcile?:boolean;historical?:boolean}){
 const[state,action,pending]=useActionState(consumptionAction,{});
 return <form action={action}><input type="hidden" name="organisation" value={org}/><input type="hidden" name="job" value={job??''}/><input type="hidden" name="evidence" value={evidence??''}/><fieldset disabled={pending}>{historical?<><input type="hidden" name="intent" value="HISTORY"/><label>First sales date<input type="date" name="from" required/></label><label>Last sales date<input type="date" name="to" required/></label><p>Prepare up to 93 days and 1,000 sales lines for review. Existing stock remains unchanged.</p></>:reconcile?<><label><input type="checkbox" name="reconcile" required/> I reviewed the affected counts and the dated stock movements.</label><label>Reconciliation reason<textarea name="note" required minLength={5} maxLength={1000}/></label></>:null}<button className="secondary-button" disabled={pending}>{pending?'Saving...':historical?'Prepare historical sales':reconcile?'Approve late-sales reconciliation':'Post standard consumption'}</button></fieldset>{state.error&&<p className="auth-alert" role="alert">{state.error}</p>}</form>;
}
