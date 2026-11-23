import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from './helpers/active-restaurant-db.mjs';

test('restaurant units and safe unused-material corrections preserve linked history',async t=>{
 const db=new PGlite(),[owner,otherOwner,finance]=Array.from({length:3},()=>randomUUID());
 const val=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
 const rejects=(work,code='22023')=>assert.rejects(work,e=>e.code===code);
 let org,other,kg,g,bag,rice;
 const unit=(code,name,dim,factor)=>val('select public.create_catalogue_unit($1,$2,$3,$4,$5)',[org,code,name,dim,factor]);
 const material=(code,id=null,uom=kg)=>val("select public.save_catalogue_material($1,$2,$3,$3,'RAW','',$4,true,true)",[org,id,code,uom]);
 const status=id=>val('select public.material_editability($1,$2)',[org,id]);
 try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
 for(const id of [owner,otherOwner,finance])await db.query('insert into auth.users values($1,now(),$2)',[id,`${id}@example.test`]);
 for(const name of(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
 for(const id of[otherOwner,owner]){await login(id);await val("select public.save_restaurant_setup('Unit Test','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");const created=await val('select public.complete_restaurant_setup()');if(id===owner)org=created;else other=created;}
 kg=await val("select id from public.units_of_measure where code='KG' and organisation_id=$1",[org]);g=await val("select id from public.units_of_measure where code='G' and organisation_id=$1",[org]);bag=await val("select id from public.units_of_measure where code='BAG' and organisation_id=$1",[org]);
 await t.test('custom units retain precise factors, packages have no universal size, retries are safe',async()=>{
 const dozen=await unit('dozen','Dozen','COUNT','12');assert.equal(await unit('DOZEN','Dozen','COUNT','12'),dozen);await unit('CRATE','Crate','PACKAGE',null);await unit('MG','Milligram','MASS','0.000001');
 assert.equal(await val('select canonical_factor::text from public.units_of_measure where id=$1',[dozen]),'12.000000');
 await rejects(unit('DOZEN','Dozen','COUNT','24'),'23505');for(const factor of ['0','-2','NaN','0.0000001','1e3','100000000000000'])await rejects(unit('BAD','Bad','COUNT',factor));await rejects(unit('BOX','Box','PACKAGE','10'));await rejects(unit('BAD CODE','Bad','MASS','1'));await rejects(unit('X','X','OTHER','1'));
 await rejects(db.query('update public.units_of_measure set canonical_factor=2 where id=$1',[dozen]),'42501');
 });
 await t.test('unused base unit can be corrected through the normal material setup API',async()=>{
 rice=await material('UNUSED');assert.equal((await status(rice)).can_change_unit,true);
 await val('select public.save_material_setup($1,$2)',[org,{id:rice,code:'UNUSED',name:'Corrected material',item_type:'RAW',base_uom_id:g,stock_tracked:true,is_active:true,supply_class:'PURCHASED'}]);assert.equal(await val('select base_uom_id from public.items where id=$1',[rice]),g);
 await material('UNUSED',rice,kg);await rejects(material('CHANGED',rice));await rejects(material('UNUSED',rice,bag));
 });
 await t.test('unused deletion requires exact confirmation and preserves audit evidence',async()=>{
 const id=await material('DELETE_ME');await rejects(val('select public.delete_unused_material($1,$2,$3)',[org,id,'WRONG']));await val('select public.delete_unused_material($1,$2,$3)',[org,id,'DELETE_ME']);assert.equal(await val('select count(*)::int from public.items where id=$1',[id]),0);assert.equal(await val("select count(*)::int from public.audit_events where event_type='material.deleted' and entity_id=$1",[id]),1);await rejects(val('select public.delete_unused_material($1,$2,$3)',[org,id,'DELETE_ME']));
 });
 await t.test('versioned conversions prevent unit edits and deletion but allow ordinary edits',async()=>{
 await val("select public.save_material_conversion($1,$2,$3,'50','2026-01-01')",[org,rice,bag]);assert.equal((await status(rice)).can_change_unit,false);await rejects(material('UNUSED',rice,g));await rejects(val('select public.delete_unused_material($1,$2,$3)',[org,rice,'UNUSED']));assert.equal(await material('UNUSED',rice),rice);
 });
 await t.test('draft stock documents with embedded item IDs protect their captured quantities',async()=>{
 const id=await material('STOCK_DRAFT'),member=await val('select id from public.organisation_memberships where organisation_id=$1 and user_id=$2',[org,owner]);const site=await val('select public.save_stock_centre($1,$2)',[org,{code:'MAIN',name:'Main store',kind:'STORE',responsible:member}]);
 await db.exec('reset role');await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,'inventory_manager')",[org,member]);await login(owner);
 await val('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),{kind:'OPENING',destination_id:site,date:'2026-01-01',note:'Opening test'},[{item_id:id,quantity:'10'}]]);
 assert.equal((await status(id)).can_delete,false);await rejects(material('STOCK_DRAFT',id,g));await rejects(val('select public.delete_unused_material($1,$2,$3)',[org,id,'STOCK_DRAFT']));await db.exec('reset role');assert.equal(await val('select count(*)::int from public.stock_ledger'),0);await login(owner);
 });
 await t.test('permissions block outsiders, Finance, direct deletes and inactive restaurants',async()=>{
 await db.exec('reset role');const m=await val('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,finance]);await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,'finance')",[org,m]);
 for(const id of[finance,otherOwner]){await login(id);await rejects(unit('FORBIDDEN','Forbidden','COUNT','1'),'42501');await rejects(status(rice),'42501');await rejects(val('select public.delete_unused_material($1,$2,$3)',[org,rice,'UNUSED']),'42501');}
 await login(owner);const foreignUnit=await (async()=>{await login(otherOwner);const id=await val("select id from public.units_of_measure where organisation_id=$1 and code='KG'",[other]);await login(owner);return id;})();await rejects(material('FOREIGN',null,foreignUnit));await rejects(db.query('delete from public.items where id=$1',[rice]),'42501');
 await db.exec('reset role');await db.query("update public.organisation_memberships set status='inactive' where organisation_id=$1 and user_id=$2",[org,owner]);await login(owner);await rejects(unit('INACTIVE','Inactive','COUNT','1'),'42501');
 await db.exec('reset role;set role anon');await rejects(db.query("select public.create_catalogue_unit($1,'X','X','COUNT','1')",[org]),'42501');
 });
 }finally{await db.close();}
});
