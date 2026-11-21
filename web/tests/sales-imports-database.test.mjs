import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID, createHash } from "node:crypto";
import { readFile, readdir } from "node:fs/promises";
import { PGlite } from "@electric-sql/pglite";
const headers = 'Organisation_Code,Source_System,Location_Code,Sale_Date,Transaction_Ref,Line_Ref,Menu_Code,Quantity,Gross_Sales,Discount,Tax,Net_Sales,Channel_Code,Line_Type,Parent_Line_Ref,Status';
const base = ['ORG001','POS_A','PRIMARY','2020-01-15','TX001','001','MENU001','2','3000','0','0','3000','DINE_IN','NORMAL','','PAID'];
const row = (changes = {}) => base.map((value, i) => changes[i] ?? value);
const csv = rows => headers + '\r\n' + rows.map(values => values.map(value => '"' + value.replaceAll('"','""') + '"').join(',')).join('\r\n');

test('sales imports reconcile source receipts, pin menu versions and expose incomplete food margins', async t => {
 const db = new PGlite();
 const ids = Array.from({ length: 8 }, (_, i) => `70000000-0000-0000-0000-${String(i+1).padStart(12,'0')}`);
 const [owner, other, finance, ceo, procurement, operations, scoped, founder] = ids;
 const scalar = async (sql, params = []) => Object.values((await db.query(sql,params)).rows[0])[0];
 const login = async id => { await db.exec('reset role'); await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]); await db.exec('set role authenticated'); };
 const rejects = (work, code = '22023') => assert.rejects(work, error => error.code === code);
 let org, otherOrg, location, secondLocation, brand, kg, pcs, ingredient, recipe, menu, menuVersion, batch;
 const stage = (text, { request = randomUUID(), basis = 'EXCLUSIVE', currency = 'NGN', maps = {}, tenant = org } = {}) => scalar("select public.stage_sales_import($1,$2,'sales.csv',$3,'ORG001',$4,$5,$6::jsonb)",[tenant,request,text,basis,currency,JSON.stringify(maps)]);
 const detail = id => scalar('select public.get_sales_import($1,$2)',[org,id]);
 const post = async (id, controls) => scalar('select public.post_sales_import($1,$2,$3::jsonb)',[org,id,JSON.stringify(controls ?? Object.fromEntries((await detail(id)).report.receipts.filter(r => !r.duplicate).map(r => [r.key,r.total])))]);
 const overview = (from='2020-01-15',to=from,loc=null,tenant=org) => scalar('select public.executive_overview($1,$2,$3,$4)',[tenant,from,to,loc]);
 const summary = (from='2020-01-15',to=from,loc=null,tenant=org) => scalar('select public.sales_period_summary($1,$2,$3,$4)',[tenant,from,to,loc]);
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
  for(const id of [other,owner]) { await login(id); await db.query("select public.save_restaurant_setup('Restaurant','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)"); const created=await scalar('select public.complete_restaurant_setup()'); if(id===owner) org=created; else otherOrg=created; }
  brand=await scalar('select id from public.brands limit 1'); location=await scalar('select id from public.locations limit 1');
  kg=await scalar("select id from public.units_of_measure where code='KG'"); pcs=await scalar("select id from public.units_of_measure where code='PCS'");
  ingredient=await scalar("select public.save_catalogue_material($1,null,'RICE','Rice','RAW','',$2,true,true)",[org,kg]); await priceMaterial('RICE','900');
  recipe=await publishRecipe('RECIPE',ingredient); menuVersion=await publishMenu(); menu=await scalar('select menu_item_id from public.menu_item_versions where id=$1',[menuVersion]);
  await scalar("select public.save_menu_selling_price($1,$2,$3,$4,'DINE_IN',9999,'NONE',0,'2020-01-01',null,'Different listed price')",[org,menu,randomUUID(),location]);

  await t.test('staging retains original UTF-8 source, findings and dated menu bindings without recording sales',async()=>{
   const text='\uFEFF'+csv([row(),row({5:'002',7:'1',8:'1500',9:'150',11:'1350'})]); const request=randomUUID();
   batch=await stage(text,{request}); assert.equal(await stage(text,{request}),batch); await rejects(stage(text+'\n',{request}));
   const data=await detail(batch); assert.equal(data.state,'REVIEW'); assert.equal(data.report.ready,2); assert.equal(data.report.rows[0].prepared.menu_version_id,menuVersion);
   assert.equal(data.report.receipts[0].total,'4350'); assert.equal(data.source_hash,createHash('sha256').update(text).digest('hex'));
   assert.equal((await scalar('select public.sales_import_source($1,$2)',[org,batch])).csv,text);
   assert.equal(await scalar('select count(*)::int from public.sales_headers'),0); assert.equal('source_csv' in data,false);
   await rejects(db.query('select source_csv from public.sales_import_batches'),'42501');
  });
  await t.test('receipt controls gate atomic recording; totals use imported revenue and discounts, not menu list prices',async()=>{
   await rejects(post(batch,{})); const controls=Object.fromEntries((await detail(batch)).report.receipts.map(r=>[r.key,'1'])); await rejects(post(batch,controls));
   assert.equal(await scalar('select count(*)::int from public.sales_lines'),0); assert.equal((await post(batch)).new_lines,2); assert.equal((await post(batch)).already_posted,true);
   const result=await summary(); assert.equal(result.net_revenue,'4350.000000000000'); assert.equal(result.quantity,'3.000000');
   assert.equal(result.estimated_food_cost,'2700.000000000000'); assert.equal(result.estimated_food_margin,'1650.000000000000'); assert.equal(result.food_margin_percent,'37.931034');
   assert.equal(result.receipts,1); assert.equal(result.discounts,'150.000000');
   const history=await scalar("select public.operational_report($1,'SALES','2020-01-15','2020-01-15',null,null,'RECORDED','',1,true)",[org]);
   assert.equal(history.documents,1);assert.equal(Number(history.rows[0].amount),4350);assert.equal(Number(history.rows[0].discount),150);assert.equal(Number(history.rows[0].customer_total),4350);assert.equal(history.rows[0].params.batch,batch);
   assert.equal(await scalar('select count(*)::int from public.inventory_movements'),0);
   await rejects(db.query('delete from public.sales_lines'),'42501');
  });
  await t.test('executive overview reconciles trend, mix, outlets and source receipts without zero-filling missing days',async()=>{
   const result=await overview('2020-01-15','2020-01-16');
   assert.equal(result.summary.net_revenue,'4350.000000000000');assert.equal(result.summary.estimated_food_cost,'2700.000000000000');
   assert.equal(result.daily.length,2);assert.equal(result.daily[0].net_revenue,'4350.000000000000');assert.equal(result.daily[1].net_revenue,null);assert.equal(result.daily[1].lines,0);
   assert.equal(result.channels[0].share_percent,'100.000000');assert.equal(result.outlets[0].net_revenue,result.summary.net_revenue);
   assert.equal(result.recent_receipts[0].batch_id,batch);assert.equal(result.recent_receipts[0].reference,'TX001');
   assert.equal(result.comparison.net_revenue,null);assert.match(result.comparison.reason,/No sales/);assert.ok(result.refreshed_at);
   const prior=await overview('2020-01-16');assert.equal(prior.comparison.net_revenue,'4350.000000000000');assert.equal(prior.comparison.change_percent,null);
   assert.equal((await overview('2020-03-01')).summary.lines,0);
  });
  await t.test('reimports skip exact economic duplicates and reject changed or additional receipt lines',async()=>{
   const duplicate=await stage(csv([row({7:'2.0',8:'3000.00'})])); assert.equal((await detail(duplicate)).report.duplicates,1); assert.equal((await post(duplicate)).new_lines,0);
   for(const changes of [{8:'3100',11:'3100'},{5:'NEW'},{3:'2020-01-16'},{12:'TAKEAWAY'}]) {
    const id=await stage(csv([row(changes)])); assert.equal((await detail(id)).state,'INVALID'); await rejects(post(id));
   }
   const sameFile=await stage(csv([row({4:'NEW'}),row({4:'NEW'})])); assert.equal((await detail(sameFile)).report.rejected,1);
  });
  await t.test('invalid files, arithmetic, combo children, returns and missing identities never partially record',async()=>{
   const malformed=await stage('bad,headers\n1,2'); assert.match((await detail(malformed)).report.file_error,/template headers/);
   for(const changes of [{0:'OTHER'},{1:''},{2:'UNKNOWN'},{3:'2020-02-31'},{3:'2999-01-01'},{6:'UNKNOWN'},{7:'0'},{7:'-1'},{7:'1e3'},{7:'0.0000001'},{8:'=1+1'},{9:''},{10:''},{11:'0'},{12:'UNKNOWN'},{13:'COMBO_PARENT'},{13:'COMBO_CHILD',14:'PARENT',8:'0',11:'0'},{14:'PARENT'},{15:'REFUND'},{15:'VOID'}]) {
    const id=await stage(csv([row({4:'BAD',5:'A'}),row({4:'BAD',5:'B',...changes})])); assert.equal((await detail(id)).state,'INVALID',JSON.stringify(changes)); await rejects(post(id));
   }
   const tooMany=await stage(csv(Array.from({length:101},(_,i)=>row({5:String(i)})))); assert.match((await detail(tooMany)).report.file_error,/100 sales rows/);
   assert.equal(await scalar('select count(*)::int from public.sales_lines'),2);
   await rejects(stage(csv([row()]),{currency:'USD'}));
  });
  await t.test('all supported source tax formats normalise to equivalent net revenue and customer totals',async()=>{
   for(const [basis,gross,net] of [['EXCLUSIVE','1000','900'],['INCLUSIVE','1100','990'],['GROSS_INCLUSIVE','1100','900']]) {
    const id=await stage(csv([row({3:'2020-01-17',4:`TAX-${basis}`,7:'1',8:gross,9:basis==='EXCLUSIVE'?'100':'110',10:'90',11:net})]),{basis});
    const prepared=(await detail(id)).report.rows[0].prepared; assert.equal(prepared.net_revenue,'900'); assert.equal(prepared.customer_total,'990'); await post(id);
   }
   const result=await summary('2020-01-17'); assert.equal(result.net_revenue,'2700.000000000000'); assert.equal(result.tax,'270.000000'); assert.equal(result.customer_total,'2970.000000000000');
  });
  await t.test('explicit mappings and location-scoped source identities retain distinct receipts',async()=>{
   const mapped=await stage(csv([row({4:'MAPPED',2:'EXT-LOC',6:'EXT-MENU',12:'EAT-IN'})]),{maps:{menu_items:{'EXT-MENU':'MENU001'},locations:{'EXT-LOC':'PRIMARY'},channels:{'EAT-IN':'DINE_IN'}}});
   assert.equal((await detail(mapped)).report.ready,1); await post(mapped);
   await db.exec('reset role'); secondLocation=await scalar("insert into public.locations(organisation_id,brand_id,code,name,timezone) values($1,$2,'SECOND','Second outlet','Africa/Lagos') returning id",[org,brand]); await login(owner);
   const separate=await stage(csv([row({2:'SECOND'})])); assert.equal((await detail(separate)).report.ready,1); await post(separate);
   const one=await summary('2020-01-15','2020-01-15',secondLocation); assert.equal(one.receipts,1); assert.equal(one.net_revenue,'3000.000000000000'); const outletView=await overview('2020-01-15','2020-01-15',secondLocation);assert.equal(outletView.outlets.length,1);assert.equal(outletView.outlets[0].id,secondLocation);assert.equal(outletView.summary.net_revenue,one.net_revenue);
   await rejects(summary('2020-01-15','2020-01-15',randomUUID()),'42501');
  });
  await t.test('new menu versions trigger review before posting and never rewrite saved recipe bindings',async()=>{
   const id=await stage(csv([row({3:'2020-01-19',4:'LATER',7:'1',8:'1500',11:'1500'})]));
   await publishMenu({id:menu,quantity:'2'}); assert.equal((await post(id)).posted,false); assert.equal((await detail(id)).report.rows[0].prepared.menu_version,2); await post(id);
   assert.equal((await summary('2020-01-19')).estimated_food_cost,'1800.000000000000'); assert.equal((await summary('2020-01-19')).estimated_food_margin,'-300.000000000000');
   const original=await scalar("select menu_version_id from public.sales_lines l join public.sales_headers h on h.organisation_id=l.organisation_id and h.id=l.sale_id where h.transaction_ref='TX001' and h.location_id=$1 limit 1",[location]); assert.equal(original,menuVersion);
   const reimport=await stage(csv([row()])); assert.equal((await detail(reimport)).report.duplicates,1); await post(reimport);
  });
  await t.test('missing reference costs retain sales revenue, block full margins and can be corrected later',async()=>{
   const item=await scalar("select public.save_catalogue_material($1,null,'MISSING','Unpriced','RAW','',$2,true,true)",[org,kg]);
   await publishMenu({code:'MISSING-MENU',source:await publishRecipe('MISSING-RECIPE',item)});
   const id=await stage(csv([row({3:'2020-01-20',4:'UNCOSTED',6:'MISSING-MENU',7:'1',8:'1000',11:'1000'})])); await post(id);
   const result=await summary('2020-01-20'); assert.equal(result.net_revenue,'1000.000000000000'); assert.equal(result.missing_lines,1); assert.equal(result.estimated_food_margin,null); assert.equal(result.known_subtotal,null);assert.equal((await overview('2020-01-20')).summary.estimated_food_margin,null);
   await priceMaterial('MISSING','500'); assert.equal((await summary('2020-01-20')).estimated_food_margin,'500.000000000000');
   const free=await stage(csv([row({3:'2020-01-21',4:'FREE',7:'1',8:'1500',9:'1500',11:'0'})])); await post(free);
   const zero=await summary('2020-01-21'); assert.equal(zero.net_revenue,'0.000000000000'); assert.equal(zero.estimated_food_margin,'-1800.000000000000'); assert.equal(zero.food_margin_percent,null);const zeroOverview=await overview('2020-01-21');assert.equal(zeroOverview.daily[0].net_revenue,'0.000000000000');assert.equal(zeroOverview.channels[0].share_percent,null);assert.equal(zeroOverview.negative_menus[0].estimated_food_margin,'-1800.000000000000');
  });
  await t.test('historical inactive menus and outlets are retained, while empty and out-of-range summaries stay explicit',async()=>{
   await scalar('select public.set_menu_item_active($1,$2,false)',[org,menu]);
   await db.exec('reset role'); await db.query('update public.locations set is_active=false where id=$1',[location]); await login(owner);
   const id=await stage(csv([row({3:'2020-01-22',4:'HISTORICAL'})])); assert.equal((await detail(id)).report.rows[0].warnings.length,2); await post(id);
   assert.equal((await summary('2020-01-22')).priced_lines,1);
   const empty=await summary('2019-01-01'); assert.equal(empty.lines,0); assert.equal(empty.estimated_food_margin,null);
   await rejects(summary('2020-01-01','2020-12-31')); await rejects(summary('2999-01-01')); await rejects(summary('2020-02-01','2020-01-01'));
   const cancel=await stage('bad,header\n1,2'); await scalar('select public.cancel_sales_import($1,$2)',[org,cancel]); assert.equal((await detail(cancel)).state,'CANCELLED'); await rejects(post(cancel));
   const history=await scalar('select public.sales_import_history($1,1)',[org]); assert.ok(history.total>25); assert.equal(history.batches.length,25);
  });
  await t.test('large previews refuse incomplete totals and recorded currencies are never mixed',async()=>{
   await db.exec('reset role');
   await db.query(`insert into public.sales_headers(organisation_id,source_system,location_id,transaction_ref,sale_date,channel_code,currency_code,source_status,net_basis,receipt_total,import_batch_id,created_by)
    select $1,'SCALE',$2,'SCALE-'||g,'2020-01-31','DINE_IN','NGN','PAID','EXCLUSIVE',1500,$3,$4 from generate_series(1,1001) g`,[org,location,batch,owner]);
   await db.query(`insert into public.sales_lines(organisation_id,sale_id,line_ref,menu_item_id,menu_version_id,quantity,gross_sales,discount,tax,source_net_sales,net_revenue,customer_total,source_row,source_input,source_fingerprint,import_batch_id,created_by)
    select $1,id,'1',$2,$3,1,1500,0,0,1500,1500,1500,1,'{}','fixture',$4,$5 from public.sales_headers where organisation_id=$1 and source_system='SCALE'`,[org,menu,menuVersion,batch,owner]);
   await login(owner); await rejects(summary('2020-01-31')); await rejects(overview('2020-01-31')); assert.match((await overview('2020-02-01')).comparison.reason,/1,000/);
   await db.exec('reset role'); await db.query("update public.organisations set currency_code='USD' where id=$1",[org]); await login(owner); await rejects(summary()); await rejects(overview());
   await db.exec('reset role'); await db.query("update public.organisations set currency_code='NGN' where id=$1",[org]); await login(owner);
  });
  await t.test('sales revenue and source files are visible to admin, finance, CEO and business Operations; only admin can write',async()=>{
   await db.exec('reset role');
   for(const [id,role,scope] of [[finance,'finance',null],[ceo,'ceo',null],[procurement,'procurement',null],[operations,'operations',null],[scoped,'restaurant_admin',location]]) {
    const m=await scalar('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,id]);
    await db.query('insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,$3,$4)',[org,m,role,scope]);
   }
   await db.query('insert into private.platform_admins(user_id) values($1)',[founder]);
   for(const id of [finance,ceo,operations]) { await login(id); assert.equal((await detail(batch)).state,'POSTED'); assert.ok((await summary()).lines>0); assert.ok((await overview()).summary.lines>0); assert.equal((await scalar('select public.workspace_navigation_access($1)',[org])).overview,true); await rejects(stage(csv([row()])),'42501'); await rejects(post(batch),'42501'); }
   for(const id of [other,procurement,scoped,founder]) {
    await login(id); await rejects(detail(batch),'42501'); await rejects(summary(),'42501'); await rejects(overview(),'42501'); assert.equal((await scalar('select public.workspace_navigation_access($1)',[org])).overview,false); await rejects(stage(csv([row()])),'42501');
    await rejects(scalar('select public.sales_import_source($1,$2)',[org,batch]),'42501'); assert.equal(await scalar('select count(*)::int from public.sales_lines where organisation_id=$1',[org]),0);
   }
   await login(other); assert.equal((await scalar('select public.sales_import_history($1,1)',[otherOrg])).total,0);
   await db.exec('reset role; set role anon'); await rejects(detail(batch),'42501'); await rejects(overview(),'42501');
  });
 } finally { await db.close(); }
});
