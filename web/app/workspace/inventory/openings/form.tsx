"use client";
import { useActionState } from "react";
import { submitImportedOpening } from "./actions";
export function SubmitOpeningForm({ org, batch, direct=false }: { org: string; batch: string; direct?:boolean }) {
 const [state, action, pending] = useActionState(submitImportedOpening, {});
 return <form action={action} className="setup-form"><input type="hidden" name="organisation" value={org}/><input type="hidden" name="batch" value={batch}/>{direct&&<input type="hidden" name="direct_opening" value="on"/>}<label><input type="checkbox" name="confirmed" required disabled={pending}/> {direct?"I verified these opening quantities and understand that recording updates stock immediately.":"I checked these physical opening quantities."}</label>{state.error && <p role="alert">{state.error}</p>}<button className="auth-button" disabled={pending}>{pending ? "Saving..." : direct?"Record opening stock":"Submit opening for review"}</button></form>;
}
