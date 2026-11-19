import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile,readdir} from 'node:fs/promises';import {randomUUID} from 'node:crypto';import {PGlite} from '@electric-sql/pglite';
test('direct processing is centre-scoped, atomic, named and safe to retry',async t=>{
 const db=new PGlite(),[owner,manager,chef,outsider]=Array.from({length:4},()=>randomUUID()),today=new Date().toISOString().slice(0,10);
 const val=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0],login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');},bad=(work,code='22023')=>assert.rejects(work,e=>e.code===code);
 let org,outlet,kg,pcs,fish,cut,version,main,kitchen,standard,managerMember,chefMember,batch,route;
 const history=(site=null,kind='BATCHES',page=1)=>val('select public.processing_activity($1,$2,$3,$3,$4,$5)',[org,site,today,kind,page]);
 const balance=async(site,item)=>Number((await val('select public.stock_workspace($1,$2,1)',[org,site])).balances.find(b=>b.item_id===item)?.quantity??0);
 const request=(doc,lines,id=randomUUID())=>val('select public.request_stock_document($1,$2,$3,$4)',[org,id,{date:today,note:'Physical batch record',...doc},lines]);
 const action=(id,choice,received=null)=>val('select public.stock_document_action($1,$2,$3,$4,$5)',[org,id,choice,'Verified evidence',received]);
 const centre=(name,kind,responsible,processing=true,id=null)=>val('select public.save_stock_centre($1,$2)',[org,{id,code:name,name,kind,responsible,processing_enabled:processing,...(kind==='KITCHEN'||kind==='BAR'?{outlet_id:outlet}:{})}]);
 const standardValue=()=>({recipe_version_id:version,primary_item_id:fish,output_spec:'120 uniform approved cuts',target_piece_weight_kg:'0.3',expected_trim_kg:'4',tolerance_percent:'0',site_ids:[main,kitchen]});
 const production=(site,input='36',actual='100',waste='2',extra={})=>request({kind:'PRODUCTION',source_id:site,recipe_version_id:version,processing_standard_id:standard,actual_output:actual,variance_reason:'Measured cuts differed from standard',usable_weight_kg:'32',processing_waste:waste==='0'?[]:[{item_id:fish,quantity:waste,reason:'Measured trim'}],waste_confirmed:true,...extra},[{item_id:fish,quantity:input}]);
 try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
 for(const id of[owner,manager,chef,outsider])await db.query('insert into auth.users values($1,now(),$2)',[id,`${id}@example.test`]);for(const name of(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
 await login(owner);await val("select public.save_restaurant_setup('Centres Test','FINE_DINING','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");org=await val('select public.complete_restaurant_setup()');outlet=await val('select id from public.locations where organisation_id=$1',[org]);kg=await val("select id from public.units_of_measure where organisation_id=$1 and code='KG'",[org]);pcs=await val("select id from public.units_of_measure where organisation_id=$1 and code='PCS'",[org]);
 await db.exec('reset role');for(const[id,role]of[[manager,'inventory_manager'],[chef,'stock_department']]){const m=await val('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,id]);await db.query('insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,$3,$4)',[org,m,role,id===chef?outlet:null]);if(id===manager)managerMember=m;else chefMember=m;}await login(owner);
 fish=await val("select public.save_catalogue_material($1,null,'FISH','Whole Fish','RAW','Fish',$2,true,true)",[org,kg]);cut=await val('select public.save_material_setup($1,$2)',[org,{code:'CUT',name:'Snapper Cut',item_type:'SEMI_FINISHED',base_uom_id:pcs,category:'Fish',supply_class:'PROCESSED',stock_tracked:'true',is_active:'true',weekly_count_required:'true'}]);version=await val("select public.publish_recipe_version($1,null,$2,'CUTTING','Fish processing','SUB_RECIPE',$3,120,$4,'',$5)",[org,randomUUID(),today,pcs,[{kind:'ITEM',target_id:fish,quantity:'40',uom_id:kg}]]);await val("select public.save_stock_configuration($1,'BINDING',$2)",[org,{recipe_version_id:version,item_id:cut}]);
 const prices=[{material_code:'FISH',quantity:'1',unit_code:'KG',total_price:'1000',price_date:today,source_note:'Supplier price'}],preview=await val('select public.preview_material_reference_prices($1,$2)',[org,prices]);await val("select public.save_material_reference_prices($1,$2,'MANUAL',$3,$4)",[org,randomUUID(),prices,preview]);

 main=await centre('MAIN','STORE',managerMember);kitchen=await centre('KITCHEN','KITCHEN',chefMember);await centre('BAR','BAR',chefMember,false);
 await val("select public.save_stock_member_access($1,$2,0,'ASSIGNED',$3)",[org,chefMember,[{location_id:kitchen,can_request:true,can_handle:false,can_approve:false,can_dispatch:false,can_receive:true}]]);
 standard=await val('select public.save_processing_standard($1,$2,$3)',[org,randomUUID(),standardValue()]);
 await login(manager);for(const site of [main,kitchen]){const id=await request({kind:'OPENING',destination_id:site},[{item_id:fish,quantity:'80'}]);await login(owner);await action(id,'APPROVE');await login(manager);await action(id,'POST');}
 const row=(input='40',output='110',extra={})=>({standard_id:standard,actual_output:output,inputs:[{item_id:fish,quantity:input}],waste:[{item_id:fish,quantity:'4',reason:'Measured trim'}],usable_weight_kg:'36',...extra});
 const value=(rows,extra={})=>({source_id:kitchen,date:today,submitter_name:'Ada',note:'',rows,...extra});
 const submit=(v,id=randomUUID())=>val('select public.submit_material_processing($1,$2,$3)',[org,id,v]);
 const count=async()=>{await db.exec('reset role');const result=await val('select count(*) from public.stock_documents where organisation_id=$1',[org]);await login(chef);return Number(result);};
 await t.test('Kitchen posts directly with an optional empty note, inclusive waste and frozen costs',async()=>{
  await login(chef);const ids=await submit(value([row()]));assert.equal(ids.length,1);batch=ids[0];assert.equal(await balance(kitchen,fish),40);assert.equal(await balance(kitchen,cut),110);
  const b=(await history(kitchen)).rows.find(r=>r.id===batch);assert.equal(b.state,'POSTED');assert.equal(b.submitter_name,'Ada');assert.equal(b.reviewed_by,null);assert.equal(b.can_complete,false);assert.equal(Number(b.expected_output),120);assert.equal(Number(b.output_variance),-10);assert.equal(Number(b.input_weight_kg),40);assert.equal(Number(b.waste_weight_kg),4);assert.equal(Number(b.usable_weight_kg),36);assert.equal(b.outside_tolerance,true);
  await login(owner);assert.equal(Number((await history(kitchen)).rows.find(r=>r.id===batch).costs.batch_cost),40000);
 });
 await t.test('multiple rows post together and an identical retry returns the same records',async()=>{
  await login(chef);const id=randomUUID(),v=value([row('10','28',{waste:[],usable_weight_kg:''}),row('10','29',{waste:[],usable_weight_kg:''})]);const ids=await submit(v,id);assert.equal(ids.length,2);assert.deepEqual(await submit(v,id),ids);assert.equal(await balance(kitchen,fish),20);assert.equal(await balance(kitchen,cut),167);await bad(submit({...v,note:'Changed'},id));assert.equal(await balance(kitchen,fish),20);
 });
 await t.test('combined shortage rolls back even if each row separately fits available stock',async()=>{
  const before=await count();await bad(submit(value([row('15','40',{waste:[],usable_weight_kg:''}),row('15','40',{waste:[],usable_weight_kg:''})])));assert.equal(await count(),before);assert.equal(await balance(kitchen,fish),20);assert.equal(await balance(kitchen,cut),167);
 });
 await t.test('invalid last row leaves no partial posting, records or submission token',async()=>{
  const before=await count(),id=randomUUID();await bad(submit(value([row('1','3',{waste:[],usable_weight_kg:''}),row('2','5',{waste:[{item_id:fish,quantity:'3',reason:'Invalid'}],usable_weight_kg:''})]),id));assert.equal(await count(),before);assert.equal(await balance(kitchen,fish),20);await submit(value([row('1','3',{waste:[],usable_weight_kg:''})]),id);assert.equal(await balance(kitchen,fish),19);
 });
 await t.test('centre permissions, names, future dates and forged outputs cannot be bypassed',async()=>{
  await bad(submit(value([row()],{source_id:main})),'42501');await bad(submit(value([row()],{submitter_name:''})));await bad(submit(value([row()],{date:'2099-01-01'})));await bad(submit(value([row('1','3',{inputs:[{item_id:cut,quantity:'1'}],waste:[],usable_weight_kg:''})])));await login(outsider);await bad(submit(value([row()])),'42501');await login(chef);
 });
 await t.test('older pending batch can be explicitly completed by its original recorder without approval',async()=>{
  const pending=await production(kitchen,'2','5','0',{usable_weight_kg:'',variance_reason:'Older batch'});assert.equal(await balance(kitchen,fish),19);assert.equal((await history(kitchen)).rows.find(r=>r.id===pending).can_complete,true);
  await login(manager);await bad(val('select public.complete_processing_record($1,$2,$3)',[org,pending,'Emeka']),'42501');await login(chef);await val('select public.complete_processing_record($1,$2,$3)',[org,pending,'Ada']);await val('select public.complete_processing_record($1,$2,$3)',[org,pending,'Ada']);assert.equal(await balance(kitchen,fish),17);assert.equal(await balance(kitchen,cut),175);
 });
 await t.test('reserved transfers cannot be consumed by direct processing at Main Store',async()=>{
  await login(owner);route=await val("select public.save_stock_configuration($1,'ROUTE',$2)",[org,{source_id:main,destination_id:kitchen,kind:'TRANSFER',approval_role:'inventory_manager'}]);await login(chef);const transfer=await request({kind:'TRANSFER',route_id:route},[{item_id:fish,quantity:'75'}]);await login(manager);await action(transfer,'APPROVE');await action(transfer,'DISPATCH');await bad(submit(value([row('10','30',{waste:[],usable_weight_kg:''})],{source_id:main,submitter_name:'Emeka'})));assert.equal(await balance(main,fish),80);
  await submit(value([row('5','15',{waste:[],usable_weight_kg:''})],{source_id:main,submitter_name:'Emeka'}));assert.equal(await balance(main,fish),75);assert.equal(await balance(main,cut),15);
 });
 await t.test('private helpers and anonymous submission are not callable',async()=>{
  await login(chef);await bad(val('select private.pp_finish_processing($1,$2,$3)',[org,batch,'Ada']),'42501');await db.exec('reset role;set role anon');await bad(submit(value([row()])),'42501');
 });
 }finally{await db.close();}
});
