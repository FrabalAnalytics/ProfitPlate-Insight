import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { PGlite } from "@electric-sql/pglite";

test("onboarding preserves existing access, saves privately and creates isolated businesses once", async (t) => {
  const db = new PGlite();
  const ids = Array.from({ length: 7 }, (_, index) => `00000000-0000-0000-0000-${String(index + 1).padStart(12, "0")}`);
  const [founder, ownerA, ownerB, staff, legacyOwner, legacyManager, unconfirmed] = ids;
  const read = async (sql, params = []) => (await db.query(sql, params)).rows;
  const scalar = async (sql, params = []) => Object.values((await read(sql, params))[0])[0];
  const login = async (id) => {
    await db.exec("reset role");
    await db.query("select set_config('request.jwt.claim.sub', $1, false)", [id]);
    await db.exec("set role authenticated");
  };
  const denied = (sql, params = [], code = "42501") => assert.rejects(db.query(sql, params), error => error.code === code);
  const migration = async name => db.exec(await readFile(new URL(`../supabase/migrations/${name}`, import.meta.url), "utf8"));
  const save = async (name = "Restaurant A") => scalar(
    "select public.save_restaurant_setup($1,'QSR','NG','NGN',$2,'Main outlet','Africa/Lagos','Lekki',3)", [name, `${name} brand`]);
  try {
    await db.exec(`
      create role anon; create role authenticated;
      create schema auth;
      create table auth.users (id uuid primary key, email_confirmed_at timestamptz);
      create function auth.uid() returns uuid language sql stable as $$
        select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
      $$;
      grant usage on schema public,auth to authenticated,anon;
      grant execute on function auth.uid() to authenticated,anon;
    `);
    for (const id of ids) await db.query("insert into auth.users values ($1,$2)", [id, id === unconfirmed ? null : "2026-11-14T00:00:00Z"]);
    await migration("202611140001_initial_schema.sql");
    await migration("202611140002_platform_admin_access.sql");
    await db.query("insert into private.platform_admins(user_id) values ($1)", [founder]);
    const legacyOrg = await scalar("insert into public.organisations(name,owner_id) values ('Existing restaurant',$1) returning id", [legacyOwner]);
    const legacyBranch = await scalar("insert into public.branches(organisation_id,name) values ($1,'Existing branch') returning id", [legacyOrg]);
    await db.query("insert into public.organisation_members values ($1,$2,'manager',now())", [legacyOrg, legacyManager]);
    await migration("202611140003_restaurant_onboarding.sql");

    await t.test("founder record is preserved and has no automatic tenant access", async () => {
      await login(founder);
      assert.equal(await scalar("select public.is_platform_admin()"), true);
      assert.equal((await read("select * from public.organisations")).length, 0);
      await assert.rejects(save(), e => e.code === "42501");
    });
    await t.test("legacy branch identity and owner/manager access survive migration", async () => {
      await login(legacyOwner);
      assert.equal(await scalar("select id from public.locations"), legacyBranch);
      await login(legacyManager);
      assert.equal((await read("select * from public.organisations")).length, 1);
      await db.query("insert into public.suppliers(organisation_id,name) values ($1,'Legacy supplier')", [legacyOrg]);
    });
    await t.test("unconfirmed and anonymous users cannot create restaurant drafts", async () => {
      await login(unconfirmed); await assert.rejects(save(), e => e.code === "42501");
      await db.exec("reset role; set role anon");
      await denied("select public.complete_restaurant_setup()");
    });
    let orgA, orgB, locationA, brandA;
    await t.test("partial drafts save, resume and remain private", async () => {
      await login(ownerA);
      await scalar("select public.save_restaurant_setup('','','NG','NGN','','','Africa/Lagos','',1)");
      assert.equal(await scalar("select step from public.restaurant_setup_drafts"), 1);
      await assert.rejects(db.query("select public.complete_restaurant_setup()"), e => e.code === "22023");
      await save();
      await login(ownerB);
      assert.equal((await read("select * from public.restaurant_setup_drafts")).length, 0);
      await denied("update public.restaurant_setup_drafts set business_name='Intrusion'");
    });
    await t.test("completion creates the entire business once and writes its audit", async () => {
      await login(ownerA);
      orgA = await scalar("select public.complete_restaurant_setup()");
      await save("Attempted duplicate");
      assert.equal(await scalar("select public.complete_restaurant_setup()"), orgA);
      assert.equal((await read("select * from public.organisations")).length, 1);
      assert.equal(await scalar("select name from public.organisations"), "Restaurant A");
      assert.equal((await read("select * from public.membership_roles")).length, 2);
      assert.equal((await read("select * from public.audit_events")).length, 1);
      locationA = await scalar("select id from public.locations");
      brandA = await scalar("select id from public.brands");
      assert.equal(await scalar("select legacy_branch_id from public.locations"), locationA);
    });
    await t.test("a second tenant can reuse local codes without seeing the first", async () => {
      await login(ownerB); await save("Restaurant B");
      orgB = await scalar("select public.complete_restaurant_setup()");
      assert.notEqual(orgA, orgB);
      assert.equal(await scalar("select code from public.brands"), "PRIMARY");
      assert.equal((await read("select * from public.organisations where id=$1", [orgA])).length, 0);
      assert.equal((await read("select * from public.locations where organisation_id=$1", [orgA])).length, 0);
      for (const sql of ["insert into public.brands(organisation_id,code,name) values ($1,'X','Intrusion')", "update public.locations set name='Intrusion' where organisation_id=$1", "delete from public.locations where organisation_id=$1"])
        await denied(sql, [orgA]);
      await denied("insert into public.organisations(name,owner_id) values ('Bypass',$1)", [ownerB]);
    });
    await t.test("cross-tenant parent links fail even for a privileged write", async () => {
      await db.exec("reset role");
      await denied("insert into public.locations(organisation_id,brand_id,code,name,timezone) values ($1,$2,'BAD','Bad link','Africa/Lagos')", [orgB, brandA], "23503");
    });
    await t.test("location scope does not expose another location or legacy financial tables", async () => {
      const member = await scalar("insert into public.organisation_memberships(organisation_id,user_id) values ($1,$2) returning id", [orgA, staff]);
      const secondLocation = await scalar("insert into public.locations(organisation_id,brand_id,code,name,timezone) values ($1,$2,'SECOND','Second outlet','Africa/Lagos') returning id", [orgA, brandA]);
      await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values ($1,$2,'operations',$3)", [orgA, member, locationA]);
      await login(staff);
      assert.equal((await read("select * from public.organisations")).length, 1);
      assert.equal((await read("select * from public.locations")).length, 1);
      assert.equal((await read("select * from public.locations where id=$1", [secondLocation])).length, 0);
      assert.equal(await scalar("select private.pp_has_access($1,false)", [orgA]), false);
      await denied("insert into public.sales(organisation_id,branch_id,receipt_number) values ($1,$2,'FORBIDDEN')", [orgA, locationA]);
      await denied("insert into public.membership_roles(organisation_id,membership_id,role_code) values ($1,$2,'restaurant_admin')", [orgA, member]);
      await db.exec("reset role");
      await db.query("update public.organisation_memberships set status='inactive' where id=$1", [member]);
      await login(staff);
      assert.equal((await read("select * from public.organisations")).length, 0);
      assert.equal((await read("select * from public.locations")).length, 0);
    });
  } finally { await db.close(); }
});
