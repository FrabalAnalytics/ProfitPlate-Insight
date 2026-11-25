import type { Metadata } from "next";
import Link from "next/link";
import { ArrowRight, ArrowUpRight, Check, ChevronDown, ClipboardList, MapPin, PackageCheck, Users, LayoutDashboard, ShieldCheck, Sparkles, UtensilsCrossed } from "lucide-react";
import { Brand } from "./components/brand";
import { HomeHeader } from "./components/home-header";
import {StockValuePreview} from "./components/stock-value-preview";
import { CostPreview } from "./components/cost-preview";
import {TeamPreview} from "./components/team-preview";
import {InventoryWorkflow} from "./components/inventory-workflow";
import "./home.css";

export const metadata: Metadata = {
  title: "ProfitPlate Insights | Restaurant margins, stock control & accountability",
  description: "Connect menu margins, imported POS sales and stock by centre. Build accountability with daily waste reporting, weekly and monthly counts, and independent review.",
};

const capabilities = [
  { icon: UtensilsCrossed, number: "01", title: "Spot dishes that need a review", text: "See which dishes protect your margin and which need a pricing or portion review before they erode profit.", detail: "Menu profitability" },
  { icon: LayoutDashboard, number: "02", title: "Connect sales to the stock used", text: "Understand what recorded sales should have used, then investigate stock gaps with a clearer basis for accountability.", detail: "Sales-linked stock consumption" },
  { icon: ClipboardList, number: "03", title: "Plan before the kitchen starts", text: "Give the kitchen a clearer view of what it needs before work starts. Reduce last-minute shortages and spot production losses.", detail: "Material plans & production" },
  { icon: PackageCheck, number: "04", title: "Catch purchase cost pressure", text: "See where supplier price changes threaten margins, with the evidence you need to review purchases and respond.", detail: "Purchasing & price tracking" },
  { icon: Users, number: "05", title: "Make waste reporting a habit", text: "Make losses visible, identify recurring causes and give managers a clear starting point for reducing avoidable waste.", detail: "Daily waste & analysis" },
  { icon: ShieldCheck, number: "06", title: "Turn stock gaps into action", text: "Find differences between recorded stock and what is on the shelves, so managers can investigate and put corrective action in place.", detail: "Weekly & monthly stock counts" },
];
const questions = [
  ["How is ProfitPlate Insights different from a regular ERP?", "ProfitPlate Insights gives meaning to your daily records: where margins are under pressure, why losses keep recurring and who needs to act. That gives you a clearer basis for decisions about purchasing, pricing, portions and accountability."],
  ["We already have a POS. What would we gain?", "Your POS tells you what sold. ProfitPlate Insights helps you understand what those sales leave behind: which dishes have weak margins, where purchase costs are rising and where stock or waste needs attention."],
  ["Will setup mean retyping all our restaurant data?", "No, you can bulk import your existing material, recipe and menu records, including known purchase prices, opening stock and selling prices, without retyping them manually. Add any missing details later."],
  ["My team struggles to record consistently. Will another system help?", "Yes, with your managers leading the follow-up. Clear daily responsibilities and visible reporting gaps help your team build consistent habits, giving you more dependable information to run the business."],
  ["Will it find theft?", "No. It highlights stock gaps and who is responsible for following them up; it does not prove theft. Unexplained differences need investigation, not accusation."],
  ["Will the margin figures tell me our actual net profit?", "No. Menu margins show what each dish contributes before other business costs. They help you spot pricing and cost pressure, but they are estimates, not your final net profit."],
  ["Who can see our figures or change our restaurant records?", "Your figures are kept separate from other restaurants. You control which colleagues can view or change your records, and can revoke their access without losing your restaurant's history."],
];

export default function Home() {
  return <div className="marketing-page">
    <a className="marketing-skip-link" href="#main-content">Skip to content</a>
    <HomeHeader />
    <main id="main-content">
      <section className="marketing-hero marketing-container">
        <div className="marketing-hero-copy"><p className="marketing-eyebrow"><span /> FOR RESTAURANT OWNERS & OPERATIONS MANAGERS</p><h1>Protect your<br />restaurant margins.<br /><span>Keep every centre accountable.</span></h1><p className="marketing-hero-description">Rising purchase prices. Unreported waste. Stock you cannot explain.</p><p className="marketing-hero-context">See which menus are under pressure, how sales use stock and where your team needs to act.</p><div className="marketing-hero-actions"><Link className="marketing-button" href="/signup">Request workspace access <ArrowUpRight size={17} /></Link><a className="marketing-text-link" href="#product">Explore the product <ArrowRight size={16} /></a></div><p className="marketing-availability"><Check size={14} /> Built for one outlet or a restaurant group.</p></div>
        <div className="marketing-hero-preview"><CostPreview /><p className="marketing-preview-caption"><Sparkles size={14} /> Try it: see what an ingredient cost change means for one plate.</p></div>
      </section>

      <section className="marketing-clarity marketing-container" aria-label="Three questions ProfitPlate helps you answer">{[
        ["01", "Margins in view", "See menu costs and pricing exceptions."],
        ["02", "Stock with context", "Trace stock value, dated usage and physical differences."],
        ["03", "Clear next actions", "Follow reporting gaps and accountable handovers."],
      ].map(([number,title,text])=><div key={number}><span>{number}</span><div><h2>{title}</h2><p>{text}</p></div></div>)}</section>

      <section id="product" className="marketing-section marketing-container"><div className="marketing-section-heading"><div><p className="marketing-eyebrow">A CLEARER BASIS FOR EVERY DECISION</p><h2>Turn daily records into useful decisions.</h2></div><p>See the cost, the context and the next step.</p></div><div className="marketing-capabilities">{capabilities.map(({ icon: Icon, number, title, text, detail }) => <article key={number}><div className="capability-top"><Icon size={25} strokeWidth={1.5} /><span>{detail}</span></div><h3>{title}</h3><p>{text}</p></article>)}</div></section>

      <section id="stock-value" className="marketing-section marketing-container marketing-value-grid"><div className="marketing-value-copy"><p className="marketing-eyebrow">FROM BUSINESS TOTAL TO ONE MATERIAL</p><h2>Know the value on your shelves.</h2><p>See what your posted stock is worth at current reference estimates. Start with the business total, then open Main Store, Kitchen or Bar.</p><ul><li><Check size={16}/>Responsible centre managers see their own stock value.</li><li><Check size={16}/>Unpriced materials stay flagged, rather than valued at zero.</li><li><Check size={16}/>Weekly and monthly counts expose gaps between records and shelves.</li></ul><p className="marketing-value-prompt">Try the example: select a centre to see the calculation.</p></div><StockValuePreview/></section>

      <section id="daily-accountability" className="marketing-section marketing-container marketing-waste-grid" aria-labelledby="daily-accountability-heading">
        <div className="marketing-waste-copy"><p className="marketing-eyebrow">CONSISTENT RECORDS. BETTER DECISIONS.</p><h2 id="daily-accountability-heading">No waste?<br />Confirm it. Don&apos;t leave it blank.</h2><p>Give every stock centre a daily reporting habit, from the Main Store to the Kitchen and Bar.</p><ul><li><Check size={16} />Record waste with a name and reason. No approval queue.</li><li><Check size={16} />Confirm waste recorded or explicitly confirm no waste.</li><li><Check size={16} />See who has reported and what needs follow-up.</li></ul><a href="#management-report" className="marketing-text-link">Turn the records into a clearer review <ArrowRight size={16} /></a></div>
        <div className="marketing-waste-preview" aria-label="Illustrative daily waste reporting"><div className="marketing-waste-preview-top"><span>DAILY WASTE REPORTING</span><span>Fictional example</span></div><h3>Every centre accounted for.</h3><p><strong>2 of 3</strong> centres confirmed today</p><ul>{[{centre:"Main Store",detail:"Emeka confirmed",status:"No waste",tone:"complete"},{centre:"Kitchen",detail:"Ada confirmed",status:"Waste recorded",tone:"complete"},{centre:"Bar",detail:"Daily confirmation missing",status:"Overdue",tone:"overdue"}].map(row=><li key={row.centre}><div><strong>{row.centre}</strong><span>{row.detail}</span></div><span className={`marketing-waste-status marketing-waste-status-${row.tone}`}>{row.status}</span></li>)}</ul><div className="marketing-waste-insight"><ShieldCheck size={20} /><p><strong>A missing report is not zero waste.</strong><span>Review loss trends, reasons and processing yield alongside reporting completeness.</span></p></div></div>
      </section>

      <TeamPreview />

      <InventoryWorkflow />

      <section id="management-report" className="marketing-report-section"><div className="marketing-container marketing-report-grid"><div><p className="marketing-eyebrow">VISIBILITY FOR OWNERS. FOLLOW-THROUGH FROM OPERATIONS.</p><h2>See the numbers.<br />Put someone in charge of the next step.</h2><p>Owners see performance at a glance. Operations Managers follow reporting gaps, stock handovers and cost exceptions back to the centre and source record.</p><ul><li><Check size={16}/>Key metrics come before operational detail.</li><li><Check size={16}/>Warnings and reporting gaps stay in Needs attention.</li><li><Check size={16}/>Review count compliance and independently approved adjustments.</li></ul><Link className="marketing-text-link" href="/signup">Start with your restaurant <ArrowRight size={16}/></Link></div><div className="marketing-report-preview" aria-label="Illustrative management report"><div className="marketing-report-preview-heading"><div><span>PROFITPLATE INSIGHTS</span><h3>Owner workspace</h3><p>Example restaurant &middot; Single day &middot; NGN</p></div><span className="marketing-report-tag">Fictional sample</span></div><div className="marketing-report-sample-metrics"><div><span>Recorded net sales</span><strong>NGN 4,350</strong><small>3 menu units</small></div><div><span>Est. gross profit margin</span><strong>37.93%</strong><small>NGN 1,650 est. contribution</small></div><div><span>Estimated stock value now</span><strong>NGN 318,000</strong><small>3 centres / reference estimates</small></div><div><span>Recorded operating expenses</span><strong>NGN 500</strong><small>Your own expense categories</small></div></div><div className="marketing-report-review"><ShieldCheck size={17}/><p>2 centre counts await review.<br /><span>Check the quantities, submitter and supporting movements.</span></p></div><p className="marketing-report-disclaimer">Fictional figures, not live restaurant data. Stock and food margins are reference estimates; other costs are not deducted from food margin.</p></div></div></section>


      <section id="how-it-works" className="marketing-section marketing-container"><div className="marketing-section-heading"><div><p className="marketing-eyebrow">A CONTROLLED START. A PRACTICAL ROUTINE.</p><h2>Start with your restaurant.<br />Build the habit together.</h2></div><p>One approved workspace, clear responsibilities and records your team can explain.</p></div><div className="marketing-steps"><article><span>01</span><h3>Request your workspace</h3><p>Register, verify your email and submit your restaurant details. The system super admin reviews your request before activating the workspace.</p></article><article><span>02</span><h3>Set up your people and data</h3><p>Bring in the records you already use and give each team member clear responsibilities, so you can start with less repetitive work.</p></article><article><span>03</span><h3>Record, follow up and improve</h3><p>Build a dependable daily routine. Review cost pressures and unexplained losses, then assign the next step to the right person.</p></article></div></section>

      <section id="questions" className="marketing-faq-section"><div className="marketing-container marketing-faq-grid"><div><p className="marketing-eyebrow">BEFORE YOU BRING YOUR TEAM ON BOARD</p><h2>Questions owners ask.<br />Straight answers.</h2><p>What it means for your margins, your team and your decisions.</p></div><div className="marketing-faq-list">{questions.map(([question, answer]) => <details key={question}><summary>{question}<ChevronDown size={17} /></summary><p>{answer}</p></details>)}</div></div></section>

      <section className="marketing-container marketing-cta-wrap"><div className="marketing-cta"><div><p className="marketing-eyebrow">LET’S START WITH YOUR BUSINESS</p><h2>Bring your margins and accountability into view.</h2><p>Start with a restaurant review. Build a daily routine your team can sustain.</p></div><Link href="/signup" className="marketing-button marketing-button-light">Request workspace access <ArrowUpRight size={17} /></Link></div></section>
    </main>
    <footer className="marketing-footer"><div className="marketing-container"><div className="marketing-footer-top"><div><Brand /><p>Know your costs. Understand your margins.<br />Make better decisions.</p></div><nav aria-label="Footer navigation"><a href="#product">The product</a><a href="#how-it-works">How it works</a><a href="#questions">Questions</a><Link href="/login">Sign in</Link></nav></div><div className="marketing-footer-bottom"><span>© ProfitPlate Insights</span><span><MapPin size={13} /> Built with restaurant businesses in mind.</span></div></div></footer>
  </div>;
}
