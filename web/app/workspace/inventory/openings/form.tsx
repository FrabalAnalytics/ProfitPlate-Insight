"use client";
import { useActionState } from "react";
import { submitImportedOpening } from "./actions";
export function SubmitOpeningForm({ org, batch }: { org: string; batch: string }) {
 const [state, action, pending] = useActionState(submitImportedOpening, {});
 return <form action={action} className="setup-form"><input type="hidden" name="organisation" value={org}/><input type="hidden" name="batch" value={batch}/><label><input type="checkbox" required disabled={pending}/> I checked these physical opening quantities.</label>{state.error && <p role="alert">{state.error}</p>}<button className="auth-button" disabled={pending}>{pending ? "Submitting..." : "Submit opening for review"}</button></form>;
}
