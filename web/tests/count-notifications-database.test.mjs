import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from './helpers/active-restaurant-db.mjs';

test('count notifications distinguish independent review from posting across all pending records',async t=>{
 const db=new PGlite(),owner=randomUUID(),manager=randomUUID(),department=randomUUID();
 const value=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
 const rejected=p=>assert.rejects(p,e=>e.code==='42501');
 let org,member,rice,weeklySite;
 const today=new Date().toISOString().slice(0,10),centres=[];
 const queue=(frequency,state,site=null,page=1)=>value('select public.count_action_queue($1,$2,$3,$4,$5)',[org,frequency,state,site,page]);
 const workspace=frequency=>value(`select public.${frequency==='MONTHLY'?'monthly':'weekly'}_counts_workspace($1)`,[org]);
 const centre=async(code,day=today)=>{
  await login(owner);const id=await value('select public.save_stock_centre($1,$2)',[org,{code,name:code,kind:'STORE',responsible:member}]);
  await db.exec('reset role');await db.query('delete from private.monthly_count_programmes where organisation_id=$1 and site_id=$2',[org,id]);await db.query("insert into private.monthly_count_programmes values($1,$2,$3,true,extract(day from $3::date)::integer,'00:00','Africa/Lagos',24,'Ada')",[org,id,day]);await login(manager);return id;
 };
 const submitMonthly=async(site,day=today)=>{
  const id=await value('select public.start_monthly_count($1,$2,$3)',[org,site,day]);
  await value('select public.save_monthly_count($1,$2,0,$3,$4,true,$5,$6,false)',[org,id,randomUUID(),[{item_id:rice,physical:'0',note:'Verified count'}],'Ada','Verified stock']);return id;
 };
 const act=(id,rev,action)=>value('select public.weekly_count_action($1,$2,$3,$4,$5,$6)',[org,id,rev,randomUUID(),action,'Independent review']);
 try{
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
  for(const id of[owner,manager,department])await db.query('insert into auth.users values($1,now(),$2)',[id,`${id}@example.test`]);
  for(const f of(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(f=>f.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${f}`,import.meta.url),'utf8'));
  await login(owner);await value("select public.save_restaurant_setup('Count Notifications','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");org=await value('select public.complete_restaurant_setup()');member=await value('select id from public.organisation_memberships where organisation_id=$1 and user_id=$2',[org,owner]);
  const kg=await value("select id from public.units_of_measure where organisation_id=$1 and code='KG'",[org]);rice=await value('select public.save_material_setup($1,$2)',[org,{code:'RICE',name:'Rice',item_type:'RAW',base_uom_id:kg,stock_tracked:true,is_active:true,weekly_count_required:true,supply_class:'PURCHASED'}]);
  await db.exec('reset role');const m=await value('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,manager]);await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,'inventory_manager')",[org,m]);
  await t.test('monthly submission moves from review to posting and disappears after posting',async()=>{
   const site=await centre('FIRST'),id=await submitMonthly(site);await rejected(act(id,1,'APPROVE'));await login(owner);let status=await workspace('MONTHLY');assert.equal(status.review_waiting,1);assert.equal(status.posting_waiting,0);assert.equal((await queue('MONTHLY','SUBMITTED')).total,1);
   await login(owner);await act(id,1,'APPROVE');status=await workspace('MONTHLY');assert.equal(status.review_waiting,0);assert.equal(status.posting_waiting,1);assert.equal((await queue('MONTHLY','SUBMITTED')).total,0);assert.equal((await queue('MONTHLY','APPROVED')).rows[0].count_id,id);
   await login(owner);await act(id,2,'POST');status=await workspace('MONTHLY');assert.equal(status.review_waiting,0);assert.equal(status.posting_waiting,0);assert.equal((await queue('MONTHLY','APPROVED')).total,0);
  });
  await t.test('weekly review and posting are separate without changing count permissions',async()=>{
   weeklySite=await centre('WEEKLY');await db.exec('reset role');await db.query('delete from private.weekly_count_programmes where organisation_id=$1 and site_id=$2',[org,weeklySite]);await db.query("insert into private.weekly_count_programmes values($1,$2,$3,true,extract(dow from $3::date)::integer,'00:00','Africa/Lagos',24,1,null,'Ada')",[org,weeklySite,today]);await db.query('select private.pp_count_scope_seed($1,$2,$3,$4,true)',[org,weeklySite,rice,today]);await login(manager);
   const id=await value('select public.start_weekly_count($1,$2,$3)',[org,weeklySite,today]);await value('select public.save_weekly_count($1,$2,0,$3,$4,true,$5,$6)',[org,id,randomUUID(),[{item_id:rice,physical:'0',note:'Verified'}],'Ada','Verified']);await login(owner);let status=await workspace('WEEKLY');assert.equal(status.review_waiting,1);assert.equal(status.posting_waiting,0);assert.equal((await queue('WEEKLY','SUBMITTED')).total,1);
   await login(owner);await act(id,1,'APPROVE');status=await workspace('WEEKLY');assert.equal(status.review_waiting,0);assert.equal(status.posting_waiting,1);assert.equal((await queue('WEEKLY','APPROVED')).rows[0].count_id,id);await login(owner);await act(id,2,'POST');assert.equal((await workspace('WEEKLY')).posting_waiting,0);
  });
  await t.test('totals cover records beyond the preview and queue pagination, including older dates',async()=>{
   for(let i=0;i<28;i++){const day=i===27?'2020-01-16':today,site=await centre(`QUEUE_${i}`,day),id=await submitMonthly(site,day);centres.push({site,id});if(i<2){await login(owner);await act(id,1,'APPROVE');}}
   await login(owner);const status=await workspace('MONTHLY');assert.equal(status.review_waiting,26);assert.equal(status.posting_waiting,2);assert.ok(status.rows.length<=8);
   const first=await queue('MONTHLY','SUBMITTED'),second=await queue('MONTHLY','SUBMITTED',null,2);assert.equal(first.total,26);assert.equal(first.rows.length,25);assert.equal(second.rows.length,1);assert.equal(first.rows[0].day,'2020-01-16');assert.ok(first.rows.every(r=>r.state==='SUBMITTED'));assert.equal((await queue('MONTHLY','APPROVED')).total,2);
   await db.exec('reset role');assert.equal(await value('select count(*)::integer from public.stock_ledger'),0);await login(owner);
  });
  await t.test('centre scope, cross-business and anonymous access are enforced',async()=>{
   await db.exec('reset role');const m=await value('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,department]);await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,'stock_department')",[org,m]);await login(owner);await value("select public.save_stock_member_access($1,$2,0,'ASSIGNED',$3)",[org,m,[{location_id:centres[0].site,can_request:true,can_handle:false,can_approve:false,can_dispatch:false,can_receive:true}]]);
   await login(department);assert.equal((await queue('MONTHLY','APPROVED')).total,0);assert.equal((await queue('MONTHLY','SUBMITTED')).total,0);await rejected(queue('MONTHLY','APPROVED',centres[1].site));await rejected(value("select public.count_action_queue($1,'MONTHLY','SUBMITTED',null,1)",[randomUUID()]));
   await db.exec('reset role;set role anon');await rejected(queue('MONTHLY','APPROVED'));
  });
 }finally{await db.close();}
});
