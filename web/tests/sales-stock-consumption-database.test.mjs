import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile, readdir } from "node:fs/promises";
import { PGlite } from "./helpers/active-restaurant-db.mjs";
const headers = 'Organisation_Code,Source_System,Location_Code,Sale_Date,Transaction_Ref,Line_Ref,Menu_Code,Quantity,Gross_Sales,Discount,Tax,Net_Sales,Channel_Code,Line_Type,Parent_Line_Ref,Status';
const base = ['ORG001','POS_A','PRIMARY','2020-01-15','TX001','001','MENU001','2','3000','0','0','3000','DINE_IN','NORMAL','','PAID'];
const row = (changes = {}) => base.map((value, i) => changes[i] ?? value);
const csv = rows => headers + '\r\n' + rows.map(values => values.map(value => '"' + value.replaceAll('"','""') + '"').join(',')).join('\r\n');

test('dated POS consumption reconciles stock without double depletion', async t => {
 const db = new PGlite();
 const ids = Array.from({ length: 8 }, (_, i) => `70000000-0000-0000-0000-${String(i+1).padStart(12,'0')}`);
 const [owner, other, finance, , procurement] = ids;
 const scalar = async (sql, params = []) => Object.values((await db.query(sql,params)).rows[0])[0];
 const login = async id => { await db.exec('reset role'); await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]); await db.exec('set role authenticated'); };
 const rejects = (work, code = '22023') => assert.rejects(work, error => error.code === code);
 let org, location, brand, kg, pcs, ingredient, recipe, menu, menuVersion;
 const stage = (text, { request = randomUUID(), basis = 'EXCLUSIVE', currency = 'NGN', maps = {}, tenant = org } = {}) => scalar("select public.stage_sales_import($1,$2,'sales.csv',$3,'ORG001',$4,$5,$6::jsonb)",[tenant,request,text,basis,currency,JSON.stringify(maps)]);
 const detail = id => scalar('select public.get_sales_import($1,$2)',[org,id]);
 const post = async (id, controls) => scalar('select public.post_sales_import($1,$2,$3::jsonb)',[org,id,JSON.stringify(controls ?? Object.fromEntries((await detail(id)).report.receipts.filter(r => !r.duplicate).map(r => [r.key,r.total])))]);
 const priceMaterial = async (code, amount) => {
  const rows=JSON.stringify([{material_code:code,quantity:'1',unit_code:'KG',total_price:amount,price_date:'2020-01-01',source_note:'Fictional cost'}]);
  const review=await scalar('select public.preview_material_reference_prices($1,$2::jsonb)',[org,rows]);
  await scalar("select public.save_material_reference_prices($1,$2,'MANUAL',$3::jsonb,$4::jsonb)",[org,randomUUID(),rows,JSON.stringify(review)]);
 };
 const publishRecipe = (code,item) => scalar("select public.publish_recipe_version($1,null,$2,$3,$3,'FINAL','2020-01-01',1,$4,'',$5::jsonb)",[org,randomUUID(),code,pcs,JSON.stringify([{kind:'ITEM',target_id:item,quantity:'1',uom_id:kg}])]);
 const publishMenu = ({id=null,code='MENU001',source=recipe,quantity='1'}={}) => scalar("select public.publish_menu_item_version($1,$2,$3,$4,$4,$5,'Mains',$6,$7,'2020-01-01','')",[org,id,randomUUID(),code,brand,source,quantity]);
 try {
  await db.exec(`create role anon; create role authenticated; create schema auth; create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);
   create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
   grant usage on schema public,auth to authenticated,anon; grant execute on function auth.uid() to authenticated,anon;`);
  for(const id of ids) await db.query('insert into auth.users(id,email_confirmed_at) values($1,now())',[id]);
  for(const name of (await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(name=>name.endsWith('.sql')).sort()) await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
  for(const id of [other,owner]) { await login(id); await db.query("select public.save_restaurant_setup('Restaurant','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)"); const created=await scalar('select public.complete_restaurant_setup()'); if(id===owner) org=created; }
  brand=await scalar('select id from public.brands limit 1'); location=await scalar('select id from public.locations limit 1');
  kg=await scalar("select id from public.units_of_measure where code='KG'"); pcs=await scalar("select id from public.units_of_measure where code='PCS'");
  ingredient=await scalar("select public.save_catalogue_material($1,null,'RICE','Rice','RAW','',$2,true,true)",[org,kg]); await priceMaterial('RICE','900');
  recipe=await publishRecipe('RECIPE',ingredient); menuVersion=await publishMenu(); menu=await scalar('select menu_item_id from public.menu_item_versions where id=$1',[menuVersion]);
  await scalar("select public.save_menu_selling_price($1,$2,$3,$4,'DINE_IN',9999,'NONE',0,'2020-01-01',null,'Different listed price')",[org,menu,randomUUID(),location]);


  await db.exec('reset role');
  const member=await scalar('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,procurement]);
  await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,'inventory_manager')",[org,member]);
  await login(owner);const ownerMember=await scalar('select id from public.organisation_memberships where organisation_id=$1 and user_id=$2',[org,owner]);
  const centre=await scalar('select public.save_stock_centre($1,$2)',[org,{code:'KITCHEN',name:'Kitchen',kind:'KITCHEN',responsible:ownerMember}]);
  const read=async(sql,args=[])=>{await db.exec('reset role');try{return await scalar(sql,args);}finally{await db.exec('set role authenticated');}};
  const balance=()=>read('select coalesce(sum(quantity),0) from public.stock_ledger where organisation_id=$1 and location_id=$2 and item_id=$3',[org,centre,ingredient]);
  const opening=async(qty,day='2020-01-01')=>{
   await login(procurement);const id=await scalar('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),{kind:'OPENING',destination_id:centre,date:day,note:'Verified opening'},[{item_id:ingredient,quantity:String(qty)}]]);
   await login(owner);await scalar("select public.stock_document_action($1,$2,'APPROVE','Verified',null)",[org,id]);await login(procurement);await scalar("select public.stock_document_action($1,$2,'POST','Verified',null)",[org,id]);await login(owner);
  };
  await opening(100);
  const queue=()=>scalar("select public.sales_stock_queue($1,null,null,null,1,'ALL')",[org]);
  await t.test('missing mapping retains financial sales but no stock deduction',async()=>{
   const b=await stage(csv([row()]));await post(b);assert.equal(Number(await balance()),100);
   const q=await queue();assert.equal(q.pending,1);assert.match(q.rows[0].reason,/stock centre/i);
  });
  await t.test('dated mapping, standard deduction and retries are exact',async()=>{
   const token=randomUUID();const args=[org,token,menu,location,centre,'RECIPE','2020-01-01'];
   const mapping=await scalar('select public.save_menu_stock_mapping($1,$2,$3,$4,$5,$6,$7)',args);assert.equal(await scalar('select public.save_menu_stock_mapping($1,$2,$3,$4,$5,$6,$7)',args),mapping);
   const job=(await queue()).rows[0].id;let p=await scalar('select public.sales_stock_review($1,$2)',[org,job]);assert.deepEqual(p.errors,[]);assert.equal(Number(p.lines[0].quantity),2);
   const args2=[org,job,p.evidence,false,''];const doc=await scalar('select public.resolve_sales_stock($1,$2,$3,$4,$5)',args2);assert.ok(doc);assert.equal(await scalar('select public.resolve_sales_stock($1,$2,$3,$4,$5)',args2),doc);assert.equal(Number(await balance()),98);
   assert.equal(await read("select occurred_on::text from public.stock_ledger where document_id=$1",[doc]),'2020-01-15');
   const dup=await stage(csv([row()]));await post(dup);assert.equal((await queue()).total,1);assert.equal(Number(await balance()),98);
  });
  await t.test('new sales consume automatically; insufficient dated stock stays actionable',async()=>{
   await post(await stage(csv([row({4:'AUTO',7:'3',8:'4500',11:'4500'})])));assert.equal(Number(await balance()),95);
   await post(await stage(csv([row({4:'SHORT',7:'200',8:'300000',11:'300000'})])));const q=await queue();assert.equal(q.pending,1);assert.match(q.rows.find(r=>r.state==='PENDING').reason,/Insufficient dated stock/);assert.equal(Number(await balance()),95);
  });

  await t.test('a late sale is independently reconciled against posted physical stock once',async()=>{
   // Resolve the deliberately short receipt before opening this count: isolate this scenario.
   await db.exec('reset role');
   await db.query("insert into private.monthly_count_programmes values($1,$2,'2020-01-01',true,16,'23:59','Africa/Lagos',24,'Ada')",[org,centre]);
   const fm=await scalar('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,finance]);await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,'finance')",[org,fm]);
   await login(procurement);const c=await scalar("select public.start_monthly_count_actual($1,$2,'2020-01-16','2020-01-16','AFTER_CLOSING','')",[org,centre]);
   let d=await scalar('select public.monthly_count_detail($1,$2)',[org,c]);assert.equal(Number(d.lines[0].book),95);
   await scalar('select public.save_monthly_count($1,$2,0,$3,$4,true,$5,$6,false)',[org,c,randomUUID(),[{item_id:ingredient,physical:'90',note:'Counted'}],'Ada','Physical check']);
   await login(owner);await scalar("select public.weekly_count_action($1,$2,1,$3,'APPROVE','Reviewed')",[org,c,randomUUID()]);
   await login(procurement);await assert.rejects(scalar("select public.weekly_count_action($1,$2,2,$3,'POST','Posted')",[org,c,randomUUID()]),e=>e.code==='22023'&&/Resolve pending sales consumption/.test(e.message));assert.equal(Number(await balance()),95);
   // Remove the deliberately invalid shortage fixture only after verifying the production gate.
   await db.exec('reset role');await db.query("update private.sales_stock_jobs set state='EXCLUDED',reason='Isolated shortage fixture' where organisation_id=$1 and state='PENDING'",[org]);await login(procurement);
   await scalar("select public.weekly_count_action($1,$2,2,$3,'POST','Posted')",[org,c,randomUUID()]);assert.equal(Number(await balance()),90);
   await login(owner);await post(await stage(csv([row({4:'LATE',7:'2',8:'3000',11:'3000'})])));const job=(await queue()).rows.find(r=>r.transaction_ref==='LATE');assert.equal(job.state,'PENDING');assert.equal(Number(await balance()),90);
   let plan=await scalar('select public.sales_stock_review($1,$2)',[org,job.id]);assert.deepEqual(plan.errors,[]);assert.equal(plan.needs_review,true);assert.equal(plan.can_reconcile,false);
   await rejects(scalar('select public.resolve_sales_stock($1,$2,$3,true,$4)',[org,job.id,plan.evidence,'Checked late sales']),'42501');
   await login(finance);plan=await scalar('select public.sales_stock_review($1,$2)',[org,job.id]);assert.equal(plan.can_reconcile,true);
   const args=[org,job.id,plan.evidence,'Reconcile fulfilled sales already counted'];const doc=await scalar('select public.resolve_sales_stock($1,$2,$3,true,$4)',args);assert.ok(doc);assert.equal(Number(await balance()),90);await scalar('select public.resolve_sales_stock($1,$2,$3,true,$4)',args);assert.equal(Number(await balance()),90);
   const completed=await scalar('select public.sales_stock_review($1,$2)',[org,job.id]);assert.equal(completed.state,'RECONCILED');assert.equal(completed.needs_review,false);assert.deepEqual(completed.errors,[]);
   d=await scalar('select public.monthly_count_detail($1,$2)',[org,c]);assert.equal(Number(d.lines[0].book),95);assert.equal(Number(d.sales_reconciliations[0].book_delta),-2);assert.equal(d.state,'POSTED');
   const analysis=await scalar("select public.monthly_count_analysis($1,$2,'2020-01-01','2020-01-31',1)",[org,centre]);assert.equal(Number(analysis.summary.book_value),83700);assert.equal(Number(analysis.summary.shortage_value),2700);
   await login(owner);
  });

  await t.test('stocked sub-recipes and finished menus never consume production inputs twice',async()=>{
   const cut=await scalar('select public.save_material_setup($1,$2)',[org,{code:'CUT',name:'Cut fish',item_type:'SEMI_FINISHED',base_uom_id:pcs,stock_tracked:true,is_active:true,supply_class:'PROCESSED'}]);
   const finished=await scalar('select public.save_material_setup($1,$2)',[org,{code:'FINISHED',name:'Packed plate',item_type:'FINISHED',base_uom_id:pcs,stock_tracked:true,is_active:true,supply_class:'PROCESSED'}]);
   const child=await scalar("select public.publish_recipe_version($1,null,$2,'CUTTING','Cutting','SUB_RECIPE','2020-01-01',120,$3,'',$4)",[org,randomUUID(),pcs,[{kind:'ITEM',target_id:ingredient,quantity:'40',uom_id:kg}]]);
   await scalar("select public.save_stock_configuration($1,'BINDING',$2)",[org,{recipe_version_id:child,item_id:cut}]);
   const final=await scalar("select public.publish_recipe_version($1,null,$2,'PLATE','Plate','FINAL','2020-01-01',1,$3,'',$4)",[org,randomUUID(),pcs,[{kind:'RECIPE',target_id:child,quantity:'2',uom_id:pcs}]]);
   const version=await scalar("select public.publish_menu_item_version($1,null,$2,'PLATE','Plate',$3,'Mains',$4,1,'2020-01-01','')",[org,randomUUID(),brand,final]);const dish=await scalar('select menu_item_id from public.menu_item_versions where id=$1',[version]);
   await scalar('select public.save_menu_stock_mapping($1,$2,$3,$4,$5,$6,$7)',[org,randomUUID(),dish,location,centre,'RECIPE','2020-01-01']);
   await login(procurement);const doc=await scalar('select public.request_stock_document($1,$2,$3,$4)',[org,randomUUID(),{kind:'OPENING',destination_id:centre,date:'2020-01-01',note:'Fixture finished stock'},[{item_id:cut,quantity:'10'},{item_id:finished,quantity:'10'}]]);await login(owner);await scalar("select public.stock_document_action($1,$2,'APPROVE','Verified',null)",[org,doc]);await login(procurement);await scalar("select public.stock_document_action($1,$2,'POST','Posted',null)",[org,doc]);await login(owner);
   await post(await stage(csv([row({4:'STOCKED-CHILD',6:'PLATE',7:'1',8:'1500',11:'1500'})])));
   let job=(await queue()).rows.find(r=>r.transaction_ref==='STOCKED-CHILD');assert.equal(job.state,'POSTED',job.reason);assert.equal(Number(await read('select sum(quantity) from public.stock_ledger where location_id=$1 and item_id=$2',[centre,cut])),8);assert.equal(Number(await balance()),90);
   await scalar("select public.save_stock_configuration($1,'BINDING',$2)",[org,{recipe_version_id:final,item_id:finished}]);
   await scalar('select public.save_menu_stock_mapping($1,$2,$3,$4,$5,$6,$7)',[org,randomUUID(),dish,location,centre,'FINISHED','2020-01-01']);
   await post(await stage(csv([row({4:'FINISHED-SALE',6:'PLATE',7:'1',8:'1500',11:'1500'})])));job=(await queue()).rows.find(r=>r.transaction_ref==='FINISHED-SALE');assert.equal(job.state,'POSTED',job.reason);assert.equal(Number(await read('select sum(quantity) from public.stock_ledger where location_id=$1 and item_id=$2',[centre,finished])),9);assert.equal(Number(await read('select sum(quantity) from public.stock_ledger where location_id=$1 and item_id=$2',[centre,cut])),8);assert.equal(Number(await balance()),90);
  });

  await t.test('menu bulk review validates and saves centre mappings with the standard price',async()=>{
   const cats=await scalar('select public.menu_categories($1)',[org]);
   if(!cats.categories.some(c=>c.major==='FOOD'&&c.name==='Mains'))await scalar('select public.save_menu_categories($1,$2,$3)',[org,cats.revision,[...cats.categories,{major:'FOOD',name:'Mains',is_active:true}]]);
   const rows=[{action:'CREATE',menu_code:'IMPORTED',menu_name:'Imported plate',major_category:'FOOD',subcategory:'Mains',recipe_code:'RECIPE',recipe_version:'',recipe_quantity:'1',selling_price:'6000',tax_setting:'NONE',tax_percent:'0',effective_from:'2020-01-01',stock_centre_code:'KITCHEN',consumption_mode:'RECIPE'}];
   const preview=await scalar('select public.preview_menu_catalogue_import($1,$2,$3)',[org,location,rows]);assert.equal(preview.valid,true,JSON.stringify(preview));
   await scalar('select public.post_menu_catalogue_import($1,$2,$3,$4,$5)',[org,location,randomUUID(),rows,preview]);
   const id=await scalar("select id from public.menu_items where organisation_id=$1 and code='IMPORTED'",[org]);const dir=await scalar('select public.menu_stock_directory($1,$2)',[org,id]);assert.equal(dir.routes[0].site_id,centre);
   rows[0].action='UPDATE';const again=await scalar('select public.preview_menu_catalogue_import($1,$2,$3)',[org,location,rows]);assert.equal(again.rows[0].action,'UNCHANGED');
  });
  await t.test('tenant and anonymous access cannot review or map another business',async()=>{
   const job=(await queue()).rows[0].id;await login(other);await rejects(scalar('select public.sales_stock_review($1,$2)',[org,job]),'42501');await rejects(scalar('select public.save_menu_stock_mapping($1,$2,$3,$4,$5,$6,$7)',[org,randomUUID(),menu,location,centre,'RECIPE','2020-01-01']),'42501');await login(owner);
  });
 }finally{await db.close();}
});
