import { chromium } from "@playwright/test";
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";
import { mkdir } from "node:fs/promises";

const folder = resolve("public/templates/pilot-testing-2026-11-17-v2");
const browser = await chromium.launch({ channel: "chrome", headless: true });
try {
 const page = await browser.newPage({ viewport: { width: 1100, height: 900 } });
 await page.goto(pathToFileURL(resolve(folder, "Full-Test-Guide.html")).href);
 if (await page.locator("article").count() !== 84) throw new Error("The guide is missing test cases.");
 if (!await page.getByRole("heading", { name: "ProfitPlate full pilot test guide", exact: true }).isVisible()) throw new Error("The guide did not render.");
 await page.pdf({ path: resolve(folder, "Full-Test-Guide.pdf"), format: "A4", printBackground: true, preferCSSPageSize: true });
 await mkdir("test-results", { recursive: true });
 await page.screenshot({ path: "test-results/pilot-guide-preview.png" });
 await page.setViewportSize({ width: 375, height: 812 });
 if (!await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)) throw new Error("The guide overflows the mobile viewport.");
 console.log("Rendered 84 cases, printed PDF, and checked mobile page width.");
} finally {
 await browser.close();
}
