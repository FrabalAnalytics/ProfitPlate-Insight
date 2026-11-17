import Link from "next/link";
import { ArrowRight, TriangleAlert, Percent, Layers3 } from "lucide-react";
import { expenseMoney, type ExpenseReport } from "@/lib/expenses";
import { displayPercent } from "@/lib/display";

export function OverviewCosts({ report, error, href, timeZone }: { report: ExpenseReport | null; error: string; href: string; timeZone: string }) {
  const money = (value: string) => expenseMoney(value, report!.currency_code);
  const reviewNeeded = report && (!report.labour_coverage.valid || !report.operating_coverage.valid);
  return <section className="overview-panel overview-costs" aria-labelledby="overview-costs-heading">
    <div className="overview-section-heading"><h2 id="overview-costs-heading">Labour & operating costs</h2><Link className="record-edit" href={href}>Review costs <ArrowRight size={14}/></Link></div>
    {!report ? <p role="status" className="overview-footnote">{error || "Cost reporting is temporarily unavailable. Recorded sales remain available."}</p> : <>
      <div className="overview-cost-kpis">
        <article><span>Recorded labour</span><strong>{report.labour_entries || report.labour_coverage.valid ? money(report.labour_amount) : "Not confirmed"}</strong><small>{report.labour_coverage.valid ? "Coverage reviewed for this selection" : "Coverage needs review; entries may be partial"}</small>{report.labour_cost_percent !== null && <p>{displayPercent(report.labour_cost_percent)}% of recorded net sales</p>}</article>
        <article><span>Recorded operating expenses</span><strong>{report.operating_entries || report.operating_coverage.valid ? money(report.operating_amount) : "Not confirmed"}</strong><small>{report.operating_coverage.valid ? "Coverage reviewed for this selection" : "Coverage needs review; entries may be partial"}</small></article>
        <article><span><Layers3 size={14} aria-hidden="true"/> Estimated prime cost</span><strong>{report.estimated_prime_cost === null ? "Unavailable" : money(report.estimated_prime_cost)}</strong><small>Reference food-cost estimate + reviewed labour</small>{report.prime_cost_percent !== null && <p className="overview-cost-ratio"><Percent size={15} aria-hidden="true"/>Prime cost: {displayPercent(report.prime_cost_percent)}%</p>}</article>
      </div>
      {reviewNeeded && <div className="overview-exception overview-cost-warning"><TriangleAlert size={18}/><div><h3>Cost coverage needs review</h3><p>{!report.labour_coverage.valid ? "Labour coverage is not reviewed for this exact period and location selection; estimated prime cost is unavailable. " : ""}{!report.operating_coverage.valid ? "Operating expense entries may be partial. " : ""}An administrator can review completeness in Labour & expenses.</p></div></div>}
      {report.estimated_prime_cost === null && report.labour_coverage.valid && <p className="overview-footnote">Estimated prime cost requires recorded sales with complete food costs for this selection.</p>}
      {report.sales_error && <p className="overview-footnote">Sales comparison could not be completed. Prime cost and sales-based ratios are unavailable.</p>}
      {report.excluded_central_entries > 0 ? <p className="overview-footnote">{report.excluded_central_entries} central / unallocated entries are excluded from this outlet selection.</p> : <p className="overview-footnote">Central / unallocated recorded subtotal included above: {money(report.central_amount)}.</p>}
      {report.legacy_entries > 0 && <p className="overview-footnote">Legacy expense records require reconciliation and are excluded from these totals. Review costs before relying on completeness.</p>}
      <p className="overview-footnote">Operating expenses are separate from prime cost. {report.daily_allocated_entries > 0 ? `${report.daily_allocated_entries} ${report.daily_allocated_entries === 1 ? "entry uses" : "entries use"} daily management allocation. ` : ""}These figures do not establish actual accounting profit.</p>
      <p className="overview-footnote">Cost data refreshed: <time dateTime={report.refreshed_at}>{new Intl.DateTimeFormat("en-GB",{timeZone,dateStyle:"medium",timeStyle:"medium"}).format(new Date(report.refreshed_at))}</time> ({timeZone})</p>
    </>}
  </section>;
}
