"use client";

import { useActionState, useState } from "react";
import { reviewReport } from "./actions";
import { type ReviewAction, type ReportReview } from "@/lib/report-reviews";

export function ReviewReportForm({ organisation, report, review, request }: { organisation: string; report: string; review: ReportReview; request: string }) {
  const actions: { value: ReviewAction; label: string }[] = [];
  if (review.status === "SAVED" || review.status === "CHANGES_REQUESTED") actions.push({ value: "SUBMIT", label: review.status === "CHANGES_REQUESTED" ? "Respond and resubmit" : "Submit for review" });
  if (review.can_approve && review.status === "IN_REVIEW") actions.push({ value: "APPROVE", label: "Approve for management use" }, { value: "REQUEST_CHANGES", label: "Request changes" });
  if (review.can_approve && review.status === "APPROVED") actions.push({ value: "WITHDRAW_APPROVAL", label: "Withdraw approval" });
  actions.push({ value: "COMMENT", label: "Add a comment" });
  const [action, setAction] = useState<ReviewAction>(actions[0].value);
  const [state, formAction, pending] = useActionState(reviewReport, {});
  const noteRequired = ["COMMENT", "REQUEST_CHANGES", "WITHDRAW_APPROVAL"].includes(action) || (action === "SUBMIT" && review.status === "CHANGES_REQUESTED");
  return <form action={formAction} className="management-review-form management-no-print" aria-busy={pending}>
    <input type="hidden" name="organisation" value={organisation}/><input type="hidden" name="report" value={report}/><input type="hidden" name="request" value={request}/><input type="hidden" name="revision" value={review.revision}/>
    <div className="setup-field"><label htmlFor="review-action">Review action</label><select id="review-action" name="action" value={action} onChange={event => setAction(event.target.value as ReviewAction)} disabled={pending}>{actions.map(item => <option key={item.value} value={item.value}>{item.label}</option>)}</select></div>
    <div className="setup-field"><label htmlFor="review-note">{noteRequired ? "Review note (required)" : "Review note (optional)"}</label><textarea id="review-note" name="note" rows={3} maxLength={2000} required={noteRequired} disabled={pending} aria-describedby="review-note-help"/><small id="review-note-help">Visible to financial report readers. If figures need correcting, save a new report; this copy remains unchanged.</small></div>
    {action === "APPROVE" && <label className="management-review-confirm"><input name="acknowledged" type="checkbox" required disabled={pending}/>I have reviewed the saved figures, reference-cost estimates and coverage warnings. I approve this copy for management use; this does not confirm accounting accuracy or close the period.</label>}
    {action === "WITHDRAW_APPROVAL" && <p className="management-warning">Withdrawing approval marks this copy as Changes requested. The previous approval remains in its review history.</p>}
    {state.error && <p role="alert" className="auth-alert">{state.error}</p>}
    {state.success && <p role="status" className="auth-notice">{state.success}</p>}
    <button className="secondary-button" type="submit" disabled={pending}>{pending ? "Saving review…" : "Save review action"}</button>
  </form>;
}
