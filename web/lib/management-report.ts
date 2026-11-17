import type { Overview } from "./overview";
import type { ExpenseReport } from "./expenses";

export type ManagementReportContext = { organisation: string; organisationId: string; from: string; to: string; location: string; locationId: string; currency: string; timeZone: string; generatedAt: string };
export type ManagementReportRow = { section: string; metric: string; value: string | null; unit: string; status: string; notes: string };
export type SavedManagementReport = { id: string; title: string; format_version: "MANAGEMENT_SNAPSHOT_V1"; created_at: string; payload: { context: ManagementReportContext; overview: Overview; costs: ExpenseReport } };
export type ManagementReportHistory = { total: number; reports: { id: string; title: string; from: string; to: string; location: string; currency: string; created_at: string; review_status?: "SAVED" | "IN_REVIEW" | "CHANGES_REQUESTED" | "APPROVED" }[] };
export const savedManagementReportBasis = "Saved management estimate. Source figures and coverage are preserved as at the save time. Food costs use reference prices, not actual inventory COGS. This report is not an approved accounting statement or a period close.";
export const managementReportBasis = "Live management report. Food costs use saved sale recipes and dated reference prices; these are estimates, not actual inventory COGS. Labour and operating expenses use coverage dates, not payment dates. Operating expenses are excluded from prime cost. This is not a finalised accounting statement.";

/** Exact percentage from source decimals, rounded to six places without Number. */
export function costPercent(amount: string | null, netSales: string): string | null {
  if (amount === null) return null;
  const parts = (value: string) => {
    if (!/^-?\d+(?:\.\d+)?$/.test(value)) throw new Error("Invalid report decimal");
    const [whole, fraction = ""] = value.replace(/^-/, "").split(".");
    return { whole, fraction, negative: value.startsWith("-") };
  };
  const left = parts(amount), right = parts(netSales);
  // Computed recipe costs can retain more than six decimal places. Use a common
  // exact scale rather than rounding those source costs before division.
  const places = Math.max(left.fraction.length, right.fraction.length);
  const scaled = (part: ReturnType<typeof parts>) => {
    const integer = BigInt(part.whole + part.fraction.padEnd(places, "0"));
    return part.negative ? -integer : integer;
  };
  const numerator = scaled(left), denominator = scaled(right);
  if (denominator === BigInt(0)) return null;
  const negative = (numerator < BigInt(0)) !== (denominator < BigInt(0));
  const top = (numerator < BigInt(0) ? -numerator : numerator) * BigInt(100000000);
  const bottom = denominator < BigInt(0) ? -denominator : denominator;
  let ratio = top / bottom;
  if ((top % bottom) * BigInt(2) >= bottom) ratio += BigInt(1);
  return `${negative && ratio ? "-" : ""}${ratio / BigInt(1000000)}.${(ratio % BigInt(1000000)).toString().padStart(6, "0")}`;
}

/** Source totals are retained; food-cost percentage uses exact decimal arithmetic. */
export function managementReportRows(context: ManagementReportContext, overview: Overview, costs: ExpenseReport | null): ManagementReportRow[] {
  const rows: ManagementReportRow[] = [];
  const add = (section: string, metric: string, value: string | null, unit = "", status = "CONTEXT", notes = "") => rows.push({ section, metric, value, unit, status, notes });
  const s = overview.summary, hasSales = s.lines > 0;
  for (const [metric, value] of Object.entries({ Format: "EXECUTIVE_MANAGEMENT_CSV_V1", Business: context.organisation, "Business ID": context.organisationId, From: context.from, Through: context.to, Location: context.location, "Location ID": context.locationId || "ALL", Currency: context.currency, "Time zone": context.timeZone, "Generated at": context.generatedAt, "Sales refreshed at": overview.refreshed_at, "Costs refreshed at": costs?.refreshed_at ?? "Unavailable", "Reporting basis": managementReportBasis })) add("Context", metric, value);
  add("Performance", "Recorded net sales", hasSales ? s.net_revenue : null, context.currency, hasSales ? "RECORDED" : "NO_RECORDS", "After source discounts; excluding declared tax. Import completeness is not confirmed.");
  add("Performance", "Estimated food cost", hasSales ? s.estimated_food_cost : null, context.currency, !hasSales ? "NO_RECORDS" : s.estimated_food_cost === null ? "MISSING" : "ESTIMATED", `${s.priced_lines} of ${s.lines} sales lines costed.`);
  const foodCostPercent = hasSales ? costPercent(s.estimated_food_cost, s.net_revenue) : null;
  add("Performance", "Estimated food cost percent", foodCostPercent, "%", foodCostPercent === null ? "UNAVAILABLE" : "ESTIMATED", "Reference ingredient and direct packaging cost divided by recorded net sales; undefined at zero net sales.");
  add("Performance", "Estimated food margin", hasSales ? s.estimated_food_margin : null, context.currency, !hasSales ? "NO_RECORDS" : s.estimated_food_margin === null ? "MISSING" : "ESTIMATED", "Excludes labour, overheads, waste and channel fees.");
  add("Performance", "Estimated food margin percent", hasSales ? s.food_margin_percent : null, "%", s.food_margin_percent === null || !hasSales ? "UNAVAILABLE" : "ESTIMATED", "Share of recorded net sales; undefined at zero net sales.");
  if (s.missing_lines > 0) add("Performance", "Known food cost subtotal", s.known_subtotal, context.currency, "PARTIAL", "Incomplete subtotal; not the full food cost.");
  add("Performance", "Recorded labour", costs && (costs.labour_entries > 0 || costs.labour_coverage.valid) ? costs.labour_amount : null, context.currency, !costs ? "UNAVAILABLE" : costs.labour_coverage.valid ? "REVIEWED" : costs.labour_entries > 0 ? "PARTIAL" : "MISSING", "Review applies only to this exact period and location scope.");
  add("Performance", "Recorded operating expenses", costs && (costs.operating_entries > 0 || costs.operating_coverage.valid) ? costs.operating_amount : null, context.currency, !costs ? "UNAVAILABLE" : costs.operating_coverage.valid ? "REVIEWED" : costs.operating_entries > 0 ? "PARTIAL" : "MISSING", "Separate from prime cost; no menu-level allocation.");
  add("Performance", "Estimated prime cost", costs?.estimated_prime_cost ?? null, context.currency, costs?.estimated_prime_cost == null ? "UNAVAILABLE" : "ESTIMATED", "Reference food-cost estimate plus reviewed labour, from the expense report.");
  add("Performance", "Labour cost percent", costs?.labour_cost_percent ?? null, "%", costs?.labour_cost_percent == null ? "UNAVAILABLE" : "ESTIMATED", "Share of recorded net sales.");
  add("Performance", "Estimated prime cost percent", costs?.prime_cost_percent ?? null, "%", costs?.prime_cost_percent == null ? "UNAVAILABLE" : "ESTIMATED", "Share of recorded net sales.");
  add("Coverage", "Recorded receipts", String(s.receipts), "receipts", "RECORDED");
  add("Coverage", "Recorded menu units", s.quantity, "units", "RECORDED");
  add("Coverage", "Missing food-cost lines", String(s.missing_lines), "lines", s.missing_lines ? "MISSING" : "RECORDED");
  add("Coverage", "Days with recorded sales", String(overview.daily.filter(day => day.lines > 0).length), "days", "RECORDED", `${overview.daily.length} days selected. Days without records do not confirm zero trading.`);
  add("Coverage", "Labour coverage", costs ? costs.labour_coverage.valid ? "Reviewed" : "Needs review" : null, "", costs?.labour_coverage.valid ? "REVIEWED" : "NEEDS_REVIEW");
  add("Coverage", "Operating expense coverage", costs ? costs.operating_coverage.valid ? "Reviewed" : "Needs review" : null, "", costs?.operating_coverage.valid ? "REVIEWED" : "NEEDS_REVIEW");
  add("Coverage", "Central recorded subtotal included", costs?.central_amount ?? null, context.currency, costs ? "RECORDED" : "UNAVAILABLE", "Included for all business locations; unallocated to individual outlets.");
  add("Coverage", "Central entries excluded", costs ? String(costs.excluded_central_entries) : null, "entries", costs ? "RECORDED" : "UNAVAILABLE");
  add("Coverage", "Legacy expense records excluded", costs ? String(costs.legacy_entries) : null, "entries", costs?.legacy_entries ? "NEEDS_REVIEW" : costs ? "RECORDED" : "UNAVAILABLE", "Legacy records need reconciliation before inclusion.");
  add("Coverage", "Daily management allocation entries", costs ? String(costs.daily_allocated_entries) : null, "entries", costs ? "RECORDED" : "UNAVAILABLE");
  for (const day of overview.daily) add("Daily sales", day.date, day.net_revenue, context.currency, day.net_revenue === null ? "NO_RECORDS" : "RECORDED", `${day.receipts} receipts; ${day.lines} lines.`);
  for (const outlet of overview.outlets) add("Outlet sales", `${outlet.code} · ${outlet.name}`, outlet.net_revenue, context.currency, "RECORDED", `${outlet.receipts} receipts; ${outlet.quantity} menu units.`);
  for (const channel of overview.channels) add("Channel sales", channel.code, channel.net_revenue, context.currency, "RECORDED", `${channel.quantity} menu units.`);
  for (const menu of s.menus) {
    const group = `Menu: ${menu.code} · ${menu.name}`;
    add(group, "Recorded net sales", menu.net_revenue, context.currency, "RECORDED", `${menu.quantity} units; ${menu.priced_lines}/${menu.lines} lines costed.`);
    add(group, "Estimated food cost", menu.estimated_food_cost, context.currency, menu.estimated_food_cost === null ? "MISSING" : "ESTIMATED");
    add(group, "Estimated food margin", menu.estimated_food_margin, context.currency, menu.estimated_food_margin === null ? "MISSING" : "ESTIMATED");
  }
  for (const gap of s.missing) add("Cost exceptions", `${gap.menu_name} · ${gap.sale_date}`, null, context.currency, "MISSING", `${gap.reason}; menu version ${gap.menu_version_id}`);
  if (!costs) add("Exceptions", "Expense report unavailable", null, "", "UNAVAILABLE", "Expense totals, coverage, prime cost and ratios could not be loaded. Recorded sales are retained.");
  if (costs?.sales_error) add("Exceptions", "Expense sales comparison unavailable", null, "", "UNAVAILABLE", "Prime cost and sales-based ratios are unavailable.");
  add("Limits", "Report limits", "93 days; 1,000 sales lines; 2,000 expense entries", "", "CONTEXT", "Source decimals retained. Display rounding does not change exported values. This downloaded copy is not an approved period close or a saved report history.");
  return rows;
}

export function managementReportCsv(rows: ManagementReportRow[]): string {
  // Quote every field and neutralise spreadsheet formula prefixes in text, including whitespace/control prefixes.
  const field = (value: string | null, numeric = false) => {
    let text = value ?? "";
    if (!(numeric && /^-?\d+(?:\.\d+)?$/.test(text)) && /^[\s\u0000-\u001f]*[=+\-@]/.test(text)) text = "'" + text;
    return '"' + text.replaceAll('"', '""') + '"';
  };
  const lines = rows.map(row => [field(row.section), field(row.metric), field(row.value, !!row.unit), field(row.unit), field(row.status), field(row.notes)].join(","));
  return '\uFEFF"Section","Metric","Value","Unit","Status","Notes"\r\n' + lines.join("\r\n") + "\r\n";
}

/** V1 snapshot renderer. Retain this contract when introducing later versions. */
export function savedManagementReportRows(report: SavedManagementReport): ManagementReportRow[] {
  if (report.format_version !== "MANAGEMENT_SNAPSHOT_V1") throw new Error("Unsupported saved report version");
  const { context, overview, costs } = report.payload;
  const rows = managementReportRows(context, overview, costs).map(row => {
    if (row.section === "Context" && row.metric === "Format") return { ...row, value: "EXECUTIVE_MANAGEMENT_SAVED_CSV_V1" };
    if (row.section === "Context" && row.metric === "Reporting basis") return { ...row, value: savedManagementReportBasis };
    if (row.section === "Limits") return { ...row, notes: "Source decimals and coverage preserved at save time. Saved estimates are not an approved period close. Source links open current records." };
    return row;
  });
  rows.push({ section: "Context", metric: "Saved report ID", value: report.id, unit: "", status: "SAVED", notes: "" },
    { section: "Context", metric: "Report name", value: report.title, unit: "", status: "SAVED", notes: "" },
    { section: "Context", metric: "Saved at", value: report.created_at, unit: "", status: "SAVED", notes: "" });
  return rows;
}
