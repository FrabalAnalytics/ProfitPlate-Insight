import type { Metadata } from "next";
import { AuthShell } from "@/app/components/auth-shell";
import { AuthForm } from "@/app/components/auth-form";

export const metadata: Metadata = { title: "Reset your password | ProfitPlate Insights" };
export const instant = false;

export default async function ForgotPasswordPage({ searchParams }: { searchParams: Promise<{ message?: string }> }) {
  const { message } = await searchParams;
  return <AuthShell><AuthForm mode="forgot" notice={message === "invalid-link" ? "This reset link is invalid or has expired. Request a new one below." : undefined} /></AuthShell>;
}
