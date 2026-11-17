import {DataTable} from "@/app/components/data-table";
import Link from "next/link";
import { reviewActionLabel, reviewStatusLabel, type ReportReview } from "@/lib/report-reviews";
import { ReviewReportForm } from "./review-report-form";
import { ReportDisclosure } from "./report-content";

export function ReportReviewPanel({ organisation, report, review, error, page, timeZone }: { organisation: string; report: string; review: ReportReview | null; error: string; page: number; timeZone: string }) {
  if (!review) return <section className="management-review-panel" aria-labelledby="report-review-heading"><h2 id="report-review-heading">Management review</h2><p role="alert" className="auth-alert">{error}</p><p className="overview-footnote">Review status is unavailable. No approval is inferred; saved financial figures remain available.</p></section>;
  const date = (at: string) => new Intl.DateTimeFormat("en-GB", { timeZone, dateStyle: "medium", timeStyle: "medium" }).format(new Date(at));
  const href = (target: number) => `/workspace/reports/history?${new URLSearchParams({ organisation, report, reviewPage: String(target) })}`;
  return <section className="management-review-panel" aria-labelledby="report-review-heading">
    <div className="overview-section-heading"><h2 id="report-review-heading">Management review</h2><strong className={`management-review-status ${review.status === "APPROVED" ? "management-review-approved" : ""}`} role="status">{reviewStatusLabel[review.status]}</strong></div>
    <p className="overview-footnote">CEO and Restaurant Administrator approve. Finance can submit and comment. Approval records a management decision; estimates and missing-data warnings retain their original basis.</p>
    {review.decision && <p className="management-review-decision"><strong>{reviewActionLabel[review.decision.action]}</strong> by {review.decision.actor} · <time dateTime={review.decision.at}>{date(review.decision.at)}</time> ({timeZone}){review.decision.note && <span>{review.decision.note}</span>}</p>}
    <ReviewReportForm key={`${report}:${review.revision}`} organisation={organisation} report={report} review={review} request={crypto.randomUUID()}/>
    <ReportDisclosure id="report-review-activity" title="Review activity" description={`${review.revision} ${review.revision === 1 ? "event" : "events"} · newest first`}>
      <DataTable label="Management report review activity" columns={[{label:"Action"},{label:"Actor"},{label:`Date / time (${timeZone})`},{label:"Note"}]} rows={review.events.map(event=>({id:event.id,cells:[reviewActionLabel[event.action],event.actor,<time key="at" dateTime={event.at}>{date(event.at)}</time>,event.note||"Not provided"]}))} empty={page===1?"No review activity yet.":"No review activity on this page."}/>
      <p className="overview-footnote">Activity page {page}. Up to 20 events shown; all events remain in the audit history.</p>
      <nav className="management-history-pages management-no-print" aria-label="Review activity pages">{page > 1 && <Link className="secondary-button" href={href(page - 1)}>Newer activity</Link>}{page * 20 < review.revision && <Link className="secondary-button" href={href(page + 1)}>Older activity</Link>}</nav>
    </ReportDisclosure>
  </section>;
}
