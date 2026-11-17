export const teamRoles = [
  ["ceo", "CEO / Managing Director", "Read business-wide costs, sales and estimates."],
  ["finance", "Finance / Auditor", "Review financial data and imports; no configuration writes."],
  ["procurement", "Procurement", "Issue purchase orders, record supplier invoices and request purchase corrections."],
  ["inventory", "Inventory / Receiving", "Confirm deliveries and generate GRNs within assigned locations; cannot issue purchase orders."],
  ["stock_department", "Department stock user", "Request stock and accept or reject transfers for assigned Kitchen, Bar or other departments."],
  ["stock_receiver", "Stock receiver (optional)", "Confirm assigned receiving processes without stock approval, dispatch or financial permissions."],
  ["stock_dispatcher", "Stock dispatcher (optional)", "Dispatch approved movements from assigned stock locations; no approval, receiving or financial access."],
  ["inventory_manager", "Inventory Manager", "Oversee stock across all business locations, configure movements and department access, and approve physical stock records."],
  ["operations", "Operations Manager", "Manage recipes and operational masters; no sales revenue."],
  ["restaurant_admin", "Restaurant Administrator", "Manage business configuration and team access when organisation-wide."],
] as const;
export type Assignment = {role_code: string; location_id: string | null; location_name?: string | null};
export type TeamMember = {id: string; user_id: string; email: string; status: string; updated_at: string; is_owner: boolean; is_self: boolean; assignments: Assignment[]};
export type TeamInvite = {id: string; email: string; state: string; expires_at: string; created_at: string; assignments: Assignment[]};
export type TeamDirectory = {members: TeamMember[]; member_total: number; invitations: TeamInvite[]; invitation_total: number};
export type TeamState = {error?: string; success?: string; token?: string; expires?: string};
export const roleName = (code: string) => teamRoles.find(([key])=>key===code)?.[1] ?? code;
export const invitationCookie = "pp_team_invitation";
export const validInvitationToken = (value: string) => /^[a-f0-9]{64}$/.test(value);
