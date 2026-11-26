import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from './helpers/active-restaurant-db.mjs';
test('management-only stock corrections preserve independent review and operational stock' ,async t=>{
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

 const today=new Intl.DateTimeFormat('en-CA',{timeZone:'Africa/Lagos',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 const header=()=>({kind:'COUNT',source_id:main,date:today,note:'Opening was wrongly confirmed zero; verified physical count'});
 const correction=(id=randomUUID(),h=header(),ls=qty(rice,'20'))=>val('select public.request_stock_correction($1,$2,$3,$4)',[org,id,h,ls]);
 const balance=async()=>Number((await packet(null)).balances.find(b=>b.item_id===rice&&b.location_id===main)?.quantity??0);
 await val("select public.confirm_zero_opening($1,$2,$3,$4,'Checked original zero opening')",[org,rice,main,today]);
 await t.test('administrator submits a zero-opening correction; Finance reviews and Administrator posts once',async()=>{
  token=randomUUID();first=await correction(token);assert.equal(await correction(token),first);assert.equal(await balance(),0);await deny(action(first,'APPROVE'));await login(manager);let d=(await packet(first)).selected_document;assert.equal(!!d.actions.approve,false);assert.equal(!!d.actions.post,false);await deny(action(first,'APPROVE'));await deny(action(first,'POST'));await deny(correction());
  await login(finance);await action(first,'APPROVE');await login(manager);assert.equal(!!(await packet(first)).selected_document.actions.post,false);await deny(action(first,'POST'));await login(admin);await action(first,'POST');assert.equal(await balance(),20);await deny(action(first,'POST'),'22023');assert.equal(await correction(token),first);assert.equal(await balance(),20);
 });
 await t.test('explicit zero corrects a positive balance and is not treated as missing',async()=>{
  await login(admin);const id=await correction(randomUUID(),header(),qty(rice,'0'));await login(finance);await action(id,'APPROVE');await action(id,'POST');assert.equal(await balance(),0);
 });
 await t.test('stock changes invalidate a pending correction instead of overwriting new movements',async()=>{
  await login(admin);const id=await correction();await login(finance);await action(id,'APPROVE');await db.exec('reset role');await db.query("update public.stock_documents set completed_at=clock_timestamp() where id=$1",[first]);
  // A real operational receipt changes the ledger snapshot.
  await login(admin);await direct(randomUUID(),doc(main),qty(fish,'3'));await login(finance);await deny(action(id,'POST'),'22023');assert.equal((await packet(id)).selected_document.state,'APPROVED');
 });
 await t.test('Inventory cannot approve or post opening adjustments; Administrator can finish pending openings',async()=>{
  await login(manager);const id=await val('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),doc(kitchen),qty()]);await deny(action(id,'APPROVE'));await deny(action(id,'POST'));await login(finance);await action(id,'APPROVE');await login(admin);assert.equal((await packet(id)).selected_document.actions.post,true);await action(id,'POST');assert.equal((await packet(id)).selected_document.state,'POSTED');
 });
 await t.test('weekly and monthly count posting is management-only while Inventory can still record counts',async()=>{
  await login(admin);const site=await val("select public.save_stock_configuration($1,'LOCATION',$2)",[org,{code:'COUNT_CONTROL',name:'Count controls',kind:'STORE'}]);
  for(const monthly of[false,true]){
   await db.exec('reset role');const id=await val("insert into private.weekly_counts(organisation_id,site_id,count_date,cutoff,deadline,time_zone,state,created_by,submitted_by,submitter_name,monthly_date) values($1,$2,$3,now(),now()+interval '1 day','Africa/Lagos','SUBMITTED',$4,$4,'Stock counter',$5) returning id",[org,site,monthly?'2020-01-02':today,manager,monthly?today:null]);
   await db.query("insert into private.weekly_count_lines(count_id,item_id,name,code,unit,book,physical,note) values($1,$2,'Rice','RICE','KG',0,0,'Verified zero')",[id,rice]);
   await login(manager);const detail=await val('select public.weekly_count_detail($1,$2)',[org,id]);assert.equal(detail.can_record,true);assert.equal(detail.can_review,false);assert.equal(detail.can_post,false);await deny(val("select public.weekly_count_action($1,$2,0,$3,'APPROVE','Checked independently')",[org,id,randomUUID()]));
   await login(finance);await val("select public.weekly_count_action($1,$2,0,$3,'APPROVE','Checked independently')",[org,id,randomUUID()]);await login(manager);await deny(val("select public.weekly_count_action($1,$2,1,$3,'POST','Checked stock')",[org,id,randomUUID()]));await login(admin);assert.equal((await val('select public.weekly_count_detail($1,$2)',[org,id])).can_post,true);await val("select public.weekly_count_action($1,$2,1,$3,'POST','Posted by management')",[org,id,randomUUID()]);
  }
 });
 await t.test('Inventory valuation is read-only: prices and produced-SKU cost links cannot be changed',async()=>{
  await login(manager);assert.equal((await packet(null)).can_cost_bindings,false);assert.equal((await val('select public.reference_price_access($1)',[org])).write,false);await deny(val("select public.save_stock_configuration($1,'BINDING',$2)",[org,{recipe_version_id:randomUUID(),item_id:rice}]));await login(admin);assert.equal((await packet(null)).can_cost_bindings,true);
 });
 await t.test('wrong dates, malformed inputs, foreign scopes and unsupported users are rejected',async()=>{
  await login(admin);await deny(correction(randomUUID(),{...header(),date:'2020-01-01'}),'22023');await deny(correction(randomUUID(),header(),qty(rice,'-1')),'22023');await deny(correction(randomUUID(),{...header(),note:'a'}),'22023');await login(other);await deny(correction());await db.exec('reset role;set role anon');await deny(correction());
 });
 }finally{await db.close();}
});
