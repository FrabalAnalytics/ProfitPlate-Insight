import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';

test('executive briefing connects corrected purchase prices, posted loss exposure and accountable handovers without claiming actual profit',async t=>{
 const db=new PGlite(),[owner,finance,ceo,department,outsider]=Array.from({length:5},()=>randomUUID());
 const val=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
 let org,outlet,kg,bag,pcs,rice,unpriced,supplier,main,kitchen,brand,menu,version,currentPurchase;
 const briefing=(from='2020-01-15',to=from,site=null)=>val('select public.executive_profitability_briefing($1,$2,$3,$4)',[org,from,to,site]);
 const invoice=(day,ref,price,qty='10')=>({supplier_id:supplier,location_id:outlet,date:day,reference:ref,currency:'NGN',route:'DIRECT',direct_reason:'Pilot evidence',evidence:'Verified supplier invoice',price_basis:'EXCLUSIVE',total:String(Number(price)*Number(qty))});
 const lines=(price,qty='10')=>[{item_id:rice,uom_id:kg,quantity:qty,unit_price:price,discount:'0',tax:'0'}];
 const purchase=async(day,ref,price,pack=false)=>{
  const purchasedLines=pack?[{...lines(String(Number(price)*10),'1')[0],uom_id:bag}]:lines(price);
  const id=await val('select public.stage_manual_purchase($1,$2,$3,$4)',[org,randomUUID(),invoice(day,ref,price),purchasedLines]);
  const data=await val('select public.get_purchase_import($1,$2)',[org,id]);
  await val('select public.post_purchase_import($1,$2,$3)',[org,id,Object.fromEntries(data.report.documents.map(d=>[d.key,d.total]))]);
  return val('select id from public.purchase_headers where organisation_id=$1 and import_batch_id=$2',[org,id]);
 };
 try {
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
  for(const id of[owner,finance,ceo,department,outsider])await db.query('insert into auth.users values($1,now(),$2)',[id,`${id}@example.test`]);
  for(const name of(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
  await login(owner);await val("select public.save_restaurant_setup('Executive Evidence','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");org=await val('select public.complete_restaurant_setup()');
  outlet=await val('select id from public.locations where organisation_id=$1',[org]);brand=await val('select brand_id from public.locations where id=$1',[outlet]);kg=await val("select id from public.units_of_measure where organisation_id=$1 and code='KG'",[org]);pcs=await val("select id from public.units_of_measure where organisation_id=$1 and code='PCS'",[org]);
  rice=await val("select public.save_catalogue_material($1,null,'RICE','Rice','RAW','',$2,true,true)",[org,kg]);unpriced=await val("select public.save_catalogue_material($1,null,'UNKNOWN','Unpriced','RAW','',$2,true,true)",[org,kg]);supplier=await val("select public.save_catalogue_supplier($1,null,'SUP','Supplier','','','',true)",[org]);
  bag=await val("select id from public.units_of_measure where organisation_id=$1 and code='BAG'",[org]);await val("select public.save_material_conversion($1,$2,$3,10,'2020-01-01')",[org,rice,bag]);
  const prices=[{material_code:'RICE',quantity:'1',unit_code:'KG',total_price:'90',price_date:'2020-01-01',source_note:'Reviewed reference'}];const preview=await val('select public.preview_material_reference_prices($1,$2)',[org,prices]);await val("select public.save_material_reference_prices($1,$2,'MANUAL',$3,$4)",[org,randomUUID(),prices,preview]);
  const recipe=await val("select public.publish_recipe_version($1,null,$2,'PLATE','Plate','FINAL','2020-01-01',1,$3,'',$4)",[org,randomUUID(),pcs,[{kind:'ITEM',target_id:rice,quantity:'1',uom_id:kg}]]);
  version=await val("select public.publish_menu_item_version($1,null,$2,'DISH','Dish',$3,'Mains',$4,1,'2020-01-01','')",[org,randomUUID(),brand,recipe]);menu=await val('select menu_item_id from public.menu_item_versions where id=$1',[version]);
  // Sales use actual source net revenue; the recipe is pinned and priced at 90.
  const header='Organisation_Code,Source_System,Location_Code,Sale_Date,Transaction_Ref,Line_Ref,Menu_Code,Quantity,Gross_Sales,Discount,Tax,Net_Sales,Channel_Code,Line_Type,Parent_Line_Ref,Status\n';
  const csv=header+'ORG,POS,PRIMARY,2020-01-14,PREVIOUS,1,DISH,1,200,0,0,200,DINE_IN,NORMAL,,PAID\nORG,POS,PRIMARY,2020-01-15,CURRENT,1,DISH,2,300,0,0,300,DINE_IN,NORMAL,,PAID';
  const batch=await val("select public.stage_sales_import($1,$2,'sales.csv',$3,'ORG','EXCLUSIVE','NGN','{}')",[org,randomUUID(),csv]);const sales=await val('select public.get_sales_import($1,$2)',[org,batch]);await val('select public.post_sales_import($1,$2,$3)',[org,batch,Object.fromEntries(sales.report.receipts.map(r=>[r.key,r.total]))]);
  await purchase('2020-01-14','PRIOR','100');currentPurchase=await purchase('2020-01-15','CURRENT','120',true);
  main=await val("select public.save_stock_configuration($1,'LOCATION',$2)",[org,{code:'MAIN',name:'Main Store',kind:'STORE',outlet_id:outlet}]);kitchen=await val("select public.save_stock_configuration($1,'LOCATION',$2)",[org,{code:'KIT',name:'Kitchen',kind:'KITCHEN',outlet_id:outlet}]);
  await db.exec('reset role');for(const[id,role,scope]of[[finance,'finance',null],[ceo,'ceo',null],[department,'stock_department',outlet]]){const member=await val('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,id]);await db.query('insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,$3,$4)',[org,member,role,scope]);}
  // Seed ledger evidence directly: tests below exercise reporting, not posting permissions.
  const stock=async(kind,state,qty,item=rice)=>{
   const id=await val("insert into public.stock_documents(organisation_id,request_id,input_hash,reference,kind,state,source_id,destination_id,document_date,note,lines,created_by,created_at,dispatched_at) values($1,$2,'fixture',$3,$4,$5,$6,$7,'2020-01-15','Reporting evidence','[]',$8,now()-interval '2 days',case when $5 in ('DISPATCHED','PARTIAL') then now()-interval '2 days' end) returning id",[org,randomUUID(),randomUUID(),kind,state,main,['ISSUE','TRANSFER'].includes(kind)?kitchen:null,owner]);
   if(qty!==null)await db.query("insert into public.stock_ledger(organisation_id,document_id,location_id,item_id,quantity,occurred_on) values($1,$2,$3,$4,$5,'2020-01-15')",[org,id,main,item,qty]);return id;
  };
  await stock('WASTE','POSTED','-2');await stock('COUNT','POSTED','-1');await stock('COUNT','POSTED','5');await stock('WASTE','POSTED','-3',unpriced);await stock('WASTE','REQUESTED',null);const pending=await stock('ISSUE','DISPATCHED',null);const partial=await stock('TRANSFER','PARTIAL',null);
  await login(ceo);
  await t.test('shows real sales/margin comparison, menu risk location and normalised purchasing exposure',async()=>{
   const p=await briefing();assert.equal(Number(p.summary.net_revenue),300);assert.equal(Number(p.previous.net_revenue),200);assert.equal(Number(p.summary.estimated_food_margin),120);assert.equal(Number(p.summary.food_margin_percent),40);assert.equal(Number(p.previous.food_margin_percent),55);
   assert.equal(p.prices.total,1);assert.equal(Number(p.prices.impact),200);assert.equal(Number(p.prices.rows[0].change_percent),20);assert.equal(p.prices.rows[0].unit,'KG');assert.equal(Number(p.prices.rows[0].current_price),120);assert.equal(p.menus.total,1);assert.equal(p.menus.rows[0].menu_item_id,menu);assert.equal(Number(p.menus.rows[0].food_cost_percent),60);assert.equal(p.menus.rows[0].locations,'Outlet');assert.equal(Number(p.food_margin_change_pp),-15);assert.equal(Number(p.food_cost_change_pp),15);
  });
  await t.test('values only posted waste and negative counts, preserves missing price coverage, and avoids stock-gain netting',async()=>{
   const p=await briefing();assert.equal(p.waste.lines,3);assert.equal(p.waste.unpriced,1);assert.equal(Number(p.waste.known_value),270);assert.equal(Number(p.waste.waste_value),180);assert.equal(Number(p.waste.shortage_value),90);assert.equal(Number(p.summary.estimated_food_margin),120);
  });
  await t.test('live accountability remains visible in an empty historical sales period and resolved follow-ups disappear',async()=>{
   const p=await briefing('2020-02-01');assert.equal(p.summary.lines,0);assert.equal(p.movements.open,2);assert.equal(p.movements.handover,2);assert.equal(p.movements.overdue,2);assert.match(p.movements.rows.find(r=>r.id===pending).next_action,/Kitchen: accept/);
   await db.exec('reset role');await db.query('update public.stock_documents set resolved_at=now(),resolved_by=$2,resolution_note=$3 where id=$1',[partial,owner,'Physically returned']);await login(ceo);assert.equal((await briefing()).movements.open,1);
  });
  await t.test('approved financial corrections replace original price evidence and approved voids remove it',async()=>{
   await login(owner);const request=await val("select public.request_purchase_correction($1,$2,$3,0,'REPLACE','Correct invoice price',$4,$5)",[org,currentPurchase,randomUUID(),invoice('2020-01-15','CURRENT','110'),lines('110')]);await login(finance);await val("select public.decide_purchase_correction($1,$2,true,'Verified supplier correction')",[org,request]);assert.equal(Number((await briefing()).prices.impact),100);
   await login(owner);const voidRequest=await val("select public.request_purchase_correction($1,$2,$3,1,'VOID','Void duplicate evidence',null,null)",[org,currentPurchase,randomUUID()]);await login(finance);await val("select public.decide_purchase_correction($1,$2,true,'Confirmed void')",[org,voidRequest]);assert.equal((await briefing()).prices.total,0);
  });
  await t.test('financial authorisation, tenant isolation and date/outlet boundaries apply before evidence is returned',async()=>{
   await login(department);await assert.rejects(briefing(),e=>e.code==='42501');await login(outsider);await assert.rejects(briefing(),e=>e.code==='42501');await login(ceo);await assert.rejects(briefing('2020-01-01','2020-12-31'),e=>e.code==='22023');await assert.rejects(briefing('2020-01-15','2020-01-15',randomUUID()),e=>e.code==='42501');await db.exec('reset role;set role anon');await assert.rejects(briefing(),e=>e.code==='42501');
  });
 }finally{await db.close();}
});
