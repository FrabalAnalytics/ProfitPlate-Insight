import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile,readdir} from 'node:fs/promises';import {randomUUID} from 'node:crypto';import {PGlite} from '@electric-sql/pglite';

test('one Inventory Manager and departments complete acceptance, rejection, returns, reservations, filters and alerts',async t=>{
 const db=new PGlite(),[owner,manager,kitchen,bar,receiver,dispatcher]=Array.from({length:6},()=>randomUUID());
 const val=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
 const deny=(sql,args,code='42501')=>assert.rejects(db.query(sql,args),e=>e.code===code);
 let org,main,kit,barSite,rice,kg,route,barRoute,reverse,first,receiverMember;
 const today=new Date().toISOString().slice(0,10);
 const configure=(kind,data)=>val('select public.save_stock_configuration($1,$2,$3)',[org,kind,data]);
 const packet=(filter='ALL',search='',page=1,doc=null)=>val('select public.stock_workspace_v2($1,null,$2,$3,$4,$5)',[org,page,filter,search,doc]);
 const alerts=()=>val('select public.stock_workspace_alerts($1)',[org]);
 const count=async queue=>(await val('select public.workspace_attention($1,$2,1)',[org,queue])).total;
 const balances=async()=>{const p=await packet();return [Number(p.balances.find(b=>b.location_id===main)?.quantity??0),Number(p.balances.find(b=>b.location_id===kit)?.quantity??0)];};
 const request=(kind,lines,extra={})=>val('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),{kind,date:today,note:'Department requisition',...extra},lines]);
 const qty=n=>[{item_id:rice,quantity:String(n)}];
 const act=(id,action,received=null)=>val('select public.stock_document_action($1,$2,$3,$4,$5)',[org,id,action,'Checked physical stock and receiver decision',received]);
 const grants=(site,{request=false,receive=false,dispatch=false}={})=>[{location_id:site,can_request:request,can_receive:receive,can_dispatch:dispatch,can_handle:false,can_approve:false}];
 try{
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
  for(const id of[owner,manager,kitchen,bar,receiver,dispatcher])await db.query('insert into auth.users values($1,now(),$2)',[id,`${id}@example.test`]);
  for(const name of(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
  await login(owner);await val("select public.save_restaurant_setup('Acceptance Test','FINE_DINING','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");org=await val('select public.complete_restaurant_setup()');
  const outlet=await val('select id from public.locations where organisation_id=$1',[org]);kg=await val("select id from public.units_of_measure where organisation_id=$1 and code='KG'",[org]);rice=await val("select public.save_catalogue_material($1,null,'RICE','Rice','RAW','',$2,true,true)",[org,kg]);
  const members=[];await db.exec('reset role');for(const[user,role]of[[manager,'inventory_manager'],[kitchen,'stock_department'],[bar,'stock_department'],[receiver,'stock_receiver'],[dispatcher,'stock_dispatcher']]){const m=await val('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,user]);members.push(m);await db.query('insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,$3,$4)',[org,m,role,role==='inventory_manager'?null:outlet]);}
  await login(manager);main=await configure('LOCATION',{code:'MAIN',name:'Main Store',kind:'STORE',outlet_id:outlet});kit=await configure('LOCATION',{code:'KIT',name:'Kitchen',kind:'KITCHEN',outlet_id:outlet});barSite=await configure('LOCATION',{code:'BAR',name:'Bar',kind:'BAR',outlet_id:outlet});
  route=await configure('ROUTE',{source_id:main,destination_id:kit,kind:'ISSUE',approval_role:'inventory_manager'});barRoute=await configure('ROUTE',{source_id:main,destination_id:barSite,kind:'ISSUE',approval_role:'inventory_manager'});reverse=await configure('ROUTE',{source_id:kit,destination_id:main,kind:'TRANSFER',approval_role:'inventory_manager'});
  for(const[member,site,cap]of[[members[1],kit,{request:true,receive:true}],[members[2],barSite,{request:true,receive:true}],[members[3],kit,{receive:true}],[members[4],main,{dispatch:true}]])await val("select public.save_stock_member_access($1,$2,0,'ASSIGNED',$3)",[org,member,grants(site,cap)]);receiverMember=members[3];
  const opening=await request('OPENING',qty(100),{destination_id:main});await login(owner);await act(opening,'APPROVE');await login(manager);await act(opening,'POST');
  await t.test('approval and dispatch stay with the manager and leave both balances unchanged',async()=>{
   await login(kitchen);first=await request('ISSUE',qty(10),{route_id:route});await login(manager);assert.equal((await alerts()).approval,1);assert.equal(await count('REQUEST_APPROVAL'),1);await act(first,'APPROVE');assert.equal(await count('REQUEST_APPROVAL'),0);assert.equal(await count('READY_DISPATCH'),1);await act(first,'DISPATCH');assert.equal(await count('READY_DISPATCH'),0);assert.equal(await count('DEPARTMENT_CONFIRMATION'),1);
   assert.deepEqual(await balances(),[100,0]);const balance=(await packet()).balances.find(b=>b.location_id===main);assert.equal(Number(balance.reserved),10);assert.equal(Number(balance.available),90);
   await db.exec('reset role');assert.equal(Number(await val('select count(*) from public.stock_ledger where document_id=$1',[first])),0);await login(manager);
   await deny('select public.stock_document_action($1,$2,$3,$4,$5)',[org,first,'RECEIVE','Manager cannot receive for Kitchen',qty(10)]);
   await login(kitchen);assert.equal((await alerts()).incoming,1);assert.equal(await count('INCOMING_TRANSFER'),1);await login(bar);assert.equal((await alerts()).incoming,0);assert.equal(await count('INCOMING_TRANSFER'),0);assert.equal((await packet()).documents.some(d=>d.id===first),false);
  });
  await t.test('partial acceptance posts only accepted quantities and sends a resolvable follow-up',async()=>{
   await login(kitchen);await act(first,'RECEIVE',[{item_id:rice,quantity:'8',reason:'2 KG not accepted; returned to source'}]);
   await login(manager);assert.deepEqual(await balances(),[92,8]);assert.equal((await packet('INCOMPLETE')).documents[0].state,'PARTIAL');assert.equal((await packet('COMPLETED')).documents.some(d=>d.id===first),false);assert.equal((await alerts()).follow_up,1);assert.equal(await count('STOCK_FOLLOW_UP'),1);assert.equal(await count('DEPARTMENT_CONFIRMATION'),0);
   assert.equal(Number((await packet()).balances.find(b=>b.location_id===main).reserved),2);await act(first,'RESOLVE');assert.equal((await alerts()).follow_up,0);assert.equal((await packet('FOLLOW_UP')).total,0);
  });
  await t.test('departments return excess to Main Store without needing another inventory staff account',async()=>{
   await login(kitchen);const id=await request('TRANSFER',qty(3),{route_id:reverse});await login(manager);await act(id,'APPROVE');await act(id,'DISPATCH');assert.deepEqual(await balances(),[92,8]);
   assert.equal(await count('DEPARTMENT_RETURNS'),1);await act(id,'RECEIVE',qty(3));assert.equal(await count('DEPARTMENT_RETURNS'),0);assert.deepEqual(await balances(),[95,5]);assert.equal((await packet('COMPLETED')).documents.find(d=>d.id===id).state,'RECEIVED');
   await db.exec('reset role');assert.equal((await val("select details from public.audit_events where entity_id=$1 and event_type='STOCK_RECEIVE'",[id])).manager_return,true);await login(manager);
  });
  await t.test('a receiving department can reject the whole transfer without moving stock',async()=>{
   await login(bar);const id=await request('ISSUE',qty(7),{route_id:barRoute});await login(manager);await act(id,'APPROVE');await act(id,'DISPATCH');await login(bar);await act(id,'REJECT');
   await login(manager);assert.deepEqual(await balances(),[95,5]);assert.equal((await packet('REJECTED')).documents[0].state,'REJECTED');assert.equal((await alerts()).follow_up,1);
   await deny('select public.stock_document_action($1,$2,$3,$4,null)',[org,id,'POST','Cannot post rejected transfer'],'22023');await act(id,'RESOLVE');assert.equal((await alerts()).follow_up,0);
  });
  await t.test('reservations prevent over-allocation and consumption while awaiting receiver confirmation',async()=>{
   await login(kitchen);const held=await request('ISSUE',qty(80),{route_id:route});await login(bar);const competing=await request('ISSUE',qty(20),{route_id:barRoute});await login(manager);await act(held,'APPROVE');await act(held,'DISPATCH');await act(competing,'APPROVE');
   await deny('select public.stock_document_action($1,$2,$3,$4,null)',[org,competing,'DISPATCH','Available stock too low'],'22023');
   const usage=await request('CONSUMPTION',qty(16),{source_id:main});await login(owner);await act(usage,'APPROVE');await login(manager);await deny('select public.stock_document_action($1,$2,$3,$4,null)',[org,usage,'POST','Reserved stock'],'22023');assert.deepEqual(await balances(),[95,5]);
   await login(kitchen);await act(held,'REJECT');await login(manager);await act(held,'RESOLVE');await act(usage,'POST');await act(competing,'CANCEL');assert.deepEqual(await balances(),[79,5]);
  });
  await t.test('optional receiver and dispatcher roles cannot acquire approvals or other process powers',async()=>{
   await login(dispatcher);await deny('select public.save_stock_configuration($1,$2,$3)',[org,'LOCATION',{code:'BAD',name:'Bad',kind:'STORE'}]);await deny('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),{kind:'CONSUMPTION',source_id:main,date:today,note:'Not allowed'},qty(1)]);
   await login(kitchen);const id=await request('ISSUE',qty(2),{route_id:route});await login(manager);await act(id,'APPROVE');await login(dispatcher);await act(id,'DISPATCH');await deny('select public.stock_document_action($1,$2,$3,$4,$5)',[org,id,'RECEIVE','No receiving authority',qty(2)]);
   await login(manager);await val("select public.save_stock_member_access($1,$2,1,'ASSIGNED',$3)",[org,receiverMember,grants(kit,{receive:false})]);
   await login(receiver);await deny('select public.stock_document_action($1,$2,$3,$4,$5)',[org,id,'RECEIVE','Receiving permission revoked',qty(2)]);
   await login(manager);await val("select public.save_stock_member_access($1,$2,2,'ASSIGNED',$3)",[org,receiverMember,grants(kit,{receive:true})]);
   await login(receiver);await deny('select public.stock_document_action($1,$2,$3,$4,null)',[org,id,'APPROVE','No approval authority']);await act(id,'RECEIVE',qty(2));
   await login(manager);await deny("select public.save_stock_member_access($1,$2,3,'ASSIGNED',$3)",[org,receiverMember,[{location_id:kit,can_request:true,can_handle:false,can_approve:false,can_dispatch:false,can_receive:true}]],'22023');
   await deny("select public.save_stock_member_access($1,$2,3,'OUTLET','[]')",[org,receiverMember],'22023');
  });
  await t.test('status/search filters apply before pagination and old alerts still open their exact record',async()=>{
   await login(kitchen);for(let i=0;i<16;i++)await request('ISSUE',qty(1),{route_id:route,note:`Pagination cohort ${i}`});await login(manager);
   const firstPage=await packet('PENDING','Pagination cohort',1),second=await packet('PENDING','Pagination cohort',2);assert.equal(firstPage.total,16);assert.equal(firstPage.documents.length,10);assert.equal(second.documents.length,6);const attention=await val('select public.workspace_attention($1,$2,1)',[org,'REQUEST_APPROVAL']);assert.equal(attention.total,16);assert.equal(attention.records.length,10);assert.equal((await val('select public.workspace_attention($1,$2,2)',[org,'REQUEST_APPROVAL'])).records.length,6);
   assert.equal((await packet('PENDING','Pagination cohort',2,first)).selected_document.id,first);
   await login(bar);assert.equal((await packet('PENDING','Pagination cohort')).total,0);assert.equal((await packet('ALL','',1,first)).selected_document,null);
  });
 }finally{await db.close();}
});

test('migration preserves historical source deductions and restores rejected legacy quantities without a second deduction',async()=>{
 const db=new PGlite(),owner=randomUUID(),staff=randomUUID();const val=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const login=async user=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);await db.exec('set role authenticated');};
 try{
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
  for(const id of[owner,staff])await db.query('insert into auth.users values($1,now(),$2)',[id,`${id}@example.test`]);
  for(const name of(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')&&n<'202611170026').sort())await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
  await login(owner);await val("select public.save_restaurant_setup('Legacy','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");const org=await val('select public.complete_restaurant_setup()'),outlet=await val('select id from public.locations where organisation_id=$1',[org]),kg=await val("select id from public.units_of_measure where organisation_id=$1 and code='KG'",[org]),rice=await val("select public.save_catalogue_material($1,null,'RICE','Rice','RAW','',$2,true,true)",[org,kg]);
  const configure=(x)=>val("select public.save_stock_configuration($1,'LOCATION',$2)",[org,x]);const main=await configure({code:'MAIN',name:'Main',kind:'STORE',outlet_id:outlet}),kit=await configure({code:'KIT',name:'Kitchen',kind:'KITCHEN',outlet_id:outlet});
  await db.exec('reset role');const member=await val('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,staff]);await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,'inventory')",[org,member]);await login(owner);
  const route=await val("select public.save_stock_configuration($1,'ROUTE',$2)",[org,{source_id:main,destination_id:kit,kind:'ISSUE',approval_role:'inventory'}]);const req=(kind,n,extra)=>val('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),{kind,date:'2020-10-02',note:'Historical source',...extra},[{item_id:rice,quantity:String(n)}]]);const act=(id,a,lines=null)=>val('select public.stock_document_action($1,$2,$3,$4,$5)',[org,id,a,'Verified historical quantities',lines]);
  await login(staff);const opening=await req('OPENING',100,{destination_id:main});await login(owner);await act(opening,'APPROVE');await login(staff);await act(opening,'POST');const movement=await req('ISSUE',20,{route_id:route});await login(owner);await act(movement,'APPROVE');await login(staff);await act(movement,'DISPATCH');
  await db.exec('reset role');assert.equal(Number(await val('select sum(quantity) from public.stock_ledger where location_id=$1',[main])),80);await db.exec(await readFile(new URL('../supabase/migrations/202611170026_receiver_confirmed_stock.sql',import.meta.url),'utf8'));assert.equal(Number(await val('select sum(quantity) from public.stock_ledger where location_id=$1',[main])),80);
  // Receiver must differ from dispatcher. Give the owner an explicit receiving process role.
  const ownerMember=await val('select id from public.organisation_memberships where organisation_id=$1 and user_id=$2',[org,owner]);await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,'inventory')",[org,ownerMember]);await login(owner);await act(movement,'RECEIVE',[{item_id:rice,quantity:'15',reason:'5 rejected and returned'}]);
  await db.exec('reset role');assert.equal(Number(await val('select sum(quantity) from public.stock_ledger where location_id=$1',[main])),85);assert.equal(Number(await val('select sum(quantity) from public.stock_ledger where location_id=$1',[kit])),15);
 }finally{await db.close();}
});
