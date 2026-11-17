import type { ManagementReportRow, SavedManagementReport } from "./management-report";
import { savedManagementReportRows } from "./management-report";

export type ReviewStatus = "SAVED" | "IN_REVIEW" | "CHANGES_REQUESTED" | "APPROVED";
export type ReviewAction = "SUBMIT" | "COMMENT" | "APPROVE" | "REQUEST_CHANGES" | "WITHDRAW_APPROVAL";
export type ReviewDecision = { action: ReviewAction; actor: string; at: string; note: string; revision: number };
export type ReportReview = { status: ReviewStatus; revision: number; can_approve: boolean; decision: ReviewDecision | null; events: (ReviewDecision & { id: string; status: ReviewStatus })[] };
export const reviewStatusLabel: Record<ReviewStatus, string> = { SAVED: "Not submitted", IN_REVIEW: "Awaiting review", CHANGES_REQUESTED: "Changes requested", APPROVED: "Approved for management use" };
export const reviewActionLabel: Record<ReviewAction, string> = { SUBMIT: "Submitted for review", COMMENT: "Comment added", APPROVE: "Approved for management use", REQUEST_CHANGES: "Changes requested", WITHDRAW_APPROVAL: "Approval withdrawn" };

/** Financial V1 rows remain intact. Review metadata describes the read revision. */
export function reviewedManagementReportRows(report: SavedManagementReport, review: ReportReview | null): ManagementReportRow[] {
  const rows = savedManagementReportRows(report);
  const add = (metric: string, value: string | null, notes = "") => rows.push({ section: "Management review", metric, value, unit: "", status: "CONTEXT", notes });
  if (!review) {
    add("Review status", null, "Review metadata could not be loaded. No approval is inferred.");
    return rows;
  }
  // Keep unchanged, unsubmitted V1 downloads identical across source refreshes.
  if (review.revision === 0) return rows;
  const format = rows.find(row => row.section === "Context" && row.metric === "Format")!;
  format.value = "EXECUTIVE_MANAGEMENT_REVIEW_CSV_V1";
  add("Financial snapshot format", "EXECUTIVE_MANAGEMENT_SAVED_CSV_V1");
  add("Review status", reviewStatusLabel[review.status], "Approval is for management use. Financial figures and coverage remain as saved; this does not close an accounting period or verify actual inventory COGS.");
  add("Review revision", String(review.revision), "Review status and comments can change independently of the saved financial figures. This export captures the revision shown.");
  if (review.decision) {
    add("Latest decision", reviewActionLabel[review.decision.action]);
    add("Decision by", review.decision.actor);
    add("Decision at", review.decision.at);
    add("Decision note", review.decision.note);
  }
  return rows;
}
