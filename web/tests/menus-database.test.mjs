import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile, readdir } from "node:fs/promises";
import { PGlite } from "./helpers/active-restaurant-db.mjs";

test("menu versions and dated prices give scoped, explicit reference food margins", async t => {
 const db = new PGlite();
 const ids = Array.from({ length: 8 }, (_, i) => `60000000-0000-0000-0000-${String(i + 1).padStart(12, "0")}`);
 const [owner, other, finance, procurement, operations, scoped, founder, ceo] = ids;
 const scalar = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
 const login = async id => { await db.exec("reset role"); await db.query("select set_config('request.jwt.claim.sub',$1,false)", [id]); await db.exec("set role authenticated"); };
 let org, brand, location, otherBrandLocation, otherOrg, legacy, kg, pcs, rice, sourceRecipe, recipe, menu, version;
 const rejects = (work, code = "22023") => assert.rejects(work, error => error.code === code);
 const publishRecipe = (code, qty, { root = null, type = "FINAL", item = rice } = {}) => scalar("select public.publish_recipe_version($1,$2,$3,$4,$4,$5,'2020-01-01',1,$6,'',$7::jsonb)", [org, root, randomUUID(), code, type, pcs, JSON.stringify([{ kind: "ITEM", target_id: item, quantity: qty, uom_id: kg }])]);
 const publish = ({ id = null, code = "MENU001", name = "Rice plate", source = recipe, qty = "1", date = "2020-01-01", request = randomUUID(), tenant = org, targetBrand = brand } = {}) => scalar("select public.publish_menu_item_version($1,$2,$3,$4,$5,$6,'Mains',$7,$8,$9,'Sample menu')", [tenant, id, request, code, name, targetBrand, source, qty, date]);
 const price = ({ id = menu, value = "1500", setting = "NONE", rate = "0", channel = "DINE_IN", from = "2020-01-01", to = null, request = randomUUID(), loc = location } = {}) => scalar("select public.save_menu_selling_price($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,'Fictional price')", [org, id, request, loc, channel, value, setting, rate, from, to]);
 const packet = (id = menu, selected = null) => scalar("select public.get_menu_item($1,$2,$3)", [org, id, selected]);
 const estimate = ({ selected = version, date = "2020-02-01", channel = "DINE_IN", loc = location, tenant = org } = {}) => scalar("select public.menu_food_margin_estimate($1,$2,$3,$4,$5)", [tenant, selected, loc, channel, date]);
 const profitability = ({date="2020-02-01",channel="DINE_IN",loc=location,tenant=org,search="",page=1}={}) => scalar("select public.menu_profitability($1,$2,$3,$4,$5,$6)",[tenant,loc,channel,date,search,page]);
 try {
  await db.exec(`create role anon; create role authenticated; create schema auth; create table auth.users(id uuid primary key,email_confirmed_at timestamptz);
   create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
   grant usage on schema public,auth to authenticated,anon; grant execute on function auth.uid() to authenticated,anon;`);
  for (const id of ids) await db.query("insert into auth.users values($1,now())", [id]);
  for (const name of (await readdir(new URL("../supabase/migrations/", import.meta.url))).filter(name => name.endsWith(".sql") && name < "202611140009").sort()) await db.exec(await readFile(new URL(`../supabase/migrations/${name}`, import.meta.url), "utf8"));
  for (const id of [other, owner]) {
   await login(id); await db.query("select public.save_restaurant_setup('Restaurant','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");
   const result = await scalar("select public.complete_restaurant_setup()"); if (id === owner) org = result; else otherOrg = result;
  }
  brand = await scalar("select id from public.brands limit 1"); location = await scalar("select id from public.locations limit 1");
  await db.exec("reset role"); legacy = await scalar("insert into public.menu_items(organisation_id,name,selling_price) values($1,'Legacy dish',500) returning id", [org]);
  const extraBrand = await scalar("insert into public.brands(organisation_id,code,name) values($1,'OTHER','Other brand') returning id", [org]);
  otherBrandLocation = await scalar("insert into public.locations(organisation_id,brand_id,code,name,timezone) values($1,$2,'OTHER','Other outlet','Africa/Lagos') returning id", [org, extraBrand]);
  await db.exec(await readFile(new URL("../supabase/migrations/202611140009_menu_items_and_prices.sql", import.meta.url), "utf8"));
  await db.exec(await readFile(new URL("../supabase/migrations/202611160022_menu_profitability.sql", import.meta.url), "utf8"));
  await login(owner); kg = await scalar("select id from public.units_of_measure where code='KG'"); pcs = await scalar("select id from public.units_of_measure where code='PCS'");
  rice = await scalar("select public.save_catalogue_material($1,null,'RICE','Rice','RAW','',$2,true,true)", [org, kg]);
  recipe = await publishRecipe("PLATE", "1"); sourceRecipe = await scalar("select recipe_id from public.recipe_versions where id=$1", [recipe]);
  const rows = JSON.stringify([{ material_code: "RICE", quantity: "1", unit_code: "KG", total_price: "900", price_date: "2020-01-01", source_note: "Sample cost" }]);
  const review = await scalar("select public.preview_material_reference_prices($1,$2::jsonb)", [org, rows]);
  await scalar("select public.save_material_reference_prices($1,$2,'MANUAL',$3::jsonb,$4::jsonb)", [org, randomUUID(), rows, JSON.stringify(review)]);

  await t.test("legacy menu values and IDs are preserved without inventing dated selling prices", async () => {
   const old = await packet(legacy); assert.equal(old.item.id, legacy); assert.equal(old.version, null); assert.deepEqual(old.prices, []);
   assert.equal(await scalar("select selling_price::text from public.menu_items where id=$1", [legacy]), "500.00");
   assert.match(old.item.code, /^MENU-/); assert.equal(old.item.brand_id, null);
  });
  await t.test("publishing is immutable, tenant-safe and retry-safe with exact recipe quantity strings", async () => {
   const request = randomUUID(); version = await publish({ request }); assert.equal(await publish({ request }), version);
   await rejects(publish({ request, name: "Changed request" })); menu = await scalar("select menu_item_id from public.menu_item_versions where id=$1", [version]);
   const data = await packet(); assert.equal(data.version.recipe_quantity, "1.000000"); assert.equal(data.recipe.id, recipe);
   assert.equal(await scalar("select selling_price from public.menu_items where id=$1", [menu]), null);
   await rejects(db.query("update public.menu_item_versions set name='Rewrite'"), "42501");
   const sub = await publishRecipe("SUB", "1", { type: "SUB_RECIPE" }); await rejects(publish({ code: "SUB-MENU", source: sub }));
   await rejects(publish({ code: "EARLY", date: "2019-01-01" })); await rejects(publish({ id: menu, code: "RECODE" }));
   await rejects(publish({ code: "TENANT", tenant: otherOrg }), "42501");
   const search = await scalar("select public.search_menu_recipes($1,'',0)", [org]); assert.equal(search.length, 1); assert.equal(search[0].id, recipe);
  });
  await t.test("missing selling price blocks margin while retaining the available recipe estimate", async () => {
   const result = await estimate(); assert.equal(result.cost_state, "MISSING"); assert.equal(result.price_issue, "MISSING_SELLING_PRICE");
   assert.equal(result.estimated_food_cost, "900.000000000000"); assert.equal(result.estimated_food_margin, null); assert.equal(result.net_revenue, null);
  });
  await t.test("no-tax and inclusive/exclusive price settings produce the declared net revenue and food margin", async () => {
   const request = randomUUID(), saved = await price({ request }); assert.equal(await price({ request }), saved); await rejects(price({ request, value: "1600" }));
   const none = await estimate(); assert.equal(none.net_revenue, "1500.000000000000"); assert.equal(none.estimated_food_margin, "600.000000000000");
   assert.equal(none.food_margin_percent, "40.000000"); assert.equal(none.food_cost_percent, "60.000000"); assert.equal(none.tax_amount, "0.000000000000");
   await price({ channel: "TAKEAWAY", value: "1650", setting: "INCLUSIVE", rate: "10" });
   await price({ channel: "DELIVERY", setting: "EXCLUSIVE", rate: "10" });
   for (const channel of ["TAKEAWAY", "DELIVERY"]) {
    const result = await estimate({ channel }); assert.equal(result.net_revenue, "1500.000000000000"); assert.equal(result.customer_total, "1650.000000000000");
    assert.equal(result.tax_amount, "150.000000000000"); assert.equal(result.estimated_food_margin, "600.000000000000");
   }
   await rejects(db.query("delete from public.menu_price_versions"), "42501");
  });
  await t.test("price events select by scope/date, retain corrections and never resume expired old prices", async () => {
   await price({ value: "1700", from: "2021-01-01", to: "2021-01-31" });
   assert.equal((await estimate()).net_revenue, "1500.000000000000");
   assert.equal((await estimate({ date: "2021-02-01" })).price_issue, "EXPIRED_SELLING_PRICE");
   await price({ value: "1800", from: "2021-01-01", to: "2021-01-31" });
   assert.equal((await estimate({ date: "2021-01-15" })).net_revenue, "1800.000000000000");
   await price({ value: "1600", from: "2020-06-01" });
   assert.equal((await estimate({ date: "2020-07-01" })).net_revenue, "1600.000000000000");
   assert.equal((await estimate({ date: "2021-02-01" })).estimated_food_margin, null);
   await rejects(price({ loc: otherBrandLocation }));
   assert.ok((await packet()).prices.length >= 6);
  });
  await t.test("new recipe versions leave old menu bindings unchanged; explicit new menu versions expose negative margins", async () => {
   const nextRecipe = await publishRecipe("PLATE", "2", { root: sourceRecipe });
   assert.equal((await estimate({ channel: "TAKEAWAY" })).estimated_food_cost, "900.000000000000");
   const nextMenu = await publish({ id: menu, source: nextRecipe, date: "2021-01-01" });
   assert.equal((await estimate({ selected: nextMenu, date: "2021-01-15", channel: "TAKEAWAY" })).estimated_food_margin, "-300.000000000000");
   assert.equal((await estimate({ selected: nextMenu, date: "2021-01-15", channel: "TAKEAWAY" })).food_margin_percent, "-20.000000");
   assert.equal((await packet(menu, version)).recipe.id, recipe);
  });
  await t.test("missing ingredient prices suppress full margin and currency changes suppress mismatched prices", async () => {
   const missingItem = await scalar("select public.save_catalogue_material($1,null,'MISSING','Unpriced material','RAW','',$2,true,true)", [org, kg]);
   const incompleteRecipe = await publishRecipe("MISSING", "1", { item: missingItem });
   const incompleteVersion = await publish({ code: "MISSING-MENU", source: incompleteRecipe });
   const id = await scalar("select menu_item_id from public.menu_item_versions where id=$1", [incompleteVersion]); await price({ id });
   const incomplete = await estimate({ selected: incompleteVersion }); assert.equal(incomplete.cost_state, "MISSING"); assert.equal(incomplete.estimated_food_cost, null);
   assert.equal(incomplete.estimated_food_margin, null); assert.equal(incomplete.recipe_estimate.missing_count, 1); assert.equal(incomplete.net_revenue, "1500.000000000000");
   await db.exec("reset role"); await db.query("update public.organisations set currency_code='USD' where id=$1", [org]); await login(owner);
   const changed = await estimate(); assert.equal(changed.price_issue, "PRICE_CURRENCY_MISMATCH"); assert.equal(changed.estimated_food_margin, null);
   await db.exec("reset role"); await db.query("update public.organisations set currency_code='NGN' where id=$1", [org]); await login(owner);
  });
  await t.test("profitability reuses exact per-serving estimates, date-effective versions, scoped prices and missing states", async () => {
   const initial=await profitability(),row=initial.rows.find(row=>row.id===menu);
   assert.equal(initial.currency_code,"NGN");assert.equal(initial.unassigned_menu_count,1);
   assert.equal(row.version_id,version);assert.deepEqual(row.estimate,await estimate());
   assert.equal(row.estimate.estimated_food_cost,"900.000000000000");assert.equal(row.estimate.food_cost_percent,"60.000000");
   assert.equal(row.estimate.food_margin_percent,"40.000000");
   const missing=initial.rows.find(row=>row.code==="MISSING-MENU");assert.equal(missing.estimate.estimated_food_cost,null);assert.equal(missing.estimate.net_revenue,"1500.000000000000");
   assert.equal(missing.estimate.recipe_estimate.missing_count,1);
   const negative=(await profitability({date:"2021-01-15",channel:"TAKEAWAY"})).rows.find(row=>row.id===menu);
   assert.equal(negative.version,2);assert.equal(negative.estimate.estimated_food_margin,"-300.000000000000");
   assert.equal(negative.estimate.customer_total,"1650.000000000000");assert.equal(negative.estimate.net_revenue,"1500.000000000000");
   await publish({id:menu,qty:"0.5",date:"2020-03-01"});
   assert.equal((await profitability({date:"2021-01-15",channel:"TAKEAWAY"})).rows.find(row=>row.id===menu).version,2);
   assert.equal((await profitability({date:"2020-04-01"})).rows.find(row=>row.id===menu).estimate.estimated_food_cost,"450.000000000000");
   assert.equal((await profitability({date:"2021-02-01"})).rows.find(row=>row.id===menu).estimate.price_issue,"EXPIRED_SELLING_PRICE");
   await publish({code:"PROFIT-NO-PRICE",name:"No selling price"});
   const noPrice=(await profitability({search:"PROFIT-NO-PRICE"})).rows[0];assert.equal(noPrice.estimate.net_revenue,null);assert.equal(noPrice.estimate.estimated_food_cost,"900.000000000000");
   await publish({code:"PROFIT-LATER",name:"Later menu",date:"2022-01-01"});
   assert.equal((await profitability({search:"PROFIT-LATER"})).rows[0].estimate,null);
   assert.equal((await profitability({loc:otherBrandLocation})).total,0);
   assert.equal((await profitability({search:"Rice%"})).total,0);
   await rejects(profitability({tenant:otherOrg}),"42501");
   for(const options of [{date:"2099-01-01"},{channel:"OTHER"},{page:0},{loc:randomUUID()},{search:"x".repeat(81)}])await rejects(profitability(options));
  });
  await t.test("profitability searches and counts before pagination and excludes inactive menus",async()=>{
   for(let i=0;i<26;i++)await publish({code:`PROFIT-PAGE-${i}`,name:`Comparison row ${String(i).padStart(2,"0")}`});
   const first=await profitability({search:"Comparison row"}),second=await profitability({search:"Comparison row",page:2});
   assert.equal(first.total,26);assert.equal(first.rows.length,25);assert.equal(second.total,26);assert.equal(second.rows.length,1);
   assert.equal(new Set([...first.rows,...second.rows].map(row=>row.id)).size,26);
   await scalar("select public.set_menu_item_active($1,$2,false)",[org,second.rows[0].id]);
   assert.equal((await profitability({search:"Comparison row"})).total,25);
  });
  await t.test("invalid prices, rates, quantities, dates and inactive items cannot bypass validation", async () => {
   for (const options of [{ value: "0" }, { value: "-1" }, { rate: "101", setting: "INCLUSIVE" }, { rate: "10", setting: "NONE" }, { rate: "0.0000001", setting: "EXCLUSIVE" }, { channel: "UNKNOWN" }, { from: "2021-01-02", to: "2021-01-01" }]) await rejects(price(options));
   await rejects(publish({ code: "ZERO", qty: "0" })); await rejects(publish({ code: "PRECISION", qty: "0.0000001" }));
   await rejects(estimate({ date: "2999-01-01" })); await rejects(estimate({ date: "2019-01-01" }));
   await scalar("select public.set_menu_item_active($1,$2,false)", [org, menu]); await rejects(price(), "42501"); await rejects(estimate());
   assert.equal((await packet()).item.is_active, false);
   await scalar("select public.set_menu_item_active($1,$2,true)", [org, menu]); assert.equal((await estimate()).cost_state, "ESTIMATED");
   assert.equal(await scalar("select count(*)::int from public.sales"), 0);
  });
  await t.test("business-wide financial readers cannot edit; scoped staff and unrelated accounts cannot read", async () => {
   await db.exec("reset role");
   for (const [id, role, scope] of [[finance, "finance", null], [procurement, "procurement", null], [operations, "operations", null], [scoped, "restaurant_admin", location], [ceo, "ceo", null]]) {
    const membership = await scalar("insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id", [org, id]);
    await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,$3,$4)", [org, membership, role, scope]);
   }
   await db.query("insert into private.platform_admins(user_id) values($1)", [founder]);
   for (const id of [finance, procurement, ceo]) { await login(id); assert.equal((await estimate()).cost_state, "ESTIMATED"); assert.ok((await profitability()).total>0); await rejects(price(), "42501"); await rejects(publish({ code: "NO-WRITE" }), "42501"); }
   for (const id of [operations, scoped, other, founder]) {
    await login(id); await rejects(packet(), "42501"); await rejects(estimate(), "42501"); await rejects(profitability(), "42501"); await rejects(price(), "42501");
    assert.equal(await scalar("select count(*)::int from public.menu_items where organisation_id=$1", [org]), 0);
    assert.equal(await scalar("select count(*)::int from public.menu_price_versions where organisation_id=$1", [org]), 0);
   }
   await db.exec("reset role; set role anon"); await rejects(estimate(), "42501"); await rejects(profitability(), "42501");
  });
 } finally { await db.close(); }
});
