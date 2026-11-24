import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from './helpers/active-restaurant-db.mjs';
test('explicit centre catalogues separate permitted materials from stock quantities and preserve history',async t=>{
 const db=new PGlite(),[owner,manager,finance,other]=Array.from({length:4},()=>randomUUID());
 const val=async(sql,args=[])=>{const row=(await db.query(sql,args)).rows[0];return row?Object.values(row)[0]:null;};
 const login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
 const deny=(work,code='22023')=>assert.rejects(work,e=>e.code===code);
 let org,kg,a,b,main,kitchen,bar;
 const catalogue=site=>val('select public.centre_material_catalogue($1,$2)',[org,site]);
 const save=(site,revision,items,token=randomUUID())=>val('select public.save_centre_materials($1,$2,$3,$4,$5)',[org,site,revision,token,items]);
 const packet=()=>val("select public.stock_workspace_v2($1,null,1,'ALL','',null)",[org]);
 try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
 for(const id of[owner,manager,finance,other])await db.query('insert into auth.users values($1,now(),$2)',[id,`${id}@example.test`]);
 for(const name of(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
 await login(owner);await val("select public.save_restaurant_setup('Centre catalogue test','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");org=await val('select public.complete_restaurant_setup()');kg=await val("select id from public.units_of_measure where organisation_id=$1 and code='KG'",[org]);
 a=await val("select public.save_catalogue_material($1,null,'FISH','Fish','RAW','',$2,true,true)",[org,kg]);b=await val("select public.save_catalogue_material($1,null,'BEER','Beer','RAW','',$2,true,true)",[org,kg]);
 const ownMember=await val('select id from public.organisation_memberships where organisation_id=$1 and user_id=$2',[org,owner]);
 await db.exec('reset role');for(const[id,role]of[[owner,'inventory_manager'],[manager,'inventory_manager'],[finance,'finance']]){let member=await val('select id from public.organisation_memberships where organisation_id=$1 and user_id=$2',[org,id]);if(!member)member=await val('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,id]);await db.query('insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,$3)',[org,member,role]);}await login(owner);
 for(const code of['MAIN','KITCHEN','BAR']){const id=await val('select public.save_stock_centre($1,$2)',[org,{code,name:code,kind:'STORE',responsible:ownMember,restrict_materials:true}]);if(code==='MAIN')main=id;else if(code==='KITCHEN')kitchen=id;else bar=id;}
 await t.test('new explicit centres start empty; assignment is audited, revisioned and retry safe',async()=>{
 assert.equal((await catalogue(main)).legacy,false);assert.equal((await packet()).items.length,0);const request=randomUUID();assert.equal(await save(main,0,[a,b],request),1);assert.equal(await save(main,0,[a,b],request),1);await deny(save(main,0,[a]));await deny(save(main,1,[a],request));await save(kitchen,0,[a]);await save(bar,0,[b]);
 const p=await packet();assert.deepEqual(p.items.find(i=>i.id===a).centre_ids.sort(),[main,kitchen].sort());assert.equal(p.items.find(i=>i.id===a).centre_ids.includes(bar),false);
 });
 await t.test('assigned zero-stock materials remain requestable; unassigned requests fail on the server',async()=>{
 const route=await val("select public.save_stock_configuration($1,'ROUTE',$2)",[org,{source_id:main,destination_id:kitchen,kind:'ISSUE',approval_role:'inventory_manager'}]);
 const doc=await val('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),{kind:'ISSUE',route_id:route,date:'2026-01-01',note:'Kitchen can request before delivery'},[{item_id:a,quantity:'5'}]]);
 await deny(save(kitchen,1,[]));await val("select public.stock_document_action($1,$2,'CANCEL','Cancel fixture request',null)",[org,doc]);
 await deny(val('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),{kind:'OPENING',destination_id:bar,date:'2026-01-01',note:'Not assigned here'},[{item_id:a,quantity:'2'}]]));
 });
 await t.test('real holdings block removal and historical movement rows remain available',async()=>{
 await db.exec('reset role');const doc=await val("insert into public.stock_documents(organisation_id,request_id,input_hash,reference,kind,state,destination_id,document_date,note,lines,created_by) values($1,$2,'fixture','CAT-OPEN','OPENING','POSTED',$3,'2026-01-01','Verified fixture stock',$4,$5) returning id",[org,randomUUID(),main,[{item_id:a,quantity:'10'}],owner]);await db.query("insert into public.stock_ledger(organisation_id,document_id,location_id,item_id,quantity,occurred_on) values($1,$2,$3,$4,10,'2026-01-01')",[org,doc,main,a]);await login(owner);await deny(save(main,1,[b]));assert.equal((await catalogue(main)).items.find(i=>i.id===a).held,'10.000000000000');
 await save(kitchen,1,[]);assert.equal((await packet()).items.find(i=>i.id===a).centre_ids.includes(kitchen),false);
 });
 await t.test('production outputs and dated count scope obey the centre catalogue',async()=>{
 await db.exec('reset role');
 await deny(db.query("insert into public.stock_documents(organisation_id,request_id,input_hash,reference,kind,state,source_id,document_date,note,lines,output,created_by) values($1,$2,'fixture','CAT-BAD-PROD','PRODUCTION','REQUESTED',$3,current_date,'Invalid output centre',$4,$5,$6)",[org,randomUUID(),bar,[{item_id:b,quantity:'1'}],{item_id:a,quantity:'3'},owner]));
 assert.equal(await val('select private.pp_centre_material($1,$2,$3,current_date)',[org,bar,a]),false);
 assert.equal(await val("select private.pp_centre_material($1,$2,$3,'2020-01-01')",[org,bar,a]),true);
 await login(owner);const scope=await val('select public.weekly_count_scope($1,$2)',[org,bar]);assert.equal(scope.items.some(i=>i.id===a),false);
 });
 await t.test('scope choices do not change quantities, unit correction rules or confidentiality',async()=>{
 const unused=await val("select public.save_catalogue_material($1,null,'UNUSED','Unused material','RAW','',$2,true,true)",[org,kg]);await save(bar,1,[b,unused]);assert.equal((await val('select public.material_editability($1,$2)',[org,unused])).can_change_unit,true);
 await login(manager);assert.equal((await catalogue(bar)).centre,'BAR');await login(finance);await deny(catalogue(bar),'42501');await deny(save(bar,2,[]),'42501');await login(other);await deny(catalogue(bar),'42501');await login(owner);await deny(save(bar,2,[randomUUID()]));await db.exec('reset role;set role anon');await deny(catalogue(bar),'42501');
 });
 }finally{await db.close();}
});
