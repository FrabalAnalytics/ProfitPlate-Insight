import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { PGlite } from "./helpers/active-restaurant-db.mjs";

test("recipe reference estimates preserve composition, coverage and financial boundaries", async t => {
 const db = new PGlite();
 const ids = Array.from({ length: 8 }, (_, i) => `40000000-0000-0000-0000-${String(i + 1).padStart(12, "0")}`);
 const [owner, other, finance, procurement, scoped, operations, founder, ceo] = ids;
 const scalar = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
 const login = async id => { await db.exec("reset role"); await db.query("select set_config('request.jwt.claim.sub',$1,false)", [id]); await db.exec("set role authenticated"); };
 let org, kg, pcs, rice, chicken, box, child, parent;
 const line = (target, quantity, unit, kind = "ITEM") => ({ kind, target_id: target, quantity, uom_id: unit });
 const publish = (code, components, { recipe = null, type = "FINAL", yieldQty = "12", unit = pcs } = {}) => scalar("select public.publish_recipe_version($1,$2,$3,$4,$4,$5,'2020-01-01',$6,$7,'',$8::jsonb)", [org, recipe, randomUUID(), code, type, yieldQty, unit, JSON.stringify(components)]);
 const price = async (code, amount, date = "2020-01-01", unit = "KG") => {
  const data = JSON.stringify([{ material_code: code, quantity: "1", unit_code: unit, total_price: amount, price_date: date, source_note: "Fictional test price" }]);
  const reviewed = await scalar("select public.preview_material_reference_prices($1,$2::jsonb)", [org, data]);
  await scalar("select public.save_material_reference_prices($1,$2,'MANUAL',$3::jsonb,$4::jsonb)", [org, randomUUID(), data, JSON.stringify(reviewed)]);
 };
 const estimate = (version = parent, date = "2020-06-01", quantity = "12", tenant = org) => scalar("select public.recipe_reference_cost_estimate($1,$2,$3,$4)", [tenant, version, date, quantity]);
 try {
  await db.exec(`create role anon; create role authenticated; create schema auth;
   create table auth.users(id uuid primary key,email_confirmed_at timestamptz);
   create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
   grant usage on schema public,auth to authenticated,anon; grant execute on function auth.uid() to authenticated,anon;`);
  for (const id of ids) await db.query("insert into auth.users values($1,now())", [id]);
  for (const name of ["202611140001_initial_schema.sql", "202611140002_platform_admin_access.sql", "202611140003_restaurant_onboarding.sql", "202611140004_materials_and_suppliers.sql", "202611140005_versioned_recipes.sql", "202611140006_material_reference_prices.sql", "202611140007_recipe_reference_costs.sql"])
   await db.exec(await readFile(new URL(`../supabase/migrations/${name}`, import.meta.url), "utf8"));
  for (const id of [other, owner]) {
   await login(id); await db.query("select public.save_restaurant_setup('Restaurant','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");
   const result = await scalar("select public.complete_restaurant_setup()"); if (id === owner) org = result;
  }
  kg = await scalar("select id from public.units_of_measure where code='KG'");
  pcs = await scalar("select id from public.units_of_measure where code='PCS'");
  for (const [code, unit, type] of [["RICE", kg, "RAW"], ["CHICKEN", kg, "RAW"], ["BOX", pcs, "PACKAGING"]]) {
   const id = await scalar("select public.save_catalogue_material($1,null,$2,$2,$3,'',$4,true,true)", [org, code, type, unit]);
   if (code === "RICE") rice = id; else if (code === "CHICKEN") chicken = id; else box = id;
  }
  child = await publish("BASE", [line(rice, "8", kg)], { type: "SUB_RECIPE", yieldQty: "10", unit: kg });
  parent = await publish("PLATE", [line(child, "1", kg, "RECIPE"), line(rice, "0.2", kg), line(chicken, "1", kg), line(box, "12", pcs)]);

  await t.test("unpriced recipes have null totals, and partially priced recipes expose only a labelled subtotal", async () => {
   const missing = await estimate(); assert.equal(missing.cost_state, "MISSING"); assert.equal(missing.missing_count, 3);
   assert.equal(missing.batch_cost, null); assert.equal(missing.known_subtotal, null); assert.equal(missing.cost_per_output_unit, null);
   await price("RICE", "1800");
   const partial = await estimate(); assert.equal(partial.missing_count, 2); assert.equal(partial.priced_count, 1);
   assert.equal(partial.known_subtotal, "1800.000000000000"); assert.equal(partial.batch_cost, null); assert.equal(partial.target_cost, null);
  });
  await t.test("nested ingredients aggregate exactly and direct packaging is counted once", async () => {
   await price("CHICKEN", "6000"); await price("BOX", "100", "2020-01-01", "PCS");
   const result = await estimate(parent, "2020-06-01", "24");
   assert.equal(result.cost_state, "ESTIMATED"); assert.equal(result.batch_cost, "9000.000000000000");
   assert.equal(result.cost_per_output_unit, "750.000000000000"); assert.equal(result.target_cost, "18000.000000000000");
   assert.equal(result.lines.find(line => line.item_id === rice).quantity, "1.000000000000");
   assert.equal(result.lines.find(line => line.item_id === box).batch_cost, "1200.000000000000");
   assert.ok(result.lines.every(line => line.price_id && line.price_version === 1));
   assert.equal((await estimate(child)).yield_unit_code, "KG");
  });
  await t.test("new child versions do not change the parent's saved composition", async () => {
   const childRecipe = await scalar("select recipe_id from public.recipe_versions where id=$1", [child]);
   await publish("BASE", [line(rice, "9", kg)], { recipe: childRecipe, type: "SUB_RECIPE", yieldQty: "10", unit: kg });
   assert.equal((await estimate()).batch_cost, "9000.000000000000");
  });
  await t.test("cost date filters prices and same-date corrections are explicit live estimates", async () => {
   await price("RICE", "3000", "2021-01-01");
   assert.equal((await estimate()).batch_cost, "9000.000000000000");
   assert.equal((await estimate(parent, "2021-01-01")).batch_cost, "10200.000000000000");
   await price("RICE", "2000");
   const corrected = await estimate(); assert.equal(corrected.batch_cost, "9200.000000000000");
   assert.equal(corrected.lines.find(line => line.item_id === rice).price_version, 3);
  });
  await t.test("unsupported dates, outputs and tiny costs fail without substituting zero", async () => {
   for (const date of ["2019-01-01", "2999-01-01", null]) await assert.rejects(estimate(parent, date), e => e.code === "22023");
   for (const qty of ["0", "-1", "0.0000001", null]) await assert.rejects(estimate(parent, "2020-01-01", qty), e => e.code === "22023");
   const tiny = await publish("TINY", [line(rice, "0.000001", kg)], { yieldQty: "99999999999999" });
   await assert.rejects(estimate(tiny), e => e.code === "22023" && /precision/.test(e.message));
   assert.equal(await scalar("select count(*)::int from public.purchases"), 0);
   assert.equal(await scalar("select count(*)::int from public.inventory_movements"), 0);
  });
  await t.test("currency changes never silently reuse a price in a different currency", async () => {
   await db.exec("reset role"); await db.query("update public.organisations set currency_code='USD' where id=$1", [org]); await login(owner);
   const result = await estimate(); assert.equal(result.cost_state, "MISSING"); assert.equal(result.missing_count, 3);
   assert.ok(result.lines.every(line => line.missing_reason === "CURRENCY_MISMATCH" && line.unit_cost === null));
   await db.exec("reset role"); await db.query("update public.organisations set currency_code='NGN' where id=$1", [org]);
  });
  await t.test("read-only finance and CEO can cost; scoped, operational and unrelated accounts cannot", async () => {
   await db.exec("reset role");
   const location = await scalar("select id from public.locations where organisation_id=$1 limit 1", [org]);
   for (const [id, role, scope] of [[finance, "finance", null], [procurement, "procurement", null], [scoped, "finance", location], [operations, "operations", null], [ceo, "ceo", null]]) {
    const membership = await scalar("insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id", [org, id]);
    await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,$3,$4)", [org, membership, role, scope]);
   }
   await db.query("insert into private.platform_admins(user_id) values($1)", [founder]);
   for (const id of [finance, procurement, ceo]) { await login(id); assert.equal((await estimate()).cost_state, "ESTIMATED"); }
   for (const id of [scoped, operations, other, founder]) { await login(id); await assert.rejects(estimate(), e => e.code === "42501"); }
   await login(owner); await assert.rejects(estimate(parent, "2020-01-01", "12", randomUUID()), e => e.code === "42501");
   await db.exec("reset role; set role anon"); await assert.rejects(estimate(), e => e.code === "42501");
  });
 } finally { await db.close(); }
});
