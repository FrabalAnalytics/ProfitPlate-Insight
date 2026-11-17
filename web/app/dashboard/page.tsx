import { redirect } from "next/navigation";
import { getPlatformAccess, workspacePath } from "@/lib/auth";

export const instant = false;

export default async function DashboardPage() {
  redirect(workspacePath(await getPlatformAccess()));
}
