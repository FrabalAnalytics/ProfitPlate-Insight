import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile,readdir} from 'node:fs/promises';import {randomUUID} from 'node:crypto';import {PGlite} from './helpers/active-restaurant-db.mjs';
test('same-page profitability filters menus and recipes before summaries and pagination',async t=>{
 const db=new PGlite(),[owner,procurement,finance,other,scoped,inventory,inventoryScoped]=Array.from({length:7},()=>randomUUID());
 const value=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
 const deny=(work,code='42501')=>assert.rejects(work,e=>e.code===code);
 let org,otherOrg,supplier,location,item,kg,pcs,recipe,menu,version;
 const today=new Date().toISOString().slice(0,10),save=(rows,revision)=>value('select public.save_sales_channels($1,$2,$3)',[org,revision,rows]);
 const configured=[{code:'COUNTER',name:'Counter sales',is_active:true},{code:'ROOM_SERVICE',name:'Room service',is_active:true}];
 const dash=(channel='ALL')=>value("select public.menu_profitability_dashboard($1,$2,$3,$4,'',1,'ALL')",[org,location,channel,today]);
 const price=(channel,amount)=>value("select public.save_menu_selling_price($1,$2,$3,$4,$5,$6,'NONE',0,$7,null,'Training')",[org,menu,randomUUID(),location,channel,amount,today]);
 try{
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
  for(const id of[owner,procurement,finance,other,scoped,inventory,inventoryScoped])await db.query('insert into auth.users values($1,now(),$2)',[id,`${id}@example.test`]);
  for(const name of(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
  for(const id of[other,owner]){await login(id);await value("select public.save_restaurant_setup('Procurement Test','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");const result=await value('select public.complete_restaurant_setup()');if(id===owner)org=result;else otherOrg=result;}
  location=await value('select id from public.locations where organisation_id=$1',[org]);kg=await value("select id from public.units_of_measure where organisation_id=$1 and code='KG'",[org]);item=await value("select public.save_catalogue_material($1,null,'RICE','Rice','RAW','',$2,true,true)",[org,kg]);supplier=await value("select public.save_catalogue_supplier($1,null,'SUP','Supplier','','','',true)",[org]);
  await db.exec('reset role');for(const[id,role,scope]of[[procurement,'procurement',null],[finance,'finance',null],[scoped,'procurement',location],[inventory,'inventory',null],[inventoryScoped,'inventory',location]]){const m=await value('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,id]);await db.query('insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,$3,$4)',[org,m,role,scope]);}await login(procurement);

 await login(owner);

 await save(configured,0);pcs=await value("select id from public.units_of_measure where organisation_id=$1 and code='PCS'",[org]);
 const brand=await value('select brand_id from public.locations where id=$1',[location]);
 const prices=[{material_code:'RICE',quantity:'1',unit_code:'KG',total_price:'1000',price_date:today,source_note:'Starting price'}],preview=await value('select public.preview_material_reference_prices($1,$2)',[org,prices]);await value("select public.save_material_reference_prices($1,$2,'MANUAL',$3,$4)",[org,randomUUID(),prices,preview]);
 recipe=await value("select public.publish_recipe_version($1,null,$2,'CHANNEL-RECIPE','Channel recipe','FINAL',$3,1,$4,'',$5)",[org,randomUUID(),today,pcs,[{kind:'ITEM',target_id:item,quantity:'1',uom_id:kg}]]);
 version=await value("select public.publish_menu_item_version($1,null,$2,'CHANNEL-MENU','Channel plate',$3,'Mains',$4,1,$5,'')",[org,randomUUID(),brand,recipe,today]);menu=await value('select menu_item_id from public.menu_item_versions where id=$1',[version]);await value("select public.save_setup_profile($1,'MENU',$2,null,'FOOD','Mains',false,'PURCHASED')",[org,menu]);await value('select public.save_cost_targets($1,null,40,25)',[org]);await price('COUNTER','2000');await price('ROOM_SERVICE','4000');
 const compare=(kind='MENU',page=1,search='',status='ALL',channel='ALL')=>value('select public.profitability_items_dashboard($1,$2,$3,$4,$5,$6,$7,$8)',[org,location,channel,today,search,page,status,kind]);
 await t.test('Menu keeps channel rows; Recipes appears once with costs and no invented selling margins',async()=>{
  const m=await compare();assert.equal(m.total,2);assert.ok(m.rows.every(r=>r.item_kind==='MENU'));assert.deepEqual(m.summary.at_risk,(await dash()).summary.at_risk);
  const r=await compare('RECIPE');assert.equal(r.total,1);assert.equal(r.summary.recipes_costed,1);assert.equal(r.summary.target_not_set,0);assert.equal(r.summary.incomplete,0);assert.equal(r.rows[0].channel_code,null);assert.equal(r.rows[0].target,null);assert.equal(r.rows[0].target_state,'COSTED');assert.equal(Number(r.rows[0].estimate.cost_per_output_unit),1000);assert.equal(r.rows[0].estimate.net_revenue,undefined);assert.equal(r.rows[0].output_unit,'PCS');assert.equal((await compare('RECIPE',1,'','ALL','COUNTER')).total,1);
  const all=await compare('ALL');assert.equal(all.total,3);assert.equal(all.summary.at_risk,1);assert.equal(all.summary.within_target,1);assert.equal(all.summary.recipes_costed,1);assert.equal((await compare('RECIPE',1,'','AT_RISK')).total,0);
 });
 await t.test('search, type and status apply before pagination with more than 60 recipes',async()=>{
  await db.exec('reset role');
  for(let n=0;n<61;n++)await db.query("insert into public.recipes(organisation_id,code,name,recipe_type,created_by) values($1,$2,$3,'SUB_RECIPE',$4)",[org,'DRAFT-'+n,'Draft '+String(n).padStart(2,'0'),owner]);
  await login(owner);const r=await compare('RECIPE',2);assert.equal(r.total,62);assert.equal(r.rows.length,25);assert.ok(r.rows.every(r=>r.item_kind==='RECIPE'));assert.equal(r.summary.incomplete,61);assert.equal(r.summary.recipes_costed,1);assert.equal((await compare('MENU')).total,2);assert.equal((await compare('ALL')).total,64);assert.equal((await compare('RECIPE',1,'DRAFT-60')).total,1);assert.equal((await compare('RECIPE',1,'','COSTED')).total,1);assert.equal((await compare('RECIPE',3)).rows.length,12);
 });
 await t.test('dated and location-scoped recipe versions stay in their permitted scope',async()=>{
  await db.exec('reset role');const loc=await value("insert into public.locations(organisation_id,brand_id,code,name,timezone) values($1,$2,'OTHER','Other outlet','Africa/Lagos') returning id",[org,brand]);await db.query("update public.recipes set location_id=$1 where organisation_id=$2 and code='DRAFT-60'",[loc,org]);await login(owner);assert.equal((await compare('RECIPE',1,'DRAFT-60')).total,0);
  const old=await value("select public.profitability_items_dashboard($1,$2,'ALL',$3,'CHANNEL-RECIPE',1,'ALL','RECIPE')",[org,location,'2000-01-01']);assert.equal(old.rows[0].version_id,null);assert.equal(old.rows[0].target_state,'INCOMPLETE');
 });
 await t.test('financial role gates and tenant isolation are retained',async()=>{
  await login(finance);assert.ok((await compare('ALL')).total>0);await login(inventory);await deny(compare('ALL'));await login(scoped);await deny(compare('RECIPE'));await login(other);await deny(compare('ALL'));await login(owner);await deny(compare('INVALID'),'22023');await deny(compare('ALL',1,'','INVALID'),'22023');await deny(compare('ALL',1,'','ALL','MISSING'),'22023');assert.ok(otherOrg&&supplier);
 });
 }finally{await db.close();}
});
