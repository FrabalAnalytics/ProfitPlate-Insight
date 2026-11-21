import type { ReactNode } from "react";
import Link from "next/link";
import { ArrowLeft, ArrowUpRight, ChartNoAxesCombined, ShieldCheck, UtensilsCrossed } from "lucide-react";
import { Brand } from "./brand";
import "./auth-shell.css";

export function AuthShell({ children, variant = 'standard' }: { children: ReactNode; variant?:'standard'|'login' }) {
  const login=variant==='login';
  return (
    <main className="auth-layout auth-refined auth-welcome">
      <aside className="auth-story">
        <Brand light />
        <div className="auth-story-content">
          <p className="eyebrow story-eyebrow"><span /> YOUR RESTAURANT, IN VIEW</p>
          <h2>{login?<>Your numbers.<br /><em>Your next move.</em></>:<>See your margins.<br /><em>Stay in control.</em></>}</h2>
          <p className="story-description">{login?'Margins, stock value and the work that needs attention, in your assigned workspace.':'Know what changed and where your team needs to act.'}</p>
          {login?<div className="auth-workspace-preview" aria-label="Illustrative workspace preview"><div><span>OWNER WORKSPACE</span><span>Fictional sample</span></div><p>Estimated stock value</p><strong>NGN 318,000</strong><small>Main Store · Kitchen · Bar</small><ul><li><span>Menu prices to review</span><b>2</b></li><li><span>Weekly stock count due</span><b>1</b></li></ul></div>:null}
          <div className={`auth-outcomes ${login?'auth-outcomes-compact':''}`} aria-label="Your business priorities">
            <div><ChartNoAxesCombined size={20} aria-hidden="true" /><span>{login?'See margins and current stock estimates':'Understand cost changes'}</span></div>
            <div><UtensilsCrossed size={20} aria-hidden="true" /><span>{login?'Plan materials before production':'Find dishes worth reviewing'}</span></div>
            <div><ShieldCheck size={20} aria-hidden="true" /><span>{login?'Follow waste reports and weekly counts':'Keep stock handovers accountable'}</span></div>
          </div>
          <Link className="auth-product-link" href="/">Explore ProfitPlate <ArrowUpRight size={16} aria-hidden="true" /></Link>
        </div>
        <p className="story-footer">For the people behind every service.</p>
      </aside>
      <section className="auth-main" aria-label="Account access">
        <div className="auth-mobile-brand"><Brand /></div>
        <div className="auth-form-container"><Link className="auth-home-link" href="/"><ArrowLeft size={15} aria-hidden="true" />Back to ProfitPlate</Link>{children}</div>
        <footer className="auth-footer"><span>ProfitPlate Insight</span><span>{login?'Your assigned workspace opens after sign-in':'Your restaurant workspace'}</span></footer>
      </section>
    </main>
  );
}
