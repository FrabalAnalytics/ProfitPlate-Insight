import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { WorkspaceShell } from "@/app/components/workspace-shell";
import { OnboardingForm } from "./setup-form";
import { normaliseSetup } from "@/lib/onboarding";

export const metadata: Metadata = { title: "Set up your restaurant | ProfitPlate Insight" };
export const instant = false;

export default async function OnboardingPage() {
  const user = await requireUser();
  const access = await getPlatformAccess();
  if (access !== "member") redirect(workspacePath(access));
  const supabase = await createClient();
  const { data, error } = await supabase.from("restaurant_setup_drafts")
    .select("business_name,concept,country_code,currency_code,brand_name,location_name,timezone,address,step,completed_organisation_id")
    .eq("user_id", user.id).maybeSingle();
  if (data?.completed_organisation_id) redirect(`/workspace?organisation=${data.completed_organisation_id}`);
  return <WorkspaceShell email={user.email} sectionLabel="RESTAURANT SETUP">
    <div className="setup-intro"><p className="eyebrow form-eyebrow">LET’S GET YOU STARTED</p><h1 className="workspace-title">A home for your business.</h1><p className="workspace-description">Tell us about your restaurant. You can save your progress and come back at any time.</p></div>
    {error ? <section className="access-status-card"><h2>Setup is temporarily unavailable</h2><p>We couldn’t load your saved progress. Please try again shortly. If this is your first visit, the platform administrator may need to finish the setup update.</p><a href="/onboarding" className="auth-button">Try again</a></section>
      : <OnboardingForm initial={normaliseSetup(data)} />}
  </WorkspaceShell>;
}
