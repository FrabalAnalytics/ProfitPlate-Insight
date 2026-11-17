import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { PGlite } from "@electric-sql/pglite";

test("optional material reference estimates are exact, isolated and append-only", async t => {
 const db = new PGlite();
 const ids = Array.from({ length: 7 }, (_, i) => `30000000-0000-0000-0000-${String(i + 1).padStart(12, "0")}`);
 const [owner, other, procurement, finance, scoped, founder, operations] = ids;
 const rows = async (sql, params = []) => (await db.query(sql, params)).rows;
 const scalar = async (sql, params = []) => Object.values((await rows(sql, params))[0])[0];
 const login = async id => { await db.exec("reset role"); await db.query("select set_config('request.jwt.claim.sub',$1,false)", [id]); await db.exec("set role authenticated"); };
 let org, otherOrg, item, kg, bag, g;
 const input = (extra = {}) => ({ material_code: "RICE", quantity: "1", unit_code: "BAG", total_price: "90000", price_date: "2020-02-01", source_note: "Last supplier invoice", ...extra });
 const preview = (list, tenant = org) => scalar("select public.preview_material_reference_prices($1,$2::jsonb)", [tenant, JSON.stringify(list)]);
 const save = async (list, { request = randomUUID(), reviewed, tenant = org, source = "MANUAL" } = {}) => scalar("select public.save_material_reference_prices($1,$2,$3,$4::jsonb,$5::jsonb)", [tenant, request, source, JSON.stringify(list), JSON.stringify(reviewed ?? await preview(list, tenant))]);
 const list = (id = null) => scalar("select public.list_material_reference_prices($1,'',1,$2)", [org, id]);
 try {
  await db.exec(`create role anon; create role authenticated; create schema auth;
   create table auth.users(id uuid primary key,email_confirmed_at timestamptz);
   create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
   grant usage on schema public,auth to authenticated,anon; grant execute on function auth.uid() to authenticated,anon;`);
  for (const id of ids) await db.query("insert into auth.users values($1,now())", [id]);
  for (const file of ["202611140001_initial_schema.sql", "202611140002_platform_admin_access.sql", "202611140003_restaurant_onboarding.sql", "202611140004_materials_and_suppliers.sql", "202611140005_versioned_recipes.sql", "202611140006_material_reference_prices.sql"])
   await db.exec(await readFile(new URL(`../supabase/migrations/${file}`, import.meta.url), "utf8"));
  for (const id of [other, owner]) {
   await login(id); await db.query("select public.save_restaurant_setup('Restaurant','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");
   const created = await scalar("select public.complete_restaurant_setup()"); if (id === owner) org = created; else otherOrg = created;
  }
  const units = await rows("select id,code from public.units_of_measure");
  [kg, bag, g] = ["KG", "BAG", "G"].map(code => units.find(u => u.code === code).id);
  item = await scalar("select public.save_catalogue_material($1,null,'RICE','Rice','RAW','',$2,true,true)", [org, kg]);
  await scalar("select public.save_catalogue_material($1,null,'FLOUR','Flour','RAW','',$2,true,true)", [org, kg]);

  await t.test("materials can remain unpriced without invented zero costs", async () => {
   const data = await list(); assert.equal(data.active_materials, 2); assert.equal(data.priced_materials, 0);
   assert.ok(data.items.every(item => item.latest === null));
   await assert.rejects(preview([input()]), e => e.code === "22023" && /package conversion/.test(e.message));
  });
  await t.test("dated package conversions and standard units normalize exactly", async () => {
   await scalar("select public.save_material_conversion($1,$2,$3,50,'2020-01-01')", [org, item, bag]);
   await scalar("select public.save_material_conversion($1,$2,$3,40,'2021-01-01')", [org, item, bag]);
   const prepared = (await preview([input()]))[0];
   assert.equal(prepared.base_quantity, "50.000000000000"); assert.equal(prepared.cost_per_base_unit, "1800.000000000000");
   assert.equal(prepared.currency_code, "NGN"); assert.equal(prepared.cost_state, "ESTIMATED");
   assert.equal((await preview([input({ unit_code: "G", quantity: "250", total_price: "450" })]))[0].cost_per_base_unit, "1800.000000000000");
   assert.equal((await preview([input({ price_date: "2021-02-01" })]))[0].cost_per_base_unit, "2250.000000000000");
  });
  await t.test("review creates no records; commits are retry-safe and audited", async () => {
   const request = randomUUID(), data = [input()], prepared = await preview(data);
   assert.equal(await scalar("select count(*)::int from public.material_reference_prices"), 0);
   const batch = await save(data, { request, reviewed: prepared });
   assert.equal(await save(data, { request, reviewed: prepared }), batch);
   await assert.rejects(save([input({ total_price: "80000" })], { request }), e => e.code === "22023");
   assert.equal(await scalar("select count(*)::int from public.material_reference_prices"), 1);
   assert.equal(await scalar("select count(*)::int from public.audit_events where event_type='reference_prices.saved'"), 1);
   assert.equal((await list()).priced_materials, 1);
   assert.deepEqual(await scalar("select public.material_reference_price_coverage($1,$2::uuid[])", [org, [item]]), { [item]: true });
   assert.equal(await scalar("select count(*)::int from public.purchases"), 0);
   assert.equal(await scalar("select count(*)::int from public.inventory_movements"), 0);
  });
  await t.test("corrections append history; backdated entries do not replace newer price dates", async () => {
   await save([input({ total_price: "100000" })]);
   await save([input({ price_date: "2020-01-15", total_price: "50000" })]);
   const data = await list(item);
   assert.equal(data.items[0].latest.cost_per_base_unit, "2000.000000000000");
   assert.equal(data.history.length, 3); assert.equal(data.history[2].total_price, "90000.000000");
   await assert.rejects(db.query("update public.material_reference_prices set total_price=0"), e => e.code === "42501");
   await assert.rejects(db.query("delete from public.material_reference_prices"), e => e.code === "42501");
  });
  await t.test("bad batches save no partial rows and reject invalid dimensions, dates and precision", async () => {
   const before = await scalar("select count(*)::int from public.material_reference_prices");
   for (const bad of [{ unit_code: "L" }, { quantity: "0" }, { total_price: "0" }, { total_price: "NaN" }, { quantity: "0.0000001" }, { price_date: "2020-02-31" }, { price_date: "2999-01-01" }, { source_note: "" }, { material_code: "UNKNOWN" }, { unit_code: "KG", quantity: "99999999999999", total_price: "0.000001" }])
    await assert.rejects(save([input({ material_code: "FLOUR", unit_code: "KG" }), input(bad)], { source: "CSV" }), e => e.code === "22023");
   await assert.rejects(preview([input(), input()]), e => e.code === "22023");
   await assert.rejects(preview(Array.from({ length: 101 }, () => input())), e => e.code === "22023");
   assert.equal(await scalar("select count(*)::int from public.material_reference_prices"), before);
  });
  await t.test("a changed conversion after review requires a fresh review", async () => {
   const data = [input({ price_date: "2020-06-01" })], reviewed = await preview(data);
   await scalar("select public.save_material_conversion($1,$2,$3,45,'2020-05-01')", [org, item, bag]);
   await assert.rejects(save(data, { reviewed }), e => e.code === "22023" && /Review your prices again/.test(e.message));
   await save(data);
   const price = (await rows("select conversion_factor::text,base_quantity::text from public.material_reference_prices where price_date='2020-06-01'"))[0];
   assert.equal(price.conversion_factor, "45.000000000000"); assert.equal(price.base_quantity, "45.000000000000");
  });
  await t.test("financial read scope and write roles are enforced on tables and RPCs", async () => {
   await db.exec("reset role");
   const location = await scalar("select id from public.locations where organisation_id=$1 limit 1", [org]);
   for (const [id, role, scope] of [[procurement, "procurement", null], [finance, "finance", null], [scoped, "procurement", location], [operations, "operations", null]]) {
    const membership = await scalar("insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id", [org, id]);
    await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,$3,$4)", [org, membership, role, scope]);
   }
   await db.query("insert into private.platform_admins(user_id) values($1)", [founder]);
   await login(procurement); await save([input({ total_price: "85000" })]);
   await login(finance); assert.equal((await list()).priced_materials, 1);
   await assert.rejects(preview([input()]), e => e.code === "42501");
   for (const id of [other, scoped, founder, operations]) {
    await login(id);
    assert.equal(await scalar("select count(*)::int from public.material_reference_prices where organisation_id=$1", [org]), 0);
    await assert.rejects(list(), e => e.code === "42501");
    await assert.rejects(scalar("select public.material_reference_price_coverage($1,$2::uuid[])", [org, [item]]), e => e.code === "42501");
    await assert.rejects(preview([input()]), e => e.code === "42501");
    await assert.rejects(save([input()], { reviewed: [] }), e => e.code === "42501");
   }
   await login(other); assert.equal((await scalar("select public.list_material_reference_prices($1,'',1,null)", [otherOrg])).total, 0);
   await db.exec("reset role; set role anon");
   await assert.rejects(list(), e => e.code === "42501");
  });
 } finally { await db.close(); }
});
