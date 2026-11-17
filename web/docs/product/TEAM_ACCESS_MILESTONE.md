# Users, roles and controlled invitations

Apply `supabase/migrations/202611150011_team_access.sql` once after 010. This
migration has not been applied to the live Supabase project by the coding agent.
Refresh the restaurant workspace and open **Users & roles**.

## Delivered

- Organisation-wide Restaurant Administrators can search/paginate their team,
  create invitations, revoke pending invitations, update roles and deactivate or
  reactivate members. Owner access and the caller's own access are protected.
- Five existing roles can be combined and assigned organisation-wide or to
  individual active locations. The database validates all tenant/location links.
  Existing business-wide financial/import modules still require organisation-wide
  grants; assigning a scoped role does not enable those screens.
- Invitations have a seven-day expiry, are bound to the invited email and require
  a verified Supabase account with that email. Platform founders remain separate.
  No auth accounts are created and no invitation emails are sent automatically.
- Creation returns a secret link once. Copy it before leaving the page. Only a
  SHA-256 hash is retained in the database. Lost links must be revoked and replaced;
  histories never reveal the token. Creation and acceptance are retry-safe.
- The `/join#token` fragment keeps the token out of URL query/server-access logs.
  After an explicit Review invitation action, an HttpOnly, SameSite cookie keeps
  the invitation through sign-in/signup in the same browser. HTTPS uses a Secure
  cookie. The fragment is removed from browser history. Accepted/discarded invites
  clear the cookie. Only one pending invitation is retained per browser.
- Sign-in and email confirmation return a pending invite to review. Acceptance
  requires explicit permission review and saves exactly the invitation's grants.
  Expired, revoked, wrong-email and unverified-email attempts cannot add membership.
- Member edits use a version check. Deactivation preserves records and roles;
  reactivation requires an explicit valid set of grants. Saving access revokes
  outstanding invitations created by that member. Acceptance also rechecks that
  the inviter is still an authorised administrator. Existing memberships cannot
  be overwritten by an invitation.
- Membership changes and invitation lifecycle events are audited without secrets.
  Direct client invitation reads/writes and direct membership writes remain denied.

## Beginner test

1. Sign into a restaurant administrator account, open Users & roles, then Invite
   colleague. Use a different test account email and choose Finance / Auditor with
   All business locations. Review permissions and create the invitation.
2. Copy the complete invitation link. In a private browser window open it, select
   Review invitation, then sign in or register using the invited email.
3. Verify the account email when required. Review the named business and grants,
   then Accept invitation. The user should have read-only sales access.
4. In the administrator's original window, refresh the team list and manage the
   new member. Deactivation should remove that user's business access on the next
   protected request; earlier restaurant transactions stay intact.
5. Create/revoke another invitation and verify it cannot be accepted.

Links use the browser's current site origin. `localhost` links only work on the
same computer. For phone tests create/open links using the reachable LAN address;
for remote staff use the deployed HTTPS address. Links and sessions must use the
same host. Existing Supabase email-confirmation URL/delivery configuration still
applies; reopening the invitation in the verified browser is supported.

## Verification and limits

Real PostgreSQL/PGlite checks cover tenant isolation, protected owner/self access,
verified email matching, expiry/revocation, duplicate requests/acceptance, exact
role grants and combinations, stale edits, deactivation/reactivation, scoped
financial restrictions, audit and direct-client denials. Browser tests cover the
complete signed-out invite/login/accept/deactivate flow, revoked-link rejection,
and the mobile multi-role editor, alongside the existing application workflows.

Live Supabase confirmation is still required after applying 011. Automatic email
delivery, bulk invites, owner transfer, account deletion, brand-specific grants,
location-level financial screens and a broader role-relevant navigation pass are
future work. Revocation takes effect at subsequent server/database checks; it
does not erase records already displayed or downloaded by an authorised user.
