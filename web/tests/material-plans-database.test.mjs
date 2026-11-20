import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile,readdir} from 'node:fs/promises';import {randomUUID} from 'node:crypto';import {PGlite} from '@electric-sql/pglite';
test('material plans consolidate versioned recipe targets without changing stock',async t=>{
 const db=new PGlite(),[owner,manager,chef,outsider]=Array.from({length:4},()=>randomUUID()),today=new Date().toISOString().slice(0,10);
 const val=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0],login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');},bad=(work,code='22023')=>assert.rejects(work,e=>e.code===code);
 let org,outlet,kg,pcs,fish,cut,version,main,kitchen,standard,managerMember,chefMember;
 const balance=async(site,item)=>Number((await val('select public.stock_workspace($1,$2,1)',[org,site])).balances.find(b=>b.item_id===item)?.quantity??0);
 const request=(doc,lines,id=randomUUID())=>val('select public.request_stock_document($1,$2,$3,$4)',[org,id,{date:today,note:'Physical batch record',...doc},lines]);
 const action=(id,choice,received=null)=>val('select public.stock_document_action($1,$2,$3,$4,$5)',[org,id,choice,'Verified evidence',received]);
 const centre=(name,kind,responsible,processing=true,id=null)=>val('select public.save_stock_centre($1,$2)',[org,{id,code:name,name,kind,responsible,processing_enabled:processing,...(kind==='KITCHEN'||kind==='BAR'?{outlet_id:outlet}:{})}]);
 const standardValue=()=>({recipe_version_id:version,primary_item_id:fish,output_spec:'120 uniform approved cuts',target_piece_weight_kg:'0.3',expected_trim_kg:'4',tolerance_percent:'0',site_ids:[main,kitchen]});
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


 let oil,meal,nested;
 const generate=(site,rows,basis='STOCK',date=today)=>val('select public.generate_material_plan($1,$2,$3,$4,$5)',[org,site,date,rows,basis]);
 const target=(recipe_version_id,quantity)=>({recipe_version_id,quantity});
 await t.test('recipes and a processing baseline consolidate shared inputs and preserve exact target scaling',async()=>{
  await login(owner);oil=await val("select public.save_catalogue_material($1,null,'OIL','Cooking Oil','RAW','Cooking',$2,true,true)",[org,kg]);
  meal=await val("select public.publish_recipe_version($1,null,$2,'MEAL','Fish Meal','FINAL',$3,10,$4,'',$5)",[org,randomUUID(),today,pcs,[{kind:'ITEM',target_id:fish,quantity:'20',uom_id:kg},{kind:'ITEM',target_id:oil,quantity:'2',uom_id:kg}]]);
  const plan=await generate(main,[target(version,'12'),target(meal,'2')]);assert.equal(plan.recipes.length,2);assert.equal(Number(plan.materials.find(m=>m.item_id===fish).required),8);assert.equal(Number(plan.materials.find(m=>m.item_id===oil).required),0.4);assert.equal(plan.recipes[0].baseline_id,standard);assert.equal(plan.centre_id,main);
  const options=await val('select public.material_plan_options($1,$2,$3)',[org,main,today]);assert.ok(options.recipes.find(r=>r.id===meal));
 });
 await t.test('zero stock and shortages do not reject plans, reserve stock, or create stock documents',async()=>{
  await db.exec('reset role');const before=await val('select count(*) from public.stock_documents where organisation_id=$1',[org]);await login(chef);const balances=await balance(kitchen,fish);
  const plan=await generate(kitchen,[target(meal,'100')]);assert.equal(Number(plan.materials.find(m=>m.item_id===oil).available),0);assert.equal(Number(plan.materials.find(m=>m.item_id===oil).shortage),20);assert.equal(Number(plan.materials.find(m=>m.item_id===fish).shortage),120);
  assert.equal(await balance(kitchen,fish),balances);await db.exec('reset role');assert.equal(await val('select count(*) from public.stock_documents where organisation_id=$1',[org]),before);await login(chef);assert.deepEqual((await generate(kitchen,[target(meal,'100')])).materials,plan.materials);
 });
 await t.test('stocked child preparations and expanded pinned sub-recipes are separate, with no double counting',async()=>{
  await login(owner);nested=await val("select public.publish_recipe_version($1,null,$2,'NESTED','Nested Meal','FINAL',$3,2,$4,'',$5)",[org,randomUUID(),today,pcs,[{kind:'RECIPE',target_id:version,quantity:'6',uom_id:pcs},{kind:'ITEM',target_id:oil,quantity:'1',uom_id:kg}]]);
  const stock=await generate(main,[target(nested,'2')]);assert.equal(stock.materials.length,2);assert.equal(Number(stock.materials.find(m=>m.item_id===cut).required),6);assert.equal(stock.materials.some(m=>m.item_id===fish),false);
  const ingredients=await generate(main,[target(nested,'2')],'RECIPE');assert.equal(ingredients.materials.some(m=>m.item_id===cut),false);assert.equal(Number(ingredients.materials.find(m=>m.item_id===fish).required),2);assert.equal(Number(ingredients.materials.find(m=>m.item_id===oil).required),1);
 });
 await t.test('targets reject duplicates, missing recipes and invalid quantities; generated requirements normalise material units',async()=>{
  await bad(generate(main,[target(meal,'0')]));await bad(generate(main,[target(meal,'1'),target(meal,'1')]));await bad(generate(main,[target(randomUUID(),'1')]));await bad(generate(main,[target(meal,'1')],'WRONG'));
  const gram=await val("select id from public.units_of_measure where organisation_id=$1 and code='G'",[org]);const unitRecipe=await val("select public.publish_recipe_version($1,null,$2,'GRAMS','Gram recipe','SUB_RECIPE',$3,3,$4,'',$5)",[org,randomUUID(),today,pcs,[{kind:'ITEM',target_id:fish,quantity:'1000',uom_id:gram}]]);const plan=await generate(main,[target(unitRecipe,'3')]);assert.equal(plan.materials[0].unit,'KG');assert.equal(Number(plan.materials[0].required),1);
 });
 await t.test('centre, restaurant and anonymous restrictions apply to options and generation, without financial role escalation',async()=>{
  await login(chef);await bad(generate(main,[target(meal,'1')]),'42501');await bad(val('select public.material_plan_options($1,$2,$3)',[org,main,today]),'42501');
  await login(outsider);await bad(generate(kitchen,[target(meal,'1')]),'42501');await login(owner);await bad(generate(randomUUID(),[target(meal,'1')]),'42501');
  await db.exec('reset role');const member=await val('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,outsider]);await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,'finance')",[org,member]);await login(outsider);assert.equal((await val('select public.material_plan_options($1,null,$2)',[org,today])).centres.length,0);await bad(generate(main,[target(meal,'1')]),'42501');await db.exec('reset role;set role anon');await bad(generate(main,[target(meal,'1')]),'42501');
 });
 }finally{await db.close();}
});
