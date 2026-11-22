import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';

test('Founder approval gates every registration API and preserves existing restaurants',async t=>{
 const db=new PGlite(),founder=randomUUID(),legacy=randomUUID(),outsider=randomUUID(),users=Array.from({length:5},()=>randomUUID());
 const val=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
 const deny=work=>assert.rejects(work,e=>e.code==='42501');
 const save=async(name)=>{await val("select public.save_restaurant_setup($1,'QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)",[name]);await val("select public.save_setup_calendar(1,1,'23:30')");await val('select public.save_setup_sales_channels($1)',[[{code:'STANDARD',name:'Standard selling price',is_active:true}]]);await val('select public.save_setup_menu_categories($1)',[[{major:'FOOD',name:'Mains',is_active:true}]]);await val('select public.save_setup_expense_categories($1)',[[{code:'LOGISTICS',name:'Logistics',kind:'OPERATING',is_active:true}]]);};
 let old,pending;
 try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
 for(const id of[founder,legacy,outsider,...users])await db.query('insert into auth.users values($1,now(),$2)',[id,`${id}@example.test`]);
 const migrations=(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort();
 for(const name of migrations.filter(n=>n<'202611220056'))await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
 await db.query('insert into private.platform_admins(user_id) values($1)',[founder]);
 await login(legacy);await save('Existing approved restaurant');old=await val('select public.complete_restaurant_setup_with_expenses()');
 await db.exec('reset role');for(const name of migrations.filter(n=>n>='202611220056'))await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
 await t.test('existing restaurant and memberships remain active without reapproval',async()=>{
  await login(legacy);assert.equal((await val('select public.account_restaurant_access()'))[0].state,'ACTIVE');assert.equal((await val('select public.workspace_navigation_access($1)',[old])).team,true);assert.equal(await val('select public.complete_restaurant_setup_with_expenses()'),old);assert.equal((await val('select public.account_restaurant_access()'))[0].state,'ACTIVE');
 });
 await t.test('all five completion endpoints return a pending restaurant, preserve settings and retry safely',async()=>{
  const names=['complete_restaurant_setup','complete_restaurant_setup_with_calendar','complete_restaurant_setup_with_channels','complete_restaurant_setup_with_categories','complete_restaurant_setup_with_expenses'];
  for(let i=0;i<names.length;i++){
   await login(users[i]);await save(`Applicant ${i}`);const org=await val(`select public.${names[i]}()`);if(!i)pending=org;
   assert.equal((await val('select public.account_restaurant_access()'))[0].state,'PENDING');assert.equal(await val(`select public.${names[i]}()`),org);
   assert.equal(Number(await val('select count(*) from public.organisations')),0);assert.equal((await val('select public.workspace_navigation_access($1)',[org])).team,false);
   await deny(val("select public.save_catalogue_supplier($1,null,'NO','Not approved','','','',true)",[org]));
   await deny(val('select public.expense_category_setup($1)',[org]));
   await deny(val("select public.set_restaurant_access($1,'PENDING','ACTIVE','Self approval',true)",[org]));
  }
  await db.exec('reset role');assert.equal(Number(await val('select count(*) from private.restaurant_registration_runs')),0);assert.equal(Number(await val("select count(*) from public.organisations where access_state='PENDING'")),5);
 });
 await t.test('pending users cannot bypass state or private guards and Founder can inspect only platform metadata',async()=>{
  await login(users[0]);await deny(val('select private.pp_registration_begin()'));await deny(val('select private.pp_registration_finish($1)',[pending]));
  await db.exec('reset role');await deny(db.query("update public.organisations set access_state='ACTIVE' where id=$1",[pending]));
  await login(founder);const p=await val("select public.platform_workspace('','PENDING',1,$1)",[pending]);assert.equal(p.summary.pending,5);assert.equal(p.total,5);assert.equal(p.selected.access_state,'PENDING');assert.equal(p.selected.setup,null);assert.equal(Number(await val('select count(*) from public.organisations')),0);
  await login(outsider);await deny(val("select public.platform_workspace('','PENDING',1,null)"));
 });
 await t.test('Founder activation restores owner permissions, keeps settings and records a single audited decision',async()=>{
  await login(founder);await val("select public.set_restaurant_access($1,'PENDING','ACTIVE','Approved pilot restaurant',true)",[pending]);
  await assert.rejects(val("select public.set_restaurant_access($1,'PENDING','ACTIVE','Duplicate approval',true)",[pending]),e=>e.code==='40001');
  await login(users[0]);assert.equal((await val('select public.account_restaurant_access()'))[0].state,'ACTIVE');assert.equal((await val('select public.workspace_navigation_access($1)',[pending])).team,true);
  const supplier=await val("select public.save_catalogue_supplier($1,null,'SUP','Approved supplier','','','',true)",[pending]);assert.ok(supplier);
  await login(users[4]);const last=(await val('select public.account_restaurant_access()'))[0].id;await login(founder);await val("select public.set_restaurant_access($1,'PENDING','ACTIVE','Approved complete setup',true)",[last]);await login(users[4]);const cats=await val('select public.expense_category_setup($1)',[last]);assert.ok(cats.categories.some(c=>c.code==='LOGISTICS'&&c.is_active));
  await db.exec('reset role');assert.equal(Number(await val('select count(*) from private.restaurant_access_events where organisation_id=$1',[pending])),1);
 });
 await t.test('suspension also works with responsible centre owners and reactivation retains records',async()=>{
  await login(users[0]);const m=await val('select id from public.organisation_memberships where organisation_id=$1',[pending]);await val('select public.save_stock_centre($1,$2)',[pending,{code:'MAIN',name:'Main Store',kind:'STORE',responsible:m,processing_enabled:false}]);
  await login(founder);await val("select public.set_restaurant_access($1,'ACTIVE','INACTIVE','Pilot temporarily paused',true)",[pending]);
  await login(users[0]);assert.equal(Number(await val('select count(*) from public.organisations')),0);await deny(val("select public.save_catalogue_supplier($1,null,'NO','Blocked','','','',true)",[pending]));
  await login(founder);await val("select public.set_restaurant_access($1,'INACTIVE','ACTIVE','Pilot resumed',true)",[pending]);await login(users[0]);assert.equal(Number(await val('select count(*) from public.suppliers where organisation_id=$1',[pending])),1);
 });
 await t.test('declining a Pending application retains its data and permits a later Founder reactivation',async()=>{
  await login(users[1]);const org=(await val('select public.account_restaurant_access()'))[0].id;await login(founder);await val("select public.set_restaurant_access($1,'PENDING','INACTIVE','Application not approved',true)",[org]);await login(users[1]);assert.equal((await val('select public.account_restaurant_access()'))[0].state,'INACTIVE');await deny(val('select public.expense_category_setup($1)',[org]));await login(founder);await val("select public.set_restaurant_access($1,'INACTIVE','ACTIVE','Approved after follow-up',true)",[org]);await login(users[1]);assert.equal((await val('select public.workspace_navigation_access($1)',[org])).team,true);
 });
 await t.test('anonymous access and ordinary state changes stay denied',async()=>{
  await db.exec('reset role;set role anon');await deny(val("select public.set_restaurant_access($1,'ACTIVE','INACTIVE','No access',true)",[pending]));
 });
 }finally{await db.close();}
});
