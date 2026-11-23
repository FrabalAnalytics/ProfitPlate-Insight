import { cookies } from "next/headers";
import { invitationCookie } from "@/lib/team";
import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { AuthShell } from "@/app/components/auth-shell";
import { AuthForm } from "@/app/components/auth-form";
import { getUser } from "@/lib/auth";

export const metadata: Metadata = { title: "Sign in | ProfitPlate Insights",description:"Return to your assigned workspace for menu margins, current stock estimates, material plans and daily accountability." };
export const instant = false;

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ message?: string }> }) {
  const joining=(await cookies()).has(invitationCookie);
  if (await getUser()) redirect(joining?"/join":"/dashboard");
  const { message } = await searchParams;
  return <AuthShell variant="login"><AuthForm joining={joining} notice={message === "password-updated" ? "Your password has been updated. Sign in with your new password." : message === "confirmation-failed" ? "This confirmation link is invalid or has expired. Try signing in, or register again to request a new confirmation." : undefined} /></AuthShell>;
}
