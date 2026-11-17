import {clickNavigation} from './navigation';
import { test, expect, type Page } from "@playwright/test";

async function openPrices(page: Page, email = "catalogue@example.test") {
 await page.goto("/login");
 await page.getByLabel("Email address").fill(email);
 await page.getByLabel("Password", { exact: true }).fill("TestPassword123!");
 await page.getByRole("button", { name: "Sign in", exact: true }).click();
 await expect(page).toHaveURL(/\/workspace$/);
 await clickNavigation(page,'Materials & suppliers');
 await page.getByRole("link", { name: "Initial material prices", exact: true }).click();
 await expect(page.getByRole("heading", { name: "A starting point for your costs.", exact: true })).toBeVisible();
}

test("reference prices require review, preserve form details and append corrections", async ({ page }, testInfo) => {
 const errors: string[] = [];
 page.on("pageerror", error => errors.push(error.message));
 await page.setViewportSize({ width: 1440, height: 1000 });
 await openPrices(page);
 await page.getByRole("link", { name: "Reference prices for Ingredient 01", exact: true }).click();
 await page.getByLabel("Quantity covered by this price").fill("50");
 await page.getByLabel("Total price (NGN)", { exact: true }).fill("90000");
 await page.getByLabel("Price date", { exact: true }).fill("2020-02-01");
 await page.getByLabel("Source note", { exact: true }).fill("Sample last invoice");
 await page.getByRole("button", { name: "Review prices", exact: true }).click();
 await expect(page.getByRole("heading", { name: "Review before saving", exact: true })).toBeVisible();
 await expect(page.locator(".reference-review").getByText("NGN 1,800.00 / KG", { exact: true })).toBeVisible();
 await expect(page.getByLabel("Quantity covered by this price")).toHaveValue("50");
 await expect(page.getByLabel("Quantity unit", { exact: true })).toHaveValue("KG");
 await expect(page.getByText("No reference price yet. This material remains missing a price.")).toBeVisible();
 await page.screenshot({ path: testInfo.outputPath("price-review-desktop.png"), fullPage: true });
 await page.getByRole("button", { name: "Save estimated prices", exact: true }).click();
 await expect(page.getByRole("status")).toContainText("Your estimated prices have been saved");
 await page.getByRole("link", { name: "Reference prices for Ingredient 01", exact: true }).click();
 await page.getByLabel("Quantity covered by this price").fill("50");
 await page.getByLabel("Total price (NGN)", { exact: true }).fill("95000");
 await page.getByLabel("Price date", { exact: true }).fill("2020-02-01");
 await page.getByLabel("Source note", { exact: true }).fill("Corrected invoice total");
 await page.getByRole("button", { name: "Review prices", exact: true }).click();
 await expect(page.getByRole("button", { name: "Save estimated prices", exact: true })).toBeVisible();
 await page.getByLabel("Total price (NGN)", { exact: true }).fill("100000");
 await expect(page.getByRole("button", { name: "Save estimated prices", exact: true })).toHaveCount(0);
 await page.getByRole("button", { name: "Review prices", exact: true }).click();
 await expect(page.locator(".reference-review").getByText("NGN 2,000.00 / KG", { exact: true })).toBeVisible();
 await page.getByRole("button", { name: "Save estimated prices", exact: true }).click();
 await expect(page.getByRole("status")).toContainText("Your estimated prices have been saved");
 await page.getByRole("link", { name: "Reference prices for Ingredient 01", exact: true }).click();
 await expect(page.getByRole("table",{name:"Material reference price history"}).getByRole("row").filter({hasText:"Entry 2"}).filter({hasText:"Manual entry"})).toContainText("2020-02-01");
 await expect(page.getByRole("table",{name:"Material reference price history"}).getByRole("row").filter({hasText:"Entry 1"}).filter({hasText:"Manual entry"})).toContainText("2020-02-01");
 expect(errors).toEqual([]);
});

test("CSV onboarding prices validate the entire batch before saving and work on mobile", async ({ page }, testInfo) => {
 await page.setViewportSize({ width: 375, height: 812 });
 await openPrices(page);
 await page.getByRole("link", { name: "Import initial prices", exact: true }).click();
 const headers = "material_code,quantity,unit_code,total_price,price_date,source_note\r\n";
 await page.getByLabel("Initial prices CSV", { exact: true }).setInputFiles({ name: "initial-prices.csv", mimeType: "text/csv", buffer: Buffer.from(headers + 'SAMPLE2,250,G,450,2020-01-01,"Invoice, sample"\r\nUNKNOWN,1,KG,100,2020-01-01,Sample') });
 await page.getByRole("button", { name: "Review prices", exact: true }).click();
 await expect(page.getByRole("alert").filter({ hasText: "Row 2:" })).toContainText("Row 2: material code is unknown");
 await expect(page.getByRole("button", { name: "Save estimated prices", exact: true })).toHaveCount(0);
 await page.getByLabel("Initial prices CSV", { exact: true }).setInputFiles({ name: "initial-prices.csv", mimeType: "text/csv", buffer: Buffer.from(headers + 'SAMPLE2,250,G,450,2020-01-01,"Invoice, sample"\r\nTEST-BOX,1,PCS,50,2020-01-01,Supplier quote') });
 await page.getByRole("button", { name: "Review prices", exact: true }).click();
 await expect(page.getByRole("heading", { name: "Review before saving", exact: true })).toBeVisible();
 await expect(page.locator(".reference-review").getByText("NGN 1,800.00 / KG", { exact: true })).toBeVisible();
 expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
 await page.screenshot({ path: testInfo.outputPath("price-import-mobile.png"), fullPage: true });
 await page.getByRole("button", { name: "Save estimated prices", exact: true }).click();
 await expect(page.getByRole("status")).toContainText("Your estimated prices have been saved");
 await page.getByRole("link", { name: "Reference prices for Ingredient 02", exact: true }).click();
 await expect(page.getByRole("table",{name:"Material reference price history"}).getByRole("row").filter({hasText:"Entry 1"}).filter({hasText:"CSV import"})).toContainText("2020-01-01");
 await expect(page.getByText("Invoice, sample", { exact: true })).toBeVisible();
});

test("finance can inspect reference estimates but cannot add or import them", async ({ page }) => {
 await openPrices(page, "reader@example.test");
 await expect(page.getByText(/You have read-only price access/)).toBeVisible();
 await expect(page.getByRole("link", { name: "Import initial prices", exact: true })).toHaveCount(0);
 await page.getByLabel("Search material prices", { exact: true }).fill("SAMPLE3");
 await page.getByRole("button", { name: "Search", exact: true }).click();
 await page.getByRole("link", { name: "Reference prices for Ingredient 03", exact: true }).click();
 await expect(page.getByRole("button", { name: "Review prices", exact: true })).toHaveCount(0);
 await expect(page.getByText("No reference price yet. This material remains missing a price.")).toBeVisible();
 await page.goto(`${page.url()}&import=1`);
 await expect(page.getByLabel("Initial prices CSV", { exact: true })).toHaveCount(0);
});
