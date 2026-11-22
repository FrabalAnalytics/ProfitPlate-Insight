import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile, readdir } from "node:fs/promises";
import { PGlite } from "./helpers/active-restaurant-db.mjs";
const headers = 'Organisation_Code,Source_System,Location_Code,Sale_Date,Transaction_Ref,Line_Ref,Menu_Name,Quantity,Gross_Sales,Discount,Tax,Net_Sales,Channel_Code,Line_Type,Parent_Line_Ref,Status';
const base = ['ORG001','POS_A','PRIMARY','2020-01-15','TX001','001','Snapper Rice Plate','2','3000','0','0','3000','DINE_IN','NORMAL','','PAID'];
const row = (changes = {}) => base.map((value, i) => changes[i] ?? value);
const csv = rows => headers + '\r\n' + rows.map(values => values.map(value => '"' + value.replaceAll('"','""') + '"').join(',')).join('\r\n');

test('name-first sales imports preserve menu identities, saved matches and stock controls', async t => {
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
 const publishMenu = ({id=null,code='MENU001',name='Snapper Rice Plate',source=recipe,quantity='1',day='2020-01-01'}={}) => scalar("select public.publish_menu_item_version($1,$2,$3,$4,$5,$6,'Mains',$7,$8,$9,'')",[org,id,randomUUID(),code,name,brand,source,quantity,day]);
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
  await opening(100);await scalar('select public.save_menu_stock_mapping($1,$2,$3,$4,$5,$6,$7)',[org,randomUUID(),menu,location,centre,'RECIPE','2020-01-01']);

  let firstBatch,secondOutlet;
  const review=id=>scalar('select public.get_sales_import($1,$2)',[org,id]);
  const choices=(loc='PRIMARY',search='',page=0)=>scalar('select public.sales_menu_choices($1,$2,$3,$4,$5)',[org,loc,'2020-01-25',search,page]);
  await t.test('clear names match across case and whitespace; confirmed receipts deduct stock once',async()=>{
   firstBatch=await stage(csv([row({6:'  snapper   rice plate  '})]));let r=await review(firstBatch);assert.equal(r.report.ready,1);assert.equal(r.report.rows[0].source.Menu_Name,'snapper   rice plate');assert.equal(r.report.rows[0].prepared.menu_match_basis,'Name matched');assert.equal(r.report.rows[0].prepared.stock_centre,'Kitchen');assert.equal(r.report.rows[0].prepared.recipe_name,'RECIPE');
   await post(firstBatch);assert.equal(Number(await balance()),98);const replay=await stage(csv([row({6:'SNAPPER RICE PLATE'})]));assert.equal((await review(replay)).report.duplicates,1);await post(replay);assert.equal(Number(await balance()),98);
  });
  await t.test('unmatched names require selection and are remembered only after posting',async()=>{
   const unknown=csv([row({4:'UNKNOWN',3:'2020-01-16',6:'POS Snapper Special'})]);let id=await stage(unknown);assert.equal((await review(id)).report.rejected,1);assert.match((await review(id)).report.rows[0].findings[0],/No matching menu name/);
   const options=await choices();assert.equal(options.options[0].name,'Snapper Rice Plate');assert.equal(options.options[0].centre,'Kitchen');
   id=await stage(unknown,{maps:{menu_rows:{'1':'MENU001'}}});assert.equal((await review(id)).report.rows[0].prepared.menu_match_basis,'Selected during review');
   assert.equal(Number(await read('select count(*) from private.sales_menu_name_matches where source_name_key=$1',['pos snapper special'])),0);await post(id);
   const next=await stage(csv([row({4:'REMEMBERED',3:'2020-01-17',6:'pos snapper special'})]));assert.equal((await review(next)).report.rows[0].prepared.menu_match_basis,'Saved POS match');await post(next);
  });
  await t.test('duplicate names are never guessed; later saved changes do not remap older receipts',async()=>{
   const v=await publishMenu({code:'SECOND',quantity:'2'});assert.ok(v);
   const ambiguous=await stage(csv([row({4:'AMBIGUOUS',3:'2020-01-10'})]));assert.equal((await review(ambiguous)).report.rejected,1);assert.match((await review(ambiguous)).report.rows[0].findings[0],/More than one/);
   const changed=await stage(csv([row({4:'NEW-MATCH',3:'2020-01-20',6:'POS Snapper Special'})]),{maps:{menu_rows:{'1':'SECOND'}}});await post(changed);
   const older=await stage(csv([row({4:'OLDER-MATCH',3:'2020-01-18',6:'POS Snapper Special'})]));assert.equal((await review(older)).report.rows[0].prepared.menu_code,'MENU001');
   const later=await stage(csv([row({4:'LATER-MATCH',3:'2020-01-21',6:'POS Snapper Special'})]));assert.equal((await review(later)).report.rows[0].prepared.menu_code,'SECOND');
   const duplicate=await stage(csv([row({6:'SNAPPER RICE PLATE'})]));assert.equal((await review(duplicate)).report.duplicates,1);assert.equal((await review(duplicate)).report.rows[0].prepared.menu_code,'MENU001');
   const before=await balance();await post(duplicate);assert.equal(await balance(),before);
  });
  await t.test('remembered matches are scoped to the POS source and outlet',async()=>{
   const differentSource=await stage(csv([row({1:'OTHER_POS',4:'NEW-SOURCE',3:'2020-01-21',6:'POS Snapper Special'})]));assert.equal((await review(differentSource)).report.rejected,1);
   await db.exec('reset role');secondOutlet=await scalar("insert into public.locations(organisation_id,brand_id,code,name,timezone) values($1,$2,'SECOND_LOC','Second outlet','Africa/Lagos') returning id",[org,brand]);await login(owner);
   const differentOutlet=await stage(csv([row({2:'SECOND_LOC',4:'NEW-OUTLET',3:'2020-01-21',6:'POS Snapper Special'})]));assert.equal((await review(differentOutlet)).report.rejected,1);
   const m=await publishMenu({code:'SCOPED',name:'Bar Special'});await db.exec('reset role');await db.query('update public.menu_items set location_id=$1 where id=(select menu_item_id from public.menu_item_versions where id=$2)',[secondOutlet,m]);await login(owner);
   const invalid=await stage(csv([row({4:'SCOPE',6:'Bar Special'})]),{maps:{menu_rows:{'1':'SCOPED'}}});assert.equal((await review(invalid)).report.rejected,1);assert.ok(!(await choices()).options.some(c=>c.code==='SCOPED'));assert.ok((await choices('SECOND_LOC')).options.some(c=>c.code==='SCOPED'));
  });
  await t.test('menu choice search is paginated and the training sample uses actual outlet/channel/menu data',async()=>{
   for(let i=0;i<27;i++)await publishMenu({code:`CHOICE${i}`,name:`Choice ${String(i).padStart(2,'0')}`});const first=await choices('PRIMARY','Choice'),second=await choices('PRIMARY','Choice',1);assert.equal(first.options.length,25);assert.equal(first.more,true);assert.equal(second.options.length,2);assert.equal(second.more,false);
   const sample=await scalar('select public.sales_training_sample($1)',[org]);assert.equal(sample.location,'PRIMARY');assert.ok(sample.menu_name);assert.notEqual(sample.channel,'STANDARD');assert.ok(sample.date);
  });
  await t.test('legacy Menu_Code files, receipt controls and contradictory matches remain protected',async()=>{
   const legacy=csv([row({4:'LEGACY',6:'MENU001'})]).replace('Menu_Name','Menu_Code');const id=await stage(legacy);assert.equal((await review(id)).report.ready,1);await rejects(post(id,{}));await post(id);
   const conflict=await stage(csv([row({4:'CONFLICT',5:'A'}),row({4:'CONFLICT',5:'B'})]),{maps:{menu_rows:{'1':'MENU001','2':'SECOND'}}});assert.equal((await review(conflict)).report.rejected,2);assert.match((await review(conflict)).report.rows[0].findings[0],/Choose one/);
  });
  await t.test('direct RPC callers cannot bypass row-match validation',async()=>{
   for(const menu_rows of [null,[],{'0':'MENU001'},{'101':'MENU001'},{'1':5},{'1':''}])await rejects(stage(csv([row({4:'BAD-MAP'})]),{maps:{menu_rows}}));
  });
  await t.test('other businesses, read-only users and anonymous callers cannot set or inspect mappings',async()=>{
   await login(other);await rejects(choices(),'42501');await rejects(scalar('select public.sales_training_sample($1)',[org]),'42501');await rejects(stage(csv([row({4:'FOREIGN'})])),'42501');
   await db.exec('reset role');const m=await scalar('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,finance]);await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,'finance')",[org,m]);await login(finance);await rejects(choices(),'42501');await rejects(scalar('select * from private.sales_menu_name_matches'),'42501');await db.exec('reset role;set role anon');await rejects(choices(),'42501');
  });
 }finally{await db.close();}
});
