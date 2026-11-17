import { test, expect, type Page } from "@playwright/test";

async function login(page: Page, email: string) {
  await page.goto("/login");
  await page.getByLabel("Email address").fill(email);
  await page.getByLabel("Password", { exact: true }).fill("TestPassword123!");
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
}

test("owner saves, resumes and completes restaurant setup", async ({ page }, testInfo) => {
  const nullInputWarnings: string[] = [];
  page.on("console", message => {
    if (message.type() === "error" && /value.*input.*null/i.test(message.text())) nullInputWarnings.push(message.text());
  });
  await login(page, "owner@example.test");
  await expect(page).toHaveURL(/\/onboarding$/);
  await page.getByLabel("Business name", { exact: true }).fill("Tangibles Test Restaurant");
  await page.getByLabel("Business concept").selectOption("QSR");
  await page.screenshot({ path: testInfo.outputPath("onboarding-desktop.png"), fullPage: true });
  await page.getByRole("button", { name: "Save & continue" }).click();
  await expect(page.getByRole("heading", { name: "Give your brand a home." })).toBeVisible();
  await page.getByLabel("Brand name", { exact: true }).fill("Tangibles");
  await page.getByLabel("First location name").fill("Lekki Outlet");
  await page.getByLabel("Address (optional)").fill("12 Example Street, Lekki");
  await page.getByRole("button", { name: "Save for later" }).click();
  await expect(page.getByText("Progress saved to your account.")).toBeVisible();
  await page.reload();
  await expect(page.locator('input[name="completed_organisation_id"]')).toHaveCount(0);
  await expect(page.getByLabel("Brand name", { exact: true })).toHaveValue("Tangibles");
  await expect(page.getByLabel("First location name")).toHaveValue("Lekki Outlet");
  await page.getByRole("button", { name: "Save & continue" }).click();
  await expect(page.getByRole("heading", { name: "Ready to make it yours?" })).toBeVisible();
  await page.getByRole("button", { name: "Create workspace" }).click();
  await expect(page).toHaveURL(/\/workspace\/setup\?organisation=.+&welcome=1/);
  await expect(page.getByText("Your restaurant workspace is ready. Welcome to ProfitPlate.")).toBeVisible();
  await expect(page.getByRole("heading", { name: "Tangibles Test Restaurant", exact: true })).toBeVisible();
  await expect(page.getByRole("table", { name: "Business locations" }).getByRole("rowheader", { name: "Lekki Outlet", exact: true })).toBeVisible();
  await expect(page.getByText("2 OF 7 STAGES READY")).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath("workspace-desktop.png"), fullPage: true });
  await page.getByRole("button", { name: "Collapse sidebar" }).click();
  await expect(page.getByRole("button", { name: "Expand sidebar" })).toBeVisible();
  await page.getByRole("button", { name: "Expand sidebar" }).click();
  await page.setViewportSize({ width: 375, height: 812 });
  await page.getByRole("button", { name: "Open navigation" }).click();
  await expect(page.getByRole("dialog", { name: "Workspace navigation" })).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(page.getByRole("button", { name: "Open navigation" })).toBeFocused();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.screenshot({ path: testInfo.outputPath("workspace-mobile.png"), fullPage: true });
  await page.goto("/workspace?organisation=00000000-0000-0000-0000-000000000099");
  await expect(page.getByRole("heading", { name: "This business isn’t available to your account." })).toBeVisible();
  expect(nullInputWarnings).toEqual([]);
});

test("another owner cannot see the first restaurant", async ({ page }) => {
  await login(page, "other@example.test");
  await expect(page).toHaveURL(/\/onboarding$/);
  await expect(page.getByLabel("Business name", { exact: true })).toHaveValue("");
  await expect(page.getByText("Tangibles Test Restaurant", { exact: true })).toHaveCount(0);
});

test("founder remains separate from restaurant onboarding", async ({ page }) => {
  await login(page, "founder@example.test");
  await expect(page).toHaveURL(/\/admin$/);
  await page.goto("/onboarding");
  await expect(page).toHaveURL(/\/admin$/);
});

test("signup validates passwords and explains email confirmation", async ({ page }) => {
  await page.goto("/signup");
  await page.getByLabel("Email address").fill("new@example.test");
  await page.getByLabel("Password", { exact: true }).fill("TestPassword123!");
  await page.getByLabel("Confirm password", { exact: true }).fill("Mismatch123!");
  await page.getByRole("button", { name: "Create account" }).click();
  await expect(page.getByText("Your passwords do not match.")).toBeVisible();
  await page.getByLabel("Confirm password", { exact: true }).fill("TestPassword123!");
  await page.getByRole("button", { name: "Create account" }).click();
  await expect(page.getByRole("heading", { name: "Check your inbox" })).toBeVisible();
});
