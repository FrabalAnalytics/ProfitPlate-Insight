"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { getPlatformAccess, requireUser, workspacePath } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import {parseExpenseCategories} from "@/lib/expense-categories";
import {parseMenuCategories} from "@/lib/menu-categories";
import {parseChannelRows} from "@/lib/channels";
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

  let categories;try{categories=parseMenuCategories(values.menu_categories,!finishing);}catch(e){return {values,errors:{menu_categories:e instanceof Error?e.message:"Check menu categories."}};}
  let channels;try{channels=parseChannelRows(values.sales_channels,!finishing);}catch(error){return {values,errors:{sales_channels:error instanceof Error?error.message:'Check sales channels.'}};}
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
  const calendar = await supabase.rpc("save_setup_calendar", {p_week_start: values.reporting_week_start === "" ? null : Number(values.reporting_week_start), p_count_day: values.count_day === "" ? null : Number(values.count_day), p_cutoff: values.count_cutoff || null});
  if (calendar.error) return {values, error: "We could not save the reporting calendar. Check the setup update and try again."};
  const channelSave=await supabase.rpc("save_setup_sales_channels",{p_channels:channels});if(channelSave.error)return {values,error:"Sales channels could not be saved. Check database update 046 and try again."};
  const categorySave=await supabase.rpc("save_setup_menu_categories",{p_categories:categories});if(categorySave.error)return {values,error:"Menu categories could not be saved. Check database update 048."};
  const expenseSave=await supabase.rpc("save_setup_expense_categories",{p_categories:parseExpenseCategories(values.expense_categories)});if(expenseSave.error)return{values,error:"Expense categories could not be saved. Check database update 054."};
  if (!finishing) return { saved: true, values: { ...values, step: nextStep } };

  const { data: organisationId, error: completeError } = await supabase.rpc("complete_restaurant_setup_with_expenses");
  if (completeError || typeof organisationId !== "string") {
    return { values, error: "Your details are saved, but we couldn’t finish setup. Please try again." };
  }
  revalidatePath("/workspace");
  redirect(`/account-access?organisation=${encodeURIComponent(organisationId)}`);
}
