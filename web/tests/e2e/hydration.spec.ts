import { test, expect } from "@playwright/test";

test("signup remains interactive when an extension adds a body attribute", async ({ page }) => {
  const hydrationWarnings: string[] = [];
  page.on("console", message => {
    if (message.type() === "error" && /hydrat|didn't match/i.test(message.text())) {
      hydrationWarnings.push(message.text());
    }
  });
  await page.addInitScript(() => {
    const observer = new MutationObserver(() => {
      if (document.body) {
        document.body.setAttribute("location", "localhost");
        observer.disconnect();
      }
    });
    observer.observe(document, { childList: true, subtree: true });
  });
  await page.goto("/signup");
  await page.getByRole("button", { name: "Show password" }).click();
  await expect(page.getByLabel("Password", { exact: true })).toHaveAttribute("type", "text");
  await expect(page.locator("body")).toHaveAttribute("location", "localhost");
  expect(hydrationWarnings).toEqual([]);
});
