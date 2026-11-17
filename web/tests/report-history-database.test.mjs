import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';

test('saved reports are canonical, immutable, retry-safe and restricted to current financial access',async t=>{
 const db=new PGlite();
 const [owner,other,finance,scoped,founder]=Array.from({length:5},()=>randomUUID());
 const value=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
 const deny=(sql,args=[],code='42501')=>assert.rejects(db.query(sql,args),e=>e.code===code);
 let org,otherOrg,location,foreignLocation,saved,snapshot;
 const save=(request=randomUUID(),title='Daily review',from='2020-04-15',to=from,loc=null)=>value('select public.save_management_report($1,$2,$3,$4,$5,$6)',[org,from,to,loc,request,title]);
 const get=id=>value('select public.get_management_report($1,$2)',[org,id]);
 try {
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);
   create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
   grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
  for(const id of [owner,other,finance,scoped,founder])await db.query('insert into auth.users values($1,now(),$2)',[id,`${id}@example.test`]);
  for(const name of(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
  for(const id of[owner,other]){await login(id);await value("select public.save_restaurant_setup('Report Business','QSR','NG','NGN','Brand','Main','Africa/Lagos','',3)");const result=await value('select public.complete_restaurant_setup()');if(id===owner)org=result;else otherOrg=result;}
  await db.exec('reset role');location=await value('select id from public.locations where organisation_id=$1',[org]);foreignLocation=await value('select id from public.locations where organisation_id=$1',[otherOrg]);
  for(const [id,loc]of[[finance,null],[scoped,location]]){const member=await value('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,id]);await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,'finance',$3)",[org,member,loc]);}
  await db.query('insert into private.platform_admins(user_id) values($1)',[founder]);await login(owner);
  await t.test('saving builds sources in the database and retries preserve one copy and audit',async()=>{
   await value("select public.review_expense_coverage($1,'2020-04-15','2020-04-15',null,'LABOUR',true)",[org]);
   const request=randomUUID();saved=await save(request);snapshot=await get(saved);
   assert.equal(snapshot.payload.context.organisation,'Report Business');assert.equal(snapshot.payload.context.locationId,'');assert.equal(snapshot.payload.overview.summary.lines,0);
   assert.equal(snapshot.payload.costs.labour_coverage.valid,true);assert.equal(snapshot.payload.costs.estimated_prime_cost,null);
   assert.equal(await save(request),saved);await deny('select public.save_management_report($1,$2,$2,null,$3,$4)',[org,'2020-04-15',request,'Changed name'],'22023');
   assert.equal(await value("select count(*)::int from public.audit_events where organisation_id=$1 and event_type='MANAGEMENT_REPORT_SAVED'",[org]),1);
  });
  await t.test('subsequent source and business changes never alter saved payloads',async()=>{
   await db.exec('reset role');await db.query("update public.organisations set name='Renamed business',currency_code='USD' where id=$1",[org]);await login(owner);
   await value("select public.review_expense_coverage($1,'2020-04-15','2020-04-15',null,'OPERATING',true)",[org]);
   assert.deepEqual(await get(saved),snapshot);const next=await get(await save());assert.equal(next.payload.context.organisation,'Renamed business');assert.equal(next.payload.context.currency,'USD');assert.equal(next.payload.costs.operating_coverage.valid,true);assert.equal(snapshot.payload.costs.operating_coverage.valid,false);
  });
  await t.test('validation rejects foreign scope, invalid ranges and names with no write',async()=>{
   for(const [from,to,loc]of[['2020-04-16','2020-04-15',null],['2020-01-01','2020-12-31',null],['2999-01-01','2999-01-01',null]])await deny('select public.save_management_report($1,$2,$3,$4,$5,$6)',[org,from,to,loc,randomUUID(),'Invalid'],'22023');
   await deny('select public.save_management_report($1,$2,$2,$3,$4,$5)',[org,'2020-04-15',foreignLocation,randomUUID(),'Foreign']);
   for(const title of['','   ','x'.repeat(121)])await deny('select public.save_management_report($1,$2,$2,null,$3,$4)',[org,'2020-04-15',randomUUID(),title],'22023');
   await deny('select * from public.management_report_snapshots');await deny("insert into public.management_report_snapshots(title) values('forged')");
   await deny("update public.management_report_snapshots set title='forged' where id=$1",[saved]);await deny('delete from public.management_report_snapshots where id=$1',[saved]);
   await db.exec('reset role');await deny("update public.management_report_snapshots set title='forged' where id=$1",[saved]);await login(owner);
  });
  await t.test('cross-tenant, founder, scoped, anonymous and revoked users cannot read or save',async()=>{
   for(const id of[other,scoped,founder]){await login(id);await deny('select public.get_management_report($1,$2)',[org,saved]);await deny('select public.list_management_reports($1,1)',[org]);await deny('select public.save_management_report($1,$2,$2,null,$3,$4)',[org,'2020-04-15',randomUUID(),'Denied']);}
   await login(finance);assert.equal((await get(saved)).id,saved);const own=await save();assert.ok(own);
   await deny('select public.get_management_report($1,$2)',[otherOrg,saved]);
   await db.exec('reset role');await db.query("update public.organisation_memberships set status='inactive' where organisation_id=$1 and user_id=$2",[org,finance]);await login(finance);await deny('select public.get_management_report($1,$2)',[org,saved]);
   await db.exec('reset role;set role anon');await deny('select public.list_management_reports($1,1)',[org]);await login(owner);
  });
  await t.test('history is paginated, metadata-only and stable with saved labels',async()=>{
   for(let i=0;i<19;i++)await save(randomUUID(),`Report ${i}`,'2020-04-15','2020-04-15',location);
   const first=await value('select public.list_management_reports($1,1)',[org]),second=await value('select public.list_management_reports($1,2)',[org]);
   assert.equal(first.total,22);assert.equal(first.reports.length,20);assert.equal(second.reports.length,2);
   assert.equal(new Set([...first.reports,...second.reports].map(r=>r.id)).size,22);assert.equal('payload'in first.reports[0],false);
   assert.equal(second.reports.find(r=>r.id===saved).currency,'NGN');
   await deny('select public.list_management_reports($1,0)',[org],'22023');
  });
 } finally {await db.close();}
});
