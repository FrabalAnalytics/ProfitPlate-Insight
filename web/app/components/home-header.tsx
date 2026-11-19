"use client";

import { useState } from "react";
import Link from "next/link";
import { ArrowUpRight, Menu, X } from "lucide-react";
import { Brand } from "./brand";

export function HomeHeader() {
  const [open, setOpen] = useState(false);
  return <header className="marketing-header" onKeyDown={event => { if (event.key === "Escape") setOpen(false); }}>
    <div className="marketing-container marketing-nav-row"><Brand />
      <nav aria-label="Primary navigation" className="marketing-desktop-nav"><a href="#product">Why ProfitPlate</a><a href="#teams">Your team</a><a href="#how-it-works">How it works</a><a href="#questions">FAQs</a></nav>
      <div className="marketing-nav-actions"><Link href="/login">Sign in</Link><Link href="/signup" className="marketing-button marketing-button-small">Get started <ArrowUpRight size={15} /></Link></div>
      <button className="marketing-menu-button" aria-label={open ? "Close menu" : "Open menu"} aria-expanded={open} aria-controls="mobile-home-navigation" onClick={() => setOpen(!open)}>{open ? <X size={22} /> : <Menu size={22} />}</button>
    </div>
    {open && <nav id="mobile-home-navigation" aria-label="Mobile navigation" className="marketing-mobile-nav" onClick={() => setOpen(false)}><a href="#product">Why ProfitPlate</a><a href="#teams">Your team</a><a href="#how-it-works">How it works</a><a href="#questions">FAQs</a><Link href="/login">Sign in</Link><Link href="/signup">Create your workspace <ArrowUpRight size={15} /></Link></nav>}
  </header>;
}
