import type { ReactNode } from "react";
import { Brand } from "./brand";
import Link from "next/link";
import {ArrowLeft,ClipboardList,PackageCheck,CheckCircle2} from "lucide-react";

export function AuthShell({ children }: { children: ReactNode }) {
  return (
    <main className="auth-layout auth-refined">
      <aside className="auth-story">
        <Brand light />
        <div className="auth-story-content">
          <p className="eyebrow story-eyebrow"><span /> THE WORKSPACE BEHIND THE SERVICE</p>
          <h2>Know your costs.<br /><em>Keep control.</em></h2>
          <p className="story-description">From the first delivery to the final plate. Bring your stock, menu margins and management decisions into a clearer view.</p>
          <div className="auth-flow-card"><p>EVERY HANDOFF HAS AN OWNER</p><div><ClipboardList size={19}/><span>Department requests<small>Kitchen, Bar or another stock location</small></span><b>01</b></div><div><PackageCheck size={19}/><span>Inventory Manager approves & dispatches<small>Reserved stock awaits confirmation</small></span><b>02</b></div><div><CheckCircle2 size={19}/><span>Receiving side accepts or rejects<small>Only acceptance changes both balances</small></span><b>03</b></div><small className="auth-flow-caption">A workflow illustration, not live restaurant data.</small></div>
          <div className="story-pillars"><span>Menu margins</span><span>Stock control</span><span>Team accountability</span></div>
        </div>
        <p className="story-footer">Built for the people behind every great restaurant.</p>
      </aside>
      <section className="auth-main" aria-label="Account access">
        <div className="auth-mobile-brand"><Brand /></div>
        <div className="auth-form-container"><Link className="auth-home-link" href="/"><ArrowLeft size={15}/>Back to ProfitPlate</Link>{children}</div>
        <footer className="auth-footer"><span>© ProfitPlate Insight</span><span>Clarity that drives profitability.</span></footer>
      </section>
    </main>
  );
}
