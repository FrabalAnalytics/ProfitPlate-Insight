import {DataTable,StatusBadge} from "@/app/components/data-table";
import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { isUuid } from "@/lib/catalogue";
import { contextQuery } from "@/lib/overview";
import { managementReportCsv, savedManagementReportBasis, type SavedManagementReport, type ManagementReportHistory } from "@/lib/management-report";
import { reviewedManagementReportRows, reviewStatusLabel, type ReportReview } from "@/lib/report-reviews";
import { WorkspaceShell } from "@/app/components/workspace-shell";
import { ReportActions } from "../report-actions";
import { ReportContent, ReportDisclosure } from "../report-content";
import { ReportReviewPanel } from "../report-review-panel";
import "../../materials/catalogue.css";
import "../../overview/overview.css";
import "../reports.css";

export const metadata: Metadata = { title: "Report history | ProfitPlate Insights" };
export const instant = false;
type Params = { organisation?: string; report?: string; page?: string; reviewPage?: string };
export default async function ReportHistoryPage({ searchParams }: { searchParams: Promise<Params> }) {
  const user = await requireUser(), access = await getPlatformAccess();
  if (access !== "member") redirect(workspacePath(access));
  const params = await searchParams, client = await createClient();
  const orgs = await client.from("organisations").select("id,name").order("name");
  const org = params.organisation ? orgs.data?.find(item => item.id === params.organisation) : orgs.data?.[0];
  if (!org) return <WorkspaceShell email={user.email}><h1 className="workspace-title">This business is unavailable.</h1><Link href="/workspace">Return to workspace</Link></WorkspaceShell>;
  const shell = { email: user.email, restaurantName: org.name, organisationId: org.id, sectionLabel: "Report history" };
  const permission = await client.rpc("sales_import_access", { p_organisation_id: org.id });
  if (permission.error || permission.data?.read !== true) return <WorkspaceShell {...shell}><h1 className="workspace-title">Management report access is restricted.</h1><p className="workspace-description">An organisation-wide CEO, Finance member or Restaurant Administrator can review saved reports.</p></WorkspaceShell>;
  const historyHref = `/workspace/reports/history?${new URLSearchParams({ organisation: org.id })}`;
  const liveHref = `/workspace/reports?${new URLSearchParams({ organisation: org.id })}`;
  const unavailable = (message: string) => <WorkspaceShell {...shell}><h1 className="workspace-title">Report history</h1><p role="alert" className="auth-alert">{message}</p><Link className="secondary-button" href={historyHref}>Return to report history</Link><Link className="inline-link" href={liveHref}>Open live report</Link></WorkspaceShell>;
  const failure = (code?: string) => code === "PGRST202" ? "Report history needs database migration 014. Ask your administrator to complete setup." : "Saved reports could not be loaded. Check your access and connection, then try again.";
  if (params.report !== undefined) {
    if (!isUuid(params.report)) return unavailable("Saved report unavailable.");
    const result = await client.rpc("get_management_report", { p_organisation_id: org.id, p_report_id: params.report });
    if (result.error || !result.data) return unavailable(failure(result.error?.code));
    const report = result.data as SavedManagementReport;
    if (report.format_version !== "MANAGEMENT_SNAPSHOT_V1") return unavailable("This report version is not supported by the current app.");
    const reviewPage = Number(params.reviewPage ?? "1");
    const reviewResult = Number.isInteger(reviewPage) && reviewPage >= 1 && reviewPage <= 100000 ? await client.rpc("get_management_report_review", { p_organisation_id: org.id, p_report_id: report.id, p_page: reviewPage }) : { data: null, error: { code: "22023", message: "Choose a valid review activity page." } };
    const review = reviewResult.error ? null : reviewResult.data as ReportReview | null;
    const reviewError = reviewResult.error?.code === "PGRST202" ? "Report reviews need database migration 015. Ask your administrator to complete setup." : reviewResult.error?.code === "22023" ? reviewResult.error.message : "Review activity could not be loaded. Refresh to try again.";
    const { context, overview, costs } = report.payload, rows = reviewedManagementReportRows(report, review);
    const href = (path: string) => `${path}?${contextQuery(org.id, { from: context.from, to: context.to, location: context.locationId })}`;
    return <WorkspaceShell {...shell} reportingContext={{ from: context.from, to: context.to, location: context.locationId }}><div className="management-report">
      <div className="page-heading-row"><div><p className="eyebrow form-eyebrow">SAVED MANAGEMENT ESTIMATE</p><h1 className="workspace-title">{report.title}</h1><p className="workspace-description">Preserved figures and coverage from the time this report was saved.</p></div><Link className="secondary-button management-no-print" href={historyHref}>Report history</Link></div>
      <section className="overview-context management-context" aria-label="Saved report context"><div><strong>{context.organisation}</strong><strong>{context.from} to {context.to}</strong><span>{context.location} · {context.currency} · {context.timeZone}</span></div></section>
      <div className="overview-basis"><span>Saved: <time dateTime={report.created_at}>{new Intl.DateTimeFormat("en-GB", { timeZone: context.timeZone, dateStyle: "medium", timeStyle: "medium" }).format(new Date(report.created_at))}</time> ({context.timeZone})</span><span>Saved estimate · {review ? reviewStatusLabel[review.status] : "Review unavailable"}</span></div>
      <p className="management-warning">{savedManagementReportBasis}</p>
      <ReportActions saved csv={managementReportCsv(rows)} filename={`profitplate-saved-${context.from}-to-${context.to}-${report.id}.csv`}/>
      <p className="overview-footnote management-no-print">Source links open current records, which may differ from this saved report. <Link className="inline-link" href={href("/workspace/reports")}>Open current report for this selection</Link></p>
      {overview.summary.lines === 0 && <p className="management-warning">No recorded sales were available when saved. This does not confirm that no trading occurred.</p>}
      <ReportContent rows={rows} overview={overview} costs={costs} currency={context.currency} overviewHref={href("/workspace/overview")} costsHref={href("/workspace/expenses")}/>
      <ReportReviewPanel organisation={org.id} report={report.id} review={review} error={reviewError} page={reviewPage} timeZone={context.timeZone}/>
      <ReportDisclosure id="report-basis" title="Saved report basis & limits" description="Preserved source context and reporting limits"><div className="management-method"><p>{savedManagementReportBasis}</p><p>Report ID: {report.id}. Sales refreshed: {overview.refreshed_at}. Costs refreshed: {costs.refreshed_at}.</p><p>Up to 93 days, 1,000 sales lines and 2,000 expense entries. Coverage warnings and source decimal values are preserved. New saves create separate copies; existing saved reports cannot be edited or deleted.</p></div></ReportDisclosure>
    </div></WorkspaceShell>;
  }
  const page = Number(params.page ?? "1");
  if (!Number.isInteger(page) || page < 1 || page > 100000) return unavailable("Choose a valid history page.");
  const result = await client.rpc("list_management_reports", { p_organisation_id: org.id, p_page: page });
  if (result.error || !result.data) return unavailable(failure(result.error?.code));
  const history = result.data as ManagementReportHistory;
  return <WorkspaceShell {...shell}><div className="management-report">
    <div className="page-heading-row"><div><p className="eyebrow form-eyebrow">REPORTING CENTRE</p><h1 className="workspace-title">Report history</h1><p className="workspace-description">Saved management estimates for {org.name}. Each copy keeps its original figures and coverage warnings.</p></div><Link className="secondary-button" href={liveHref}>Open live report</Link></div>
    {orgs.data && orgs.data.length > 1 && <form className="business-switcher" method="get"><label htmlFor="history-business">Business</label><select id="history-business" name="organisation" defaultValue={org.id}>{orgs.data.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select><button className="secondary-button">Switch business</button></form>}
    <p className="overview-footnote">{history.total} saved {history.total === 1 ? "report" : "reports"}. Saved copies are not approved accounting statements.</p>
    {!history.reports.length ? <section className="overview-panel"><h2>{page === 1 ? "No saved reports yet" : "No reports on this page"}</h2><p>Open a live report and choose Save to report history to preserve a copy.</p></section> : <DataTable label="Saved management reports" columns={[{label:"Report"},{label:"Period"},{label:"Outlet / currency"},{label:"Saved at (UTC)"},{label:"Review status"},{label:"Action"}]} rows={history.reports.map(report=>({id:report.id,cells:[<span key="title"><Link className="inline-link" href={`${historyHref}&report=${report.id}`}>{report.title}</Link><small>Management estimate</small></span>,`${report.from} to ${report.to}`,<span key="scope">{report.location}<small>{report.currency}</small></span>,<time key="saved" dateTime={report.created_at}>{new Date(report.created_at).toISOString().replace("T"," ").slice(0,19)} UTC</time>,<StatusBadge key="review" tone={report.review_status==="APPROVED"?"success":"neutral"}>{report.review_status?reviewStatusLabel[report.review_status]:"Review status unavailable"}</StatusBadge>,<Link key="view" className="inline-link" aria-label={`Open saved report ${report.title}`} href={`${historyHref}&report=${report.id}`}>Open report</Link>]}))}/>}
    <nav className="management-history-pages" aria-label="Report history pages">{page > 1 && <Link className="secondary-button" href={`${historyHref}&page=${page - 1}`}>Previous page</Link>}<span>Page {page}</span>{page * 20 < history.total && <Link className="secondary-button" href={`${historyHref}&page=${page + 1}`}>Next page</Link>}</nav>
  </div></WorkspaceShell>;
}
