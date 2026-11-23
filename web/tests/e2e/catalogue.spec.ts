import {clickNavigation} from './navigation';
import { test, expect, type Page } from "@playwright/test";

async function openCatalogue(page: Page, email = "catalogue@example.test") {
  await page.goto("/login");
  await page.getByLabel("Email address").fill(email);
  await page.getByLabel("Password", { exact: true }).fill("TestPassword123!");
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await expect(page).toHaveURL(/\/workspace$/);
  if(email === 'reader@example.test')await page.goto('/workspace/materials');
  else await clickNavigation(page,'Materials & suppliers');
}

test("material lifecycle, duplicate codes and effective-dated package conversions", async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 1000 });
  await openCatalogue(page);
  await page.getByRole("link", { name: "Add material", exact: true }).click();
  await page.getByLabel("Material code").fill("RICE-DEMO");
  await page.getByLabel("Material name").fill("Rice");
  await page.getByLabel("Category (optional)").fill("Grains");
  await page.getByRole("button", { name: "Save material", exact: true }).click();
  await expect(page.getByText("Your material has been saved.")).toBeVisible();
  await expect(page.getByRole("row").filter({ has: page.getByRole("link", { name: "Edit Rice", exact: true }) }).getByRole("cell", { name: "Missing price", exact: true })).toBeVisible();
  await page.getByRole("link", { name: "Edit Rice", exact: true }).click();
  await expect(page.getByLabel("Material code")).toBeDisabled();
  await expect(page.getByLabel("Base unit", { exact: true })).toBeEnabled();
  await page.getByLabel("Material name").fill("Premium Rice");
  await page.getByLabel("Active material", { exact: true }).uncheck();
  await page.getByRole("button", { name: "Save material", exact: true }).click();
  await expect(page.getByRole("cell", { name: "Inactive", exact: true })).toBeVisible();
  await page.getByRole("link", { name: "Edit Premium Rice", exact: true }).click();
  await page.getByLabel("Active material", { exact: true }).check();
  await page.getByRole("button", { name: "Save material", exact: true }).click();
  await expect(page).toHaveURL(/saved=material/);
  const savedUrl = page.url();
  await page.getByRole("link", { name: "Add material", exact: true }).click();
  await page.getByLabel("Material code").fill("RICE-DEMO");
  await page.getByLabel("Material name").fill("Duplicate rice");
  await page.getByRole("button", { name: "Save material", exact: true }).click();
  await expect(page.getByRole("alert").filter({ hasText: "This code is already in use" })).toBeVisible();
  await page.goto(savedUrl);
  await expect(page.getByRole("link", { name: "Manage units for Premium Rice" })).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath("materials-desktop.png") });
  await page.getByRole("link", { name: "Manage units for Premium Rice" }).click();
  await page.getByRole("link", { name: "Add conversion", exact: true }).click();
  await page.getByLabel("Source unit").selectOption({ label: "Bag (BAG)" });
  await page.getByLabel("Quantity in KG", { exact: true }).fill("50");
  await page.getByLabel("Effective from", { exact: true }).fill("2026-11-14");
  await page.getByRole("button", { name: "Save conversion", exact: true }).click();
  await expect(page.getByRole("table", {name:"Saved material conversions"}).getByRole("row").filter({has:page.getByRole("cell",{name:"50",exact:true})})).toContainText("1 BAG");
  await page.getByRole("link", { name: "Add conversion", exact: true }).click();
  await page.getByLabel("Quantity in KG", { exact: true }).fill("40");
  await page.getByLabel("Effective from", { exact: true }).fill("2026-11-14");
  await page.getByRole("button", { name: "Save conversion", exact: true }).click();
  await expect(page.getByRole("alert").filter({ hasText: "A different conversion already exists" })).toBeVisible();
  await page.getByLabel("Effective from", { exact: true }).fill("2026-12-01");
  await page.getByRole("button", { name: "Save conversion", exact: true }).click();
  await expect(page.getByRole("table", {name:"Saved material conversions"}).getByRole("row").filter({has:page.getByRole("cell",{name:"40",exact:true})})).toContainText("1 BAG");
  await expect(page.getByRole("table", {name:"Saved material conversions"}).getByRole("row").filter({has:page.getByRole("cell",{name:"50",exact:true})})).toContainText("1 BAG");
  await page.screenshot({ path: testInfo.outputPath("conversions-desktop.png"), fullPage: true });
});

test("supplier details preserve leading zeros in responsive tables", async ({ page }, testInfo) => {
  await openCatalogue(page);
  await page.getByRole("link", { name: "Suppliers", exact: true }).click();
  await page.getByRole("link", { name: "Add supplier", exact: true }).click();
  await page.getByLabel("Supplier code").fill("SUP-TEST");
  await page.getByLabel("Supplier name").fill("Sample Foods");
  await page.getByLabel("Email (optional)").fill("hello@example.test");
  await page.getByLabel("Phone (optional)").fill("08000000002");
  await page.getByLabel("Address (optional)").fill("12 Market Road, Lagos");
  await page.getByRole("button", { name: "Save supplier", exact: true }).click();
  await expect(page.getByText("Your supplier has been saved.")).toBeVisible();
  await expect(page.getByText("08000000002", { exact: true }).first()).toBeVisible();
  await page.setViewportSize({ width: 375, height: 812 });
  await expect(page.getByRole("rowheader", { name: "Sample Foods SUP-TEST", exact: true })).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.screenshot({ path: testInfo.outputPath("suppliers-mobile.png"), fullPage: true });
});

test("read-only members can search and paginate but cannot open an editor", async ({ page }) => {
  await openCatalogue(page, "reader@example.test");
  await expect(page.getByText(/You have read-only catalogue access/)).toBeVisible();
  await expect(page.getByRole("link", { name: "Add material", exact: true })).toHaveCount(0);
  await page.getByRole("link", { name: "Next", exact: true }).click();
  await expect(page).toHaveURL(/page=2/);
  await page.getByLabel("Search materials", { exact: true }).fill("Ingredient 26");
  await page.getByRole("button", { name: "Search", exact: true }).click();
  await expect(page.getByRole("rowheader", { name: "Ingredient 26 SAMPLE26", exact: true })).toBeVisible();
  await expect(page.getByRole("rowheader", { name: "Ingredient 25 SAMPLE25", exact: true })).toHaveCount(0);
  await page.goto(`${page.url()}&new=1`);
  await expect(page.getByRole("heading", { name: "Add material", exact: true })).toHaveCount(0);
});


test("restaurant-owned units can be created and used without overwriting definitions", async ({page},testInfo)=>{
 await openCatalogue(page);
 await page.getByRole("link",{name:"Units & conversions",exact:true}).click();
 await page.locator("summary").filter({hasText:/^Add a unit$/}).click();
 await page.getByLabel("Unit code",{exact:true}).fill("DOZEN_UI");
 await page.getByLabel("Unit name",{exact:true}).fill("Dozen UI");
 await page.getByLabel("Measurement type").selectOption("COUNT");
 await page.getByLabel("1 new unit equals how many PCS?").fill("12");
 await page.getByRole("button",{name:"Add unit",exact:true}).click();
 await expect(page.getByRole("status").filter({hasText:"Unit added"})).toBeVisible();
 await expect(page.getByRole("table",{name:"Restaurant units"}).getByRole("row").filter({hasText:"DOZEN_UI"})).toContainText("12 PCS");
 await page.locator("summary").filter({hasText:/^Add a unit$/}).click();
 await page.getByLabel("Unit code",{exact:true}).fill("DOZEN_UI");await page.getByLabel("Unit name",{exact:true}).fill("Changed dozen");await page.getByLabel("Measurement type").selectOption("COUNT");await page.getByLabel("1 new unit equals how many PCS?").fill("24");await page.getByRole("button",{name:"Add unit",exact:true}).click();
 await expect(page.getByRole("alert").filter({hasText:"already exists"})).toBeVisible();await expect(page.getByLabel("Unit name",{exact:true})).toHaveValue("Changed dozen");
 await page.getByRole("link",{name:"Materials",exact:true}).click();await page.getByRole("link",{name:"Add material",exact:true}).click();await page.getByLabel("Material code").fill("CUSTOM-UOM-UI");await page.getByLabel("Material name").fill("Custom unit material");await page.getByLabel("Base unit",{exact:true}).selectOption({label:"Dozen UI (DOZEN_UI)"});await page.getByRole("button",{name:"Save material",exact:true}).click();
 await expect(page.getByRole("row").filter({has:page.getByRole("link",{name:"Edit Custom unit material",exact:true})})).toContainText("DOZEN_UI");
 await page.screenshot({path:testInfo.outputPath("custom-unit-material.png"),fullPage:true});
});

test("unused materials support correction and confirmed deletion while linked records stay protected",async({page},testInfo)=>{
 await openCatalogue(page);await page.getByRole("link",{name:"Add material",exact:true}).click();await page.getByLabel("Material code").fill("CORRECT-UOM-UI");await page.getByLabel("Material name").fill("Correct unit UI");await page.getByRole("button",{name:"Save material",exact:true}).click();
 await page.getByRole("link",{name:"Edit Correct unit UI",exact:true}).click();await expect(page.getByLabel("Base unit",{exact:true})).toBeEnabled();await page.getByLabel("Base unit",{exact:true}).selectOption({label:"Gram (G)"});await page.getByRole("button",{name:"Save material",exact:true}).click();
 await page.getByRole("link",{name:"Manage units for Correct unit UI",exact:true}).click();await page.getByRole("link",{name:"Add conversion",exact:true}).click();await page.getByLabel("Source unit").selectOption({label:"Bag (BAG)"});await page.getByLabel("Quantity in G",{exact:true}).fill("1000");await page.getByRole("button",{name:"Save conversion",exact:true}).click();
 await page.getByRole("link",{name:/Choose another material/}).click();await page.getByRole("searchbox",{name:"Search materials",exact:true}).fill("Correct unit UI");await page.getByRole("button",{name:"Search",exact:true}).click();await page.getByRole("link",{name:"Edit Correct unit UI",exact:true}).click();await expect(page.getByLabel("Base unit",{exact:true})).toBeDisabled();await expect(page.locator("summary").filter({hasText:/^Delete unused material$/})).toHaveCount(0);await expect(page.getByRole("status").filter({hasText:"Linked recipes"})).toBeVisible();
 await page.getByRole("link",{name:"Close editor",exact:true}).click();await page.getByRole("link",{name:"Add material",exact:true}).click();await page.getByLabel("Material code").fill("DELETE-UOM-UI");await page.getByLabel("Material name").fill("Delete unit UI");await page.getByRole("button",{name:"Save material",exact:true}).click();await page.getByRole("link",{name:"Edit Delete unit UI",exact:true}).click();await page.locator("summary").filter({hasText:/^Delete unused material$/}).click();await page.getByLabel("Type DELETE-UOM-UI to confirm").fill("WRONG");await page.getByLabel("I want to permanently delete this unused material.").check();await page.getByRole("button",{name:"Delete material",exact:true}).click();await expect(page.getByRole("alert").filter({hasText:"Enter the material code"})).toBeVisible();
 await page.getByLabel("Type DELETE-UOM-UI to confirm").fill("DELETE-UOM-UI");await page.getByLabel("I want to permanently delete this unused material.").check();await page.getByRole("button",{name:"Delete material",exact:true}).click();await expect(page.getByRole("status").filter({hasText:"Unused material deleted"})).toBeVisible();
 await page.setViewportSize({width:390,height:844});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await page.screenshot({path:testInfo.outputPath("catalogue-corrections-mobile.png"),fullPage:true});
});
