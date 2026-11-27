"use client";

import { useEffect, useRef, useState, type ReactNode, type KeyboardEvent } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { PanelLeftClose, PanelLeftOpen, Menu, X, Settings2, LayoutDashboard, LogOut, ShieldCheck } from "lucide-react";
import { Brand } from "./brand";
import { Button } from "./ui/button";
import { type NavigationAccess,type ReportingContext } from "@/lib/overview";
import {ReportNavigation} from "./report-navigation";
import {WorkspaceNavigation} from "./workspace-navigation";
import { signOut } from "@/app/auth/actions";

export type WorkspaceShellProps = {
  email?: string; founder?: boolean; sectionLabel?: string; restaurantName?: string;
  organisationId?: string; roleCodes?:string[]; children: ReactNode; reportingContext?:ReportingContext;
};
export function WorkspaceShellClient({ email, founder = false, sectionLabel, restaurantName, organisationId, children, reportingContext, navigation,roleCodes=[] }: WorkspaceShellProps & {navigation:NavigationAccess}) {
  const [collapsed, setCollapsed] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const pathname = usePathname();
  const sidebar = useRef<HTMLElement>(null);
  const opener = useRef<HTMLButtonElement>(null);
  const closeButton = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    if (!mobileOpen) return;
    closeButton.current?.focus();
    const previousOverflow = document.body.style.overflow;
    const trigger = opener.current;
    document.body.style.overflow = "hidden";
    return () => { document.body.style.overflow = previousOverflow; trigger?.focus(); };
  }, [mobileOpen]);
  function sidebarKeys(event: KeyboardEvent<HTMLElement>) {
    if (!mobileOpen) return;
    if (event.key === "Escape") { event.preventDefault(); setMobileOpen(false); }
    if (event.key !== "Tab") return;
    const elements = Array.from(sidebar.current?.querySelectorAll<HTMLElement>("button,a[href]") ?? []).filter(element => element.offsetParent !== null);
    const first = elements[0], last = elements.at(-1);
    if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
  }
  const accessPage = sectionLabel === "ACCOUNT ACCESS";
  const title = sectionLabel ?? (founder ? "Platform home" : "Your workspace");
  const href = founder ? "/admin" : accessPage ? "/account-access" : organisationId ? `/workspace?organisation=${organisationId}` : "/onboarding";
  const NavIcon = founder ? LayoutDashboard : accessPage ? ShieldCheck : Settings2;

  return <div className={`app-frame ${collapsed ? "sidebar-collapsed" : ""} ${mobileOpen ? "mobile-nav-open" : ""}`}>
    {mobileOpen && <button className="sidebar-overlay" aria-label="Close navigation" onClick={() => setMobileOpen(false)} />}
    <aside ref={sidebar} onKeyDown={sidebarKeys} className="app-sidebar" aria-label="Workspace navigation" role={mobileOpen ? "dialog" : undefined} aria-modal={mobileOpen ? true : undefined}>
      <div className="sidebar-brand"><Brand /><button ref={closeButton} className="mobile-close icon-button" onClick={() => setMobileOpen(false)} aria-label="Close navigation"><X size={20} /></button></div>
      <div className="sidebar-context"><span className="context-avatar">{founder ? "P" : restaurantName?.slice(0, 1) ?? "R"}</span><div><strong>{founder ? "ProfitPlate" : restaurantName ?? "Restaurant setup"}</strong><small>{founder ? "Platform administration" : "Your business workspace"}</small></div></div>
      <nav aria-label="Main navigation">
        {organisationId && !founder ? <>
          <WorkspaceNavigation organisation={organisationId} email={email} roles={roleCodes} access={navigation} pathname={pathname} context={reportingContext} onNavigate={()=>setMobileOpen(false)}/>
        </> : <><p className="sidebar-section-label">{founder ? "PLATFORM" : "WORKSPACE"}</p><Link href={href} aria-current="page" title={founder ? "Platform home" : accessPage ? "Account access" : "Data & Setup"} onClick={() => setMobileOpen(false)}><NavIcon size={18}/><span>{founder ? "Platform home" : accessPage ? "Account access" : "Data & Setup"}</span></Link></>}
      </nav>
      <div className="sidebar-bottom"><p>Know your costs.<br />Understand your margins.<br />Make better decisions.</p><button className="collapse-button" onClick={() => setCollapsed(!collapsed)} aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"} aria-expanded={!collapsed}>{collapsed ? <PanelLeftOpen size={18} /> : <><PanelLeftClose size={18} /><span>Collapse sidebar</span></>}</button></div>
    </aside>
    <div className="app-content" inert={mobileOpen ? true : undefined}><header className="app-topbar"><button ref={opener} className="mobile-menu icon-button" onClick={() => setMobileOpen(true)} aria-label="Open navigation" aria-expanded={mobileOpen}><Menu size={20} /></button><div><span className="topbar-title">{title}</span><span className="topbar-subtitle">{founder ? "System super admin workspace" : restaurantName ?? "ProfitPlate Insights"}</span></div><div className="topbar-account"><span className="account-avatar" aria-hidden="true">{email?.slice(0, 1).toUpperCase() ?? "U"}</span><span className="topbar-email">{email}</span><form action={signOut}><Button variant="ghost" aria-label="Sign out"><LogOut size={16} /><span>Sign out</span></Button></form></div></header><main className="workspace-main">{organisationId&&!founder&&<ReportNavigation organisation={organisationId} pathname={pathname} roles={roleCodes} access={navigation} context={reportingContext}/>} {children}</main><footer className="workspace-footer"><span>ProfitPlate Insights</span><span>Your business. A clearer picture.</span></footer></div>
  </div>;
}
