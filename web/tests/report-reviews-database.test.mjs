import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';

test('management review decisions enforce roles, revisions, immutable source reports and an append-only audit',async t=>{
 const db=new PGlite();
 const [owner,other,finance,ceo,admin,scoped,founder]=Array.from({length:7},()=>randomUUID());
 const value=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
 const deny=(sql,args=[],code='42501')=>assert.rejects(db.query(sql,args),e=>e.code===code);
 let org,otherOrg,report,snapshot,event,submitRequest;
 const read=(page=1)=>value('select public.get_management_report_review($1,$2,$3)',[org,report,page]);
 const act=(action,revision,note='',ack=false,request=randomUUID())=>value('select public.review_management_report($1,$2,$3,$4,$5,$6,$7)',[org,report,request,revision,action,note,ack]);
 const rejected=(action,revision,note='',ack=false,code='22023')=>deny('select public.review_management_report($1,$2,$3,$4,$5,$6,$7)',[org,report,randomUUID(),revision,action,note,ack],code);
 try {
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);
   create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
   grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
  for(const id of[owner,other,finance,ceo,admin,scoped,founder])await db.query('insert into auth.users values($1,now(),$2)',[id,`${id}@example.test`]);
  for(const name of(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
  for(const id of[owner,other]){await login(id);await value("select public.save_restaurant_setup('Review Business','QSR','NG','NGN','Brand','Main','Africa/Lagos','',3)");const result=await value('select public.complete_restaurant_setup()');if(id===owner)org=result;else otherOrg=result;}
  await db.exec('reset role');const location=await value('select id from public.locations where organisation_id=$1',[org]);
  for(const [id,role,scope]of[[finance,'finance',null],[ceo,'ceo',null],[admin,'restaurant_admin',null],[scoped,'ceo',location]]){const member=await value('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,id]);await db.query('insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,$3,$4)',[org,member,role,scope]);}
  await db.query('insert into private.platform_admins(user_id) values($1)',[founder]);await login(owner);
  report=await value("select public.save_management_report($1,'2020-04-15','2020-04-15',null,$2,'Review copy')",[org,randomUUID()]);snapshot=await value('select public.get_management_report($1,$2)',[org,report]);
  await t.test('new reports are unsubmitted and financial readers can comment before submission',async()=>{
   await login(finance);assert.deepEqual(await read(),{status:'SAVED',revision:0,can_approve:false,decision:null,events:[]});
   event=await act('COMMENT',0,'Please review the coverage warnings.');const result=await read();assert.equal(result.status,'SAVED');assert.equal(result.revision,1);assert.equal(result.decision,null);assert.equal(result.events[0].actor,`${finance}@example.test`);
   await rejected('APPROVE',1,'',true,'42501');await rejected('REQUEST_CHANGES',1,'Needs work',false,'42501');await rejected('WITHDRAW_APPROVAL',1,'Needs work',false,'42501');
  });
  await t.test('finance submits, repeat requests do not duplicate events, and changed retries fail',async()=>{
   submitRequest=randomUUID();event=await act('SUBMIT',1,'Ready for management review.',false,submitRequest);assert.equal(await act('SUBMIT',1,'Ready for management review.',false,submitRequest),event);
   assert.equal((await read()).status,'IN_REVIEW');await deny('select public.review_management_report($1,$2,$3,1,$4,$5,false)',[org,report,submitRequest,'SUBMIT','Changed retry'],'22023');
   await rejected('SUBMIT',2);await rejected('COMMENT',1,'Stale comment');await rejected('COMMENT',2,'');await rejected('COMMENT',2,'x'.repeat(2001));await rejected('UNKNOWN',2);
  });
  await t.test('CEO requests changes with a reason and Finance responds before resubmitting',async()=>{
   await login(ceo);assert.equal((await read()).can_approve,true);await rejected('REQUEST_CHANGES',2);await act('REQUEST_CHANGES',2,'Explain the missing source coverage.');
   await login(finance);await rejected('SUBMIT',3);await act('SUBMIT',3,'Warnings have been documented; no figure changes are requested.');assert.equal((await read()).status,'IN_REVIEW');
  });
  await t.test('approval needs acknowledgement; a stale decision cannot overwrite another reviewer',async()=>{
   await login(ceo);await rejected('APPROVE',4);await act('APPROVE',4,'Accepted as a management estimate.',true);
   let result=await read();assert.equal(result.status,'APPROVED');assert.equal(result.decision.actor,`${ceo}@example.test`);assert.equal(result.decision.revision,5);
   await login(admin);assert.equal((await read()).can_approve,true);await rejected('REQUEST_CHANGES',4,'Stale decision');await rejected('APPROVE',5,'',true);
   await login(finance);await act('COMMENT',5,'Noted for the executive meeting.');result=await read();assert.equal(result.status,'APPROVED');assert.equal(result.decision.revision,5);assert.equal(result.revision,6);
   assert.equal(await act('SUBMIT',1,'Ready for management review.',false,submitRequest),event);assert.equal((await read()).status,'APPROVED');
  });
  await t.test('administrator withdrawal preserves approval events and permits an explained resubmission',async()=>{
   await login(admin);await rejected('WITHDRAW_APPROVAL',6);await act('WITHDRAW_APPROVAL',6,'Management review must be revisited.');assert.equal((await read()).status,'CHANGES_REQUESTED');
   await login(finance);await act('SUBMIT',7,'Review response added; source snapshot is unchanged.');await login(admin);await act('APPROVE',8,'Management review complete.',true);
   const result=await read();assert.equal(result.status,'APPROVED');assert.equal(result.decision.actor,`${admin}@example.test`);assert.equal(result.events.filter(e=>e.action==='APPROVE').length,2);
   assert.deepEqual(await value('select public.get_management_report($1,$2)',[org,report]),snapshot);
   const history=await value('select public.list_management_reports($1,1)',[org]);assert.equal(history.reports[0].review_status,'APPROVED');
  });
  await t.test('review reads/writes deny cross-tenant, scoped, founder, anonymous and revoked actors',async()=>{
   for(const id of[other,scoped,founder]){await login(id);await deny('select public.get_management_report_review($1,$2,1)',[org,report]);await rejected('SUBMIT',9,'Denied',false,'42501');}
   await login(owner);await deny('select public.get_management_report_review($1,$2,1)',[otherOrg,report]);await deniedTableWrites();
   await db.exec('reset role');await db.query("update public.organisation_memberships set status='inactive' where organisation_id=$1 and user_id=$2",[org,admin]);await login(admin);await rejected('APPROVE',9,'',true,'42501');await deny('select public.get_management_report_review($1,$2,1)',[org,report]);
   await db.exec('reset role;set role anon');await deny('select public.get_management_report_review($1,$2,1)',[org,report]);await login(owner);
  });
  async function deniedTableWrites(){
   await deny('select * from public.management_report_review_events');await deny("insert into public.management_report_review_events(action) values('APPROVE')");await deny("update public.management_report_review_events set status='APPROVED'");await deny('delete from public.management_report_review_events');
   await db.exec('reset role');await deny("update public.management_report_review_events set note='rewritten'");await deny('delete from public.management_report_review_events');await login(owner);
  }
  await t.test('paged activity retains decision identity and audit counts without changing the source copy',async()=>{
   for(let i=0;i<15;i++)await act('COMMENT',9+i,`Meeting note ${i}`);
   const first=await read(),second=await read(2);assert.equal(first.revision,24);assert.equal(first.events.length,20);assert.equal(second.events.length,4);assert.equal(first.decision.revision,9);assert.equal(first.status,'APPROVED');
   assert.equal(new Set([...first.events,...second.events].map(e=>e.id)).size,24);
   assert.equal(await value("select count(*)::int from public.audit_events where organisation_id=$1 and event_type='MANAGEMENT_REPORT_REVIEWED'",[org]),24);
   await deny('select public.get_management_report_review($1,$2,0)',[org,report],'22023');assert.deepEqual(await value('select public.get_management_report($1,$2)',[org,report]),snapshot);
  });
 } finally {await db.close();}
});
