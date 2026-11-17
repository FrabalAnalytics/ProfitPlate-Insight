import {clickNavigation} from './navigation';
import { test, expect, type Page } from "@playwright/test";
import { readFile } from "node:fs/promises";

const headers = "Organisation_Code,Source_System,Purchase_Date,Purchase_Ref,Line_Ref,Supplier_Code,Item_Code,Quantity,Purchase_UOM,Unit_Price,Line_Discount,Tax,Location_Code,Currency,Status\r\n";
const source = headers + "ORG001,PILOT,2020-01-01,PI-001,1,SUP-IMPORT,SAMPLE1,50,KG,1800,0,0,PRIMARY,NGN,RECEIVED\r\nORG001,PILOT,2020-01-01,PI-001,2,SUP-IMPORT,TEST-BOX,12,PCS,100,0,0,PRIMARY,NGN,RECEIVED";

async function openPurchases(page: Page, email = "catalogue@example.test") {
 await page.goto("/login"); await page.getByLabel("Email address").fill(email);
 await page.getByLabel("Password", { exact: true }).fill("TestPassword123!");
 await page.getByRole("button", { name: "Sign in", exact: true }).click();
 await clickNavigation(page,'Supplier invoices');
 await page.getByRole('link', { name:'Purchase imports',exact:true }).click();
 await expect(page).toHaveURL(/\/workspace\/purchases\?/);
}
async function upload(page: Page, text: string, filename: string) {
 await page.getByRole("link", { name: "Import purchases", exact: true }).click();
 await page.getByLabel("Purchases CSV", { exact: true }).setInputFiles({ name: filename, mimeType: "text/csv", buffer: Buffer.from(text) });
 await page.getByLabel("Source organisation code", { exact: true }).fill("ORG001");
 await page.getByLabel("Unit price tax setting", { exact: true }).selectOption("EXCLUSIVE");
 await page.getByRole("button", { name: "Validate purchase file", exact: true }).click();
 await expect(page).toHaveURL(/batch=/);
 await expect(page.getByRole("heading", { name: filename, exact: true, level: 2 })).toBeVisible();
}

test("purchase review reconciles supplier totals, preserves source and skips duplicate lines", async ({ page }, testInfo) => {
 await page.setViewportSize({ width: 1440, height: 1000 });
 const errors: string[] = []; page.on("pageerror", error => errors.push(error.message));
 await openPurchases(page); await upload(page, source, "pilot-purchases.csv");
 const firstRow = page.getByRole("table",{name:"Purchase import lines",exact:true}).locator(".transaction-main").first();
 expect((await firstRow.boundingBox())!.height).toBeLessThan(100);
 await page.getByRole("button",{name:"Show details for PI-001 / 1",exact:true}).click();
 await expect(page.getByText("Converted quantity: 50 KG",{exact:true})).toBeVisible();
 await page.getByRole("button",{name:"Hide details for PI-001 / 1",exact:true}).click();
 await expect(page.getByRole("heading", { name: "Reconcile and save purchases", exact: true })).toBeVisible();
 await page.getByLabel("Invoice total for PI-001 (Import Test Foods)", { exact: true }).fill("1");
 await page.getByRole("checkbox").check();
 await page.getByRole("button", { name: "Save reviewed purchases", exact: true }).click();
 await expect(page.getByRole("alert").filter({ hasText: "Invoice total does not reconcile" })).toBeVisible();
 await page.getByLabel("Invoice total for PI-001 (Import Test Foods)", { exact: true }).fill("91200");
 await page.getByRole("button", { name: "Save reviewed purchases", exact: true }).click();
 await expect(page.getByRole("status")).toContainText("Purchase import recorded");
 await expect(page.locator(".purchase-recorded-totals")).toContainText("NGN 91,200.00");
 const downloadPromise = page.waitForEvent("download");
 await page.getByRole("button", { name: "Download original CSV", exact: true }).click();
 const download = await downloadPromise; const destination = testInfo.outputPath("original-purchases.csv");
 await download.saveAs(destination); expect(await readFile(destination, "utf8")).toBe(source);
 await expect(page.getByText("Preparing your workspace…", { exact: true })).toHaveCount(0);
 await page.screenshot({ path: testInfo.outputPath("purchases-desktop.png"), fullPage: true });
 await upload(page, source, "pilot-duplicate.csv");
 await expect(page.getByText("Already recorded — will skip", { exact: true })).toBeVisible();
 await expect(page.getByLabel("Invoice total for PI-001 (Import Test Foods)", { exact: true })).toHaveCount(0);
 await page.getByRole("checkbox").check(); await page.getByRole("button", { name: "Save reviewed purchases", exact: true }).click();
 await expect(page.getByRole("status")).toContainText("Purchase import recorded");
 await expect(page.locator(".purchase-counts article").first()).toContainText("0");
 expect(errors).toEqual([]);
});

test("source codes map into the business catalogue and a corrected attempt works on mobile", async ({ page }, testInfo) => {
 await page.setViewportSize({ width: 375, height: 812 });
 await openPurchases(page);
 await upload(page, headers + "ORG001,PILOT,2020-01-01,MAPPED-001,1,EXT-SUP,EXT-RICE,250,G,2,0,0,EXT-LOC,NGN,RECEIVED", "mapped-purchases.csv");
 await expect(page.getByText(/Unknown or inactive material code/)).toBeVisible();
 await expect(page.getByRole("button", { name: "Save reviewed purchases", exact: true })).toHaveCount(0);
 await page.getByRole("link", { name: "Correct file or map codes", exact: true }).click();
 await page.getByText("Map source material codes (1)", { exact: true }).click();
 await page.getByLabel("Map material EXT-RICE", { exact: true }).fill("SAMPLE2");
 await page.getByText("Map source supplier codes (1)", { exact: true }).click();
 await page.getByLabel("Map supplier EXT-SUP", { exact: true }).fill("SUP-IMPORT");
 await page.getByText("Map source location codes (1)", { exact: true }).click();
 await page.getByLabel("Map location EXT-LOC", { exact: true }).fill("PRIMARY");
 await page.getByRole("button", { name: "Validate purchase file", exact: true }).click();
 await expect(page.getByRole("heading", { name: "Reconcile and save purchases", exact: true })).toBeVisible();
 await page.getByRole("button", { name: "Show details for MAPPED-001 / 1", exact: true }).click();
 await expect(page.getByText("Converted quantity: 0.25 KG", { exact: true })).toBeVisible();
 await page.getByLabel("Invoice total for MAPPED-001 (Import Test Foods)", { exact: true }).fill("500");
 await page.getByRole("checkbox").check(); await page.getByRole("button", { name: "Save reviewed purchases", exact: true }).click();
 await expect(page.getByRole("status")).toContainText("Purchase import recorded");
 await expect(page.getByText("Preparing your workspace…", { exact: true })).toHaveCount(0);
 await expect(page.locator(".purchase-recorded-totals")).toBeVisible();
 expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
 await page.screenshot({ path: testInfo.outputPath("purchases-mobile.png"), fullPage: true });
});

test("malformed purchase files are retained and unposted attempts can be cancelled", async ({ page }) => {
 await openPurchases(page); await upload(page, "wrong,headers\n1,2", "invalid-purchases.csv");
 await expect(page.getByRole("alert").filter({ hasText: "template headers" })).toBeVisible();
 await page.getByRole("button", { name: "Cancel unposted import", exact: true }).click();
 await expect(page.locator(".purchase-batch-heading")).toContainText("Cancelled");
 await expect(page.getByRole("button", { name: "Download original CSV", exact: true })).toBeVisible();
 await expect(page.getByRole("button", { name: "Save reviewed purchases", exact: true })).toHaveCount(0);
});

test("finance reviews sources and correction decisions without purchase-entry controls", async ({ page }) => {
 await openPurchases(page, "reader@example.test");
 await expect(page.getByText(/Procurement handles purchase entry and imports/)).toBeVisible();
 await expect(page.getByRole("link", { name: "Import purchases", exact: true })).toHaveCount(0);
 await page.getByRole("link", { name: "Review import pilot-purchases.csv", exact: true }).click();
 await expect(page.getByRole("button", { name: "Download original CSV", exact: true })).toBeVisible();
 await expect(page.getByRole("button", { name: "Save reviewed purchases", exact: true })).toHaveCount(0);
 await page.goto(`${page.url()}&new=1`);
 await expect(page.getByLabel("Purchases CSV", { exact: true })).toHaveCount(0);
});
