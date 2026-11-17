"use client";

import { useActionState } from "react";
import { saveReport } from "./actions";

export function SaveReportForm({ organisation, from, to, location, request }: { organisation: string; from: string; to: string; location: string; request: string }) {
  const [state, action, pending] = useActionState(saveReport, {});
  return <details className="management-save management-no-print"><summary>Save to report history</summary><form action={action} aria-busy={pending}>
    <input type="hidden" name="organisation" value={organisation}/><input type="hidden" name="from" value={from}/><input type="hidden" name="to" value={to}/><input type="hidden" name="location" value={location}/><input type="hidden" name="request" value={request}/>
    <div className="setup-field"><label htmlFor="saved-report-name">Report name</label><input id="saved-report-name" name="title" maxLength={120} defaultValue={`Management report ${from} to ${to}`} required/></div>
    <p className="overview-footnote">Saving refreshes the source figures for this selection and preserves a new copy. It may differ from the live figures above. Coverage warnings are retained; saving does not approve or close the period.</p>
    {state.error && <p role="alert" className="auth-alert">{state.error}</p>}
    <button type="submit" className="secondary-button" disabled={pending}>{pending ? "Saving report…" : "Save report"}</button>
  </form></details>;
}
