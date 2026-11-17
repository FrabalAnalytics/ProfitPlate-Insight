import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import ts from "typescript";

const source = await readFile(new URL("../lib/onboarding.ts", import.meta.url), "utf8");
const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } });
const { normaliseSetup, emptySetup } = await import(`data:text/javascript;base64,${Buffer.from(outputText).toString("base64")}`);

test("saved draft metadata never enters editable form state", () => {
  const result = normaliseSetup({ ...emptySetup, business_name: "Demo Restaurant", step: 2, completed_organisation_id: null, user_id: "private-metadata", id: "draft-id" });
  assert.deepEqual(Object.keys(result).sort(), Object.keys(emptySetup).sort());
  assert.equal(result.business_name, "Demo Restaurant");
  assert.equal(result.step, 2);
  assert.equal("completed_organisation_id" in result, false);
  assert.ok(Object.values(result).every(value => value !== null && value !== undefined));
});

test("nullable or malformed draft fields become safe form values", () => {
  const result = normaliseSetup({ business_name: null, address: null, timezone: null, step: 99, country_code: 42 });
  assert.deepEqual(result, emptySetup);
  assert.deepEqual(normaliseSetup(null), emptySetup);
  assert.deepEqual(normaliseSetup([]), emptySetup);
});
