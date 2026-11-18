import type { Metadata } from "next";
import Link from "next/link";
import { ArrowRight, ArrowUpRight, Check, ChevronDown, ClipboardList, Download, MapPin, PackageCheck, ReceiptText, Users, LayoutDashboard, ShieldCheck, Sparkles, UtensilsCrossed } from "lucide-react";
import { Brand } from "./components/brand";
import { HomeHeader } from "./components/home-header";
import { CostPreview } from "./components/cost-preview";
import {InventoryWorkflow} from "./components/inventory-workflow";
import "./home.css";

export const metadata: Metadata = {
  title: "ProfitPlate Insight | Know your costs. Understand your margins.",
  description: "Compare menu profitability, manage purchase orders and receiving, and connect sales, recipes and operating costs. Review estimated margins and share management reports with ProfitPlate Insight.",
};

const capabilities = [
  { icon: UtensilsCrossed, number: "01", title: "Menu profitability", text: "Compare serving costs, selling prices and estimated food margins.", detail: "Recipes & sub-recipes" },
  { icon: PackageCheck, number: "02", title: "Purchasing & receiving", text: "Track orders, deliveries and supplier invoices separately.", detail: "POs, GRNs & invoices" },
  { icon: LayoutDashboard, number: "03", title: "Stock accountability", text: "Follow transfers, processing yields and waste by stock centre.", detail: "Inventory & movements" },
  { icon: ReceiptText, number: "04", title: "Labour & expenses", text: "Record costs against the right outlet and reporting period.", detail: "Manual entry & CSV imports" },
  { icon: ClipboardList, number: "05", title: "Management reporting", text: "Review changes, trace source records and share reports.", detail: "Executive overview & reports" },
  { icon: Users, number: "06", title: "Team access", text: "Give each person the tasks and stock centres they need.", detail: "Named users & assigned roles" },
];
const questions = [
  ["Why are my food costs rising?", "See which ingredient prices changed and review the dishes they affect. Monthly quantity-weighted purchase costs help you track the pressure on recipe estimates."],
  ["Which dishes need a pricing review?", "Compare serving cost, selling price and estimated food margin. Identify dishes above your food-cost target before deciding whether to adjust the price, portion or recipe."],
  ["How can I find avoidable waste?", "Compare actual processing output with agreed yields, then review recorded spoilage and other losses by stock centre. Use the gaps to guide your team's checks."],
  ["Who needs to act on a stock handover?", "Trace who requested, approved, dispatched and accepted the stock. Pending and incomplete handovers show where follow-up is needed; they do not by themselves prove a loss."],
  ["What should I focus on as an owner?", "Review price pressure, low-margin dishes, recorded waste and overdue handovers, with the affected outlet and source records. Your team sees the tasks relevant to its role."],
  ["Will I know how much profit I actually made?", "You can review estimated food margins alongside recorded labour and expenses. These are not actual net profit: missing costs remain flagged, and full operating profit is not calculated."],
];

export default function Home() {
  return <div className="marketing-page">
    <a className="marketing-skip-link" href="#main-content">Skip to content</a>
    <HomeHeader />
    <main id="main-content">
      <section className="marketing-hero marketing-container">
        <div className="marketing-hero-copy"><p className="marketing-eyebrow"><span /> BUILT FOR THE BUSINESS BEHIND THE FOOD</p><h1>See what is<br /><span>changing your</span><br />restaurant margins.</h1><p className="marketing-hero-description">Spot price increases, waste and low-margin dishes.</p><p className="marketing-hero-context">Give every team a clear next action, with the records behind each figure.</p><div className="marketing-hero-actions"><Link className="marketing-button" href="/signup">Create your workspace <ArrowUpRight size={17} /></Link><a className="marketing-text-link" href="#how-it-works">How it works <ArrowRight size={16} /></a></div><p className="marketing-availability"><Check size={14} /> For owners and restaurant teams.</p></div>
        <div className="marketing-hero-preview"><CostPreview /><p className="marketing-preview-caption"><Sparkles size={14} /> Adjust ingredient cost to see the margin change.</p></div>
      </section>

      <section className="marketing-concepts" aria-label="Restaurant concepts"><div className="marketing-container"><p>Different kitchens.<br /><strong>The same need for clarity.</strong></p><div><span>Restaurants</span><span>Cafés & bakeries</span><span>Cloud kitchens</span><span>Restaurant groups</span></div></div></section>

      <section id="product" className="marketing-section marketing-container"><div className="marketing-section-heading"><div><p className="marketing-eyebrow">AVAILABLE IN YOUR WORKSPACE</p><h2>Your restaurant, connected.</h2></div><p>From purchasing to the margin on each plate.</p></div><div className="marketing-capabilities">{capabilities.map(({ icon: Icon, number, title, text, detail }) => <article key={number}><div className="capability-top"><Icon size={25} strokeWidth={1.5} /><span>{number}</span></div><h3>{title}</h3><p>{text}</p><div className="capability-detail">{detail}</div></article>)}</div></section>

      <section className="marketing-section marketing-container" aria-labelledby="team-benefits-title"><div className="marketing-section-heading"><div><p className="marketing-eyebrow">YOUR TEAM. CLEAR RESPONSIBILITIES.</p><h2 id="team-benefits-title">One team. Clear responsibilities.</h2></div></div><div className="marketing-role-grid">{[
        ["Owners & CEOs", "Know what changed and where.", "Changes, estimated impact and the outlet affected."],
        ["Inventory Managers", "Keep stock handovers moving.", "Requests, receiving, processing and stock handovers."],
        ["Procurement", "Follow each purchase through.", "Orders, delivery records and invoice exceptions."],
        ["Kitchen & Bar", "Know what is coming to you.", "Material requests, transfer acceptance and waste."],
        ["Finance", "Review the evidence behind the figures.", "Invoice reviews, expenses and management reports."],
      ].map(([role,,text])=><article key={role}><p className="marketing-eyebrow">{role}</p><p>{text}</p></article>)}</div></section>

      <InventoryWorkflow />

      <section id="management-report" className="marketing-report-section"><div className="marketing-container marketing-report-grid"><div><p className="marketing-eyebrow">FROM THE WORKSPACE TO THE BOARDROOM</p><h2>The key figures.<br />The context behind them.</h2><p>Review sales, estimated margins and expenses. Save a report for Finance and management review.</p><ul><li><Check size={16}/>Period, outlet and currency stay visible.</li><li><Check size={16}/>Missing inputs and partial coverage are flagged.</li><li><Check size={16}/>Saved reports, management review, CSV and print / PDF.</li></ul><Link className="marketing-text-link" href="/signup">View your reports <ArrowRight size={16}/></Link></div><div className="marketing-report-preview" aria-label="Illustrative management report"><div className="marketing-report-preview-heading"><div><span>PROFITPLATE INSIGHT</span><h3>Management report</h3><p>Example restaurant &middot; Single day &middot; NGN</p></div><span className="marketing-report-tag">Fictional sample</span></div><div className="marketing-report-sample-metrics"><div><span>Recorded net sales</span><strong>NGN 4,350</strong><small>3 menu units</small></div><div><span>Estimated food margin</span><strong>NGN 1,650</strong><small>37.93% of net sales</small></div><div><span>Recorded labour</span><strong>NGN 600</strong><small>Coverage reviewed</small></div><div><span>Estimated prime cost</span><strong>NGN 3,300</strong><small>75.86% of net sales</small></div></div><div className="marketing-report-review"><ShieldCheck size={17}/><p>Review the basis, not just the number.<br /><span>Source context and coverage travel with the report.</span></p></div><p className="marketing-report-disclaimer">Fictional figures. Food margins are estimates; prime cost includes labour. This is not actual accounting profit.</p></div></div></section>


      <section id="how-it-works" className="marketing-section marketing-container"><div className="marketing-section-heading"><div><p className="marketing-eyebrow">A PRACTICAL START</p><h2>Your data in.<br />A clearer picture out.</h2></div><p>Start with one outlet and a checked sample.</p></div><div className="marketing-steps"><article><span>01</span><h3>Create your account</h3><p>Register and verify your email.</p></article><article><span>02</span><h3>Make it your business</h3><p>Name your outlets and stock centres, then assign your team.</p></article><article><span>03</span><h3>View your reports</h3><p>Add materials, prices, recipes and menus. Record transactions and review the results.</p><small>Start small · check the figures together</small></article></div><div className="marketing-template-download"><div><h3>Try a complete restaurant dataset</h3><p>Excel workbook, four upload CSVs, manual-entry sheets and expected results.</p></div><a className="marketing-text-link" href="/templates/profitplate-complete-test-data-2026-11-18.zip" download><Download size={17} aria-hidden="true" /> Download test data pack</a><a className="marketing-text-link" href="/templates/complete-restaurant-test-data/Complete_Restaurant_Onboarding_and_Test_Guide.docx" download>Download Word guide <ArrowRight size={16} aria-hidden="true" /></a></div></section>

      <section id="questions" className="marketing-faq-section"><div className="marketing-container marketing-faq-grid"><div><p className="marketing-eyebrow">A FEW THINGS TO KNOW</p><h2>Questions, answered.</h2><p>A clear view of what’s ready today and where we’re going next.</p></div><div className="marketing-faq-list">{questions.map(([question, answer]) => <details key={question}><summary>{question}<ChevronDown size={17} /></summary><p>{answer}</p></details>)}</div></div></section>

      <section className="marketing-container marketing-cta-wrap"><div className="marketing-cta"><div><p className="marketing-eyebrow">LET’S START WITH YOUR BUSINESS</p><h2>Bring clarity to the table.</h2><p>Start with one restaurant. See what needs attention.</p></div><Link href="/signup" className="marketing-button marketing-button-light">Create your workspace <ArrowUpRight size={17} /></Link></div></section>
    </main>
    <footer className="marketing-footer"><div className="marketing-container"><div className="marketing-footer-top"><div><Brand /><p>Know your costs. Understand your margins.<br />Make better decisions.</p></div><nav aria-label="Footer navigation"><a href="#product">The product</a><a href="#how-it-works">How it works</a><a href="#questions">Questions</a><Link href="/login">Sign in</Link></nav></div><div className="marketing-footer-bottom"><span>© ProfitPlate Insight</span><span><MapPin size={13} /> Built with restaurant businesses in mind.</span></div></div></footer>
  </div>;
}
