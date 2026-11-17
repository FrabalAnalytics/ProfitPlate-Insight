import { cookies } from "next/headers";
import { invitationCookie } from "@/lib/team";
import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getUser } from "@/lib/auth";
import { AuthShell } from "@/app/components/auth-shell";
import { AuthForm } from "@/app/components/auth-form";

export const metadata: Metadata = { title: "Create your account | ProfitPlate Insight" };
export const instant = false;

export default async function SignupPage() {
  const joining=(await cookies()).has(invitationCookie);
  if (await getUser()) redirect(joining?"/join":"/dashboard");
  return <AuthShell><AuthForm mode="signup" joining={joining} /></AuthShell>;
}
