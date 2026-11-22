import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from './helpers/active-restaurant-db.mjs';

test('reviewed master imports preserve stock controls, versions, scopes and retries',async t=>{
 const db=new PGlite();const owner=randomUUID(),finance=randomUUID(),inventory=randomUUID(),outsider=randomUUID();
 const value=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const inspect=async(sql,args=[])=>{await db.exec('reset role');try{return await value(sql,args);}finally{await db.exec('set role authenticated');}};
 const login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
 const deny=(promise,code='42501')=>assert.rejects(promise,e=>e.code===code);
 const day=new Date().toISOString().slice(0,10);let org,centre,kg;
 const material=(code='FISH',extra={})=>({action:'CREATE',material_code:code,material_name:'Whole fish',material_type:'RAW',category:'Fish',base_unit:'KG',stock_tracked:'true',weekly_count_required:'true',supply_source:'PURCHASED',requires_processing:'true',last_purchase_unit_price:'3000',last_purchase_date:day,centre_code:'',opening_quantity:'',opening_date:'',...extra});
 const recipe=(code,child,kind='ITEM',extra={})=>({action:'CREATE',recipe_code:code,recipe_name:code,recipe_type:'SUB_RECIPE',yield_quantity:'10',yield_unit:'PCS',effective_from:day,notes:'',component_kind:kind,component_code:child,component_version:'',component_quantity:'2',component_unit:'KG',...extra});
 const preview=(kind,rows,site=null)=>value('select public.preview_master_import($1,$2,$3,$4)',[org,kind,site,rows]);
 const post=(kind,rows,plan,token=randomUUID(),site=null)=>value('select public.post_master_import($1,$2,$3,$4,$5,$6)',[org,kind,site,token,rows,plan]);
 try{
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
  for(const id of[owner,finance,inventory,outsider])await db.query('insert into auth.users values($1,now(),$2)',[id,`${id}@example.test`]);
  for(const name of(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
  await login(owner);await value("select public.save_restaurant_setup('Bulk Test','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");org=await value('select public.complete_restaurant_setup()');
  const member=await value('select id from public.organisation_memberships where organisation_id=$1 and user_id=$2',[org,owner]);
  centre=await value("select public.save_stock_centre($1,$2)",[org,{code:'MAIN',name:'Main store',kind:'STORE',responsible:member,processing_enabled:false}]);
  kg=await value("select id from public.units_of_measure where organisation_id=$1 and code='KG'",[org]);
  await db.exec('reset role');
  for(const[id,role]of[[finance,'finance'],[inventory,'inventory_manager']]){const m=await value('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,id]);await db.query('insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,$3)',[org,m,role]);}await login(owner);

  await t.test('preview rolls back all master, price, audit and staged opening changes',async()=>{
   const rows=[material('FISH',{centre_code:'MAIN',opening_quantity:'40',opening_date:day})];
   const audits=await value('select count(*)::int from public.audit_events where organisation_id=$1',[org]);
   const p=await preview('MATERIAL',rows);assert.equal(p.valid,true,JSON.stringify(p));assert.equal(p.rows[0].action,'CREATE');assert.ok(centre);assert.deepEqual(await preview('MATERIAL',rows),p);
   assert.equal(await value("select count(*)::int from public.items where organisation_id=$1 and code='FISH'",[org]),0);
   assert.equal(await value('select count(*)::int from public.audit_events where organisation_id=$1',[org]),audits);
   assert.equal((await value('select public.import_opening_queue($1)',[org])).length,0);
   const token=randomUUID();assert.equal(await post('MATERIAL',rows,p,token),1);assert.equal(await post('MATERIAL',rows,p,token),0);
   assert.equal(await inspect('select count(*)::int from public.stock_ledger where organisation_id=$1',[org]),0);
   assert.equal(await value('select count(*)::int from public.material_reference_prices where organisation_id=$1',[org]),1);
   assert.equal((await preview('MATERIAL',rows)).valid,false);
   await deny(post('MATERIAL',[{...rows[0],material_name:'Changed'}],p,token),'22023');
  });
  await t.test('staged opening uses the native request, independent approval and posting rules',async()=>{
   const q=await value('select public.import_opening_queue($1)',[org]);assert.equal(q.length,1);assert.equal(q[0].can_submit,false);await deny(value('select public.submit_import_opening($1,$2)',[org,q[0].id]));
   await login(inventory);const doc=await value('select public.submit_import_opening($1,$2)',[org,q[0].id]);assert.equal(await value('select public.submit_import_opening($1,$2)',[org,q[0].id]),doc);
   assert.equal(await inspect('select state from public.stock_documents where id=$1',[doc]),'REQUESTED');assert.equal(await inspect('select count(*)::int from public.stock_ledger where organisation_id=$1',[org]),0);
   await deny(value("select public.stock_document_action($1,$2,'APPROVE','Checked',null)",[org,doc]));
   await login(owner);await value("select public.stock_document_action($1,$2,'APPROVE','Verified',null)",[org,doc]);
   await login(inventory);await value("select public.stock_document_action($1,$2,'POST','Posted',null)",[org,doc]);
   assert.equal(Number(await inspect('select sum(quantity) from public.stock_ledger where organisation_id=$1',[org])),40);await login(owner);
  });
  await t.test('invalid rows, duplicate openings and changed reviews cannot partially save',async()=>{
   const rows=[material('OIL'),material('BAD',{base_unit:'UNKNOWN'})],p=await preview('MATERIAL',rows);assert.equal(p.valid,false);assert.ok(p.rows[1].error);await deny(post('MATERIAL',rows,p),'22023');assert.equal(await value("select count(*)::int from public.items where organisation_id=$1 and code='OIL'",[org]),0);
   const duplicate=[material('FISH',{action:'UPDATE',centre_code:'MAIN',opening_quantity:'40',opening_date:day})];assert.equal((await preview('MATERIAL',duplicate)).valid,false);
   const good=[material('OIL')],review=await preview('MATERIAL',good);await value("select public.save_catalogue_material($1,null,'SIDE','Side','RAW','',$2,true,true)",[org,kg]);await deny(post('MATERIAL',good,review),'22023');
  });
  await t.test('multiple centres save one material and price; zero is distinct from blank',async()=>{
   const member=await value('select id from public.organisation_memberships where organisation_id=$1 and user_id=$2',[org,owner]);
   await value('select public.save_stock_centre($1,$2)',[org,{code:'KITCHEN',name:'Kitchen',kind:'KITCHEN',responsible:member,processing_enabled:false}]);
   const rows=[material('RICE',{centre_code:'MAIN',opening_quantity:'0',opening_date:day}),material('RICE',{centre_code:'KITCHEN',opening_quantity:'10',opening_date:day})];const p=await preview('MATERIAL',rows);assert.equal(p.valid,true,JSON.stringify(p));await post('MATERIAL',rows,p);
   assert.equal(await value("select count(*)::int from public.material_reference_prices p join public.items i on i.id=p.item_id where i.organisation_id=$1 and i.code='RICE'",[org]),1);
   const q=await value('select public.import_opening_queue($1)',[org]);assert.equal(q.length,2);assert.equal(q.find(r=>r.centre==='Main store').lines[0].quantity,'0');
   await login(inventory);assert.equal(await value('select public.submit_import_opening($1,$2)',[org,q.find(r=>r.centre==='Main store').id]),null);await login(owner);
   assert.equal(await inspect('select count(*)::int from public.zero_opening_confirmations where organisation_id=$1',[org]),1);
   const blank=[material('NO_PRICE',{last_purchase_unit_price:'',last_purchase_date:''})];const a=await preview('MATERIAL',blank);assert.equal(a.valid,true);assert.match(a.rows[0].warning,/No purchase price/);await post('MATERIAL',blank,a);
  });
  await t.test('recipe import resolves unsorted nested dependencies and pins versions',async()=>{
   const rows=[recipe('PLATE','PREP','RECIPE',{recipe_type:'FINAL',component_unit:'PCS',component_quantity:'1',yield_quantity:'1'}),recipe('PREP','FISH')];
   const p=await preview('RECIPE',rows);assert.equal(p.valid,true,JSON.stringify(p));assert.equal(p.rows[0].code,'PREP');assert.equal(await value("select count(*)::int from public.recipes where organisation_id=$1 and code in('PREP','PLATE')",[org]),0);
   const token=randomUUID();await post('RECIPE',rows,p,token);assert.equal(await post('RECIPE',rows,p,token),0);
   const update=[recipe('PREP','FISH','ITEM',{action:'NEW_VERSION',component_quantity:'3'})];const p2=await preview('RECIPE',update);assert.equal(p2.valid,true);await post('RECIPE',update,p2);
   assert.equal(await value("select v.version from public.recipe_components c join public.recipe_versions p on p.id=c.recipe_version_id join public.recipes a on a.id=p.recipe_id join public.recipe_versions v on v.id=c.child_recipe_version_id where a.organisation_id=$1 and a.code='PLATE'",[org]),1);
   assert.equal(await inspect('select count(*)::int from public.stock_ledger where organisation_id=$1',[org]),1);
  });
  await t.test('cycles, inconsistent headers, invalid units and missing children block publication',async()=>{
   for(const rows of [[recipe('CYCLE_A','CYCLE_B','RECIPE',{component_unit:'PCS'}),recipe('CYCLE_B','CYCLE_A','RECIPE',{component_unit:'PCS'})],[recipe('BAD_RECIPE','MISSING')],[recipe('HEADER','FISH'),recipe('HEADER','RICE','ITEM',{recipe_name:'Different'})],[recipe('UNIT','FISH','ITEM',{component_unit:'PCS'})]]){const p=await preview('RECIPE',rows);assert.equal(p.valid,false,JSON.stringify(p));await deny(post('RECIPE',rows,p),'22023');}
   assert.equal(await value("select count(*)::int from public.recipes where organisation_id=$1 and code like 'CYCLE%'",[org]),0);
  });
  await t.test('menu imports resolve an omitted version to the latest eligible final recipe and save one standard price',async()=>{
   const site=await value('select id from public.locations where organisation_id=$1',[org]);
   await value('select public.save_menu_categories($1,0,$2)',[org,[{major:'FOOD',name:'Mains',is_active:true}]]);
   const rows=[{action:'CREATE',menu_code:'PLATE_MENU',menu_name:'Fish plate',major_category:'FOOD',subcategory:'Mains',recipe_code:'PLATE',recipe_version:'',recipe_quantity:'1',selling_price:'6000',tax_setting:'NONE',tax_percent:'0',effective_from:day}];
   const p=await value('select public.preview_menu_catalogue_import($1,$2,$3)',[org,site,rows]);assert.equal(p.valid,true,JSON.stringify(p));assert.ok(p.rows[0].value.recipe_version_id);
   assert.equal(await value('select public.post_menu_catalogue_import($1,$2,$3,$4,$5)',[org,site,randomUUID(),rows,p]),1);
   assert.equal(await value("select count(*)::int from public.menu_price_versions p join public.menu_items i on i.id=p.menu_item_id where i.organisation_id=$1 and i.code='PLATE_MENU'",[org]),1);
  });
  await t.test('imports reject unauthorised roles and foreign scopes; Founder suspension blocks even retries',async()=>{
   for(const id of[finance,inventory,outsider]){await login(id);await deny(preview('MATERIAL',[material('UNAUTH')]));await deny(preview('RECIPE',[recipe('UNAUTH','FISH')]));}await login(owner);
   await deny(preview('MATERIAL',[material('FOREIGN')],randomUUID()),'22023');
   await db.exec('reset role');await db.query('insert into private.platform_admins(user_id) values($1)',[outsider]);await login(outsider);
   await value("select public.set_restaurant_access($1,'ACTIVE','INACTIVE','Import suspension check',true)",[org]);
   await login(owner);await deny(preview('MATERIAL',[material('LOCKED')]));await deny(preview('RECIPE',[recipe('LOCKED','FISH')]));
   await deny(value('select public.import_opening_queue($1)',[org]));
  });
 }finally{await db.close();}
});
