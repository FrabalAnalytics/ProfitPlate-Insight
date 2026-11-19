import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile,readdir} from 'node:fs/promises';import {randomUUID} from 'node:crypto';import {PGlite} from '@electric-sql/pglite';
test('PO last purchase prices honour source corrections, historical dates, units and access',async t=>{
 const db=new PGlite(),[owner,procurement,finance,other,scoped,inventory,inventoryScoped]=Array.from({length:7},()=>randomUUID());
 const value=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
 const deny=(sql,args=[],code='42501')=>assert.rejects(db.query(sql,args),e=>e.code===code);
 let org,otherOrg,supplier,location,item,kg,grams,bag,latest;
 const lookup=(unit=kg,date='2020-10-03')=>value('select public.po_last_purchase_price($1,$2,$3,$4)',[org,item,unit,date]);
 const record=async(ref,price,qty,unit,date)=>{
  const total=String(Number(price)*Number(qty));
  const b=await value('select public.stage_manual_purchase($1,$2,$3,$4)',[org,randomUUID(),{supplier_id:supplier,location_id:location,date,reference:ref,price_basis:'EXCLUSIVE',total,route:'DIRECT',direct_reason:'Training purchase',evidence:'Paper invoice'},[{item_id:item,uom_id:unit,quantity:qty,unit_price:price,discount:'0',tax:'0'}]]);
  const report=await value('select public.get_purchase_import($1,$2)',[org,b]);await value('select public.post_purchase_import($1,$2,$3)',[org,b,Object.fromEntries(report.report.documents.map(d=>[d.key,d.total]))]);
  return value('select id from public.purchase_headers where organisation_id=$1 and purchase_ref=$2',[org,ref]);
 };
 try{
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
  for(const id of[owner,procurement,finance,other,scoped,inventory,inventoryScoped])await db.query('insert into auth.users values($1,now(),$2)',[id,`${id}@example.test`]);
  for(const name of(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
  for(const id of[other,owner]){await login(id);await value("select public.save_restaurant_setup('Procurement Test','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");const result=await value('select public.complete_restaurant_setup()');if(id===owner)org=result;else otherOrg=result;}
  location=await value('select id from public.locations where organisation_id=$1',[org]);kg=await value("select id from public.units_of_measure where organisation_id=$1 and code='KG'",[org]);item=await value("select public.save_catalogue_material($1,null,'RICE','Rice','RAW','',$2,true,true)",[org,kg]);supplier=await value("select public.save_catalogue_supplier($1,null,'SUP','Supplier','','','',true)",[org]);
  await db.exec('reset role');for(const[id,role,scope]of[[procurement,'procurement',null],[finance,'finance',null],[scoped,'procurement',location],[inventory,'inventory',null],[inventoryScoped,'inventory',location]]){const m=await value('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,id]);await db.query('insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,$3,$4)',[org,m,role,scope]);}await login(procurement);
 grams=await value("select id from public.units_of_measure where organisation_id=$1 and code='G'",[org]);bag=await value("select id from public.units_of_measure where organisation_id=$1 and code='BAG'",[org]);
 await t.test('missing history stays absent and initial prices are identified separately',async()=>{
  assert.equal((await lookup()).status,'NOT_FOUND');const rows=[{material_code:'RICE',quantity:'1',unit_code:'KG',total_price:'1000',price_date:'2020-09-25',source_note:'Starting last purchase price'}],preview=await value('select public.preview_material_reference_prices($1,$2)',[org,rows]);await value("select public.save_material_reference_prices($1,$2,'MANUAL',$3,$4)",[org,randomUUID(),rows,preview]);const p=await lookup();assert.equal(p.source,'INITIAL_PRICE');assert.equal(Number(p.unit_price),1000);assert.equal((await lookup(kg,'2020-09-20')).status,'NOT_FOUND');
 });
 await t.test('the latest invoice price replaces the fallback and converts to the selected unit',async()=>{
  await record('OLD','100','2',kg,'2020-10-02');latest=await record('LATEST','0.3','1000',grams,'2020-10-03');const p=await lookup();assert.equal(p.source,'INVOICE');assert.equal(p.reference,'LATEST');assert.equal(p.price_basis,'EXCLUSIVE');assert.equal(Number(p.unit_price),300);assert.equal(Number((await lookup(grams)).unit_price),0.3);assert.equal(Number((await lookup(kg,'2020-10-02')).unit_price),100);
 });
 await t.test('dated package conversions are material-specific and missing conversions stay unavailable',async()=>{
  assert.equal((await lookup(bag)).status,'CONVERSION_REQUIRED');await value('select public.save_material_conversion($1,$2,$3,50,$4)',[org,item,bag,'2020-10-01']);await value('select public.save_material_conversion($1,$2,$3,25,$4)',[org,item,bag,'2020-10-05']);assert.equal(Number((await lookup(bag)).unit_price),15000);assert.equal(Number((await lookup(bag,'2020-10-05')).unit_price),7500);
 });
 await t.test('later purchases cannot leak into a historical PO price',async()=>{
  await record('LATER','900','1',kg,'2020-10-06');assert.equal(Number((await lookup()).unit_price),300);assert.equal(Number((await lookup(kg,'2020-10-06')).unit_price),900);
 });
 await t.test('pending corrections are excluded; approved corrections and voids replace source evidence',async()=>{
  const correction=await value('select public.request_purchase_correction($1,$2,$3,$4,$5,$6,$7,$8)',[org,latest,randomUUID(),0,'REPLACE','Supplier correction',{supplier_id:supplier,location_id:location,date:'2020-10-03',reference:'LATEST',price_basis:'EXCLUSIVE',total:'400'},[{item_id:item,uom_id:grams,quantity:'1000',unit_price:'0.4',discount:'0',tax:'0'}]]);assert.equal(Number((await lookup()).unit_price),300);
  await login(finance);await value("select public.decide_purchase_correction($1,$2,true,'Checked')",[org,correction]);await login(procurement);assert.equal(Number((await lookup()).unit_price),400);
  const v=await value('select public.request_purchase_correction($1,$2,$3,$4,$5,$6,$7,$8)',[org,latest,randomUUID(),1,'VOID','Duplicate invoice',{},[]]);await login(finance);await value("select public.decide_purchase_correction($1,$2,true,'Checked')",[org,v]);await login(procurement);assert.equal(Number((await lookup()).unit_price),100);
 });
 await t.test('read-only lookup cannot expose another restaurant or broaden role scope',async()=>{
  for(const actor of [finance,inventory,scoped,other]){await login(actor);await deny('select public.po_last_purchase_price($1,$2,$3,null)',[org,item,kg]);}await login(procurement);await deny('select public.po_last_purchase_price($1,$2,$3,null)',[otherOrg,item,kg]);await deny('select public.po_last_purchase_price($1,$2,$3,null)',[org,randomUUID(),kg],'22023');await db.exec('reset role;set role anon');await deny('select public.po_last_purchase_price($1,$2,$3,null)',[org,item,kg]);
 });
 }finally{await db.close();}
});
