import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile,readdir} from 'node:fs/promises';import {randomUUID} from 'node:crypto';import {PGlite} from './helpers/active-restaurant-db.mjs';
test('multi-centre single-output production preserves stock controls and direct kitchen requests',async t=>{
 const db=new PGlite(),[owner,manager,chef,outsider]=Array.from({length:4},()=>randomUUID()),today=new Date().toISOString().slice(0,10);
 const val=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0],login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');},bad=(work,code='22023')=>assert.rejects(work,e=>e.code===code);
 let org,outlet,kg,pcs,fish,cut,version,main,kitchen,standard,managerMember,chefMember;
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

 let oil,soup,multi,front,frontMember;
 const enabled=async(ids,revision)=>(await val('select public.save_processing_centres($1,$2,$3)',[org,ids,revision??(await val('select public.processing_setup($1)',[org])).processing_centres_revision]));
 const setup=()=>val('select public.processing_setup($1)',[org]);
 const submit=(site,rows,id=randomUUID())=>val('select public.submit_material_processing($1,$2,$3)',[org,id,{source_id:site,date:today,submitter_name:'Measured operator',note:'Single-output preparation',rows}]);
 const row=(fishQty='10',oilQty='0.6',output='48')=>({standard_id:multi,actual_output:output,inputs:[{item_id:fish,quantity:fishQty},{item_id:oil,quantity:oilQty}],waste:[],usable_weight_kg:''});
 await t.test('upgrade preserves the old designated centre, then enables Main Store and Kitchen without moving stock',async()=>{
  await login(owner);await val('select public.set_processing_unit($1,$2)',[org,kitchen]);assert.deepEqual((await setup()).processing_centre_ids,[kitchen]);
  const beforeMain=await balance(main,fish),beforeKitchen=await balance(kitchen,fish),revision=(await setup()).processing_centres_revision;
  await enabled([main,kitchen],revision);assert.equal((await setup()).sites.filter(s=>s.processing_enabled).length,2);assert.equal(await balance(main,fish),beforeMain);assert.equal(await balance(kitchen,fish),beforeKitchen);await bad(enabled([main],revision));await val('select public.save_stock_centre($1,$2)',[org,{id:main,code:'MAIN',name:'MAIN',kind:'STORE',responsible:managerMember}]);assert.equal((await setup()).sites.find(s=>s.id===main).processing_enabled,true);
  await login(chef);await bad(enabled([main,kitchen],0),'42501');await login(owner);await bad(enabled([randomUUID()]));
 });
 await t.test('a guided baseline supports multiple inputs, one output and explicitly permitted centres with derived cost',async()=>{
  await db.exec('reset role');await db.query('update public.items set requires_processing=true where id=$1',[fish]);await login(owner);
  oil=await val("select public.save_catalogue_material($1,null,'OIL','Cooking Oil','RAW','Cooking',$2,true,true)",[org,kg]);
  soup=await val('select public.save_material_setup($1,$2)',[org,{code:'SOUP',name:'Prepared Soup',item_type:'SEMI_FINISHED',base_uom_id:pcs,supply_class:'PROCESSED',stock_tracked:true,is_active:true}]);
  const rows=[{material_code:'OIL',quantity:'1',unit_code:'KG',total_price:'500',price_date:today,source_note:'Measured purchase'}],preview=await val('select public.preview_material_reference_prices($1,$2)',[org,rows]);await val("select public.save_material_reference_prices($1,$2,'MANUAL',$3,$4)",[org,randomUUID(),rows,preview]);
  const value={code:'SOUP_BATCH',name:'Prepared Soup',input_item_id:fish,inputs:[{item_id:fish,quantity:'40'},{item_id:oil,quantity:'2'}],output_item_id:soup,output_quantity:'200',effective_from:today,output_spec:'One approved portion',tolerance_percent:'0',site_ids:[main,kitchen]},id=randomUUID();
  multi=await val('select public.save_material_processing_baseline($1,$2,$3)',[org,id,value]);assert.equal(await val('select public.save_material_processing_baseline($1,$2,$3)',[org,id,value]),multi);
  const saved=(await setup()).standards.find(s=>s.id===multi);assert.equal(saved.inputs.length,2);assert.equal(saved.output_item_id,soup);assert.equal(saved.site_ids.length,2);
  const costs=await val('select public.material_cost_estimates($1,$2,$3)',[org,[soup],today]);assert.equal(Number(costs[soup].unit_cost),205);
  await bad(val('select public.save_material_processing_baseline($1,$2,$3)',[org,randomUUID(),{...value,code:'BAD',inputs:[...value.inputs,{item_id:fish,quantity:'1'}]}]));
  for(const site of [main,kitchen]){await login(manager);const id=await request({kind:'OPENING',destination_id:site},[{item_id:oil,quantity:'5'}]);await login(owner);await action(id,'APPROVE');await login(manager);await action(id,'POST');}
 });
 await t.test('both centres consume actual multi-input quantities and create only their own single output',async()=>{
  await login(manager);const token=randomUUID(),ids=await submit(main,[row()],token);assert.equal(ids.length,1);assert.deepEqual(await submit(main,[row()],token),ids);assert.equal(await balance(main,fish),70);assert.equal(await balance(main,oil),4.4);assert.equal(await balance(main,soup),48);assert.equal(await balance(kitchen,soup),0);
  await login(chef);await submit(kitchen,[row('10','0.4','49')]);assert.equal(await balance(kitchen,fish),70);assert.equal(await balance(kitchen,oil),4.6);assert.equal(await balance(kitchen,soup),49);
  await bad(submit(main,[row()]),'42501');
  await login(manager);const before=await balance(main,soup);await bad(submit(main,[row('1','4','4'),row('1','4','4')]));assert.equal(await balance(main,fish),70);assert.equal(await balance(main,soup),before);
 });
 await t.test('new baseline refuses disabled centres and cannot consume its own output',async()=>{
  await login(owner);const saved=(await setup()).standards.find(s=>s.id===multi);
  const badValue={code:'INVALID',name:'Invalid',input_item_id:fish,inputs:[{item_id:fish,quantity:'1'},{item_id:soup,quantity:'1'}],output_item_id:soup,output_quantity:'3',effective_from:today,output_spec:'Invalid',tolerance_percent:'0',site_ids:[main]};await bad(val('select public.save_material_processing_baseline($1,$2,$3)',[org,randomUUID(),badValue]));
  const barSite=(await setup()).sites.find(s=>s.kind==='BAR').id;await bad(val('select public.save_processing_standard($1,$2,$3)',[org,randomUUID(),{recipe_version_id:saved.recipe_version_id,primary_item_id:fish,output_spec:'No disabled centre',tolerance_percent:'0',site_ids:[barSite]}]));
 });
 await t.test('Front Kitchen requests both raw store materials and prepared Central Kitchen stock; acceptance alone moves them',async()=>{
  await login(owner);await db.exec('reset role');frontMember=await val('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,outsider]);await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,'stock_department',$3)",[org,frontMember,outlet]);await login(owner);
  front=await centre('FRONT','KITCHEN',frontMember,false);await val("select public.save_stock_member_access($1,$2,0,'ASSIGNED',$3)",[org,frontMember,[{location_id:front,can_request:true,can_handle:false,can_approve:false,can_dispatch:false,can_receive:true}]]);
  for(const [source,item,qty]of [[main,fish,'5'],[kitchen,soup,'10']]){
   await login(owner);const route=await val("select public.save_stock_configuration($1,'ROUTE',$2)",[org,{source_id:source,destination_id:front,kind:'TRANSFER',approval_role:'inventory_manager'}]);
   await login(outsider);const id=await request({kind:'TRANSFER',route_id:route},[{item_id:item,quantity:qty}]);await login(manager);const before=await balance(source,item);await action(id,'APPROVE');await action(id,'DISPATCH');assert.equal(await balance(source,item),before);assert.equal(await balance(front,item),0);
   await login(outsider);await action(id,'RECEIVE',[{item_id:item,quantity:qty,reason:''}]);await login(manager);assert.equal(await balance(source,item),before-Number(qty));assert.equal(await balance(front,item),Number(qty));
  }
 });
 await t.test('disabling one centre does not disable another and cannot strand a pending batch or rewrite history',async()=>{
  await login(manager);const pending=await production(kitchen,'2','5','0',{usable_weight_kg:'',variance_reason:'Measured output'});await login(owner);await bad(enabled([main]));assert.equal((await setup()).sites.find(s=>s.id===kitchen).processing_enabled,true);
  await login(manager);await val('select public.complete_processing_record($1,$2,$3)',[org,pending,'Emeka']);await login(owner);await enabled([main]);assert.equal((await setup()).sites.find(s=>s.id===main).processing_enabled,true);assert.equal((await setup()).sites.find(s=>s.id===kitchen).processing_enabled,false);
  await login(chef);await bad(submit(kitchen,[row('1','0.1','4')]));assert.ok((await history(kitchen)).rows.some(b=>b.id===pending));await login(owner);await enabled([main,kitchen]);
  await db.exec('reset role;set role anon');await bad(val('select public.save_processing_centres($1,$2,0)',[org,[main]]),'42501');
 });
 }finally{await db.close();}
});
