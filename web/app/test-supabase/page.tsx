"use client";

import Link from "next/link";
import { useState } from "react";
import { supabase } from "@/lib/supabase/Client";

export default function TestSupabasePage() {
  const [status, setStatus] = useState<"idle" | "loading" | "success" | "error">("idle");
  const [message, setMessage] = useState("Click the button to read the sample message from Supabase.");

  async function testConnection() {
    setStatus("loading");
    setMessage("Connecting to Supabase...");

    try {
      const { data, error } = await supabase
        .from("connection_test")
        .select("message")
        .eq("id", 1)
        .abortSignal(AbortSignal.timeout(15000))
        .single();

      if (error) throw error;
      if (typeof data?.message !== "string") {
        throw new Error("The sample row does not contain a message.");
      }

      setStatus("success");
      setMessage(data.message);
    } catch (error: unknown) {
      const detail =
        error && typeof error === "object" && "message" in error
          ? String(error.message)
          : "Check your internet connection and try again.";
      setStatus("error");
      setMessage(`Connection test failed: ${detail}`);
    }
  }

  return (
    <main className="flex-1 bg-background px-6 py-16 font-sans text-foreground">
      <div className="mx-auto max-w-xl rounded-2xl border border-border bg-surface p-6 sm:p-10">
        <Link href="/" className="text-sm font-medium text-brand underline underline-offset-4">
          Back to ProfitPlate Insight
        </Link>
        <h1 className="mt-6 text-3xl font-semibold tracking-tight text-brand">
          Supabase Connection Test
        </h1>
        <p className="mt-4 leading-7">
          Read the sample message from your connection_test table to check that
          this app can reach your database.
        </p>
        <button
          type="button"
          onClick={testConnection}
          disabled={status === "loading"}
          className="mt-6 rounded-lg bg-brand px-5 py-3 font-medium text-brand-foreground hover:bg-brand-deep focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-brand disabled:cursor-wait disabled:opacity-60"
        >
          {status === "loading" ? "Testing..." : "Test connection"}
        </button>
        <div role="status" aria-live="polite" className="mt-6 rounded-lg border border-border p-4">
          {status === "success" && <p className="mb-2 font-semibold text-brand">Connection successful</p>}
          {status === "error" && <p className="mb-2 font-semibold text-destructive">Connection needs attention</p>}
          <p className="break-words leading-7">{message}</p>
        </div>
        <p className="mt-5 text-sm leading-6 text-muted-foreground">
          This test reads one sample row. It does not change data or test login
          and organisation permissions.
        </p>
      </div>
    </main>
  );
}
