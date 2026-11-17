"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { getPlatformAccess, requireUser, workspacePath } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { setupValues, validateSetup, type SetupValues } from "@/lib/onboarding";

export type SetupState = { error?: string; errors?: Record<string, string>; saved?: boolean; values?: SetupValues };

export async function saveSetup(_state: SetupState, form: FormData): Promise<SetupState> {
  await requireUser();
  const access = await getPlatformAccess();
  if (access !== "member") redirect(workspacePath(access));
  const values = setupValues(form);
  const finishing = form.get("intent") === "complete";
  const nextStep = form.get("intent") === "continue" ? Math.min(values.step + 1, 3)
    : form.get("intent") === "back" ? Math.max(values.step - 1, 1) : values.step;
  const errors = validateSetup(values, finishing, ["save", "back"].includes(String(form.get("intent"))));
  if (Object.keys(errors).length) return { errors, values };

  const supabase = await createClient();
  const { error } = await supabase.rpc("save_restaurant_setup", {
    p_business_name: values.business_name, p_concept: values.concept,
    p_country_code: values.country_code, p_currency_code: values.currency_code,
    p_brand_name: values.brand_name, p_location_name: values.location_name,
    p_timezone: values.timezone, p_address: values.address, p_step: nextStep,
  });
  if (error) {
    return { values, error: error.code === "PGRST202"
      ? "Restaurant setup is not available yet. Please ask the platform administrator to finish the setup update."
      : "We couldn’t save your details. Please try again. Your entries are still here." };
  }
  if (!finishing) return { saved: true, values: { ...values, step: nextStep } };

  const { data: organisationId, error: completeError } = await supabase.rpc("complete_restaurant_setup");
  if (completeError || typeof organisationId !== "string") {
    return { values, error: "Your details are saved, but we couldn’t finish setup. Please try again." };
  }
  revalidatePath("/workspace");
  redirect(`/workspace/setup?organisation=${encodeURIComponent(organisationId)}&welcome=1`);
}
