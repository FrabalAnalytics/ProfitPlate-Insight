import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { AuthShell } from "@/app/components/auth-shell";
import { AuthForm } from "@/app/components/auth-form";
import { getUser } from "@/lib/auth";

export const metadata: Metadata = { title: "Choose a new password | ProfitPlate Insight" };
export const instant = false;

export default async function ResetPasswordPage() {
  if (!await getUser()) redirect("/forgot-password?message=invalid-link");
  return <AuthShell><AuthForm mode="reset" /></AuthShell>;
}
