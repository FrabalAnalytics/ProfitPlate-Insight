// Installed only in the spawned test server process, never normal dev/start.
if (process.env.PROFITPLATE_E2E !== "1") throw new Error("Test redirect requires PROFITPLATE_E2E=1");
const original = globalThis.fetch;
const origin = new URL(process.env.NEXT_PUBLIC_SUPABASE_URL).origin;
globalThis.fetch = (input, init) => {
  const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
  if (url.startsWith(`${origin}/`)) {
    const target = `http://127.0.0.1:54398${url.slice(origin.length)}`;
    return original(input instanceof Request ? new Request(target, input) : target, init);
  }
  return original(input, init);
};
