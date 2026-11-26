import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from './helpers/active-restaurant-db.mjs';
test('standalone requisitions keep scoped queues, pagination and receiver-confirmed stock',async t=>{
 const db=new PGlite(),[owner,manager,kitchen,outsider]=Array.from({length:4},()=>randomUUID());
 const val=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
 const deny=(work,code='42501')=>assert.rejects(work,e=>e.code===code);
 let org,main,kit,bar,material,route,opening,requestId;
 const packet=(status='ALL',page=1,queue='ALL',search='',doc=null,site=null)=>val('select public.requisition_workspace($1,$2,$3,$4,$5,$6,$7)',[org,site,page,status,search,doc,queue]);
 const act=(id,decision,received=null)=>val('select public.stock_document_action($1,$2,$3,$4,$5)',[org,id,decision,'Verified physical handover',received]);
 const request=(kind,n,extra={})=>val('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),{kind,date:new Date().toISOString().slice(0,10),note:'Standalone requisition test',...extra},[{item_id:material,quantity:String(n)}]]);
 try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
 for(const id of[owner,manager,kitchen,outsider])await db.query('insert into auth.users values($1,now(),$2)',[id,`${id}@example.test`]);
 for(const name of(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
 await login(owner);await val("select public.save_restaurant_setup('Requisition Test','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");org=await val('select public.complete_restaurant_setup()');const kg=await val("select id from public.units_of_measure where organisation_id=$1 and code='KG'",[org]);material=await val("select public.save_catalogue_material($1,null,'RICE','Rice','RAW','',$2,true,true)",[org,kg]);
 await db.exec('reset role');let kitchenMember;for(const[id,role]of[[manager,'inventory_manager'],[kitchen,'stock_department']]){const member=await val('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,id]);if(id===kitchen)kitchenMember=member;await db.query('insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,$3)',[org,member,role]);}
 await login(manager);const config=(kind,data)=>val('select public.save_stock_configuration($1,$2,$3)',[org,kind,data]);
 main=await config('LOCATION',{code:'MAIN',name:'Main Store',kind:'STORE'});kit=await config('LOCATION',{code:'KIT',name:'Kitchen',kind:'KITCHEN'});bar=await config('LOCATION',{code:'BAR',name:'Bar',kind:'BAR'});route=await config('ROUTE',{source_id:main,destination_id:kit,kind:'ISSUE',approval_role:'inventory_manager'});
 await val("select public.save_stock_member_access($1,$2,0,'ASSIGNED',$3)",[org,kitchenMember,[{location_id:kit,can_request:true,can_receive:true,can_dispatch:false,can_handle:false,can_approve:false}]]);
 await t.test('requesting needs no on-hand stock; only an independent approver sees approval actions',async()=>{
 await login(kitchen);requestId=await request('ISSUE',5,{route_id:route});let p=await packet();assert.equal(p.total,1);assert.equal(p.queues.APPROVAL,0);await deny(act(requestId,'APPROVE'));
 await login(manager);p=await packet('ALL',1,'APPROVAL');assert.equal(p.total,0);assert.equal(p.queues.APPROVAL,0);await deny(act(requestId,'APPROVE'));await login(owner);p=await packet('ALL',1,'APPROVAL');assert.equal(p.total,1);assert.equal(p.queues.APPROVAL,1);await act(requestId,'APPROVE');await login(manager);assert.equal((await packet('ALL',1,'DISPATCH')).total,1);await deny(act(requestId,'DISPATCH'), '22023');
 const attention=await val("select public.workspace_attention($1,'READY_DISPATCH',1)",[org]);assert.equal(attention.records[0].path,'/workspace/requisitions');assert.equal(attention.records[0].params.document,requestId);
 });
 await t.test('opening balances stay outside requisitions; dispatch reserves and acceptance posts once',async()=>{
 opening=await request('OPENING',20,{destination_id:main});await login(owner);await act(opening,'APPROVE');await act(opening,'POST');await login(manager);await act(requestId,'DISPATCH');assert.equal((await packet()).queues.DISPATCH,0);
 let stock=await val("select public.stock_workspace_v2($1)",[org]);assert.equal(Number(stock.balances.find(b=>b.location_id===main).quantity),20);assert.equal(Number(stock.balances.find(b=>b.location_id===main).reserved),5);
 assert.equal((await packet('ALL',1,'ALL','',opening)).selected_document,null);
 await login(kitchen);let p=await packet('ALL',1,'ACCEPTANCE');assert.equal(p.total,1);assert.equal(p.queues.ACCEPTANCE,1);await act(requestId,'RECEIVE',[{item_id:material,quantity:'4',reason:'One kg returned to store'}]);p=await packet('INCOMPLETE');assert.equal(p.total,1);assert.equal(p.queues.FOLLOW_UP,1);assert.equal(p.documents[0].state,'PARTIAL');await deny(act(requestId,'RECEIVE',[{item_id:material,quantity:'4'}]),'22023');
 await login(manager);stock=await val('select public.stock_workspace_v2($1)',[org]);assert.equal(Number(stock.balances.find(b=>b.location_id===main).quantity),16);assert.equal(Number(stock.balances.find(b=>b.location_id===kit).quantity),4);
 });
 await t.test('filters and pagination count only requisitions before applying the page limit',async()=>{
 await login(kitchen);for(let i=0;i<12;i++)await request('ISSUE',1,{route_id:route,note:'Pagination request'});await login(owner);
 const a=await packet('PENDING',1,'APPROVAL','Pagination'),b=await packet('PENDING',2,'APPROVAL','Pagination');assert.equal(a.total,12);assert.equal(a.documents.length,10);assert.equal(b.documents.length,2);assert.equal(new Set([...a.documents,...b.documents].map(d=>d.id)).size,12);
 assert.equal((await packet('ALL',1,'ALL','missing reference')).total,0);assert.equal((await packet('ALL',1,'ALL','',null,bar)).total,0);await deny(packet('ALL',1,'INVALID'),'22023');await deny(packet('ALL',0),'22023');
 });
 await t.test('unassigned centres, other accounts and anonymous callers cannot obtain the register',async()=>{
 await login(kitchen);await deny(packet('ALL',1,'ALL','',null,bar));await login(outsider);await deny(packet());await db.exec('reset role;set role anon');await deny(packet());
 });
 }finally{await db.close();}
});
