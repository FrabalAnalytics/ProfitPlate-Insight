import {clickNavigation} from './navigation';
import { test, expect, type Page } from "@playwright/test";

async function openMenus(page: Page, email = "catalogue@example.test") {
 await page.goto("/login"); await page.getByLabel("Email address").fill(email);
 await page.getByLabel("Password", { exact: true }).fill("TestPassword123!");
 await page.getByRole("button", { name: "Sign in", exact: true }).click();
 await clickNavigation(page,'Menu & prices');
 await expect(page).toHaveURL(/\/workspace\/menus\?/);
}
async function addPrice(page: Page, { value = "1500", setting = "NONE", rate = "", channel = "DINE_IN" } = {}) {
 await page.getByRole("link", { name: "Add selling price", exact: true }).click();
 await page.getByLabel("Price sales channel", { exact: true }).selectOption(channel);
 await page.getByLabel("Selling price (NGN)", { exact: true }).fill(value);
 await page.getByLabel("Selling price tax setting", { exact: true }).selectOption(setting);
 if (setting !== "NONE") await page.getByLabel("Tax rate (%)", { exact: true }).fill(rate);
 await page.getByLabel("Price effective from", { exact: true }).fill("2020-01-01");
 await page.getByLabel("Price source / change note", { exact: true }).fill("Fictional menu test price");
 await page.getByRole("button", { name: "Save selling price", exact: true }).click();
 await expect(page.getByRole("status").filter({ hasText: "Selling price saved" })).toContainText("Selling price saved");
}
async function createMenu(page: Page, code: string, name: string, recipe: string) {
 await page.getByRole("link", { name: "Create menu item", exact: true }).click();
 await page.getByLabel("Menu code", { exact: true }).fill(code);
 await page.getByLabel("Menu item name", { exact: true }).fill(name);
 await page.getByLabel("Category (optional)", { exact: true }).fill("Mains");
 await page.getByLabel("Search saved final recipes", { exact: true }).fill(recipe);
 await page.getByLabel("Saved recipe version", { exact: true }).selectOption({ label: recipe === "Menu cost recipe" ? "Menu cost recipe · v1 (MENU-RECIPE)" : "Menu unpriced recipe · v1 (MENU-MISSING-RECIPE)" });
 await page.getByLabel("Menu version effective from", { exact: true }).fill("2020-01-01");
 await page.getByRole("button", { name: "Publish menu version", exact: true }).click();
 await expect(page.getByRole("status").filter({ hasText: "Menu version published" })).toContainText("Menu version published");
}

test("menu prices calculate declared tax and preserve recipe bindings, versions and negative food margins", async ({ page }, testInfo) => {
 await page.setViewportSize({ width: 1440, height: 1000 });
 const errors: string[] = []; page.on("pageerror", error => errors.push(error.message));
 await openMenus(page); await createMenu(page, "MENU-PLATE", "Menu test plate", "Menu cost recipe");
 await expect(page.getByText(/No selling price is available for this location/)).toBeVisible();
 await expect(page.locator(".menu-margin-cards article").filter({ hasText: "Estimated food margin" })).toContainText("Unavailable");
 await addPrice(page);
 await expect(page.locator(".menu-margin-cards article").filter({ has: page.getByText("Net selling revenue", { exact: true }) })).toContainText("NGN 1,500.00");
 await expect(page.locator(".menu-margin-cards article").filter({ hasText: "Estimated food margin" })).toContainText("NGN 600.00");
 await expect(page.locator(".menu-margin-cards article").filter({ hasText: "Estimated food margin" })).toContainText("40% of net selling revenue");
 await addPrice(page, { value: "1650", setting: "INCLUSIVE", rate: "10", channel: "TAKEAWAY" });
 await expect(page.locator(".menu-tax-breakdown")).toContainText("Customer total: NGN 1,650.00");
 await expect(page.locator(".menu-tax-breakdown")).toContainText("Declared tax: NGN 150.00");
 await expect(page.locator(".menu-margin-cards article").filter({ has: page.getByText("Net selling revenue", { exact: true }) })).toContainText("NGN 1,500.00");
 await page.getByRole("link", { name: "Create menu version", exact: true }).click();
 await expect(page.getByLabel("Menu code", { exact: true })).toBeDisabled();
 await page.getByLabel("Recipe output per menu item (PCS)", { exact: true }).fill("2");
 await page.getByLabel("Menu version effective from", { exact: true }).fill("2020-01-01");
 await page.getByRole("button", { name: "Publish menu version", exact: true }).click();
 await expect(page.getByRole("status").filter({ hasText: "Menu version published" })).toContainText("Menu version published");
 await expect(page.locator(".menu-negative")).toContainText("NGN -300.00");
 await page.getByLabel("Saved menu version", { exact: true }).selectOption({ label: "Version 1 · 2020-01-01" });
 await page.getByRole("button", { name: "View version", exact: true }).click();
 await expect(page.locator(".menu-margin-cards article").filter({ hasText: "Estimated food margin" })).toContainText("NGN 600.00");
 await expect(page.getByText("Preparing your workspace…", { exact: true })).toHaveCount(0);
 await expect(page.locator(".menu-margin-preview")).toBeVisible();
 await page.screenshot({ path: testInfo.outputPath("menu-margins-desktop.png"), fullPage: true });
 await page.setViewportSize({ width: 375, height: 812 });
 await expect(page.locator(".menu-margin-preview")).toBeVisible();
 expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
 await page.screenshot({ path: testInfo.outputPath("menu-margins-mobile.png"), fullPage: true });
 await page.getByRole("button", { name: "Deactivate menu item", exact: true }).click();
 await expect(page.getByText(/This menu item is inactive/)).toBeVisible();
 await page.getByRole("button", { name: "Reactivate menu item", exact: true }).click();
 await expect(page.locator(".menu-margin-preview")).toBeVisible();
 expect(errors).toEqual([]);
});

test("unpriced recipe components prevent a complete menu margin and link to the missing material", async ({ page }) => {
 await openMenus(page); await createMenu(page, "MENU-INCOMPLETE", "Incomplete menu plate", "Menu unpriced recipe");
 await addPrice(page);
 await expect(page.getByText(/Recipe cost incomplete: 1 material needs/)).toBeVisible();
 await expect(page.locator(".menu-margin-cards article").filter({ hasText: "Estimated ingredient & packaging cost" })).toContainText("Incomplete");
 await expect(page.locator(".menu-margin-cards article").filter({ hasText: "Estimated food margin" })).toContainText("Unavailable");
 await expect(page.getByRole("link", { name: /Menu missing ingredient.*Review reference price/ })).toBeVisible();
 await page.getByRole("link", { name: /Menu missing ingredient.*Review reference price/ }).click();
 await page.getByLabel("Quantity covered by this price").fill("1");
 await page.getByLabel("Total price (NGN)", { exact: true }).fill("900");
 await page.getByLabel("Price date", { exact: true }).fill("2020-01-01");
 await page.getByLabel("Source note", { exact: true }).fill("Fictional missing-menu-price test");
 await page.getByRole("button", { name: "Review prices", exact: true }).click();
 await page.getByRole("button", { name: "Save estimated prices", exact: true }).click();
 await expect(page.getByRole("status")).toContainText("Your estimated prices have been saved");
 await clickNavigation(page,'Menu & prices');
 await page.getByRole("link", { name: "View menu item Incomplete menu plate", exact: true }).click();
 await expect(page.locator(".menu-margin-cards article").filter({ hasText: "Estimated food margin" })).toContainText("NGN 600.00");
});

test("finance can inspect menu food margins but cannot publish menu versions or selling prices", async ({ page }) => {
 await openMenus(page, "reader@example.test");
 await expect(page.getByText(/You have read-only menu access/)).toBeVisible();
 await expect(page.getByRole("link", { name: "Create menu item", exact: true })).toHaveCount(0);
 await page.getByRole("link", { name: "View menu item Menu test plate", exact: true }).click();
 await expect(page.locator(".menu-margin-preview")).toBeVisible();
 await expect(page.getByRole("link", { name: "Add selling price", exact: true })).toHaveCount(0);
 await expect(page.getByRole("link", { name: "Create menu version", exact: true })).toHaveCount(0);
 await page.goto(`${page.url()}&price=1&edit=1`);
 await expect(page.getByRole("button", { name: "Save selling price", exact: true })).toHaveCount(0);
 await expect(page.getByRole("button", { name: "Publish menu version", exact: true })).toHaveCount(0);
});
