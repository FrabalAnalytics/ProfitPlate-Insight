import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';

test('configurable stock flows preserve quantities, role scopes and an immutable audit ledger',async t=>{
 const db=new PGlite();
 const [owner,storekeeper,receiver,ops,finance,outsider,manager]=Array.from({length:7},()=>randomUUID());
 const value=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
 const denied=(sql,args=[],code='42501')=>assert.rejects(db.query(sql,args),e=>e.code===code);
 let org,outlet,warehouse,kitchen,kg,pcs,rice,baseItem,finalItem,opening,route,transfer,baseVersion,finalVersion,supplier;
 const workspace=(site=null,page=1)=>value('select public.stock_workspace($1,$2,$3)',[org,site,page]);
 const configure=(kind,input)=>value('select public.save_stock_configuration($1,$2,$3)',[org,kind,input]);
 const request=async(kind,site,lines,extra={},id=randomUUID())=>{if(kind==='PRODUCTION'){const setup=await value('select public.processing_setup($1)',[org]),standard=setup.standards.find(s=>s.recipe_version_id===extra.recipe_version_id),recipe=(await workspace()).recipes.find(r=>r.id===extra.recipe_version_id);lines=standard.inputs.map(i=>({item_id:i.item_id,quantity:String(Number(i.quantity)*Number(extra.planned_output)/Number(recipe.yield))}));extra={...extra,processing_standard_id:standard.id,variance_reason:'Measured yield result',processing_waste:[],waste_confirmed:true};}return value('select public.request_stock_document($1,$2,$3,$4)',[org,id,{kind,date:new Date().toISOString().slice(0,10),note:'Checked source record',...(kind==='OPENING'||kind==='GRN'||kind==='DIRECT_RECEIPT'?{destination_id:site}:{source_id:site}),...extra},lines]);};
 const action=(id,choice,received=null)=>value('select public.stock_document_action($1,$2,$3,$4,$5)',[org,id,choice,'Verified physical stock',received]);
 const balance=async(site,item)=>Number((await workspace(site)).balances.find(b=>b.item_id===item)?.quantity??0);
 const approvedPost=async id=>{await login(finance);await action(id,'APPROVE');await login(storekeeper);await action(id,'POST');};
 try{
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
  for(const id of[owner,storekeeper,receiver,ops,finance,outsider,manager])await db.query('insert into auth.users values($1,now(),$2)',[id,`${id}@example.test`]);
  for(const name of(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
  for(const user of[outsider,owner]){await login(user);await value("select public.save_restaurant_setup('Stock Test','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");const id=await value('select public.complete_restaurant_setup()');if(user===owner)org=id;}
  outlet=await value('select id from public.locations where organisation_id=$1',[org]);
  kg=await value("select id from public.units_of_measure where organisation_id=$1 and code='KG'",[org]);pcs=await value("select id from public.units_of_measure where organisation_id=$1 and code='PCS'",[org]);
  rice=await value("select public.save_catalogue_material($1,null,'RICE','Rice','RAW','',$2,true,true)",[org,kg]);
  baseItem=await value("select public.save_catalogue_material($1,null,'BASE','Prepared base','SEMI_FINISHED','',$2,true,true)",[org,kg]);
  finalItem=await value("select public.save_catalogue_material($1,null,'PLATE','Finished plate','FINISHED','',$2,true,true)",[org,pcs]);
  supplier=await value("select public.save_catalogue_supplier($1,null,'SUP','Supplier','','','',true)",[org]);
  await db.exec('reset role');
  for(const[user,role,location]of[[storekeeper,'inventory',null],[receiver,'inventory',outlet],[ops,'operations',outlet],[finance,'finance',null]]){
   const m=await value('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,user]);
   await db.query('insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,$3,$4)',[org,m,role,location]);
  }
  await login(owner);
  await t.test('administrator configures central warehouses, outlet departments and allowed routes',async()=>{
   warehouse=await configure('LOCATION',{code:'WH',name:'Central warehouse',kind:'WAREHOUSE'});
   kitchen=await configure('LOCATION',{code:'KIT',name:'Kitchen',kind:'KITCHEN',outlet_id:outlet,department:'Food production'});
   route=await configure('ROUTE',{source_id:warehouse,destination_id:kitchen,kind:'ISSUE',approval_role:'inventory'});
   await denied('select public.save_stock_configuration($1,$2,$3)',[org,'ROUTE',{source_id:warehouse,destination_id:warehouse,kind:'TRANSFER',approval_role:'inventory'}],'22023');
   await login(storekeeper);await denied('select public.save_stock_configuration($1,$2,$3)',[org,'LOCATION',{code:'NO',name:'No',kind:'STORE'}]);
   const token=randomUUID();opening=await request('OPENING',warehouse,[{item_id:rice,quantity:'100'}],{},token);
   assert.equal(await request('OPENING',warehouse,[{item_id:rice,quantity:'100'}],{},token),opening);
   await denied('select public.stock_document_action($1,$2,$3,$4,null)',[org,opening,'APPROVE','Self approval']);
   await approvedPost(opening);assert.equal(await balance(warehouse,rice),100);
   await denied('select public.stock_document_action($1,$2,$3,$4,null)',[org,opening,'POST','Retry'],'22023');
   assert.equal(await balance(warehouse,rice),100);
   const extra=await request('OPENING',warehouse,[{item_id:baseItem,quantity:'1'}]);
   await approvedPost(extra);assert.equal(await balance(warehouse,baseItem),1);
   await denied('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),{kind:'OPENING',destination_id:warehouse,date:'2020-10-02',note:'Duplicate opening'},[{item_id:rice,quantity:'10'}]],'22023');
  });
  await t.test('department requests use configured routes, source approval and separate receiving',async()=>{
   await login(ops);transfer=await request('ISSUE',null,[{item_id:rice,quantity:'20'}],{route_id:route});
   assert.equal((await workspace()).locations.find(s=>s.id===warehouse).read,false);
   await denied('select public.stock_workspace($1,$2,1)',[org,warehouse]);
   await login(storekeeper);await action(transfer,'APPROVE');await action(transfer,'DISPATCH');
   assert.equal(await balance(warehouse,rice),100);
   await denied('select public.stock_document_action($1,$2,$3,$4,$5)',[org,transfer,'RECEIVE','Self receiving',[{item_id:rice,quantity:'20'}]]);
   await login(receiver);
   await denied('select public.stock_document_action($1,$2,$3,$4,$5)',[org,transfer,'RECEIVE','Too much',[{item_id:rice,quantity:'21'}]],'22023');
   await denied('select public.stock_document_action($1,$2,$3,$4,$5)',[org,transfer,'RECEIVE','Missing reason',[{item_id:rice,quantity:'19'}]],'22023');
   await action(transfer,'RECEIVE',[{item_id:rice,quantity:'19',reason:'1 KG damaged in transit'}]);
   assert.equal(await balance(kitchen,rice),19);
   assert.equal((await workspace()).documents.find(d=>d.id===transfer).received_lines[0].reason,'1 KG damaged in transit');
   await login(owner);await action(transfer,'RESOLVE');await login(receiver);
   await denied('select public.stock_document_action($1,$2,$3,$4,null)',[org,transfer,'CANCEL','Already received'],'42501');
  });
  await t.test('negative balances, stale counts and backdated movements cannot post',async()=>{
   await login(storekeeper);let id=await request('WASTE',warehouse,[{item_id:rice,quantity:'82'}]);
   await login(finance);await action(id,'APPROVE');await login(storekeeper);
   await denied('select public.stock_document_action($1,$2,$3,$4,null)',[org,id,'POST','Too much'],'22023');assert.equal(await balance(warehouse,rice),81);
   const count=await request('COUNT',warehouse,[{item_id:rice,quantity:'79'}]);
   id=await request('CONSUMPTION',warehouse,[{item_id:rice,quantity:'1'}]);await approvedPost(id);
   await login(finance);await action(count,'APPROVE');await login(storekeeper);
   await denied('select public.stock_document_action($1,$2,$3,$4,null)',[org,count,'POST','Stale count'],'22023');
   id=await request('COUNT',warehouse,[{item_id:rice,quantity:'78'}]);await approvedPost(id);assert.equal(await balance(warehouse,rice),78);
   id=await request('WASTE',warehouse,[{item_id:rice,quantity:'1'}],{date:'2020-10-01'});await login(finance);await action(id,'APPROVE');await login(storekeeper);
   await denied('select public.stock_document_action($1,$2,$3,$4,null)',[org,id,'POST','Backdated'],'22023');
  });
  await t.test('production consumes stocked sub-recipes once, pins the version and records actual yield',async()=>{
   await login(owner);
   baseVersion=await value("select public.publish_recipe_version($1,null,$2,'SAUCE','Sauce','SUB_RECIPE','2020-10-01',8,$3,'',$4)",[org,randomUUID(),kg,[{kind:'ITEM',target_id:rice,quantity:'10',uom_id:kg}]]);
   finalVersion=await value("select public.publish_recipe_version($1,null,$2,'MEAL','Meal','FINAL','2020-10-01',10,$3,'',$4)",[org,randomUUID(),pcs,[{kind:'RECIPE',target_id:baseVersion,quantity:'2',uom_id:kg}]]);
   await configure('BINDING',{recipe_version_id:baseVersion,item_id:baseItem});await configure('BINDING',{recipe_version_id:finalVersion,item_id:finalItem});
   const responsible=await value('select id from public.organisation_memberships where organisation_id=$1 and user_id=$2',[org,storekeeper]);await value('select public.save_stock_centre($1,$2)',[org,{id:warehouse,code:'WH',name:'Central warehouse',kind:'WAREHOUSE',responsible,processing_enabled:true}]);
   for(const version of[baseVersion,finalVersion]){const inputs=await value('select public.processing_recipe_inputs($1,$2)',[org,version]);await value('select public.save_processing_standard($1,$2,$3)',[org,randomUUID(),{recipe_version_id:version,primary_item_id:inputs[0].item_id,output_spec:'Approved standard batch',tolerance_percent:'0',site_ids:[warehouse]}]);}
   await login(storekeeper);
   let id=await request('PRODUCTION',warehouse,[],{recipe_version_id:baseVersion,planned_output:'8',actual_output:'7'});await approvedPost(id);
   assert.equal(await balance(warehouse,rice),68);assert.equal(await balance(warehouse,baseItem),8);
   id=await request('PRODUCTION',warehouse,[],{recipe_version_id:finalVersion,planned_output:'10',actual_output:'9'});await approvedPost(id);
   assert.equal(await balance(warehouse,rice),68);assert.equal(await balance(warehouse,baseItem),6);assert.equal(await balance(warehouse,finalItem),9);
   await login(owner);await denied('select public.save_stock_configuration($1,$2,$3)',[org,'BINDING',{recipe_version_id:baseVersion,item_id:baseItem}],'22023');
  });
  await t.test('direct deliveries need supplier evidence and do not manufacture invoices',async()=>{
   await login(receiver);await denied('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),{kind:'DIRECT_RECEIPT',destination_id:kitchen,date:'2020-10-02',note:'Delivery'},[{item_id:rice,quantity:'5'}]],'22023');
   const direct={supplier_id:supplier,delivery_reference:'DIRECT-001',note:'Supplier delivery note DIRECT-001',date:new Date().toISOString().slice(0,10)};
   const id=await request('DIRECT_RECEIPT',kitchen,[{item_id:rice,quantity:'5'}],direct);
   await assert.rejects(request('DIRECT_RECEIPT',kitchen,[{item_id:rice,quantity:'5'}],{...direct,delivery_reference:'direct-001'}),e=>e.code==='22023');
   await login(finance);await action(id,'APPROVE');await login(receiver);await action(id,'POST');assert.equal(await balance(kitchen,rice),24);
   await db.exec('reset role');assert.equal(await value('select count(*)::int from public.purchase_headers where organisation_id=$1',[org]),0);
  });
  await t.test('GRNs post accepted quantities once using saved conversion factors and retain their source evidence',async()=>{
   await login(owner);
   const bag=await value("select id from public.units_of_measure where organisation_id=$1 and code='BAG'",[org]);
   await value("select public.save_material_conversion($1,$2,$3,50,'2020-01-01')",[org,rice,bag]);
   const po=await value('select public.save_purchase_order($1,null,$2,0,$3,$4)',[org,randomUUID(),{supplier_id:supplier,location_id:outlet,date:'2020-10-01',price_basis:'EXCLUSIVE',total:'1000'},[{item_id:rice,uom_id:bag,quantity:'2',unit_price:'500',discount:'0',tax:'0'}]]);
   await value('select public.issue_purchase_order($1,$2,1,true)',[org,po]);
   const line=(await value('select public.get_purchase_order($1,$2)',[org,po])).lines[0].id;
   await login(receiver);
   const grn=await value('select public.record_goods_receipt($1,$2,$3,$4,$5,true)',[org,po,randomUUID(),{date:'2020-10-02',delivery_reference:'INV-TEST-GRN'},[{order_line_id:line,accepted:'1',rejected:'1',reason:'Damaged bag'}]]);
   const id=await request('GRN',kitchen,[],{receipt_id:grn,date:new Date().toISOString().slice(0,10)});
   assert.equal(Number((await workspace()).documents.find(d=>d.id===id).lines[0].quantity),50);
   await denied('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),{kind:'GRN',date:'2020-10-02',note:'Duplicate',destination_id:kitchen,receipt_id:grn},[]],'22023');
   await login(finance);await action(id,'APPROVE');await login(receiver);await action(id,'POST');assert.equal(await balance(kitchen,rice),74);
   const voidRequest=await value("select public.review_goods_receipt_void($1,$2,$3,'Wrong delivery','REQUEST','')",[org,grn,randomUUID()]);
   await login(finance);await denied("select public.review_goods_receipt_void($1,$2,$3,'','APPROVE','Check stock')",[org,grn,voidRequest],'22023');
   await value("select public.review_goods_receipt_void($1,$2,$3,'','REJECT','Keep posted source and use reviewed stock correction')",[org,grn,voidRequest]);
  });
  await t.test('failed multi-line postings roll back, zero-yield batches retain losses, and disabled routes stop dispatch',async()=>{
   await login(receiver);
   const id=await request('CONSUMPTION',kitchen,[{item_id:rice,quantity:'1'},{item_id:baseItem,quantity:'1'}],{date:new Date().toISOString().slice(0,10)});
   await login(finance);await action(id,'APPROVE');await login(receiver);
   await denied('select public.stock_document_action($1,$2,$3,$4,null)',[org,id,'POST','Insufficient base stock'],'22023');
   assert.equal(await balance(kitchen,rice),74);
   await login(storekeeper);
   const failed=await request('PRODUCTION',warehouse,[],{recipe_version_id:baseVersion,planned_output:'8',actual_output:'0'});await approvedPost(failed);
   assert.equal(await balance(warehouse,rice),58);assert.equal(await balance(warehouse,baseItem),6);
   const movement=await request('ISSUE',null,[{item_id:rice,quantity:'1'}],{route_id:route});
   await login(owner);await action(movement,'APPROVE');await configure('ROUTE_STATE',{id:route,active:false});
   await login(storekeeper);await denied('select public.stock_document_action($1,$2,$3,$4,null)',[org,movement,'DISPATCH','Disabled route'],'22023');
   await action(movement,'CANCEL');
   await login(owner);await configure('ROUTE_STATE',{id:route,active:true});
  });
  await t.test('Inventory Manager is invited explicitly and oversees stock without acquiring team or financial authority',async()=>{
   await login(owner);
   await denied('select public.create_team_invitation($1,$2,$3,$4)',[org,randomUUID(),`${manager}@example.test`,[{role_code:'inventory_manager',location_id:outlet}]],'22023');
   const invitation=await value('select public.create_team_invitation($1,$2,$3,$4)',[org,randomUUID(),`${manager}@example.test`,[{role_code:'inventory_manager',location_id:null}]]);
   await login(manager);assert.equal(await value('select public.accept_team_invitation($1)',[invitation.token]),org);
   const packet=await workspace();assert.equal(packet.manage,true);assert.ok(packet.locations.every(s=>s.inventory&&s.request&&s.read));
   const nav=await value('select public.workspace_navigation_access($1)',[org]);assert.equal(nav.inventory,true);assert.equal(nav.orders,true);
   for(const field of['team','purchases','overview','expenses','menus','recipes','sales'])assert.equal(nav[field],false,field);
   assert.equal(await value('select public.team_access($1)',[org]),false);
   await denied('select public.create_team_invitation($1,$2,$3,$4)',[org,randomUUID(),'escalate@example.test',[{role_code:'restaurant_admin',location_id:null}]]);
   await denied('select public.save_purchase_order($1,null,$2,0,$3,$4)',[org,randomUUID(),{},[]]);
   await denied('select public.stage_manual_purchase($1,$2,$3,$4)',[org,randomUUID(),{},[]]);
   const newSite=await configure('LOCATION',{code:'MGR_STORE',name:'Manager configured store',kind:'STORE',outlet_id:outlet});assert.ok(newSite);
   const directory=await value('select public.stock_access_directory($1)',[org]);const member=directory.members.find(m=>m.email===`${receiver}@example.test`);
   await value('select public.save_stock_member_access($1,$2,0,$3,$4)',[org,member.id,'ASSIGNED',[{location_id:kitchen,can_request:true,can_handle:true,can_approve:false}]]);
   await login(storekeeper);const waste=await request('WASTE',warehouse,[{item_id:rice,quantity:'1'}]);
   await login(manager);assert.equal((await workspace()).documents.find(d=>d.id===waste).actions.approve,true);await action(waste,'APPROVE');await action(waste,'POST');
   const own=await request('COUNT',warehouse,[{item_id:rice,quantity:'57'}]);await denied('select public.stock_document_action($1,$2,$3,$4,null)',[org,own,'APPROVE','Self approval']);
   await login(finance);await action(own,'APPROVE');await login(manager);await action(own,'POST');
   const managerRoute=await configure('ROUTE',{source_id:warehouse,destination_id:kitchen,kind:'TRANSFER',approval_role:'inventory_manager'});
   await login(receiver);const movement=await request('TRANSFER',null,[{item_id:rice,quantity:'1'}],{route_id:managerRoute});
   await login(manager);await action(movement,'APPROVE');await action(movement,'DISPATCH');
   await denied('select public.stock_document_action($1,$2,$3,$4,$5)',[org,movement,'RECEIVE','Self receiving',[{item_id:rice,quantity:'1'}]]);
   await login(receiver);await action(movement,'RECEIVE',[{item_id:rice,quantity:'1'}]);
   await db.exec('reset role');const membership=await value('select id from public.organisation_memberships where organisation_id=$1 and user_id=$2',[org,manager]);await db.query("update public.organisation_memberships set status='inactive' where id=$1",[membership]);
   await login(manager);await denied('select public.stock_workspace($1,null,1)',[org]);await denied("select public.save_stock_configuration($1,'LOCATION',$2)",[org,{code:'DENIED',name:'Denied',kind:'STORE'}]);
  });
  await t.test('tenant separation, outlet scope, read-only roles and private helper ACLs hold',async()=>{
   await login(receiver);await denied('select public.stock_workspace($1,$2,1)',[org,warehouse]);
   await login(outsider);await denied('select public.stock_workspace($1,null,1)',[org]);
   await login(finance);await denied('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),{kind:'COUNT',source_id:warehouse,date:'2020-10-02',note:'Denied'},[{item_id:rice,quantity:'1'}]]);
   await denied('select * from public.stock_ledger');await denied('delete from public.stock_documents');
   await denied('select private.pp_stock_balance($1,$2,$3)',[org,warehouse,rice]);
   await db.exec('reset role');await db.exec('set role anon');await denied('select public.stock_workspace($1,null,1)',[org]);
  });
 }finally{await db.close();}
});
