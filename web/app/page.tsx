import type { Metadata } from "next";
import Link from "next/link";
import { ArrowRight, ArrowUpRight, Check, ChevronDown, ClipboardList, Download, MapPin, PackageCheck, ReceiptText, Users, LayoutDashboard, ShieldCheck, Sparkles, UtensilsCrossed } from "lucide-react";
import { Brand } from "./components/brand";
import { HomeHeader } from "./components/home-header";
import { CostPreview } from "./components/cost-preview";
import {TeamPreview} from "./components/team-preview";
import {InventoryWorkflow} from "./components/inventory-workflow";
import "./home.css";

export const metadata: Metadata = {
  title: "ProfitPlate Insight | Restaurant margins, stock control & accountability",
  description: "Understand changing food costs, review menu margins and keep stock movements accountable. Give restaurant owners and their teams a clear view of what needs attention.",
};

const capabilities = [
  { icon: UtensilsCrossed, number: "01", title: "Know what each dish can earn", text: "Compare serving costs, selling prices and estimated food margins.", detail: "Menu profitability" },
  { icon: ReceiptText, number: "02", title: "Understand purchase price pressure", text: "Follow monthly material costs and the recipe estimates they inform.", detail: "Quantity-weighted purchase costs" },
  { icon: PackageCheck, number: "03", title: "Keep purchases traceable", text: "Follow each order through delivery records and supplier invoices.", detail: "Separate POs, GRNs & invoices" },
  { icon: LayoutDashboard, number: "04", title: "Make stock responsibility clear", text: "Name your centres, assign their owners and choose each person's tasks.", detail: "Centres & team access" },
  { icon: Users, number: "05", title: "Build a useful waste history", text: "Record losses by centre, material, reason and submitter, without approval delays.", detail: "Simple, named waste recording" },
  { icon: ClipboardList, number: "06", title: "Review the figures with context", text: "Connect sales, estimated food costs and recorded labour and expenses.", detail: "Filterable history & management reports" },
];
const questions = [
  ["Why are my food costs rising?", "See which ingredient prices changed and review the dishes they affect. Monthly quantity-weighted purchase costs inform recipe estimates, so you can review price pressure with a clearer basis."],
  ["Which dishes need a pricing review?", "Compare cost per serving, selling price, food-cost percentage and estimated food margin. Use your targets to decide where to review the price, portion or recipe."],
  ["How can I make waste easier to track?", "Give each team access to its stock centre. They enter a submitter name, material, quantity and reason, then record the loss without approval. Review that history by centre and compare processing output with its agreed baseline."],
  ["How do I know stock reached the right department?", "The receiving team accepts or rejects a transfer. Accepted quantities update both centres together, while pending and incomplete handovers remain visible for follow-up."],
  ["Can my team work without overwhelming me?", "Each person sees the tasks and centres permitted by their role. Owners can focus on price pressure, menu margins, waste and exceptions, with source records available when they need more detail."],
  ["Will this show my restaurant's actual net profit?", "ProfitPlate shows estimated food margins alongside recorded labour and operating expenses. Complete net profit also depends on all relevant costs and accounting adjustments; those are outside the current calculation."],
];

export default function Home() {
  return <div className="marketing-page">
    <a className="marketing-skip-link" href="#main-content">Skip to content</a>
    <HomeHeader />
    <main id="main-content">
      <section className="marketing-hero marketing-container">
        <div className="marketing-hero-copy"><p className="marketing-eyebrow"><span /> FOR RESTAURANT OWNERS AND THEIR TEAMS</p><h1>Understand your<br />restaurant margins.<br /><span>Act on what changed.</span></h1><p className="marketing-hero-description">Rising ingredient costs. Recorded waste. Dishes earning less than expected.</p><p className="marketing-hero-context">See where the pressure is coming from and give your team a clear next action, with the records to back it up.</p><div className="marketing-hero-actions"><Link className="marketing-button" href="/signup">Create your workspace <ArrowUpRight size={17} /></Link><a className="marketing-text-link" href="#product">Explore the product <ArrowRight size={16} /></a></div><p className="marketing-availability"><Check size={14} /> Built for one outlet or a restaurant group.</p></div>
        <div className="marketing-hero-preview"><CostPreview /><p className="marketing-preview-caption"><Sparkles size={14} /> Try it: see what an ingredient cost change means for one plate.</p></div>
      </section>

      <section className="marketing-clarity marketing-container" aria-label="Three questions ProfitPlate helps you answer">{[
        ["01", "What changed?", "Ingredient prices, recipe estimates and recorded losses."],
        ["02", "Where does it matter?", "The affected dish, stock centre or outlet."],
        ["03", "Who needs to act?", "Named owners and tasks for the right team."],
      ].map(([number,title,text])=><div key={number}><span>{number}</span><div><h2>{title}</h2><p>{text}</p></div></div>)}</section>

      <section id="product" className="marketing-section marketing-container"><div className="marketing-section-heading"><div><p className="marketing-eyebrow">A CLEARER BASIS FOR EVERY DECISION</p><h2>Turn daily records into useful decisions.</h2></div><p>See the cost, the context and the next step.</p></div><div className="marketing-capabilities">{capabilities.map(({ icon: Icon, number, title, text, detail }) => <article key={number}><div className="capability-top"><Icon size={25} strokeWidth={1.5} /><span>{detail}</span></div><h3>{title}</h3><p>{text}</p></article>)}</div></section>

      <TeamPreview />

      <InventoryWorkflow />

      <section id="management-report" className="marketing-report-section"><div className="marketing-container marketing-report-grid"><div><p className="marketing-eyebrow">OWNER & FINANCE REVIEW</p><h2>A meeting-ready view<br />of your restaurant.</h2><p>Review sales, estimated food margins and recorded expenses for the period and outlet you choose.</p><ul><li><Check size={16}/>Period, outlet and currency stay visible.</li><li><Check size={16}/>Missing inputs and partial coverage are flagged.</li><li><Check size={16}/>Save a review, export CSV or print to PDF.</li></ul><Link className="marketing-text-link" href="/signup">Start with your restaurant <ArrowRight size={16}/></Link></div><div className="marketing-report-preview" aria-label="Illustrative management report"><div className="marketing-report-preview-heading"><div><span>PROFITPLATE INSIGHT</span><h3>Management report</h3><p>Example restaurant &middot; Single day &middot; NGN</p></div><span className="marketing-report-tag">Fictional sample</span></div><div className="marketing-report-sample-metrics"><div><span>Recorded net sales</span><strong>NGN 4,350</strong><small>3 menu units</small></div><div><span>Estimated food margin</span><strong>NGN 1,650</strong><small>37.93% of net sales</small></div><div><span>Recorded labour</span><strong>NGN 600</strong><small>Coverage reviewed</small></div><div><span>Estimated prime cost</span><strong>NGN 3,300</strong><small>75.86% of net sales</small></div></div><div className="marketing-report-review"><ShieldCheck size={17}/><p>Review the basis, not just the number.<br /><span>Source context and coverage travel with the report.</span></p></div><p className="marketing-report-disclaimer">Fictional figures. Food margins are estimates; prime cost includes labour. This is not actual accounting profit.</p></div></div></section>


      <section id="how-it-works" className="marketing-section marketing-container"><div className="marketing-section-heading"><div><p className="marketing-eyebrow">START WITH THE RESTAURANT YOU RUN</p><h2>Set up once.<br />Build the habit together.</h2></div><p>Start with one outlet, a small dataset and a real workflow.</p></div><div className="marketing-steps"><article><span>01</span><h3>Set up your restaurant</h3><p>Create your account, add your outlets and choose your reporting calendar.</p></article><article><span>02</span><h3>Give each centre an owner</h3><p>Name your Main Store, Kitchen or Bar. Save the owner and their tasks together.</p></article><article><span>03</span><h3>Record, review and improve</h3><p>Add materials, starting prices, recipes and menus. Record daily activity and review what needs attention.</p><small>Manual entry and supported CSV uploads</small></article></div><details className="marketing-pilot-resources"><summary>Planning a pilot? Start with sample data <Download size={16} aria-hidden="true"/></summary><div className="marketing-template-download"><div><h3>Try a fictional restaurant dataset</h3><p>Excel sheets, CSV samples and expected results to check your figures. Follow the setup screens for the current workflow.</p></div><a className="marketing-text-link" href="/templates/profitplate-complete-test-data-2026-11-19.zip" download><Download size={17} aria-hidden="true"/> Download test data pack</a></div></details></section>

      <section id="questions" className="marketing-faq-section"><div className="marketing-container marketing-faq-grid"><div><p className="marketing-eyebrow">THE QUESTIONS BEHIND THE NUMBERS</p><h2>Questions, answered.</h2><p>Practical answers for the decisions you make every week.</p></div><div className="marketing-faq-list">{questions.map(([question, answer]) => <details key={question}><summary>{question}<ChevronDown size={17} /></summary><p>{answer}</p></details>)}</div></div></section>

      <section className="marketing-container marketing-cta-wrap"><div className="marketing-cta"><div><p className="marketing-eyebrow">LET’S START WITH YOUR BUSINESS</p><h2>Give your restaurant a clearer next step.</h2><p>Set up your centres. Bring in your data. Start reviewing what matters.</p></div><Link href="/signup" className="marketing-button marketing-button-light">Create your workspace <ArrowUpRight size={17} /></Link></div></section>
    </main>
    <footer className="marketing-footer"><div className="marketing-container"><div className="marketing-footer-top"><div><Brand /><p>Know your costs. Understand your margins.<br />Make better decisions.</p></div><nav aria-label="Footer navigation"><a href="#product">The product</a><a href="#how-it-works">How it works</a><a href="#questions">Questions</a><Link href="/login">Sign in</Link></nav></div><div className="marketing-footer-bottom"><span>© ProfitPlate Insight</span><span><MapPin size={13} /> Built with restaurant businesses in mind.</span></div></div></footer>
  </div>;
}
