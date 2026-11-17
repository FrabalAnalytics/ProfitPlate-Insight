"use client";

import Link from "next/link";
import { Brand } from "@/app/components/brand";

export default function ErrorPage({ reset }: { reset: () => void }) {
  return <main className="flex min-h-svh flex-col items-center justify-center px-6"><Brand /><div className="mt-10 w-full max-w-sm rounded-2xl border border-border bg-surface p-8"><h1 className="text-2xl font-semibold tracking-tight">Let’s try that again.</h1><p className="mt-4 text-sm leading-7 text-muted-foreground">We couldn’t load this page. Check your connection, then try again.</p><button className="auth-button mt-6" onClick={reset}>Try again <span aria-hidden="true">↻</span></button><Link href="/login" className="auth-back">Back to sign in</Link></div></main>;
}
