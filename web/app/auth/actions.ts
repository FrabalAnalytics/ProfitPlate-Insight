"use server";
import {pendingTeamInvitations} from "@/lib/team-invitation-server";

import { cookies } from "next/headers";
import { invitationCookie } from "@/lib/team";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { siteUrl } from "@/lib/site-url";
import { signInErrorMessage } from "@/lib/auth-errors";

export type AuthState = {
  error?: string;
  success?: string;
  fieldErrors?: { email?: string; password?: string; confirmPassword?: string };
};

function emailFrom(formData: FormData) {
  return String(formData.get("email") ?? "").trim();
}

function validEmail(email: string) {
  return email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

export async function login(_state: AuthState, formData: FormData): Promise<AuthState> {
  const email = emailFrom(formData);
  const password = String(formData.get("password") ?? "");
  const fieldErrors = {
    email: validEmail(email) ? undefined : "Enter a valid email address.",
    password: password ? undefined : "Enter your password.",
  };
  if (fieldErrors.email || fieldErrors.password) return { fieldErrors };

  try {
    const supabase = await createClient();
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) return { error: signInErrorMessage(error) };
  } catch {
    return { error: "We couldn’t connect. Check your connection and try again." };
  }
  redirect((await cookies()).has(invitationCookie)||(await pendingTeamInvitations()).invitations.length?"/join":"/dashboard");
}

export async function signup(_state: AuthState, formData: FormData): Promise<AuthState> {
  const email = emailFrom(formData);
  const password = String(formData.get("password") ?? "");
  const confirmation = String(formData.get("confirmPassword") ?? "");
  const fieldErrors = {
    email: validEmail(email) ? undefined : "Enter a valid email address.",
    password: password.length >= 8 ? undefined : "Use at least 8 characters.",
    confirmPassword: password === confirmation ? undefined : "Your passwords do not match.",
  };
  if (Object.values(fieldErrors).some(Boolean)) return { fieldErrors };
  const origin = siteUrl();
  if (!origin) return { error: "Account registration is not configured yet. Please contact the platform administrator." };
  let signedIn = false;
  try {
    const supabase = await createClient();
    const { data, error } = await supabase.auth.signUp({
      email, password, options: { emailRedirectTo: `${origin}/auth/confirm` },
    });
    if (error) {
      return { error: error.code === "weak_password"
        ? "Choose a stronger password with a mix of letters, numbers, and symbols."
        : "We couldn’t create your account. Try again shortly, or sign in if you already have an account." };
    }
    signedIn = !!data.session;
  } catch {
    return { error: "We couldn’t connect. Please check your connection and try again." };
  }
  if (signedIn) redirect((await cookies()).has(invitationCookie)||(await pendingTeamInvitations()).invitations.length?"/join":"/dashboard");
  if((await cookies()).has(invitationCookie)) return {success:"If this email is eligible for registration, you will receive a confirmation link. Open it in this browser to verify your email and return to your team invitation. If you already have an account, sign in instead."};
  return { success: "If this email is eligible for registration, you’ll receive a confirmation link. Open it in this browser to verify your email, then continue setting up your restaurant. If you already have an account, sign in instead." };
}

export async function requestPasswordReset(_state: AuthState, formData: FormData): Promise<AuthState> {
  const email = emailFrom(formData);
  if (!validEmail(email)) return { fieldErrors: { email: "Enter a valid email address." } };

  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL
    || (process.env.NODE_ENV === "development" ? "http://localhost:3000" : undefined);
  if (!siteUrl) return { error: "Password recovery is not configured yet. Please contact your administrator." };

  try {
    const supabase = await createClient();
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: new URL("/auth/callback", siteUrl).toString(),
    });
    if (error) return { error: "We couldn’t send the reset link. Please wait a moment and try again." };
    return { success: "If an account exists for this email, you’ll receive a password reset link. Check your inbox and spam folder." };
  } catch {
    return { error: "We couldn’t connect. Check your connection and try again." };
  }
}

export async function updatePassword(_state: AuthState, formData: FormData): Promise<AuthState> {
  const password = String(formData.get("password") ?? "");
  const confirmation = String(formData.get("confirmPassword") ?? "");
  const fieldErrors = {
    password: password.length >= 8 ? undefined : "Use at least 8 characters.",
    confirmPassword: password === confirmation ? undefined : "Your passwords do not match.",
  };
  if (fieldErrors.password || fieldErrors.confirmPassword) return { fieldErrors };

  try {
    const supabase = await createClient();
    const { data } = await supabase.auth.getUser();
    if (!data.user) return { error: "Your reset link has expired. Request a new link to continue." };
    const { error } = await supabase.auth.updateUser({ password });
    if (error) {
      if (error.code === "same_password") return { error: "Choose a password different from your current password." };
      if (error.code === "weak_password") return { error: "Choose a stronger password with a mix of letters, numbers, and symbols." };
      return { error: "We couldn’t update your password. Please try again or request a new reset link." };
    }
    await supabase.auth.signOut({ scope: "local" });
  } catch {
    return { error: "We couldn’t connect. Check your connection and try again." };
  }
  redirect("/login?message=password-updated");
}

export async function signOut() {
  const supabase = await createClient();
  const { error } = await supabase.auth.signOut({ scope: "local" });
  if (error) redirect("/workspace?message=signout-failed");
  redirect("/login");
}
