import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID, createHash } from "node:crypto";
import { readFile, readdir } from "node:fs/promises";
import { PGlite } from "./helpers/active-restaurant-db.mjs";

const headers = "Organisation_Code,Source_System,Purchase_Date,Purchase_Ref,Line_Ref,Supplier_Code,Item_Code,Quantity,Purchase_UOM,Unit_Price,Line_Discount,Tax,Location_Code,Currency,Status";
const base = ["ORG001", "ERP_A", "2020-01-01", "INV001", "1", "SUP001", "RICE", "2", "BAG", "45000", "0", "0", "PRIMARY", "NGN", "RECEIVED"];
const row = (changes = {}) => base.map((value, index) => changes[index] ?? value);
const csv = rows => headers + "\r\n" + rows.map(values => values.map(value => '"' + value.replaceAll('"', '""') + '"').join(",")).join("\r\n");

test("purchase files stage privately, reconcile atomically and preserve source identity", async t => {
 const db = new PGlite();
 const ids = Array.from({ length: 8 }, (_, i) => `50000000-0000-0000-0000-${String(i + 1).padStart(12, "0")}`);
 const [owner, other, finance, procurement, scoped, operations, founder, ceo] = ids;
 const scalar = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
 const login = async id => { await db.exec("reset role"); await db.query("select set_config('request.jwt.claim.sub',$1,false)", [id]); await db.exec("set role authenticated"); };
 let org, otherOrg, kg, bag, rice, batch;
 const stage = (text, { request = randomUUID(), maps = {}, basis = "EXCLUSIVE", tenant = org } = {}) => scalar("select public.stage_purchase_import($1,$2,'purchases.csv',$3,'ORG001',$4,$5::jsonb)", [tenant, request, text, basis, JSON.stringify(maps)]);
 const detail = (id, tenant = org) => scalar("select public.get_purchase_import($1,$2)", [tenant, id]);
 const controls = report => Object.fromEntries(report.documents.filter(doc => !doc.duplicate).map(doc => [doc.key, doc.total]));
 const post = async (id, override) => scalar("select public.post_purchase_import($1,$2,$3::jsonb)", [org, id, JSON.stringify(override ?? controls((await detail(id)).report))]);
 const rejects = (work, code = "22023") => assert.rejects(work, error => error.code === code);
 try {
  await db.exec(`create role anon; create role authenticated; create schema auth; create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);
   create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
   grant usage on schema public,auth to authenticated,anon; grant execute on function auth.uid() to authenticated,anon;`);
  for (const id of ids) await db.query("insert into auth.users(id,email_confirmed_at) values($1,now())", [id]);
  for (const file of (await readdir(new URL("../supabase/migrations/", import.meta.url))).filter(name => name.endsWith(".sql")).sort())
   await db.exec(await readFile(new URL(`../supabase/migrations/${file}`, import.meta.url), "utf8"));
  for (const id of [other, owner]) {
   await login(id); await db.query("select public.save_restaurant_setup('Restaurant','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");
   const result = await scalar("select public.complete_restaurant_setup()"); if (id === owner) org = result; else otherOrg = result;
  }
  kg = await scalar("select id from public.units_of_measure where code='KG'"); bag = await scalar("select id from public.units_of_measure where code='BAG'");
  rice = await scalar("select public.save_catalogue_material($1,null,'RICE','Rice','RAW','',$2,true,true)", [org, kg]);
  await scalar("select public.save_catalogue_supplier($1,null,'SUP001','Sample Foods','','','',true)", [org]);
  await scalar("select public.save_material_conversion($1,$2,$3,50,'2019-01-01')", [org, rice, bag]);

  await t.test("staging preserves source bytes/hash, schema contract and provenance without posting", async () => {
   const text = "\uFEFF" + csv([row(), row({ 4: "2", 7: "1", 8: "KG", 9: "1800" })]);
   const request = randomUUID(); batch = await stage(text, { request }); assert.equal(await stage(text, { request }), batch);
   await rejects(stage(text + "\n", { request }));
   const data = await detail(batch); assert.equal(data.state, "REVIEW"); assert.equal(data.report.ready, 2);
   assert.equal(data.report.rows[0].prepared.base_quantity, "100.000000000000");
   assert.equal(data.source_hash, createHash("sha256").update(text).digest("hex"));
   const source = await scalar("select public.purchase_import_source($1,$2)", [org, batch]); assert.equal(source.csv, text);
   assert.equal("source_csv" in data, false); assert.equal("input_hash" in data, false);
   assert.equal(await scalar("select count(*)::int from public.purchase_headers"), 0);
   await rejects(db.query("select source_csv from public.purchase_import_batches"), "42501");
  });
  await t.test("supplier invoice controls must match before atomic idempotent recording", async () => {
   await rejects(post(batch, {}));
   const invalid = controls((await detail(batch)).report); invalid[Object.keys(invalid)[0]] = "1";
   await rejects(post(batch, invalid)); assert.equal(await scalar("select count(*)::int from public.purchase_lines"), 0);
   assert.equal((await post(batch)).new_lines, 2); assert.equal((await post(batch)).already_posted, true);
   assert.equal(await scalar("select invoice_total::text from public.purchase_headers"), "91800.000000000000");
   assert.equal(await scalar("select count(*)::int from public.purchase_lines"), 2);
   assert.equal(await scalar("select count(*)::int from public.inventory_movements"), 0);
   assert.equal(await scalar("select count(*)::int from public.material_reference_prices"), 0);
   await rejects(db.query("update public.purchase_lines set quantity=1"), "42501");
  });
  await t.test("duplicates survive different decimal formatting and conflicting corrections are blocked", async () => {
   const duplicate = await stage(csv([row({ 7: "2.0", 9: "45000.00", 10: "0.000000" })]));
   assert.equal((await detail(duplicate)).report.duplicates, 1); assert.equal((await post(duplicate)).new_lines, 0);
   for (const change of [{ 9: "46000" }, { 4: "3" }, { 2: "2020-01-02" }]) {
    const conflict = await stage(csv([row(change)])); assert.equal((await detail(conflict)).state, "INVALID"); await rejects(post(conflict));
   }
   const inFile = await stage(csv([row({ 3: "NEW" }), row({ 3: "NEW" })])); assert.equal((await detail(inFile)).report.rejected, 1);
  });
  await t.test("CSV errors and rejected rows stay in history; one bad row blocks the whole batch", async () => {
   const malformed = await stage('wrong,header\n1,2'); assert.match((await detail(malformed)).report.file_error, /template headers/);
   for (const change of [{ 0: "OTHER_ORG" }, { 14: "ORDERED" }, { 13: "USD" }, { 2: "2999-01-01" }, { 2: "2020-02-31" }, { 6: "UNKNOWN" }, { 8: "L" }, { 7: "0" }, { 7: "0.0000001" }, { 9: "=1+1" }, { 10: "" }, { 11: "-1" }, { 5: "UNKNOWN" }, { 12: "OTHER" }, { 10: "999999" }]) {
    const bad = await stage(csv([row({ 3: "MIXED", 4: "A" }), row({ 3: "MIXED", 4: "B", ...change })]));
    assert.equal((await detail(bad)).state, "INVALID", JSON.stringify(change)); await rejects(post(bad));
   }
   assert.equal(await scalar("select count(*)::int from public.purchase_lines"), 2);
   const oversizedRows = await stage(csv(Array.from({ length: 101 }, (_, i) => row({ 4: String(i) }))));
   assert.match((await detail(oversizedRows)).report.file_error, /100 purchase rows/);
  });
  await t.test("inclusive and exclusive tax formats preserve explicit source amounts and exact totals", async () => {
   const ex = await stage(csv([row({ 3: "TAX-EX", 7: "3", 8: "KG", 9: "100", 10: "10", 11: "21.75" })]));
   assert.equal((await detail(ex)).report.rows[0].prepared.net_amount, "290");
   assert.equal((await detail(ex)).report.rows[0].prepared.invoice_amount, "311.75"); await post(ex);
   const inc = await stage(csv([row({ 3: "TAX-IN", 7: "1", 8: "KG", 9: "311.75", 11: "21.75" })]), { basis: "INCLUSIVE" });
   assert.equal((await detail(inc)).report.rows[0].prepared.net_amount, "290.00"); await post(inc);
   const tiny = await stage(csv([row({ 3: "PRECISE", 7: "0.000001", 8: "KG", 9: "0.000001" })]));
   assert.equal((await detail(tiny)).report.rows[0].prepared.invoice_amount, "0.000000000001"); await post(tiny);
  });
  await t.test("explicit source-code mappings resolve only active masters inside the authorised business", async () => {
   const alias = csv([row({ 3: "MAPPED", 6: "EXTERNAL_RICE", 5: "EXTERNAL_SUP", 12: "EXTERNAL_LOC" })]);
   const rejected = await stage(alias); assert.equal((await detail(rejected)).state, "INVALID");
   const mapped = await stage(alias, { maps: { items: { EXTERNAL_RICE: "RICE" }, suppliers: { EXTERNAL_SUP: "SUP001" }, locations: { EXTERNAL_LOC: "PRIMARY" } } });
   assert.equal((await detail(mapped)).report.ready, 1); await post(mapped);
   assert.equal((await detail(mapped)).report.rows[0].source.Item_Code, "EXTERNAL_RICE");
  });
  await t.test("stale reviews require a second review and simultaneous imports cannot double-record", async () => {
   const text = csv([row({ 3: "RACE" })]), first = await stage(text), second = await stage(text);
   await post(first); assert.equal((await post(second)).posted, false); assert.equal((await detail(second)).report.duplicates, 1);
   assert.equal((await post(second)).new_lines, 0);
   const changing = await stage(csv([row({ 3: "CONVERSION", 2: "2020-06-01" })]));
   await scalar("select public.save_material_conversion($1,$2,$3,40,'2020-05-01')", [org, rice, bag]);
   assert.equal((await post(changing)).posted, false); assert.equal((await detail(changing)).report.rows[0].prepared.base_quantity, "80.000000000000");
   await post(changing);
  });
  await t.test("unposted attempts can be cancelled and source/history remain readable", async () => {
   const id = await stage(csv([row({ 3: "CANCEL" })])); await scalar("select public.cancel_purchase_import($1,$2)", [org, id]);
   assert.equal((await detail(id)).state, "CANCELLED"); await rejects(post(id));
   await rejects(scalar("select public.cancel_purchase_import($1,$2)", [org, batch]));
   const history = await scalar("select public.purchase_import_history($1,1)", [org]); assert.ok(history.total > 25); assert.equal(history.batches.length, 25);
   assert.equal((await scalar("select public.purchase_import_history($1,2)", [org])).batches.length, history.total - 25);
  });
  await t.test("financial read and procurement write boundaries cover source files, reports and purchase rows", async () => {
   await db.exec("reset role"); const location = await scalar("select id from public.locations where organisation_id=$1 limit 1", [org]);
   for (const [id, role, scope] of [[finance, "finance", null], [procurement, "procurement", null], [scoped, "procurement", location], [operations, "operations", null], [ceo, "ceo", null]]) {
    const membership = await scalar("insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id", [org, id]);
    await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,$3,$4)", [org, membership, role, scope]);
   }
   await db.query("insert into private.platform_admins(user_id) values($1)", [founder]);
   for (const id of [finance, ceo, operations]) {
    await login(id); assert.equal((await detail(batch)).state, "POSTED"); await rejects(stage(csv([row()])), "42501"); await rejects(post(batch), "42501");
   }
   await login(finance); assert.equal((await scalar("select public.purchase_import_access($1)", [org])).write, false); assert.equal((await scalar("select public.purchase_import_access($1)", [org])).approve_corrections, true);
   await login(procurement); assert.equal((await detail(batch)).state, "POSTED"); await stage(csv([row({ 3: "PROC" })]));
   for (const id of [other, scoped, founder]) {
    await login(id); await rejects(detail(batch), "42501"); await rejects(stage(csv([row()])), "42501"); await rejects(post(batch), "42501");
    await rejects(scalar("select public.purchase_import_source($1,$2)", [org, batch]), "42501");
    assert.equal(await scalar("select count(*)::int from public.purchase_lines where organisation_id=$1", [org]), 0);
   }
   await login(other); assert.equal((await scalar("select public.purchase_import_history($1,1)", [otherOrg])).total, 0);
   await db.exec("reset role; set role anon"); await rejects(detail(batch), "42501");
  });
 } finally { await db.close(); }
});
