# Team invitations ? migration 042

## What changed

- Invitations can include existing stock centres and their Request materials, Record waste, Accept transfers or permitted dispatch tasks. Outlet scope remains separate. Selected centre tasks are granted atomically when the recipient accepts; this does not make them a manager or centre owner.
- If centres do not exist yet, invite the person first and save their centre/owner tasks afterwards in Centres & team access. No staff member needs to create a new restaurant.
- Verified users can discover their own pending invitations after sign-in or verification, including in a different browser with no invitation cookie. `/onboarding` redirects a verified invited user to `/join`.
- A shared manual invitation link still works. Pending invitations remain bound to the exact verified email, active restaurant/issuer, expiry and revocation checks.
- New invitations request a Supabase email sign-in link through an isolated client. This works for new or existing Auth accounts and does not replace the administrator's session. The recipient joins their restaurant after reviewing the invitation and may set a password for future sign-ins.
- Invitation history shows email request/failure state and a Resend email action. Email-service acceptance is not proof of inbox delivery. Failed delivery preserves the invitation and copyable backup link. Resends have a one-minute cooldown.

## Supabase email setup

1. Migration 042 must be applied before deploying this app. Existing records and accounts are retained; do not rerun applied migrations.
2. In Supabase Authentication URL configuration, set Site URL to `https://profit-plate-insight.vercel.app` and add `https://profit-plate-insight.vercel.app/join` to allowed redirect URLs. Keep existing confirmation and password-recovery URLs.
3. In Authentication's SMTP settings, configure your chosen transactional SMTP provider and its verified sender. Enter the provider's host, port, username and password directly in Supabase, not in a test workbook.
4. Supabase's default sender is restricted to project-team addresses and a low project-wide test volume. Arbitrary restaurant staff need custom SMTP. See https://supabase.com/docs/guides/auth/auth-smtp .
5. In the Confirm signup and Magic link email templates, retain `{{ .ConfirmationURL }}` as the link target. Suggested subject: `Your ProfitPlate Insights team access`. Suggested button: `Sign in and join your restaurant`. This button authenticates the invited email; the app then displays that email's pending restaurant invitation. Do not paste a single colleague's manual invitation token into a global template.
6. Send one test invitation through Users & roles to an address you control. Check Inbox/Spam and the invitation's email state. Open the email in a fresh browser, review the restaurant/role/centres, accept, and confirm the expected role workspace. Do not test by emailing actual staff from automated checks.

Official references: https://supabase.com/docs/reference/javascript/auth-signinwithotp and https://supabase.com/docs/guides/auth/sessions/implicit-flow .

## Recover a colleague already stuck on setup

Ask the colleague to sign in with the exact invited email and visit `/join`. Their active pending invitation should appear without the original WhatsApp/browser cookie. Accept it to open the role workspace. Do not register another account or complete a second restaurant setup. The administrator then assigns their centre under Centres & team access if the earlier invitation did not contain centre tasks. If the colleague already accepted, open the existing restaurant workspace and update their centre access rather than inviting them again.

## Verification

Real-migration database tests cover verified-recipient discovery, wrong email/unverified users, selected centre grants, idempotent acceptance, invalid tasks/scopes, revoked/expired/inactive cases and email request cooldown. Browser tests use local email stubs and real database RPCs; no production invitation email is sent during tests.
