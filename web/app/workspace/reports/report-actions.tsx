"use client";
import { useEffect, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Download, Printer, RefreshCw } from "lucide-react";

export function ReportActions({ csv, filename, saved = false }: { csv: string; filename: string; saved?: boolean }) {
  const router = useRouter(), [pending, start] = useTransition();
  useEffect(() => {
    const previous = new Map<HTMLDetailsElement, boolean>();
    const expand = () => document.querySelectorAll<HTMLDetailsElement>('.management-report details[data-report-disclosure]').forEach(detail => {
      if (!previous.has(detail)) previous.set(detail, detail.open);
      detail.open = true;
    });
    const restore = () => { previous.forEach((open, detail) => { detail.open = open; }); previous.clear(); };
    const media = window.matchMedia("print");
    const changed = () => { if (media.matches) expand(); else restore(); };
    window.addEventListener("beforeprint", expand); window.addEventListener("afterprint", restore); media.addEventListener("change", changed);
    return () => { window.removeEventListener("beforeprint", expand); window.removeEventListener("afterprint", restore); media.removeEventListener("change", changed); restore(); };
  }, []);
  function download() {
    const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
    const anchor = document.createElement("a"); anchor.href = url; anchor.download = filename;
    document.body.appendChild(anchor); anchor.click(); anchor.remove();
    setTimeout(() => URL.revokeObjectURL(url), 10000);
  }
  return <div className="management-actions">
    {!saved && <button type="button" className="secondary-button" aria-label={pending ? "Refreshing report" : "Refresh report"} disabled={pending} onClick={() => start(() => router.refresh())}><RefreshCw size={14} aria-hidden="true"/><span className="management-action-full">{pending ? "Refreshing report…" : "Refresh report"}</span><span className="management-action-short" aria-hidden="true">{pending ? "Refreshing…" : "Refresh"}</span></button>}
    <button type="button" className="secondary-button" aria-label="Print / save PDF" disabled={pending} onClick={() => window.print()}><Printer size={14} aria-hidden="true"/><span className="management-action-full">Print / save PDF</span><span className="management-action-short" aria-hidden="true">Print / PDF</span></button>
    <button type="button" className="auth-button" aria-label="Download report CSV" disabled={pending} onClick={download}><Download size={14} aria-hidden="true"/><span className="management-action-full">Download report CSV</span><span className="management-action-short" aria-hidden="true">Export CSV</span></button>
  </div>;
}
