import "server-only";

import { cache } from "react";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export const getUser = cache(async () => {
  const supabase = await createClient();
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) return null;
  return data.user;
});

export async function requireUser() {
  const user = await getUser();
  if (!user) redirect("/login");
  return user;
}

export const getPlatformAccess = cache(async () => {
  await requireUser();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("is_platform_admin");
  // Missing setup and failed checks are not proof of restaurant membership.
  // Never infer administrator access from an email or editable user metadata.
  if (error?.code === "PGRST202") return "setup-required" as const;
  if (error || typeof data !== "boolean") return "unavailable" as const;
  if (data) return "admin" as const;
  const restaurants = await supabase.rpc("account_restaurant_access");
  if (restaurants.error || !Array.isArray(restaurants.data)) return "unavailable" as const;
  if (restaurants.data.some((r: {state: string}) => r.state === "INACTIVE") && !restaurants.data.some((r: {state: string}) => r.state === "ACTIVE")) return "inactive" as const;
  return "member" as const;
});

export function workspacePath(access: Awaited<ReturnType<typeof getPlatformAccess>>) {
  if (access === "admin") return "/admin";
  if (access === "member") return "/workspace";
  return "/account-access";
}

export async function requirePlatformAdmin() {
  const user = await requireUser();
  const access = await getPlatformAccess();
  if (access !== "admin") redirect(workspacePath(access));
  return user;
}
