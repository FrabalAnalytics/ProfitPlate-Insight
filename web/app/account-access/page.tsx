import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { WorkspaceShell } from "@/app/components/workspace-shell";
import { getPlatformAccess, getAccountRestaurants, requireUser, workspacePath } from "@/lib/auth";

export const metadata: Metadata = { title: "Account access | ProfitPlate Insights" };
export const instant = false;

export default async function AccountAccessPage({
  searchParams,
}: {
  searchParams: Promise<{ message?: string; organisation?:string }>;
}) {
  const user = await requireUser();
  const access = await getPlatformAccess();
  const { message,organisation } = await searchParams;
  const restaurants=await getAccountRestaurants();
  const rows=Array.isArray(restaurants.data)?restaurants.data as {id:string;name:string;state:string}[]:[];
  const selected=organisation?rows.find(r=>r.id===organisation):rows.find(r=>r.state==='PENDING');
  if(access==='admin')redirect(workspacePath(access));
  if(access==='member'&&selected?.state==='ACTIVE')redirect(`/workspace?organisation=${selected.id}`);
  if(access==='member'&&(!organisation||selected?.state!=='PENDING'))redirect(workspacePath(access));
  const pending=access==='pending'||selected?.state==='PENDING';
  const inactive = access === "inactive";
  const needsSetup = access === "setup-required";

  return (
    <WorkspaceShell email={user.email} sectionLabel="ACCOUNT ACCESS">
      <p className="eyebrow form-eyebrow">ACCOUNT ACCESS</p>
      <h1 className="workspace-title">
        {pending ? "Your restaurant is awaiting approval." : inactive ? "Your restaurant workspace is inactive." : needsSetup ? "One setup step remains." : "Let’s reconnect your workspace."}
      </h1>
      <p className="workspace-description">Your account is signed in. Workspace access depends on your restaurant status and assigned permissions.</p>
      {message === "signout-failed" && (
        <p className="auth-alert" role="alert">We couldn’t sign you out. Check your connection and try again.</p>
      )}
      <section className="access-status-card" aria-labelledby="access-heading">
        <span className="access-status-icon" aria-hidden="true">{needsSetup ? "◷" : "↻"}</span>
        <h2 id="access-heading">
          {pending ? selected?.name??'Restaurant application submitted' : inactive ? "Workspace access is paused" : needsSetup ? "Workspace access is being set up" : "Access verification is temporarily unavailable"}
        </h2>
        <p>
          {pending ? "Your restaurant details have been saved for system super admin review. After approval, you can invite your Administrator and team, enter or import your data and begin daily operations. You do not need to register again." : inactive ? "Contact your restaurant owner or the platform administrator to restore access. Your restaurant records are retained." : needsSetup
            ? "Your platform administrator needs to complete the account access setup. Once that’s ready, check your access again below."
            : "We couldn’t confirm your permissions right now. Please check your connection and try again in a moment."}
        </p>
        {/* A full navigation retries the server check rather than reusing a prefetched result. */}
        <a className="auth-button" href={organisation?`/account-access?organisation=${encodeURIComponent(organisation)}`:'/dashboard'}>Check access again <span aria-hidden="true">→</span></a>
        {access==='member'&&pending&&<p><a className="auth-back" href="/workspace">Open your active restaurant workspace</a></p>}
      </section>
    </WorkspaceShell>
  );
}
