import { test, expect } from "@playwright/test";

test("homepage explains availability and its cost example responds to keyboard input", async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1 })).toContainText("restaurant margins");
  await expect(page.getByText("Built for owners, Finance, Procurement, Inventory and department teams.")).toBeVisible();
  await expect(page.getByTestId("preview-profit")).toHaveText("₦2,750");
  const slider = page.getByRole("slider", { name: "Ingredient cost per portion" });
  await slider.focus();
  await slider.press("ArrowRight");
  await expect(page.getByTestId("preview-profit")).toHaveText("₦2,650");
  await expect(page.getByTestId("preview-margin")).toHaveText("40.8%");
  await expect(page.getByText(/Fictional example. Packaging/)).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath("homepage-desktop.png") });
  await page.getByText("What can I use today?", { exact: true }).click();
  await expect(page.getByText(/Available now: business setup, team invitations/)).toBeVisible();
  await expect(page.locator(".marketing-capabilities article")).toHaveCount(6);
  const onboardingPack = page.getByRole("link", { name: "Download onboarding pack" });
  await expect(onboardingPack).toHaveAttribute("download", "");
  const templateResponse = await page.request.get(await onboardingPack.getAttribute("href") as string);
  expect(templateResponse.ok()).toBe(true);
  expect((await templateResponse.body()).subarray(0, 2).toString()).toBe("PK");
  await page.getByText("What is still coming?", {exact:true}).click();
  await expect(page.getByText(/Pricing and promotion simulators, combos/)).toBeVisible();
  await expect(page.getByLabel("Illustrative management report")).toContainText("Fictional sample");
  await page.getByRole("link", { name: "Create your workspace", exact: true }).first().click();
  await expect(page).toHaveURL(/\/signup$/);
});

test("mobile homepage navigation and layout work without horizontal overflow", async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto("/");
  await page.getByRole("button", { name: "Open menu" }).click();
  const nav = page.getByRole("navigation", { name: "Mobile navigation" });
  await expect(nav).toBeVisible();
  await nav.getByRole("link", { name: "How it works", exact: true }).click();
  await expect(nav).toHaveCount(0);
  await expect(page).toHaveURL(/#how-it-works$/);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.goto("/");
  await page.screenshot({ path: testInfo.outputPath("homepage-mobile.png"), fullPage: true });
});
