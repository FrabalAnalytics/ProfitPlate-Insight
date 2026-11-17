import { Brand } from "@/app/components/brand";

export default function Loading() {
  return <main className="flex min-h-svh flex-col items-center justify-center gap-8 px-6"><Brand /><p role="status" className="text-sm text-muted-foreground">Preparing your workspace…</p></main>;
}
