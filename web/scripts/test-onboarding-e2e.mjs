import { spawn } from "node:child_process";
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";

const children = [];
async function start(args, ready, env = process.env) {
  const processHandle = spawn(process.execPath, args, { env, windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
  children.push(processHandle);
  await new Promise((resolveReady, reject) => {
    const timeout = setTimeout(() => reject(new Error("Test service did not start in time")), 30000);
    processHandle.stdout.on("data", chunk => { if (chunk.toString().includes(ready)) { clearTimeout(timeout); resolveReady(); } });
    processHandle.stderr.on("data", chunk => process.stderr.write(chunk));
    processHandle.on("exit", code => { clearTimeout(timeout); reject(new Error(`Test service exited: ${code}`)); });
  });
}
try {
  await start(["tests/fixtures/onboarding-service.mjs"], "MOCK_READY");
  await start(["--import", pathToFileURL(resolve("tests/fixtures/redirect-supabase.mjs")).href, "node_modules/next/dist/bin/next", "start", "--port", "3101"], "Ready", { ...process.env, PROFITPLATE_E2E: "1", NEXT_PUBLIC_SITE_URL: "http://localhost:3101" });
  const test = spawn(process.execPath, ["node_modules/@playwright/test/cli.js", "test", ...process.argv.slice(2)], { stdio: "inherit", windowsHide: true, env: process.env });
  children.push(test);
  process.exitCode = await new Promise(resolveExit => test.on("exit", code => resolveExit(code ?? 1)));
} catch (error) { console.error(error.message); process.exitCode = 1; }
finally { for (const child of children) if (child.exitCode === null) child.kill(); }
