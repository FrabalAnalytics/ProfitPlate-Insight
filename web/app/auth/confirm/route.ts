import {pendingTeamInvitations} from "@/lib/team-invitation-server";
import { invitationCookie } from "@/lib/team";
import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: NextRequest) {
  const supabase = await createClient();
  const params = request.nextUrl.searchParams;
  const code = params.get("code");
  const tokenHash = params.get("token_hash");
  if (code) {
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) return NextResponse.redirect(new URL(request.cookies.has(invitationCookie)||(await pendingTeamInvitations()).invitations.length?"/join":"/dashboard", request.url));
  } else if (tokenHash && ["signup","email","magiclink","invite"].includes(params.get("type")??"")) {
    const { error } = await supabase.auth.verifyOtp({ token_hash: tokenHash, type: params.get("type") as "signup"|"email"|"magiclink"|"invite" });
    if (!error) return NextResponse.redirect(new URL(request.cookies.has(invitationCookie)||(await pendingTeamInvitations()).invitations.length?"/join":"/dashboard", request.url));
  }
  return NextResponse.redirect(new URL("/login?message=confirmation-failed", request.url));
}
