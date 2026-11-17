import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile,readdir} from 'node:fs/promises';import {randomUUID} from 'node:crypto';import {PGlite} from '@electric-sql/pglite';
test('founder workspace provides scoped platform metadata, real counts, filters and pagination',async()=>{
 const db=new PGlite(),founder=randomUUID(),owner=randomUUID(),newOwner=randomUUID();
 const val=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
 const platform=(search='',state='ALL',page=1,org=null)=>val('select public.platform_workspace($1,$2,$3,$4)',[search,state,page,org]);
 try{
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
  for(const id of[founder,owner,newOwner])await db.query('insert into auth.users values($1,now(),$2)',[id,`${id}@example.test`]);
  for(const name of(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
  await db.query('insert into private.platform_admins(user_id) values($1)',[founder]);await login(owner);await val("select public.save_restaurant_setup('Pilot Restaurant','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");const org=await val('select public.complete_restaurant_setup()');
  await assert.rejects(platform(),e=>e.code==='42501');await login(newOwner);await val("select public.save_restaurant_setup('Starting Restaurant','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',1)");
  await login(founder);let packet=await platform();assert.equal(packet.summary.restaurants,1);assert.equal(packet.summary.outlets,1);assert.equal(packet.summary.active_memberships,1);assert.equal(packet.summary.onboarding,1);assert.equal(packet.summary.access_review,0);assert.equal(packet.businesses[0].owner_email,`${owner}@example.test`);
  assert.equal((await platform('Pilot')).total,1);assert.equal((await platform('no matching restaurant')).total,0);assert.equal((await platform('','ONBOARDING')).drafts[0].business_name,'Starting Restaurant');assert.equal((await platform('','ACCESS_REVIEW')).total,0);
  packet=await platform('','ALL',1,org);assert.equal(packet.selected.id,org);assert.ok(packet.selected.roles.some(r=>r.role_code==='restaurant_admin'));assert.equal(packet.selected.purchase_headers,undefined);assert.equal((await platform('','ALL',2)).businesses.length,0);
  await db.exec('reset role');await db.query("update public.organisation_memberships set status='inactive' where organisation_id=$1",[org]);await login(founder);assert.equal((await platform('','ACCESS_REVIEW')).total,1);assert.equal((await platform()).summary.active_memberships,0);
  await assert.rejects(platform('','INVALID'),e=>e.code==='22023');await assert.rejects(platform('','ALL',0),e=>e.code==='22023');await db.exec('reset role;set role anon');await assert.rejects(platform(),e=>e.code==='42501');
 }finally{await db.close();}
});
