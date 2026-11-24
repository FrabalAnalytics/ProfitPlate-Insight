import {clickNavigation} from './navigation';
import { test, expect, type Page } from "@playwright/test";

async function login(page: Page, email = "catalogue@example.test") {
 await page.goto("/login");
 await page.getByLabel("Email address").fill(email);
 await page.getByLabel("Password", { exact: true }).fill("TestPassword123!");
 await page.getByRole("button", { name: "Sign in", exact: true }).click();
 await expect(page).toHaveURL(/\/workspace$/);
 await expect(page.locator(".welcome-greeting")).toBeVisible();
}

test("recipe estimate stays incomplete until packaging is priced, then scales batch and portion costs", async ({ page }, testInfo) => {
 await page.setViewportSize({ width: 1440, height: 1000 });
 const errors: string[] = []; page.on("pageerror", error => errors.push(error.message));
 await login(page);
 await clickNavigation(page,'Materials & suppliers');
 await expect(page).toHaveURL(/\/workspace\/materials\?/);
 const catalogueUrl = page.url();
 for (const [code, name, type, unit] of [["COST-RICE", "Costing rice", "RAW", "Kilogram (KG)"], ["COST-BOX", "Costing takeaway box", "PACKAGING", "Piece (PCS)"]]) {
  await page.goto(catalogueUrl);
  await page.getByRole("link", { name: "Add material", exact: true }).click();
  await page.getByLabel("Material code", { exact: true }).fill(code);
  await page.getByLabel("Material name", { exact: true }).fill(name);
  await page.getByLabel("Material type", { exact: true }).selectOption(type);
  await page.getByLabel("Base unit", { exact: true }).selectOption({ label: unit });
  await page.getByRole("button", { name: "Save material", exact: true }).click();
  await expect(page.getByRole("status")).toContainText("Your material has been saved");
 }
 await page.getByRole("link", { name: "Initial material prices", exact: true }).click();
 await page.getByRole("link", { name: "Reference prices for Costing rice", exact: true }).click();
 await page.getByLabel("Quantity covered by this price").fill("50");
 await page.getByLabel("Total price (NGN)", { exact: true }).fill("90000");
 await page.getByLabel("Price date", { exact: true }).fill("2020-01-01");
 await page.getByLabel("Source note", { exact: true }).fill("Fictional recipe-cost test");
 await page.getByRole("button", { name: "Review prices", exact: true }).click();
 await page.getByRole("button", { name: "Save estimated prices", exact: true }).click();
 await expect(page.getByRole("status")).toContainText("Your estimated prices have been saved");
 await clickNavigation(page,'Recipes & scaling');
 await page.getByRole("link", { name: "Create recipe", exact: true }).click();
 await page.getByLabel("Recipe code", { exact: true }).fill("COST-PLATE");
 await page.getByLabel("Recipe name", { exact: true }).fill("Costing sample plate");
 await page.getByLabel("Effective from", { exact: true }).fill("2020-01-01");
 await page.getByLabel("Standard batch yield", { exact: true }).fill("12");
 await page.getByLabel("Search component 1", { exact: true }).fill("Costing rice");
 await page.getByLabel("Choose component 1", { exact: true }).selectOption({ label: "Costing rice" });
 await page.getByLabel("Quantity 1", { exact: true }).fill("2");
 await page.getByRole("button", { name: "Add component", exact: true }).click();
 await page.getByLabel("Search component 2", { exact: true }).fill("Costing takeaway box");
 await page.getByLabel("Choose component 2", { exact: true }).selectOption({ label: "Costing takeaway box" });
 await page.getByLabel("Quantity 2", { exact: true }).fill("12");
 await page.getByRole("button", { name: "Publish recipe version", exact: true }).click();
 await expect(page.getByText("Cost readiness: MISSING", { exact: true })).toBeVisible();
 await expect(page.locator(".cost-incomplete")).toContainText("NGN 3,600.00");
 await expect(page.locator(".cost-summary-grid")).toHaveCount(0);
 const recipeUrl = page.url();
 await page.getByRole("link", { name: "Review price", exact: true }).click();
 await page.getByLabel("Quantity covered by this price").fill("1");
 await page.getByLabel("Total price (NGN)", { exact: true }).fill("100");
 await page.getByLabel("Price date", { exact: true }).fill("2020-01-01");
 await page.getByLabel("Source note", { exact: true }).fill("Fictional packaging quote");
 await page.getByRole("button", { name: "Review prices", exact: true }).click();
 await page.getByRole("button", { name: "Save estimated prices", exact: true }).click();
 await expect(page.getByRole("status")).toContainText("Your estimated prices have been saved");
 await page.goto(recipeUrl);
 await expect(page.getByText("Cost readiness: ESTIMATED", { exact: true })).toBeVisible();
 await expect(page.locator(".cost-summary-grid article").filter({ hasText: "Estimated batch cost" })).toContainText("NGN 4,800.00");
 await expect(page.locator(".cost-summary-grid article").filter({ hasText: "Estimated cost per portion" })).toContainText("NGN 400.00");
 await page.getByLabel("Cost date", { exact: true }).fill("2020-02-01");
 await page.getByRole("button", { name: "Update estimate", exact: true }).click();
 await expect(page).toHaveURL(/cost_date=2020-02-01/);
 await page.getByLabel("Target output (PCS)", { exact: true }).fill("24");
 await page.getByRole("button", { name: "Calculate quantities", exact: true }).click();
 await expect(page.locator(".cost-summary-grid article").filter({ hasText: "Estimated target cost" })).toContainText("NGN 9,600.00");
 await expect(page.getByLabel("Cost date", { exact: true })).toHaveValue("2020-02-01");
 await expect(page.getByText("Preparing your workspace…", { exact: true })).toHaveCount(0);
 await expect(page.locator(".recipe-cost-preview")).toBeVisible();
 await page.screenshot({ path: testInfo.outputPath("recipe-cost-desktop.png"), fullPage: true });
 await page.setViewportSize({ width: 375, height: 812 });
 await expect(page.locator(".recipe-cost-preview")).toBeVisible();
 expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
 await page.screenshot({ path: testInfo.outputPath("recipe-cost-mobile.png"), fullPage: true });
 expect(errors).toEqual([]);
});

test("finance can read estimated recipe costs without recipe-edit permission", async ({ page }) => {
 await login(page, "reader@example.test");
 await page.goto("/workspace/recipes");
 await page.getByRole("link", { name: "View Costing sample plate", exact: true }).click();
 await expect(page.getByText("Cost readiness: ESTIMATED", { exact: true })).toBeVisible();
 await expect(page.getByRole("link", { name: "Create new version", exact: true })).toHaveCount(0);
});
