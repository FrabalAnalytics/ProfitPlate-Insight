import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import ts from "typescript";

const source = await readFile(new URL("../lib/onboarding.ts", import.meta.url), "utf8");
const dep=ts.transpileModule(await readFile(new URL("../lib/menu-categories.ts",import.meta.url),"utf8"),{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}}).outputText;
const expenseDep=ts.transpileModule(await readFile(new URL("../lib/expense-categories.ts",import.meta.url),"utf8"),{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}}).outputText;
const resolved=source.replace('"./expense-categories"',JSON.stringify(`data:text/javascript;base64,${Buffer.from(expenseDep).toString("base64")}`)).replace('"./menu-categories"',JSON.stringify(`data:text/javascript;base64,${Buffer.from(dep).toString("base64")}`));
const { outputText } = ts.transpileModule(resolved, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } });
const { normaliseSetup, emptySetup, validateSetup } = await import(`data:text/javascript;base64,${Buffer.from(outputText).toString("base64")}`);

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

test('reporting calendar must be explicit before completion, but incomplete drafts can be saved',()=>{
 const values={...emptySetup,business_name:'Restaurant',concept:'QSR',brand_name:'Brand',location_name:'Outlet',step:2};
 const incomplete=validateSetup(values,true);assert.ok(incomplete.reporting_week_start);assert.ok(incomplete.count_day);assert.ok(incomplete.count_cutoff);assert.deepEqual(validateSetup(values,false,true),{});
 assert.deepEqual(validateSetup({...values,reporting_week_start:'0',count_day:'6',count_cutoff:'00:00',sales_channels:'[{"code":"COUNTER","name":"Counter"}]',menu_categories:'[{"major":"FOOD","name":"Mains","is_active":true}]'},true),{});
 for(const cutoff of ['24:00','12:60','12:00:30','9:00'])assert.ok(validateSetup({...values,reporting_week_start:'3',count_day:'2',count_cutoff:cutoff},true).count_cutoff);
 assert.ok(validateSetup({...values,reporting_week_start:'7',count_day:'-1',count_cutoff:'23:30'},true).reporting_week_start);
});
