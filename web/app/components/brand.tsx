import Link from "next/link";

export function PlateMark({ className = "" }: { className?: string }) {
  return (
    <svg viewBox="0 0 40 40" fill="none" aria-hidden="true" className={className}>
      <rect width="40" height="40" rx="12" fill="currentColor" />
      <circle cx="20" cy="20" r="11" stroke="var(--accent)" strokeWidth="1.6" />
      <path d="M15 24v-5m5 5V14m5 10v-8" stroke="var(--brand-foreground)" strokeWidth="2.4" strokeLinecap="round" />
    </svg>
  );
}

export function Brand({ light = false }: { light?: boolean }) {
  return (
    <Link href="/" aria-label="ProfitPlate Insight home" className={`brand-lockup ${light ? "brand-lockup-light" : ""}`}>
      <PlateMark className="brand-mark" />
      <span>ProfitPlate<span className="brand-subtitle">INSIGHT</span></span>
    </Link>
  );
}
