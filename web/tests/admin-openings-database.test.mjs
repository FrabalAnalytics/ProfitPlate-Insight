import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from './helpers/active-restaurant-db.mjs';
test('administrators record opening stock directly while all other stock controls remain',async t=>{
 const db=new PGlite(),[admin,manager,finance,other]=Array.from({length:4},()=>randomUUID());
 const val=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
 const deny=(work,code='42501')=>assert.rejects(work,e=>e.code===code);
 let org,main,kitchen,rice,fish,kg,token,first;
 const doc=(site=main,note='Verified physical opening stock')=>({kind:'OPENING',destination_id:site,date:'2026-01-01',note});
 const qty=(item=rice,n='10')=>[{item_id:item,quantity:n}];
 const direct=(request=token,header=doc(),lines=qty())=>val('select public.record_admin_opening($1,$2,$3,$4)',[org,request,header,lines]);
 const action=(id,op,note='Checked physical quantities')=>val('select public.stock_document_action($1,$2,$3,$4,null)',[org,id,op,note]);
 const packet=id=>val("select public.stock_workspace_v2($1,null,1,'ALL','',$2)",[org,id]);
 try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
 for(const id of[admin,manager,finance,other])await db.query('insert into auth.users values($1,now(),$2)',[id,`${id}@example.test`]);
 for(const name of(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
 await login(admin);await val("select public.save_restaurant_setup('Direct opening test','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");org=await val('select public.complete_restaurant_setup()');kg=await val("select id from public.units_of_measure where organisation_id=$1 and code='KG'",[org]);rice=await val("select public.save_catalogue_material($1,null,'RICE','Rice','RAW','',$2,true,true)",[org,kg]);fish=await val("select public.save_catalogue_material($1,null,'FISH','Fish','RAW','',$2,true,true)",[org,kg]);
 await db.exec('reset role');for(const[id,role]of[[manager,'inventory_manager'],[finance,'finance']]){const member=await val('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,id]);await db.query('insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,$3)',[org,member,role]);}await login(admin);
 main=await val("select public.save_stock_configuration($1,'LOCATION',$2)",[org,{code:'MAIN',name:'Main Store',kind:'STORE'}]);kitchen=await val("select public.save_stock_configuration($1,'LOCATION',$2)",[org,{code:'KIT',name:'Kitchen',kind:'KITCHEN'}]);token=randomUUID();
 await t.test('manual entry posts once, records the administrator and completes opening readiness',async()=>{
 first=await direct();const p=await packet(first),d=p.selected_document;assert.equal(d.state,'POSTED');assert.equal(d.opening_recorded_directly,true);assert.equal(d.created_by,admin);assert.equal(d.completed_by,admin);assert.equal(d.approved_by,null);assert.equal(Number(p.balances.find(b=>b.item_id===rice&&b.location_id===main).quantity),10);assert.equal(await direct(),first);
 await db.exec('reset role');assert.equal(Number(await val("select count(*) from public.stock_ledger where document_id=$1",[first])),1);assert.equal(Number(await val("select count(*) from public.audit_events where entity_id=$1 and event_type='OPENING_VERIFIED_BY_ADMIN'",[first])),1);assert.equal(await val('select private.pp_opening_ready($1,$2,$3)',[org,rice,main]),true);await login(admin);
 await deny(direct(token,doc(),qty(rice,'12')),'22023');await deny(direct(randomUUID()),'22023');
 });
 await t.test('existing pending openings can be verified directly and validation failures roll back',async()=>{
 await login(manager);const pending=await val('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),doc(),qty(fish)]);await login(admin);assert.equal((await packet(pending)).selected_document.actions.post,true);await deny(action(pending,'POST',''),'22023');assert.equal((await packet(pending)).selected_document.state,'REQUESTED');assert.equal((await packet(pending)).selected_document.opening_recorded_directly,false);await action(pending,'POST');assert.equal((await packet(pending)).selected_document.state,'POSTED');await action(pending,'POST');
 });
 await t.test('Inventory Manager and Finance cannot use the administrator exception',async()=>{
 await login(manager);await deny(direct(randomUUID(),doc(kitchen)));const pending=await val('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),doc(kitchen),qty()]);assert.equal(Boolean((await packet(pending)).selected_document.actions.post),false);await deny(action(pending,'POST'));await deny(action(pending,'APPROVE'));
 await login(finance);await deny(direct(randomUUID(),doc(kitchen)));await login(admin);await action(pending,'APPROVE');await login(manager);await deny(action(pending,'POST'));await login(admin);await action(pending,'POST');assert.equal((await packet(pending)).selected_document.opening_recorded_directly,false);await login(admin);
 });
 await t.test('reviewed imported openings post atomically and retry without duplicating stock',async()=>{
 const batch=randomUUID();await db.exec('reset role');await db.query('insert into private.master_opening_batches(id,organisation_id,site_id,opening_date,created_by) values($1,$2,$3,$4,$5)',[batch,org,kitchen,'2026-01-01',admin]);await db.query('insert into private.master_opening_items values($1,$2,$3,$4,5)',[org,batch,fish,kitchen]);await login(admin);const id=await val('select public.record_imported_opening($1,$2)',[org,batch]);assert.equal((await packet(id)).selected_document.state,'POSTED');assert.equal(await val('select public.record_imported_opening($1,$2)',[org,batch]),id);assert.equal(Number((await packet(id)).balances.find(b=>b.location_id===kitchen&&b.item_id===fish).quantity),5);
 });
 await t.test('other kinds, unassigned materials and unauthorised accounts remain protected',async()=>{
 await deny(direct(randomUUID(),{...doc(),kind:'CONSUMPTION'}),'22023');
 const route=await val("select public.save_stock_configuration($1,'ROUTE',$2)",[org,{source_id:main,destination_id:kitchen,kind:'ISSUE',approval_role:'inventory_manager'}]);await login(manager);const transfer=await val('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),{kind:'ISSUE',route_id:route,date:'2026-01-01',note:'Normal transfer'},qty()]);await deny(action(transfer,'APPROVE'));await deny(action(transfer,'POST'),'22023');await login(admin);const restricted=await val("select public.save_stock_configuration($1,'LOCATION',$2)",[org,{code:'LIMITED',name:'Restricted Store',kind:'STORE'}]);await val('select public.save_centre_materials($1,$2,0,$3,$4)',[org,restricted,randomUUID(),[rice]]);await deny(direct(randomUUID(),doc(restricted),qty(fish)),'22023');
 await login(other);await deny(direct(randomUUID()));await db.exec('reset role;set role anon');await deny(direct(randomUUID()));await login(db.fixtureFounder);await val("select public.set_restaurant_access($1,'ACTIVE','INACTIVE','Pause the restaurant for the access-control test',true)",[org]);await login(admin);await deny(direct());await deny(action(first,'POST'));
 });
 }finally{await db.close();}
});
