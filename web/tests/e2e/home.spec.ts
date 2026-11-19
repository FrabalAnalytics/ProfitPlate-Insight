import { test, expect } from "@playwright/test";

test("homepage explains availability and its cost example responds to keyboard input", async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1 })).toContainText("restaurant margins");
  await expect(page.getByText("Built for one outlet or a restaurant group.")).toBeVisible();
  await expect(page.getByTestId("preview-profit")).toHaveText("₦2,750");
  const slider = page.getByRole("slider", { name: "Ingredient cost per portion" });
  await slider.focus();
  await slider.press("ArrowRight");
  await expect(page.getByTestId("preview-profit")).toHaveText("₦2,650");
  await expect(page.getByTestId("preview-margin")).toHaveText("40.8%");
  await expect(page.getByText(/Fictional example. Packaging/)).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath("homepage-desktop.png") });
  await page.getByText("Why are my food costs rising?", { exact: true }).click();
  await expect(page.getByText(/See which ingredient prices changed/)).toBeVisible();
  await expect(page.locator(".marketing-capabilities article")).toHaveCount(6);
  await page.getByText("Planning a pilot? Start with sample data", {exact:true}).click();
  const onboardingPack = page.getByRole("link", { name: "Download test data pack" });
  await expect(onboardingPack).toHaveAttribute("download", "");
  await expect(onboardingPack).toHaveAttribute("href", "/templates/profitplate-complete-test-data-2026-11-19.zip");
  const templateResponse = await page.request.get(await onboardingPack.getAttribute("href") as string);
  expect(templateResponse.ok()).toBe(true);
  expect((await templateResponse.body()).subarray(0, 2).toString()).toBe("PK");
  await page.getByText("How can I make waste easier to track?", {exact:true}).click();
  await expect(page.getByText(/record the loss without approval/)).toBeVisible();
  const tabs=page.getByRole('tablist',{name:'Explore team workspaces'});await tabs.getByRole('tab',{name:'Kitchen / Bar',exact:true}).click();await expect(page.getByRole('tabpanel')).toContainText('Waste needs no approval.');await expect(page.getByRole('tabpanel')).toContainText('Hello, Ada.');await tabs.getByRole('tab',{name:'Kitchen / Bar',exact:true}).press('ArrowRight');await expect(tabs.getByRole('tab',{name:'Finance',exact:true})).toHaveAttribute('aria-selected','true');await expect(page.getByRole('tabpanel')).toContainText('Management reports');await tabs.getByRole('tab',{name:'Finance',exact:true}).press('Home');await expect(tabs.getByRole('tab',{name:'Owner / CEO',exact:true})).toHaveAttribute('aria-selected','true');
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
  await page.getByRole('tab',{name:'Inventory',exact:true}).click();await expect(page.getByRole('tabpanel')).toContainText('Needs Attention');expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);await page.evaluate(()=>window.scrollTo(0,0));
  await page.screenshot({ path: testInfo.outputPath("homepage-mobile.png"), fullPage: true });
});
