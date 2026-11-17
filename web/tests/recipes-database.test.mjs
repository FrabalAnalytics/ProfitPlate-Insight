import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { PGlite } from "@electric-sql/pglite";

test("versioned recipes pin their sources and scale without inventing costs", async t => {
 const db=new PGlite();
 const a="20000000-0000-0000-0000-000000000001", b="20000000-0000-0000-0000-000000000002", reader="20000000-0000-0000-0000-000000000003";
 const rows=async(sql,params=[]) => (await db.query(sql,params)).rows;
 const scalar=async(sql,params=[]) => Object.values((await rows(sql,params))[0])[0];
 const login=async id=>{await db.exec("reset role");await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec("set role authenticated");};
 const reject=(sql,params,code="42501")=>assert.rejects(db.query(sql,params),e=>e.code===code);
 let org,otherOrg,kg,g,pcs,bag,litre,flour,box,base,parent,baseV2;
 const publish=async({recipe=null,code="BASE",name="Flour base",type="SUB_RECIPE",date="2026-11-14",yieldQty="10",uom=kg,lines,request=randomUUID(),tenant=org})=>scalar("select public.publish_recipe_version($1,$2,$3,$4,$5,$6,$7,$8,$9,'',$10::jsonb)",[tenant,recipe,request,code,name,type,date,yieldQty,uom,JSON.stringify(lines)]);
 const line=(kind,target,quantity,uom)=>({kind,target_id:target,quantity,uom_id:uom});
 const packet=id=>scalar("select public.get_recipe_version($1,$2)",[org,id]);
 const requirements=(id,qty)=>scalar("select public.recipe_material_requirements($1,$2,$3)",[org,id,qty]);
 try {
  await db.exec(`create role anon; create role authenticated; create schema auth; create table auth.users(id uuid primary key,email_confirmed_at timestamptz);
   create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
   grant usage on schema public,auth to authenticated,anon; grant execute on function auth.uid() to authenticated,anon;`);
  for(const id of [a,b,reader])await db.query("insert into auth.users values($1,now())",[id]);
  for(const file of ["202611140001_initial_schema.sql","202611140002_platform_admin_access.sql","202611140003_restaurant_onboarding.sql","202611140004_materials_and_suppliers.sql","202611140005_versioned_recipes.sql"])
   await db.exec(await readFile(new URL(`../supabase/migrations/${file}`,import.meta.url),"utf8"));
  for(const id of [b,a]){await login(id);await db.query("select public.save_restaurant_setup('Restaurant','BAKERY','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");const result=await scalar("select public.complete_restaurant_setup()");if(id===a)org=result;else otherOrg=result;}
  const units=await rows("select id,code from public.units_of_measure");
  const unit=code=>units.find(u=>u.code===code).id;
  [kg,g,pcs,bag,litre]=["KG","G","PCS","BAG","L"].map(unit);
  flour=await scalar("select public.save_catalogue_material($1,null,'FLOUR','Flour','RAW','Grains',$2,true,true)",[org,kg]);
  box=await scalar("select public.save_catalogue_material($1,null,'BOX','Box','PACKAGING','Packaging',$2,true,true)",[org,pcs]);
  await t.test("immutable version publication is retry-safe",async()=>{
   const request=randomUUID(),input={request,lines:[line("ITEM",flour,"8",kg)]};
   base=await publish(input);assert.equal(await publish(input),base);
   await assert.rejects(publish({...input,name:"Changed request"}),e=>e.code==="22023");
   assert.equal((await packet(base)).cost_state,"MISSING");
   await reject("update public.recipe_versions set name='Rewrite'",[]);
   await reject("delete from public.recipe_components",[]);
  });
  await t.test("nested recipes scale ingredient and packaging quantities exactly",async()=>{
   parent=await publish({code:"PLATE",name:"Sample plate",type:"FINAL",yieldQty:"12",uom:pcs,lines:[line("RECIPE",base,"1",kg),line("ITEM",box,"12",pcs)]});
   const result=await requirements(parent,"24");
   assert.equal(result.find(i=>i.item_id===flour).quantity,"1.600000000000");
   assert.equal(result.find(i=>i.item_id===box).quantity,"24.000000000000");
   const original=(await packet(base)).recipe.id;
   baseV2=await publish({recipe:original,lines:[line("ITEM",flour,"9",kg)]});
   assert.equal((await packet(baseV2)).version.version,2);
   assert.equal((await requirements(parent,"24")).find(i=>i.item_id===flour).quantity,"1.600000000000");
  });
  await t.test("gram quantities normalise without using floating-point arithmetic",async()=>{
   const version=await publish({code:"GRAMS",lines:[line("ITEM",flour,"250",g)]});
   assert.equal((await packet(version)).components[0].normalised_quantity,"0.250000000000");
   await assert.rejects(publish({code:"DIMENSION",lines:[line("ITEM",flour,"1",litre)]}),e=>e.code==="22023");
   await assert.rejects(publish({code:"PRECISION",lines:[line("ITEM",flour,"0.0000001",kg)]}),e=>e.code==="22023");
   const small=await publish({code:"SMALL",yieldQty:"99999999999999",lines:[line("ITEM",flour,"0.000001",kg)]});
   assert.equal((await requirements(small,"0.000001"))[0].below_precision,true);
  });
  await t.test("package conversions are required and pinned at publication",async()=>{
   await assert.rejects(publish({code:"NO-PACK",lines:[line("ITEM",flour,"1",bag)]}),e=>e.code==="22023");
   const conversion=await scalar("select public.save_material_conversion($1,$2,$3,50,'2026-11-01')",[org,flour,bag]);
   const version=await publish({code:"BAG-RECIPE",lines:[line("ITEM",flour,"1",bag)]});
   await db.query("select public.save_material_conversion($1,$2,$3,40,'2026-12-01')",[org,flour,bag]);
   const saved=(await packet(version)).components[0];
   assert.equal(saved.conversion_id,conversion);assert.equal(saved.normalised_quantity,"50.000000000000");
  });
  await t.test("self/cross-recipe cycles and future children are rejected",async()=>{
   const baseRecipe=(await packet(base)).recipe.id;
   const child=await publish({code:"CHILD",lines:[line("RECIPE",base,"1",kg)]});
   await assert.rejects(publish({recipe:baseRecipe,lines:[line("RECIPE",child,"1",kg)]}),e=>e.code==="22023");
   const future=await publish({code:"FUTURE",date:"2027-01-01",lines:[line("ITEM",flour,"1",kg)]});
   await assert.rejects(publish({code:"BAD-DATE",lines:[line("RECIPE",future,"1",kg)]}),e=>e.code==="22023");
   await assert.rejects(publish({code:"FINAL-CHILD",lines:[line("RECIPE",parent,"1",pcs)]}),e=>e.code==="22023");
  });
  await t.test("tenant boundaries protect readers, references and search",async()=>{
   await login(b);
   const otherKg=await scalar("select id from public.units_of_measure where code='KG'");
   assert.equal((await rows("select * from public.recipes where organisation_id=$1",[org])).length,0);
   await reject("select public.get_recipe_version($1,$2)",[org,parent]);
   await reject("select public.recipe_material_requirements($1,$2,12)",[org,parent]);
   await assert.rejects(publish({tenant:otherOrg,code:"BAD-TENANT",uom:otherKg,lines:[line("RECIPE",base,"1",otherKg)]}),e=>e.code==="42501");
   await reject("select public.search_recipe_components($1,'ITEM','',0)",[org]);
   await db.exec("reset role");
   const member=await scalar("insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id",[org,reader]);
   await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,'finance')",[org,member]);
   await login(reader);
   assert.equal((await packet(base)).cost_state,"MISSING");
   assert.equal(await scalar("select public.can_manage_recipes($1)",[org]),false);
   await assert.rejects(publish({code:"READONLY",lines:[line("ITEM",flour,"1",kg)]}),e=>e.code==="42501");
   await db.exec("reset role;set role anon");await reject("select * from public.recipes",[]);
  });
 }finally{await db.close();}
});
