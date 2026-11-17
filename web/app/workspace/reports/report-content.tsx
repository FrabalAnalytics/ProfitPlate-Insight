import {DataTable} from "@/app/components/data-table";
import type { ReactNode } from "react";
import Link from "next/link";
import { ArrowRight, CheckCircle2, ChevronDown, TriangleAlert, Percent, UtensilsCrossed, Layers3, ReceiptText, TrendingUp, Users, Wallet, type LucideIcon } from "lucide-react";
import { expenseMoney, type ExpenseReport } from "@/lib/expenses";
import type { Overview } from "@/lib/overview";
import { displayPercent } from "@/lib/display";
import { displayQuantity } from "@/lib/recipes";
import type { ManagementReportRow } from "@/lib/management-report";

const caution = (status: string) => ["MISSING", "NEEDS_REVIEW", "UNAVAILABLE", "PARTIAL", "NO_RECORDS"].includes(status);
const stateLabel = (status: string) => status.toLowerCase().replaceAll("_", " ");
const metricIcons: Record<string, LucideIcon> = { "Recorded net sales": ReceiptText, "Estimated food margin": TrendingUp, "Estimated food cost": UtensilsCrossed, "Recorded labour": Users, "Recorded operating expenses": Wallet, "Estimated prime cost": Layers3 };
function displayValue(row: ManagementReportRow, currency: string) {
  if (row.value === null) return row.status === "NO_RECORDS" ? "No records" : "Unavailable";
  if (row.unit === currency) return expenseMoney(row.value, currency);
  if (row.unit === "%") return `${displayPercent(row.value)}%`;
  return row.unit === "units" ? displayQuantity(row.value) : row.value;
}
export function ReportDisclosure({ id, title, description, children, open = false }: { id: string; title: string; description: string; children: ReactNode; open?: boolean }) {
  return <details id={id} className="management-disclosure" data-report-disclosure open={open}>
    <summary><span><strong>{title}</strong><small>{description}</small></span><ChevronDown size={18} aria-hidden="true"/></summary>
    <div className="management-disclosure-body">{children}</div>
  </details>;
}
export function ReportRowTable({ rows, label, currency }: { rows: ManagementReportRow[]; label: string; currency: string }) {
  return <DataTable label={label} columns={[{label:"Measure"},{label:"Value",numeric:true},{label:"Basis / coverage"}]} rows={rows.map((row,index)=>({id:String(index),cells:[row.metric,displayValue(row,currency),<span key="basis"><span className={`management-state ${caution(row.status)?"management-caution":""}`}>{stateLabel(row.status)}</span>{row.notes&&<small>{row.notes}</small>}</span>]}))}/>;
}
export function ReportContent({ rows, overview, costs, currency, overviewHref, costsHref }: { rows: ManagementReportRow[]; overview: Overview; costs: ExpenseReport | null; currency: string; overviewHref: string; costsHref: string }) {
  const metrics = ["Recorded net sales", "Estimated food margin", "Estimated food cost", "Recorded labour", "Recorded operating expenses", "Estimated prime cost"];
  const ratio: Record<string, string> = { "Estimated food margin": "Estimated food margin percent", "Estimated food cost": "Estimated food cost percent", "Recorded labour": "Labour cost percent", "Estimated prime cost": "Estimated prime cost percent" };
  const missing = overview.summary.missing_lines;
  const needsReview = !costs || !costs.labour_coverage.valid || !costs.operating_coverage.valid || costs.legacy_entries > 0;
  const money = (value: string | null) => value === null ? "Unavailable" : expenseMoney(value, currency);
  return <>

    <section id="report-summary" className="management-summary" aria-labelledby="report-summary-heading"><div className="overview-section-heading"><h2 id="report-summary-heading">Performance at a glance</h2><Link className="record-edit management-no-print" href={overviewHref}>Open Executive overview <ArrowRight size={14} aria-hidden="true"/></Link></div>
      <div className="management-metrics">{metrics.map(name => {
        const row = rows.find(item => item.section === "Performance" && item.metric === name)!;
        const percent = rows.find(item => item.section === "Performance" && item.metric === ratio[name]);
        const Icon = metricIcons[name];
        const ratioLabel = name === "Estimated food cost" ? "Food cost %" : name === "Estimated prime cost" ? "Prime cost %" : null;
        const note = percent?.value !== null && percent?.value !== undefined ? `${displayPercent(percent.value)}% of recorded net sales` : name === "Recorded net sales" ? `${overview.summary.receipts} receipts · ${displayQuantity(overview.summary.quantity)} menu units` : name === "Estimated food cost" ? `${overview.summary.priced_lines} of ${overview.summary.lines} sales lines costed` : name === "Estimated prime cost" ? "Reference food-cost estimate + reviewed labour" : name === "Recorded operating expenses" ? "Separate from prime cost" : name === "Recorded labour" ? "Coverage applies to this exact selection" : "Ingredient & direct packaging estimate";
        return <article key={name} className={name === "Estimated prime cost" ? "management-prime" : ""}><div><span className="management-metric-label"><Icon size={15} aria-hidden="true"/>{name}</span><span className={`management-state ${caution(row.status) ? "management-caution" : ""}`}>{stateLabel(row.status)}</span></div><strong>{displayValue(row, currency)}</strong>{ratioLabel && <div className="management-ratio"><span><Percent size={14} aria-hidden="true"/>{ratioLabel}</span><b>{percent?.value != null ? `${displayPercent(percent.value)}%` : "Unavailable"}</b></div>}<small>{ratioLabel ? name === "Estimated food cost" ? `${overview.summary.priced_lines} of ${overview.summary.lines} sales lines costed · % of recorded net sales` : "Reference food-cost estimate + reviewed labour · % of recorded net sales" : note}</small></article>;
      })}</div>
    </section>
    <div className={`management-review-strip ${needsReview || missing ? "management-review-attention" : ""}`}>
      {needsReview || missing ? <TriangleAlert size={19} aria-hidden="true"/> : <CheckCircle2 size={19} aria-hidden="true"/>}
      <div><strong>{missing ? `${missing} sales ${missing === 1 ? "line needs" : "lines need"} food costs` : needsReview ? "Cost coverage needs attention" : "Cost coverage reviewed for this selection"}</strong><p>{!costs ? "Expense reporting is unavailable." : !costs.labour_coverage.valid ? "Review labour completeness to enable estimated prime cost." : !costs.operating_coverage.valid ? "Operating expense entries may be partial." : costs.legacy_entries > 0 ? "Legacy expense records need reconciliation." : "Estimates retain their reference-price basis; reviewed coverage is not an audit."}{costs && costs.excluded_central_entries > 0 ? ` ${costs.excluded_central_entries} central entries excluded from this outlet.` : ""}</p></div>
      <Link className="record-edit management-no-print" href={costsHref}>Review costs <ArrowRight size={14} aria-hidden="true"/></Link>
    </div>
    <nav className="management-jump-nav management-no-print" aria-label="Report sections"><a href="#report-summary">Summary</a><a href="#report-coverage">Coverage</a><a href="#report-sales">Sales breakdown</a><a href="#report-menus">Menu performance</a><a href="#report-basis">Report basis</a></nav>
    <ReportDisclosure id="report-financial-details" title="Financial detail" description="Amounts, ratios and calculation basis"><ReportRowTable rows={rows.filter(row => row.section === "Performance")} label="Management financial performance" currency={currency}/></ReportDisclosure>
    <ReportDisclosure id="report-coverage" title="Data coverage & review priorities" description={`${overview.summary.priced_lines}/${overview.summary.lines} sales lines costed · ${overview.daily.filter(day => day.lines > 0).length}/${overview.daily.length} days have records`}>
      <ReportRowTable rows={rows.filter(row => row.section === "Coverage")} label="Management report coverage" currency={currency}/><p className="overview-footnote">Reviewed coverage is an administrator declaration for this exact selection; it is not an audit or period close. Missing costs never become zero.</p>
    </ReportDisclosure>
    <ReportDisclosure id="report-sales" title="Sales breakdown" description="Daily activity, outlets and sales channels">
      <div className="management-breakdowns">{([["Daily sales", "Daily recorded sales"], ["Outlet sales", "Outlet sales"], ["Channel sales", "Sales channels"]] as const).map(([section, title]) => <section key={section}><h3>{title}</h3>{rows.some(row => row.section === section) ? <ReportRowTable rows={rows.filter(row => row.section === section)} label={`Management ${section.toLowerCase()}`} currency={currency}/> : <p className="overview-footnote">No recorded data for this selection.</p>}</section>)}</div>
    </ReportDisclosure>
    <ReportDisclosure id="report-menus" title="Menu performance" description={`${overview.summary.menus.length} menu items · ranked by recorded net sales`}>
      <p className="overview-footnote">First 20 items shown. The CSV includes every menu item in this report.</p>
      {overview.ranked_menus.length ? <DataTable label="Management menu performance" columns={[{label:"Menu item"},{label:"Units",numeric:true},{label:"Net sales",numeric:true},{label:"Est. food cost",numeric:true},{label:"Est. food margin",numeric:true}]} rows={overview.ranked_menus.slice(0,20).map(menu=>({id:menu.menu_item_id,cells:[<span key="menu">{menu.name}<small>{menu.code} - {menu.priced_lines}/{menu.lines} lines costed</small></span>,displayQuantity(menu.quantity),money(menu.net_revenue),money(menu.estimated_food_cost),<span key="margin" className={menu.estimated_food_margin?.startsWith("-")?"management-caution":""}>{money(menu.estimated_food_margin)}</span>]}))}/> : <p className="overview-footnote">No recorded menu sales.</p>}
    </ReportDisclosure>
    {overview.summary.missing.length > 0 && <ReportDisclosure id="report-cost-gaps" title="Missing food-cost details" description="Resolve these inputs to complete the food-cost estimate" open><ReportRowTable rows={rows.filter(row => row.section === "Cost exceptions")} label="Management missing costs" currency={currency}/></ReportDisclosure>}
  </>;
}
