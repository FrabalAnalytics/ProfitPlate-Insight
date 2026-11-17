"use server";

import { redirect } from "next/navigation";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { isUuid } from "@/lib/catalogue";
import { validBusinessDate } from "@/lib/recipes";
import { revalidatePath } from "next/cache";

export type SaveReportState = { error?: string };
export async function saveReport(_state: SaveReportState, data: FormData): Promise<SaveReportState> {
  await requireUser();
  const access = await getPlatformAccess();
  if (access !== "member") redirect(workspacePath(access));
  const organisation = String(data.get("organisation") ?? ""), location = String(data.get("location") ?? "");
  const from = String(data.get("from") ?? ""), to = String(data.get("to") ?? ""), request = String(data.get("request") ?? ""), title = String(data.get("title") ?? "").trim();
  if (!isUuid(organisation) || !isUuid(request) || (location && !isUuid(location)) || !validBusinessDate(from) || !validBusinessDate(to) || !title || title.length > 120) return { error: "Enter a report name and choose valid report filters." };
  const client = await createClient();
  const result = await client.rpc("save_management_report", { p_organisation_id: organisation, p_from: from, p_to: to, p_location_id: location || null, p_request_id: request, p_title: title });
  if (result.error) return { error: result.error.code === "PGRST202" ? "Saved reports need database migration 014. Ask your administrator to complete setup." : result.error.code === "22023" ? result.error.message : "The report could not be saved. Check your access and connection, then try again. Both sales and expense reporting must be available." };
  if (!isUuid(result.data)) return { error: "The report save could not be confirmed. Try again with the same name." };
  redirect(`/workspace/reports/history?${new URLSearchParams({ organisation, report: result.data })}`);
}

export type ReviewReportState = { error?: string; success?: string };
export async function reviewReport(_state: ReviewReportState, data: FormData): Promise<ReviewReportState> {
  await requireUser();
  const access = await getPlatformAccess();
  if (access !== "member") redirect(workspacePath(access));
  const organisation = String(data.get("organisation") ?? ""), report = String(data.get("report") ?? ""), request = String(data.get("request") ?? "");
  const revision = Number(data.get("revision")), action = String(data.get("action") ?? ""), note = String(data.get("note") ?? "").trim();
  if (!isUuid(organisation) || !isUuid(report) || !isUuid(request) || !Number.isInteger(revision) || revision < 0 || !["SUBMIT", "COMMENT", "APPROVE", "REQUEST_CHANGES", "WITHDRAW_APPROVAL"].includes(action) || note.length > 2000) return { error: "Choose a valid review action and enter a note of up to 2,000 characters." };
  const client = await createClient();
  const result = await client.rpc("review_management_report", { p_organisation_id: organisation, p_report_id: report, p_request_id: request, p_expected_revision: revision, p_action: action, p_note: note, p_acknowledged: data.get("acknowledged") === "on" });
  if (result.error) return { error: result.error.code === "PGRST202" ? "Report reviews need database migration 015. Ask your administrator to complete setup." : result.error.code === "22023" ? result.error.message : "The review could not be saved. Check your access and connection, then try again." };
  revalidatePath("/workspace/reports/history");
  return { success: "Review activity saved." };
}
