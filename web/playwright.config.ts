import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests/e2e", workers: 1, timeout: 45000,
  use: { baseURL: process.env.PLAYWRIGHT_BASE_URL ?? "http://localhost:3101", browserName: "chromium", channel: "chrome", screenshot: "only-on-failure", trace: "retain-on-failure" },
});
