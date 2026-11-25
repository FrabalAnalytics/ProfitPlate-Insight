import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from './helpers/active-restaurant-db.mjs';

test('fine-dining stock assignments separate Main Store, Kitchen and Bar without broadening role access',async t=>{
 const db=new PGlite(),[owner,storeUser,kitchenUser,barUser,opsUser,financeUser,otherUser]=Array.from({length:7},()=>randomUUID());
 const value=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const login=async user=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);await db.exec('set role authenticated');};
 const denied=(sql,args=[],code='42501')=>assert.rejects(db.query(sql,args),e=>e.code===code);
 let org,outlet,kg,rice,store,kitchen,bar,central,otherSite,toKitchen,toBar,issue,storeMember,kitchenMember,barMember,opsMember;
 const configure=(kind,input)=>value('select public.save_stock_configuration($1,$2,$3)',[org,kind,input]);
 const workspace=(site=null)=>value('select public.stock_workspace($1,$2,1)',[org,site]);
 const directory=()=>value('select public.stock_access_directory($1)',[org]);
 const grant=(site,request=true,handle=true,approve=true)=>({location_id:site,can_request:request,can_handle:handle,can_approve:approve,can_dispatch:handle,can_receive:handle});
 const save=(member,revision,mode,grants)=>value('select public.save_stock_member_access($1,$2,$3,$4,$5)',[org,member,revision,mode,grants]);
 const request=(kind,site,qty='1',extra={})=>value('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),{kind,date:new Date().toISOString().slice(0,10),note:'Checked department record',...(kind==='OPENING'?{destination_id:site}:{source_id:site}),...extra},[{item_id:rice,quantity:qty}]]);
 const action=(id,choice,received=null)=>value('select public.stock_document_action($1,$2,$3,$4,$5)',[org,id,choice,'Verified department stock',received]);
 try{
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
  for(const id of[owner,storeUser,kitchenUser,barUser,opsUser,financeUser,otherUser])await db.query('insert into auth.users values($1,now(),$2)',[id,`${id}@example.test`]);
  for(const name of(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
  let foreignSite;
  for(const user of[otherUser,owner]){
   await login(user);await value("select public.save_restaurant_setup('Fine Dining','FINE_DINING','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");
   const id=await value('select public.complete_restaurant_setup()');
   if(user===owner)org=id;else foreignSite=await value("select public.save_stock_configuration($1,'LOCATION',$2)",[id,{code:'FOREIGN',name:'Other store',kind:'STORE'}]);
  }
  outlet=await value('select id from public.locations where organisation_id=$1',[org]);kg=await value("select id from public.units_of_measure where organisation_id=$1 and code='KG'",[org]);
  rice=await value("select public.save_catalogue_material($1,null,'RICE','Rice','RAW','',$2,true,true)",[org,kg]);
  store=await configure('LOCATION',{code:'MAIN',name:'Main Store',kind:'STORE',outlet_id:outlet});kitchen=await configure('LOCATION',{code:'KITCHEN',name:'Kitchen',kind:'KITCHEN',department:'Kitchen',outlet_id:outlet});bar=await configure('LOCATION',{code:'BAR',name:'Bar',kind:'BAR',department:'Bar',outlet_id:outlet});central=await configure('LOCATION',{code:'CENTRAL',name:'Central warehouse',kind:'WAREHOUSE'});
  toKitchen=await configure('ROUTE',{source_id:store,destination_id:kitchen,kind:'ISSUE',approval_role:'inventory'});toBar=await configure('ROUTE',{source_id:store,destination_id:bar,kind:'ISSUE',approval_role:'inventory'});
  await db.exec('reset role');const brand=await value('select brand_id from public.locations where id=$1',[outlet]);
  const elsewhere=await value("insert into public.locations(organisation_id,brand_id,name,code,timezone) values($1,$2,'Other outlet','OTHER','Africa/Lagos') returning id",[org,brand]);
  await login(owner);otherSite=await configure('LOCATION',{code:'OTHER',name:'Other outlet store',kind:'STORE',outlet_id:elsewhere});
  await db.exec('reset role');
  const members=[];
  for(const[user,role]of[[storeUser,'inventory'],[kitchenUser,'inventory'],[barUser,'inventory'],[opsUser,'operations'],[financeUser,'finance']]){
   const id=await value('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,user]);members.push(id);await db.query('insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,$3,$4)',[org,id,role,role==='finance'?null:outlet]);
  }
  [storeMember,kitchenMember,barMember,opsMember]=members;
  await t.test('existing access is preserved until explicit assignments narrow the member',async()=>{
   await login(kitchenUser);assert.ok((await workspace()).locations.find(s=>s.id===bar).read);
   await login(owner);await save(storeMember,0,'ASSIGNED',[grant(store)]);await save(kitchenMember,0,'ASSIGNED',[grant(kitchen)]);await save(barMember,0,'ASSIGNED',[grant(bar)]);await save(opsMember,0,'ASSIGNED',[grant(kitchen,true,false,true)]);
   await login(kitchenUser);assert.ok((await workspace()).locations.find(s=>s.id===kitchen).inventory);assert.equal((await workspace()).locations.some(s=>s.id===bar),false);
   assert.equal((await workspace()).locations.find(s=>s.id===store).read,false);
   await denied('select public.stock_workspace($1,$2,1)',[org,bar]);await denied('select public.stock_workspace($1,$2,1)',[org,store]);
  });
  await t.test('grants cannot exceed outlet scope, role capabilities or tenant boundaries; stale edits fail atomically',async()=>{
   await login(owner);
   for(const site of[central,otherSite,foreignSite])await denied('select public.save_stock_member_access($1,$2,1,$3,$4)',[org,kitchenMember,'ASSIGNED',[grant(site)]],'22023');
   await denied('select public.save_stock_member_access($1,$2,1,$3,$4)',[org,opsMember,'ASSIGNED',[grant(kitchen)]],'22023');
   await denied('select public.save_stock_member_access($1,$2,0,$3,$4)',[org,kitchenMember,'ASSIGNED',[grant(bar)]],'22023');
   await denied('select public.save_stock_member_access($1,$2,1,$3,$4)',[org,kitchenMember,'ASSIGNED',[grant(kitchen),grant(kitchen)]],'22023');
   assert.deepEqual((await directory()).members.find(m=>m.id===kitchenMember).assignments,[{...grant(kitchen),can_review_waste:false,can_record_waste:true}]);
   await login(financeUser);await denied('select public.stock_access_directory($1)',[org]);await denied('select public.save_stock_member_access($1,$2,1,$3,$4)',[org,kitchenMember,'OUTLET',[]]);
   await login(otherUser);await denied('select public.stock_access_directory($1)',[org]);
  });
  await t.test('department balances, ledger rows and unrelated requests remain isolated',async()=>{
   for(const[user,site,qty]of[[storeUser,store,'100'],[kitchenUser,kitchen,'5'],[barUser,bar,'7']]){
    await login(user);const id=await request('OPENING',site,qty);await login(owner);await action(id,'APPROVE');await login(user);await action(id,'POST');
   }
   await login(kitchenUser);const packet=await workspace();assert.equal(packet.balances.length,1);assert.equal(packet.balances[0].location_id,kitchen);assert.ok(packet.ledger.every(l=>l.location==='Kitchen'));
   assert.ok(packet.documents.every(d=>d.destination_id===kitchen));
   await denied('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),{kind:'WASTE',submitter_name:'Test User',source_id:bar,date:'2020-10-02',note:'Forbidden'},[{item_id:rice,quantity:'1'}]]);
   await login(opsUser);await denied('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),{kind:'ISSUE',route_id:toBar,date:'2020-10-02',note:'Wrong department'},[{item_id:rice,quantity:'1'}]]);
   const unrelated=await value('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),{kind:'ISSUE',route_id:toKitchen,date:'2020-10-02',note:'Kitchen requisition'},[{item_id:rice,quantity:'9'}]]);issue=unrelated;
   await login(barUser);assert.ok(!(await workspace()).documents.some(d=>d.id===issue));await denied('select public.stock_document_action($1,$2,$3,$4,null)',[org,issue,'APPROVE','Wrong department']);
  });
  await t.test('management approval and receiving enforce role and destination assignments at action time',async()=>{
   await login(kitchenUser);assert.equal((await workspace()).documents.find(d=>d.id===issue).actions.approve,undefined);
   await denied('select public.stock_document_action($1,$2,$3,$4,null)',[org,issue,'APPROVE','Cannot approve source']);
   await login(owner);await save(storeMember,1,'ASSIGNED',[grant(store,true,true,false)]);
   await login(storeUser);await denied('select public.stock_document_action($1,$2,$3,$4,null)',[org,issue,'APPROVE','Approval removed']);
   await login(owner);await save(storeMember,2,'ASSIGNED',[grant(store)]);
   await login(storeUser);await denied('select public.stock_document_action($1,$2,$3,$4,null)',[org,issue,'APPROVE','Inventory grants cannot approve requisitions']);await login(owner);await action(issue,'APPROVE');await login(storeUser);await action(issue,'DISPATCH');
   await login(owner);await save(kitchenMember,1,'ASSIGNED',[grant(kitchen,true,false,false)]);
   await login(kitchenUser);assert.equal((await workspace()).documents.find(d=>d.id===issue).actions.receive,undefined);
   await denied('select public.stock_document_action($1,$2,$3,$4,$5)',[org,issue,'RECEIVE','Handling removed',[{item_id:rice,quantity:'9'}]]);
   await login(owner);await save(kitchenMember,2,'ASSIGNED',[grant(kitchen)]);
   await login(kitchenUser);await action(issue,'RECEIVE',[{item_id:rice,quantity:'8',reason:'One KG damaged'}]);assert.equal(Number((await workspace()).balances[0].quantity),13);
   await login(storeUser);assert.equal(Number((await workspace()).balances[0].quantity),92);
  });
  await t.test('handling-only permissions cannot submit receipts or initiate transfers',async()=>{
   await login(owner);await save(barMember,1,'ASSIGNED',[grant(bar,false,true,false)]);
   await login(barUser);
   await denied('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),{kind:'OPENING',destination_id:bar,date:'2020-10-02',note:'Cannot initiate receipt'},[{item_id:rice,quantity:'1'}]]);
   await denied('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),{kind:'ISSUE',route_id:toBar,date:'2020-10-02',note:'Cannot initiate request'},[{item_id:rice,quantity:'1'}]]);
  });
  await t.test('empty assignments deny stock access; explicit outlet mode restores only existing role scope',async()=>{
   await login(owner);await save(kitchenMember,3,'ASSIGNED',[]);
   await login(kitchenUser);const none=await workspace();assert.equal(none.locations.length,0);assert.equal(none.documents.length,0);assert.equal(none.ledger.length,0);assert.equal(none.balances.length,0);
   await login(owner);await save(kitchenMember,4,'OUTLET',[]);
   await login(kitchenUser);assert.ok((await workspace()).locations.find(s=>s.id===bar).read);await denied('select public.stock_workspace($1,$2,1)',[org,central]);await denied('select public.stock_workspace($1,$2,1)',[org,otherSite]);
  });
  await t.test('management keeps review access and inactive members lose effective grants; ACLs deny direct writes',async()=>{
   await login(financeUser);assert.equal((await workspace()).balances.length,3);assert.ok((await workspace()).documents.every(d=>!d.actions.post&&!d.actions.receive&&!d.actions.dispatch));
   await login(owner);await save(kitchenMember,5,'ASSIGNED',[grant(kitchen)]);
   await db.exec('reset role');await db.query("update public.organisation_memberships set status='inactive' where id=$1",[kitchenMember]);
   await login(kitchenUser);await denied('select public.stock_workspace($1,null,1)',[org]);
   await login(owner);await denied('select * from public.stock_member_access');await denied('delete from public.stock_member_locations');await denied('select private.pp_stock_assignment($1,$2,$3)',[org,kitchen,'read']);
   await db.exec('reset role');await db.exec('set role anon');await denied('select public.stock_access_directory($1)',[org]);
  });
 }finally{await db.close();}
});
