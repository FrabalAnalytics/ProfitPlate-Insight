import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { PGlite } from "./helpers/active-restaurant-db.mjs";

test("catalogue permissions, dimensional conversions and historical integrity", async t => {
  const db = new PGlite();
  const ids = Array.from({ length: 8 }, (_, i) => `10000000-0000-0000-0000-${String(i + 1).padStart(12, "0")}`);
  const [ownerA, ownerB, procurement, finance, scoped, founder, ownerC, noRole] = ids;
  const rows = async (sql, params = []) => (await db.query(sql, params)).rows;
  const value = async (sql, params = []) => Object.values((await rows(sql, params))[0])[0];
  const login = async id => { await db.exec("reset role"); await db.query("select set_config('request.jwt.claim.sub',$1,false)", [id]); await db.exec("set role authenticated"); };
  const reject = (sql, params, code = "42501") => assert.rejects(db.query(sql, params), error => error.code === code);
  const migrate = async number => db.exec(await readFile(new URL(`../supabase/migrations/${number}`, import.meta.url), "utf8"));
  const createBusiness = async id => { await login(id); await db.query("select public.save_restaurant_setup('Restaurant','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)"); return value("select public.complete_restaurant_setup()"); };
  let orgA, orgB, item, kg, g, bag, litre;
  const material = (code = "RICE001", uom = kg, id = null, name = "Rice", active = true) => value("select public.save_catalogue_material($1,$2,$3,$4,'RAW','Grains',$5,true,$6)", [orgA, id, code, name, uom, active]);
  const convert = (from = bag, factor = "50", date = "2026-11-14") => value("select public.save_material_conversion($1,$2,$3,$4,$5)", [orgA, item, from, factor, date]);
  try {
    await db.exec(`create role anon; create role authenticated; create schema auth;
      create table auth.users(id uuid primary key,email_confirmed_at timestamptz);
      create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
      grant usage on schema public,auth to authenticated,anon; grant execute on function auth.uid() to authenticated,anon;`);
    for (const id of ids) await db.query("insert into auth.users values ($1,now())", [id]);
    for (const file of ["202611140001_initial_schema.sql", "202611140002_platform_admin_access.sql", "202611140003_restaurant_onboarding.sql"]) await migrate(file);
    await db.query("insert into private.platform_admins(user_id) values ($1)", [founder]);
    orgA = await createBusiness(ownerA); orgB = await createBusiness(ownerB);
    await db.exec("reset role");
    const legacyIngredient = await value("insert into public.ingredients(organisation_id,name,base_unit) values ($1,'Legacy rice','g') returning id", [orgA]);
    await db.query("insert into public.suppliers(organisation_id,name,phone) values ($1,'Existing supplier','08000000001')", [orgA]);
    await migrate("202611140004_materials_and_suppliers.sql");
    await login(ownerA);
    const dictionary = await rows("select id,code from public.units_of_measure");
    kg = dictionary.find(u => u.code === "KG").id; g = dictionary.find(u => u.code === "G").id;
    bag = dictionary.find(u => u.code === "BAG").id; litre = dictionary.find(u => u.code === "L").id;

    await t.test("backfill preserves legacy identities without inventing costs", async () => {
      assert.equal(dictionary.length, 9);
      assert.equal(await value("select base_uom_id from public.items where id=$1", [legacyIngredient]), g);
      assert.equal(await value("select phone from public.suppliers where name='Existing supplier'"), "08000000001");
      assert.equal(await value("select count(*)::int from information_schema.columns where table_name='items' and column_name like '%cost%'"), 0);
    });
    await t.test("material save/update audits changes and fixes code/base unit", async () => {
      item = await material();
      assert.equal(await material("RICE001", kg, item, "Long grain rice"), item);
      await assert.rejects(material("RICE001", g, item), e => e.code === "22023");
      await assert.rejects(material("CHANGED", kg, item), e => e.code === "22023");
      await assert.rejects(material("BAG-BASE", bag), e => e.code === "22023");
      await assert.rejects(material(), e => e.code === "23505");
      assert.equal(await value("select count(*)::int from public.audit_events where event_type='material.updated'"), 1);
    });
    await t.test("package factors are item-specific, versioned and retry-safe", async () => {
      const first = await convert();
      assert.equal(await convert(), first);
      await assert.rejects(convert(bag, "40"), e => e.code === "23505");
      await convert(bag, "40", "2026-12-01");
      const versions = await rows("select factor::text from public.item_uom_conversions where item_id=$1 order by effective_from", [item]);
      assert.deepEqual(versions.map(v => v.factor), ["50.000000", "40.000000"]);
      await reject("update public.item_uom_conversions set factor=1", []);
      await reject("delete from public.item_uom_conversions", []);
      assert.equal(await value("select count(*)::int from public.audit_events where event_type='conversion.created'"), 2);
    });
    await t.test("standard conversions use exact dimensions and reject unsupported precision", async () => {
      await convert(g, "0.001");
      await assert.rejects(convert(g, "1000", "2026-12-02"), e => e.code === "22023");
      await assert.rejects(convert(litre, "1"), e => e.code === "22023");
      await assert.rejects(convert(bag, "0.0000001"), e => e.code === "22023");
      await assert.rejects(convert(bag, "0"), e => e.code === "22023");
      await assert.rejects(convert(bag, "100000000000000"), e => e.code === "22023");
    });
    await t.test("suppliers preserve phone text and support reversible inactivity", async () => {
      const supplier = await value("select public.save_catalogue_supplier($1,null,'SUP001','Sample Foods','hello@example.test','08000000002','Lagos',true)", [orgA]);
      await value("select public.save_catalogue_supplier($1,$2,'SUP001','Sample Foods','hello@example.test','08000000002','Lagos',false)", [orgA, supplier]);
      assert.equal(await value("select is_active from public.suppliers where id=$1", [supplier]), false);
      assert.equal(await value("select phone from public.suppliers where id=$1", [supplier]), "08000000002");
      await reject("insert into public.suppliers(organisation_id,name) values ($1,'Bypass')", [orgA]);
      await reject("select public.save_catalogue_supplier($1,null,'BAD','Bad supplier','invalid','','',true)", [orgA], "22023");
    });
    await t.test("cross-tenant reads, writes, code linking and unit linking fail", async () => {
      await login(ownerB);
      assert.equal((await rows("select * from public.items where organisation_id=$1", [orgA])).length, 0);
      await reject("select public.save_catalogue_material($1,null,'INTRUDE','Intrusion','RAW','',$2,true,true)", [orgA, kg]);
      const kgB = await value("select id from public.units_of_measure where code='KG'");
      await value("select public.save_catalogue_material($1,null,'RICE001','Rice','RAW','',$2,true,true)", [orgB, kgB]);
      await reject("select public.save_material_conversion($1,$2,$3,50,'2026-11-14')", [orgB, item, bag]);
      await db.exec("reset role");
      await reject("insert into public.items(organisation_id,code,name,item_type,base_uom_id) values ($1,'BAD','Wrong tenant unit','RAW',$2)", [orgB, kg], "23503");
      for (const [id, role, scope] of [[procurement, "procurement", false], [finance, "finance", false], [scoped, "procurement", true]]) {
        const membership = await value("insert into public.organisation_memberships(organisation_id,user_id) values ($1,$2) returning id", [orgA, id]);
        const location = scope ? await value("select id from public.locations where organisation_id=$1 limit 1", [orgA]) : null;
        await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values ($1,$2,$3,$4)", [orgA, membership, role, location]);
      }
      await db.query("insert into public.organisation_memberships(organisation_id,user_id) values ($1,$2)", [orgA, noRole]);
    });
    await t.test("only active organisation-wide admin/procurement roles can maintain shared masters", async () => {
      await login(procurement);
      assert.equal(await value("select public.can_manage_catalogue($1)", [orgA]), true);
      await material("PROC001");
      for (const id of [finance, scoped]) {
        await login(id);
        assert.equal(await value("select public.can_manage_catalogue($1)", [orgA]), false);
        assert.ok((await rows("select * from public.items")).length > 0);
        await assert.rejects(material("FORBIDDEN"), e => e.code === "42501");
        await reject("update public.items set name='Bypass'", []);
        await reject("delete from public.items", []);
      }
      await db.exec("reset role");
      await db.query("update public.organisation_memberships set status='inactive' where user_id=$1", [procurement]);
      await login(procurement);
      assert.equal((await rows("select * from public.items")).length, 0);
      await assert.rejects(material("INACTIVE"), e => e.code === "42501");
      await login(founder);
      assert.equal((await rows("select * from public.items")).length, 0);
      await assert.rejects(material("FOUNDER"), e => e.code === "42501");
      await login(noRole);
      assert.equal((await rows("select * from public.items")).length, 0);
      assert.equal((await rows("select * from public.suppliers")).length, 0);
      await db.exec("reset role; set role anon");
      await reject("select * from public.items", []);
    });
    await t.test("new businesses receive their own unit dictionary after this migration", async () => {
      await createBusiness(ownerC);
      assert.equal(await value("select count(*)::int from public.units_of_measure"), 9);
    });
  } finally { await db.close(); }
});
