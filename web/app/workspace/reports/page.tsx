import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { isUuid } from "@/lib/catalogue";
import { validBusinessDate } from "@/lib/recipes";
import { type ExpenseReport } from "@/lib/expenses";
import { contextQuery, type Overview } from "@/lib/overview";
import { managementReportRows, managementReportCsv, managementReportBasis } from "@/lib/management-report";
import { WorkspaceShell } from "@/app/components/workspace-shell";
import { ReportActions } from "./report-actions";
import { ReportContent, ReportDisclosure } from "./report-content";
import { SaveReportForm } from "./save-report-form";
import "../materials/catalogue.css";
import "../overview/overview.css";
import "./reports.css";

export const metadata: Metadata = { title: "Management reports | ProfitPlate Insight" };
export const instant = false;
type Params = { organisation?: string; from?: string; to?: string; location?: string };
export default async function ReportsPage({ searchParams }: { searchParams: Promise<Params> }) {
  const user = await requireUser(), access = await getPlatformAccess();
  if (access !== "member") redirect(workspacePath(access));
  const params = await searchParams, client = await createClient();
  const orgResult = await client.from("organisations").select("id,name,currency_code,time_zone").order("name");
  if (!orgResult.error && !orgResult.data?.length) redirect("/onboarding");
  const org = params.organisation ? orgResult.data?.find(item => item.id === params.organisation) : orgResult.data?.[0];
  if (!org) return <WorkspaceShell email={user.email}><h1 className="workspace-title">This business is unavailable.</h1><Link href="/workspace">Return to workspace</Link></WorkspaceShell>;
  const parts = new Intl.DateTimeFormat("en", { timeZone: org.time_zone, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(new Date());
  const today = ["year", "month", "day"].map(key => parts.find(part => part.type === key)?.value).join("-");
  const from = params.from ?? `${today.slice(0, 7)}-01`, to = params.to ?? today, location = params.location ?? "", context = { from, to, location };
  const shell = { email: user.email, restaurantName: org.name, organisationId: org.id, sectionLabel: "Management reports", reportingContext: context };
  const permission = await client.rpc("sales_import_access", { p_organisation_id: org.id });
  if (permission.error || permission.data?.read !== true) return <WorkspaceShell {...shell}><h1 className="workspace-title">Management report access is restricted.</h1><p className="workspace-description">An organisation-wide CEO, Finance member or Restaurant Administrator can review financial reports. Check your access or try again shortly.</p></WorkspaceShell>;
  const locationsResult = await client.from("locations").select("id,name,is_active").eq("organisation_id", org.id).order("name");
  const locations = locationsResult.data ?? [];
  let overview: Overview | null = null, costs: ExpenseReport | null = null, error = "", costError = "";
  if (!validBusinessDate(from) || !validBusinessDate(to) || (location && !isUuid(location))) error = "Choose valid dates and a business location.";
  else if (locationsResult.error) error = "Report locations could not be loaded. Refresh to try again.";
  else if (location && !locations.some(item => item.id === location)) error = "Choose a location available in this business.";
  else {
    const args = { p_organisation_id: org.id, p_from: from, p_to: to, p_location_id: location || null };
    const [salesResult, costResult] = await Promise.all([client.rpc("executive_overview", args), client.rpc("expense_period_report", { ...args, p_page: 1 })]);
    if (salesResult.error) error = salesResult.error.code === "22023" ? salesResult.error.message : "The report could not be generated. Check your access and try again.";
    else overview = salesResult.data as Overview;
    if (costResult.error) costError = "Expense reporting could not be loaded. Cost coverage, labour, operating expenses and prime cost are unavailable in this report.";
    else costs = costResult.data as ExpenseReport;
  }
  const generatedAt = new Date().toISOString();
  const reportContext = { organisation: org.name, organisationId: org.id, from, to, location: locations.find(item => item.id === location)?.name ?? "All business locations + central costs", locationId: location, currency: org.currency_code, timeZone: org.time_zone, generatedAt };
  const rows = overview ? managementReportRows(reportContext, overview, costs) : [];
  const href = (path: string, extra: Record<string, string> = {}) => `${path}?${contextQuery(org.id, context, extra)}`;
  const week = new Date(`${today}T00:00:00Z`); week.setUTCDate(week.getUTCDate() - 6);
  const shortcuts = [["Daily", today], ["Last 7 days", week.toISOString().slice(0, 10)], ["This month", `${today.slice(0, 7)}-01`]];
  return <WorkspaceShell {...shell}><div className="management-report">
    <div className="page-heading-row"><div><p className="eyebrow form-eyebrow">REPORTING CENTRE</p><h1 className="workspace-title">Executive management report</h1></div><Link className="secondary-button management-no-print" href={href("/workspace/reports/history")}>Report history</Link></div>
    {orgResult.data && orgResult.data.length > 1 && <form className="business-switcher management-no-print" method="get"><label htmlFor="report-business">Business</label><select id="report-business" name="organisation" defaultValue={org.id}>{orgResult.data.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select><button className="secondary-button">Switch business</button></form>}
    <section className="overview-context management-context" aria-label="Management report context"><div><strong>{org.name}</strong><strong>{from} to {to}</strong><span>{reportContext.location} · {org.currency_code} · {org.time_zone}</span></div><nav aria-label="Report period shortcuts">{shortcuts.map(([label, start]) => <Link key={label} href={href("/workspace/reports", { from: start, to: today })} aria-current={from === start && to === today ? "true" : undefined}>{label}</Link>)}</nav><details className="overview-filter management-no-print"><summary>Change report filters</summary><form method="get"><input type="hidden" name="organisation" value={org.id}/><div className="setup-field"><label htmlFor="report-from">Report from</label><input id="report-from" name="from" type="date" defaultValue={from} max={today} required/></div><div className="setup-field"><label htmlFor="report-through">Report through</label><input id="report-through" name="to" type="date" defaultValue={to} max={today} required/></div><div className="setup-field"><label htmlFor="report-location">Report location</label><select id="report-location" name="location" defaultValue={location}><option value="">All business locations + central costs</option>{locations.map(item => <option key={item.id} value={item.id}>{item.name}{!item.is_active ? " (inactive)" : ""}</option>)}</select></div><button className="secondary-button">Generate report</button></form></details></section>
    {error ? <p role="alert" className="auth-alert">{error}</p> : overview && <>
      <div className="overview-basis"><span>Generated: <time dateTime={generatedAt}>{new Intl.DateTimeFormat("en-GB", { timeZone: org.time_zone, dateStyle: "medium", timeStyle: "medium" }).format(new Date(generatedAt))}</time> ({org.time_zone})</span><span>Live report · reference-price estimates · not finalised</span></div>
      <ReportActions csv={managementReportCsv(rows)} filename={`profitplate-management-${from}-to-${to}.csv`}/>
      <p className="overview-footnote">CSV and print include the complete report, including closed sections.</p>
      <SaveReportForm organisation={org.id} from={from} to={to} location={location} request={crypto.randomUUID()}/>
      {costError && <p role="alert" className="auth-alert">{costError}</p>}
      {overview.summary.lines === 0 && <p className="management-warning">No recorded sales for this selection. This does not confirm that no trading occurred. Available expense records are shown separately below.</p>}
      <ReportContent rows={rows} overview={overview} costs={costs} currency={org.currency_code} overviewHref={href("/workspace/overview")} costsHref={href("/workspace/expenses")}/>
      <ReportDisclosure id="report-basis" title="Report basis & limits" description="Sources, recognition rules and reporting limits"><div className="management-method"><p>{managementReportBasis}</p><p>Central costs are included in all-location totals and excluded from outlet selections. Daily management allocations retain the expense report’s recognition rules. No menu-level overhead allocation is applied.</p><p>Sales refreshed: {overview.refreshed_at}. Costs refreshed: {costs?.refreshed_at ?? "Unavailable"}. These are separate live reads. Later source or reference-price corrections can change a regenerated report.</p><p>Up to 93 days, 1,000 sales lines and 2,000 expense entries. Exported financial values retain source precision. Save to report history to preserve a copy. Approved reports and period close remain separate work.</p></div></ReportDisclosure>
    </>}
  </div></WorkspaceShell>;
}
