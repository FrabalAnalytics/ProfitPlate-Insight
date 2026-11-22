import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {randomUUID,createHash} from 'node:crypto';
import {PGlite} from './helpers/active-restaurant-db.mjs';
const headers=['Organisation_Code','Source_System','Expense_Ref','Line_Ref','Category_Code','Scope','Location_Code','Expense_From','Expense_To','Recognition_Method','Payment_Date','Amount','Currency','Description'];
const base={Organisation_Code:'ORG001',Source_System:'TEST_EXP',Expense_Ref:'WAGES-1',Line_Ref:'1',Category_Code:'WAGES',Scope:'LOCATION',Location_Code:'PRIMARY',Expense_From:'2020-04-15',Expense_To:'2020-04-15',Recognition_Method:'ON_DATE',Payment_Date:'2020-04-15',Amount:'600',Currency:'NGN',Description:'Fictional labour'};
const csv=rows=>headers.join(',')+'\r\n'+rows.map(row=>headers.map(key=>'"'+String({...base,...row}[key]).replaceAll('"','""')+'"').join(',')).join('\r\n');
test('expense sources, management allocation, reviewed coverage and estimated prime cost remain exact and private',async t=>{
 const db=new PGlite(),ids=Array.from({length:7},(_,i)=>`80000000-0000-0000-0000-${String(i+1).padStart(12,'0')}`),[owner,other,finance,ceo,procurement,scoped,founder]=ids;
 const scalar=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
 const deny=(sql,args=[],code='22023')=>assert.rejects(db.query(sql,args),e=>e.code===code);
 let org,otherOrg,location,batch,source,foodItem,menuVersion,legacySeedOrg;
 const stage=(text,request=randomUUID())=>scalar("select public.stage_expense_import($1,$2,'expenses.csv',$3,'ORG001')",[org,request,text]);
 const detail=id=>scalar('select public.get_expense_import($1,$2)',[org,id]);
 const post=(id,total)=>scalar('select public.post_expense_import($1,$2,$3)',[org,id,total]);
 const report=(from='2020-04-15',to=from,loc=null,page=1)=>scalar('select public.expense_period_report($1,$2,$3,$4,$5)',[org,from,to,loc,page]);
 const review=(kind='LABOUR',from='2020-04-15',to=from,loc=null)=>scalar('select public.review_expense_coverage($1,$2,$3,$4,$5,true)',[org,from,to,loc,kind]);
 try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
 for(const [i,id]of ids.entries())await db.query('insert into auth.users values($1,now(),$2)',[id,`expenses${i}@example.test`]);
 for(const name of(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort()){if(name.startsWith('202611150013'))legacySeedOrg=await scalar("insert into public.organisations(name,owner_id) values('Pre-expense legacy organisation',$1) returning id",[owner]);await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));}
 for(const id of[other,owner]){await login(id);await scalar("select public.save_restaurant_setup('Expense Test','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");const result=await scalar('select public.complete_restaurant_setup()');if(id===owner)org=result;else otherOrg=result;}
 location=await scalar('select id from public.locations where organisation_id=$1',[org]);
 await t.test('default categories seed existing/new organisations and classification is explicit',async()=>{
  await db.exec('reset role');assert.equal(await scalar('select count(*)::int from public.management_expense_categories where organisation_id=$1',[legacySeedOrg]),9);await login(owner);
  const cats=await scalar('select public.list_expense_categories($1)',[org]);assert.equal(cats.length,9);assert.equal(cats.find(c=>c.code==='WAGES').kind,'LABOUR');
  await scalar("select public.create_expense_category($1,'INSURANCE','Insurance','OPERATING')",[org]);await deny("select public.create_expense_category($1,'INSURANCE','Other','LABOUR')",[org]);
  await deny("select public.create_expense_category($1,'OTHER','Other','FOOD')",[org]);await deny('select * from public.expense_entries',[],'42501');
 });
 await t.test('staging retains raw UTF-8, is retry-safe, and requires an independent source total',async()=>{
  source='\uFEFF'+csv([{}, {Expense_Ref:'RENT-1',Category_Code:'RENT',Scope:'CENTRAL',Location_Code:'',Expense_From:'2020-04-01',Expense_To:'2020-04-30',Recognition_Method:'DAILY',Payment_Date:'2020-04-01',Amount:'3000',Description:'Fictional monthly rent'}]);
  const request=randomUUID();batch=await stage(source,request);assert.equal(await stage(source,request),batch);await deny("select public.stage_expense_import($1,$2,'changed.csv',$3,'ORG001')",[org,request,source]);
  const data=await detail(batch);assert.equal(data.report.ready,2);assert.equal(data.source_hash,createHash('sha256').update(source).digest('hex'));assert.equal(data.report.source_total,'3600.000000');assert.equal('source_csv'in data,false);
  assert.equal((await scalar('select public.expense_import_source($1,$2)',[org,batch])).csv,source);await deny('select source_csv from public.expense_import_batches',[],'42501');
  await deny('select public.post_expense_import($1,$2,$3)',[org,batch,'1']);assert.equal((await report()).active_entries,0);assert.equal((await post(batch,'3600')).new_lines,2);assert.equal((await post(batch,'3600')).already_posted,true);
 });
 await t.test('coverage dates drive exact period amounts; payment dates never drive expense totals',async()=>{
  const day=await report();assert.equal(day.labour_amount,'600.000000');assert.equal(day.operating_amount,'100.000000');assert.equal(day.central_amount,'100.000000');assert.equal(day.labour_coverage.valid,false);assert.equal(day.estimated_prime_cost,null);
  assert.equal((await report('2020-04-01')).operating_amount,'100.000000');assert.equal((await report('2020-04-01','2020-04-30')).operating_amount,'3000.000000');
  const outlet=await report('2020-04-15','2020-04-15',location);assert.equal(outlet.operating_amount,'0');assert.equal(outlet.excluded_central_entries,1);assert.equal(outlet.labour_amount,'600.000000');
 });
 await t.test('duplicate identity normalises numbers, changed records block the whole attempt, voids cannot be resurrected by reimports',async()=>{
  const duplicate=await stage(csv([{Amount:'600.0'}]));assert.equal((await detail(duplicate)).report.duplicates,1);assert.equal((await post(duplicate,'600')).new_lines,0);
  const conflict=await stage(csv([{Amount:'601'},{Expense_Ref:'VALID-BUT-BLOCKED'}]));assert.equal((await detail(conflict)).state,'INVALID');await deny('select public.post_expense_import($1,$2,$3)',[org,conflict,'1201']);assert.equal((await report()).active_entries,2);
 });
 await t.test('a stale expense review must be reviewed again before an unchanged retry records or skips rows',async()=>{
  const text=csv([{Expense_Ref:'STALE-REVIEW',Expense_From:'2020-04-25',Expense_To:'2020-04-25'}]);const first=await stage(text),second=await stage(text);await post(second,'600');
  assert.equal((await post(first,'600')).posted,false);assert.equal((await detail(first)).report.duplicates,1);assert.equal((await post(first,'600')).new_lines,0);
 });
 await t.test('invalid dates, categories, scopes, currencies, methods and amounts never partially post',async()=>{
  for(const change of[{Scope:'CENTRAL'}, {Scope:'LOCATION',Location_Code:''},{Category_Code:'MISSING'},{Currency:'USD'},{Amount:'0'},{Amount:'-2'},{Amount:'=1+1'},{Amount:'1e3'},{Expense_From:'2020-02-31'},{Expense_To:'2020-04-01'},{Expense_To:'2020-04-16'}, {Recognition_Method:''},{Payment_Date:'2999-01-01'},{Description:''},{Organisation_Code:'OTHER'}]) {
   const id=await stage(csv([{Expense_Ref:'INVALID',...change}]));assert.equal((await detail(id)).state,'INVALID',JSON.stringify(change));
  }
  const broken=await stage('bad,headers\n1,2');assert.match((await detail(broken)).report.file_error,/template headers/);
  const tooMany=await stage(csv(Array.from({length:101},(_,i)=>({Expense_Ref:`TOO-${i}`}))));assert.match((await detail(tooMany)).report.file_error,/100 expense rows/);
 });
 await t.test('explicit coverage supports known zero, is scope/range-specific and becomes stale on relevant source changes',async()=>{
  await review();assert.equal((await report()).labour_coverage.valid,true);assert.equal((await report('2020-04-15','2020-04-15',location)).labour_coverage.valid,false);assert.equal((await report('2020-04-14','2020-04-15')).labour_coverage.valid,false);
  await review('OPERATING');const additional=await stage(csv([{Expense_Ref:'MARKETING',Category_Code:'MARKETING',Amount:'30'}]));await post(additional,'30');const changed=await report();assert.equal(changed.labour_coverage.valid,true);assert.equal(changed.operating_coverage.valid,false);
  await review('LABOUR','2020-03-01');assert.equal((await report('2020-03-01')).labour_amount,'0');assert.equal((await report('2020-03-01')).labour_coverage.valid,true);
  const newLabour=await stage(csv([{Expense_Ref:'EXTRA-LABOUR',Amount:'50'}]));await post(newLabour,'50');assert.equal((await report()).labour_coverage.valid,false);
  const entry=(await report()).entries.find(e=>e.expense_ref==='EXTRA-LABOUR');await scalar('select public.void_expense_entry($1,$2,$3)',[org,entry.id,'Entered in error']);
  const reimport=await stage(csv([{Expense_Ref:'EXTRA-LABOUR',Amount:'50'}]));assert.equal((await detail(reimport)).report.rows[0].prepared.previously_voided,true);await post(reimport,'50');assert.equal((await report()).labour_amount,'600.000000');
 });
 await t.test('cumulative daily rounding reconciles adjacent slices to the source amount',async()=>{
  const id=await stage(csv([{Expense_Ref:'TINY',Category_Code:'UTILITIES',Amount:'0.01',Expense_From:'2020-02-01',Expense_To:'2020-02-03',Recognition_Method:'DAILY',Payment_Date:''}]));await post(id,'0.01');
  const a=await report('2020-02-01'),b=await report('2020-02-02'),c=await report('2020-02-03');assert.equal(a.operating_amount,'0.003333');assert.equal(b.operating_amount,'0.003334');assert.equal(c.operating_amount,'0.003333');assert.equal((await report('2020-02-01','2020-02-03')).operating_amount,'0.010000');
 });
 await t.test('estimated prime cost combines the existing food estimate with reviewed labour exactly once',async()=>{
  const kg=await scalar("select id from public.units_of_measure where organisation_id=$1 and code='KG'",[org]),pcs=await scalar("select id from public.units_of_measure where organisation_id=$1 and code='PCS'",[org]);
  foodItem=await scalar("select public.save_catalogue_material($1,null,'EXP-FOOD','Food','RAW','',$2,true,true)",[org,kg]);
  const recipe=await scalar("select public.publish_recipe_version($1,null,$2,'EXP-RECIPE','Recipe','FINAL','2020-01-01',1,$3,'',$4::jsonb)",[org,randomUUID(),pcs,JSON.stringify([{kind:'ITEM',target_id:foodItem,quantity:'1',uom_id:kg}])]);
  const brand=await scalar('select brand_id from public.locations where id=$1',[location]);menuVersion=await scalar("select public.publish_menu_item_version($1,null,$2,'EXP-MENU','Menu',$3,'',$4,1,'2020-01-01','')",[org,randomUUID(),brand,recipe]);
  const salesCsv='Organisation_Code,Source_System,Location_Code,Sale_Date,Transaction_Ref,Line_Ref,Menu_Code,Quantity,Gross_Sales,Discount,Tax,Net_Sales,Channel_Code,Line_Type,Parent_Line_Ref,Status\nORG001,EXP_POS,PRIMARY,2020-04-15,SALE1,1,EXP-MENU,3,4500,150,0,4350,DINE_IN,NORMAL,,PAID';
  const salesBatch=await scalar("select public.stage_sales_import($1,$2,'sales.csv',$3,'ORG001','EXCLUSIVE','NGN','{}'::jsonb)",[org,randomUUID(),salesCsv]);const receipt=(await scalar('select public.get_sales_import($1,$2)',[org,salesBatch])).report.receipts[0];await scalar('select public.post_sales_import($1,$2,$3::jsonb)',[org,salesBatch,JSON.stringify({[receipt.key]:'4350'})]);
  await review();assert.equal((await report()).estimated_prime_cost,null); // food is still unpriced
  const rows=JSON.stringify([{material_code:'EXP-FOOD',quantity:'1',unit_code:'KG',total_price:'900',price_date:'2020-01-01',source_note:'Fictional reference cost'}]);const preview=await scalar('select public.preview_material_reference_prices($1,$2::jsonb)',[org,rows]);await scalar("select public.save_material_reference_prices($1,$2,'MANUAL',$3::jsonb,$4::jsonb)",[org,randomUUID(),rows,JSON.stringify(preview)]);
  const result=await report();assert.equal(result.estimated_prime_cost,'3300.000000000000');assert.equal(result.prime_cost_percent,'75.862069');assert.equal(result.sales.estimated_food_cost,'2700.000000000000');assert.equal(result.labour_cost_percent,'13.793103');assert.equal(result.operating_coverage.valid,false);
 });
 await t.test('cross-tenant, scoped and nonfinancial accounts cannot read payroll data; Finance can record while CEO-only remains read-only',async()=>{
  await db.exec('reset role');for(const[id,role,scope]of[[finance,'finance',null],[ceo,'ceo',null],[procurement,'procurement',null],[scoped,'restaurant_admin',location]]){const m=await scalar('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,id]);await db.query('insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,$3,$4)',[org,m,role,scope]);}await db.query('insert into private.platform_admins(user_id) values($1)',[founder]);
  for(const id of[ceo]){await login(id);assert.equal((await report()).estimated_prime_cost,'3300.000000000000');await deny('select public.stage_expense_import($1,$2,$3,$4,$5)',[org,randomUUID(),'x.csv',csv([{}]),'ORG001'],'42501');await deny('select public.review_expense_coverage($1,$2,$3,null,$4,true)',[org,'2020-04-15','2020-04-15','LABOUR'],'42501');}
  await login(finance);assert.equal((await scalar('select public.expense_access($1)',[org])).write,true);await stage(csv([{}]));await review();
  for(const id of[other,procurement,scoped,founder]){await login(id);await deny('select public.expense_period_report($1,$2,$3,null,1)',[org,'2020-04-15','2020-04-15'],'42501');await deny('select public.expense_import_source($1,$2)',[org,batch],'42501');}
  await login(owner);await deny('select public.expense_period_report($1,$2,$3,$4,1)',[org,'2020-04-15','2020-04-15',randomUUID()],'42501');await deny("update public.expense_entries set amount=1 where organisation_id=$1",[org],'42501');await deny('delete from public.expense_entries',[],'42501');
 });
 await t.test('coverage detects new outlet scopes, report limits and currency mismatch remain explicit',async()=>{
  await login(owner);await review();await db.exec('reset role');await db.query("insert into public.locations(organisation_id,brand_id,code,name,timezone) select organisation_id,brand_id,'EXTRA','Extra','Africa/Lagos' from public.locations where id=$1",[location]);await login(owner);assert.equal((await report()).labour_coverage.valid,false);
  await deny('select public.expense_period_report($1,$2,$3,null,1)',[org,'2020-01-01','2020-12-31']);await db.exec('reset role');await db.query("update public.organisations set currency_code='USD' where id=$1",[org]);await login(owner);await deny('select public.expense_period_report($1,$2,$3,null,1)',[org,'2020-04-15','2020-04-15']);await db.exec('reset role');await db.query("update public.organisations set currency_code='NGN' where id=$1",[org]);await login(owner);
  const events=await scalar('select jsonb_agg(to_jsonb(a)) from public.audit_events a where organisation_id=$1',[org]);assert.ok(events.some(e=>e.event_type==='EXPENSE_VOIDED'));assert.ok(events.some(e=>e.event_type==='EXPENSE_COVERAGE_REVIEWED'));
  await db.exec('reset role;set role anon');await deny('select public.expense_access($1)',[org],'42501');
 });
 await t.test('legacy expense records remain preserved, excluded and restricted until explicitly reconciled',async()=>{
  await login(owner);await review();await db.exec('reset role');const category=await scalar("insert into public.expense_categories(organisation_id,name) values($1,'Legacy unclassified') returning id",[org]);
  const original=await scalar("insert into public.expenses(organisation_id,category_id,description,amount,expense_date) values($1,$2,'Historic source',75,'2020-04-15') returning id",[org,category]);
  await login(owner);const result=await report();assert.equal(result.legacy_entries,1);assert.equal(result.labour_amount,'600.000000');assert.equal(result.labour_coverage.valid,false);assert.equal(result.estimated_prime_cost,null);assert.equal(await scalar('select amount::text from public.expenses where id=$1',[original]),'75.00');
  await deny("update public.expenses set amount=1 where id=$1",[original],'42501');await login(procurement);assert.equal(await scalar('select count(*)::int from public.expenses where organisation_id=$1',[org]),0);
 });
 await t.test('large expense windows refuse partial totals while pagination preserves full totals',async()=>{
  await login(owner);assert.equal((await report('2020-04-15','2020-04-15',null,2)).labour_amount,'600.000000');await db.exec('reset role');
  await db.query(`insert into public.expense_entries(organisation_id,import_batch_id,source_system,expense_ref,line_ref,source_row,category_id,location_id,expense_from,expense_to,recognition_method,amount,currency_code,description,fingerprint,created_by)
   select $1,$2,'CAP','CAP-'||g,'1',1,category_id,location_id,'2020-01-31','2020-01-31','ON_DATE',1,'NGN','Scale fixture','fixture-'||g,$3
   from generate_series(1,2001) g cross join lateral(select category_id,location_id from public.expense_entries where organisation_id=$1 limit 1) e`,[org,batch,owner]);
  await login(owner);await deny('select public.expense_period_report($1,$2,$3,null,1)',[org,'2020-01-31','2020-01-31']);
 });
 }finally{await db.close();}
});
