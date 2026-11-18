import type { ReactNode } from "react";
import Link from "next/link";
import { ArrowLeft, ArrowUpRight, ChartNoAxesCombined, ShieldCheck, UtensilsCrossed } from "lucide-react";
import { Brand } from "./brand";
import "./auth-shell.css";

export function AuthShell({ children }: { children: ReactNode }) {
  return (
    <main className="auth-layout auth-refined auth-welcome">
      <aside className="auth-story">
        <Brand light />
        <div className="auth-story-content">
          <p className="eyebrow story-eyebrow"><span /> YOUR RESTAURANT, IN VIEW</p>
          <h2>See your margins.<br /><em>Stay in control.</em></h2>
          <p className="story-description">Know what changed and where your team needs to act.</p>
          <div className="auth-outcomes" aria-label="Your business priorities">
            <div><ChartNoAxesCombined size={20} aria-hidden="true" /><span>Understand cost changes</span></div>
            <div><UtensilsCrossed size={20} aria-hidden="true" /><span>Find dishes worth reviewing</span></div>
            <div><ShieldCheck size={20} aria-hidden="true" /><span>Keep stock handovers accountable</span></div>
          </div>
          <Link className="auth-product-link" href="/">Explore ProfitPlate <ArrowUpRight size={16} aria-hidden="true" /></Link>
        </div>
        <p className="story-footer">For the people behind every service.</p>
      </aside>
      <section className="auth-main" aria-label="Account access">
        <div className="auth-mobile-brand"><Brand /></div>
        <div className="auth-form-container"><Link className="auth-home-link" href="/"><ArrowLeft size={15} aria-hidden="true" />Back to ProfitPlate</Link>{children}</div>
        <footer className="auth-footer"><span>ProfitPlate Insight</span><span>Your restaurant workspace</span></footer>
      </section>
    </main>
  );
}
