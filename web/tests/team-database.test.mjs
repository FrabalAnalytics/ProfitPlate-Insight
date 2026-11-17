import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile,readdir } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';

test('team invitation and membership security through real migrations',async t=>{
 const db=new PGlite();
 const ids=Array.from({length:8},(_,i)=>`00000000-0000-0000-0000-${String(i+1).padStart(12,'0')}`);
 const [owner,other,invitee,wrong,unverified,founder,admin,scoped]=ids;
 const scalar=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
 const deny=async(sql,args=[],code='42501')=>assert.rejects(db.query(sql,args),e=>e.code===code);
 const roles=JSON.stringify([{role_code:'finance',location_id:null}]);
 let org,otherOrg,location,member,token;
 try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
 for(let i=0;i<ids.length;i++)await db.query('insert into auth.users values($1,$2,$3)',[ids[i],ids[i]===unverified?null:'2026-11-15',`person${i+1}@example.test`]);
 for(const name of (await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
 await db.query('insert into private.platform_admins(user_id) values($1)',[founder]);
 for(const id of [owner,other]){await login(id);await scalar("select public.save_restaurant_setup('Team Test','QSR','NG','NGN','Brand','Main','Africa/Lagos','',3)");const result=await scalar('select public.complete_restaurant_setup()');if(id===owner)org=result;else otherOrg=result;}
 await db.exec('reset role');location=await scalar('select id from public.locations where organisation_id=$1',[org]);
 for(const [id,role,scope] of [[admin,'restaurant_admin',null],[scoped,'restaurant_admin',location]]){const m=await scalar('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,id]);await db.query('insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,$3,$4)',[org,m,role,scope]);}
 await t.test('only unscoped administrators can inspect a team; founder is separate',async()=>{
  for(const id of [other,invitee,scoped,founder]){await login(id);assert.equal(await scalar('select public.team_access($1)',[org]),false);await deny('select public.team_directory($1)',[org]);}
  await login(admin);assert.equal(await scalar('select public.team_access($1)',[org]),true);
  await deny('select * from public.team_invitations');
 });
 await t.test('invitations store only a hash and creation retries do not issue more secrets',async()=>{
  await login(owner);const request=randomUUID();const result=await scalar('select public.create_team_invitation($1,$2,$3,$4::jsonb)',[org,request,'Person3@Example.Test',roles]);token=result.token;assert.match(token,/^[a-f0-9]{64}$/);
  const retry=await scalar('select public.create_team_invitation($1,$2,$3,$4::jsonb)',[org,request,'person3@example.test',roles]);assert.equal(retry.token,null);
  await deny('select public.create_team_invitation($1,$2,$3,$4::jsonb)',[org,randomUUID(),'person3@example.test',roles],'22023');
  const packet=await scalar('select public.team_directory($1)',[org]);assert.equal(JSON.stringify(packet).includes(token),false);
  await db.exec('reset role');assert.notEqual(await scalar('select token_hash from public.team_invitations where id=$1',[result.id]),token);
 });
 await t.test('wrong email, unverified email and platform founder cannot inspect or accept',async()=>{
  for(const id of [wrong,unverified,founder]){await login(id);await deny('select public.inspect_team_invitation($1)',[token],'22023');await deny('select public.accept_team_invitation($1)',[token],'22023');}
  // Verify confirmation and founder checks even when the invitation email matches.
  for(const [id,email] of [[unverified,'person5@example.test'],[founder,'person6@example.test']]) {
   await login(owner);const result=await scalar('select public.create_team_invitation($1,$2,$3,$4::jsonb)',[org,randomUUID(),email,roles]);
   await login(id);await deny('select public.accept_team_invitation($1)',[result.token],'22023');
  }
 });
 await t.test('verified matching email accepts once and gets exactly assigned access',async()=>{
  await login(invitee);const preview=await scalar('select public.inspect_team_invitation($1)',[token]);assert.equal(preview.organisation_name,'Team Test');assert.equal(await scalar('select public.accept_team_invitation($1)',[token]),org);assert.equal(await scalar('select public.accept_team_invitation($1)',[token]),org);
  assert.equal(await scalar('select public.team_access($1)',[org]),false);assert.deepEqual(await scalar('select public.sales_import_access($1)',[org]),{read:true,write:false});
  await deny('select public.team_directory($1)',[org]);
  member=await scalar('select id from public.organisation_memberships where organisation_id=$1 and user_id=$2',[org,invitee]);
 });
 await t.test('cross-tenant updates, foreign locations and unknown roles are rejected',async()=>{
  await login(other);await deny('select public.update_team_member($1,$2,now(),false,$3::jsonb)',[org,member,roles]);
  await login(owner);
  await deny('select public.create_team_invitation($1,$2,$3,$4::jsonb)',[org,randomUUID(),'new@example.test',JSON.stringify([{role_code:'superadmin'}])],'22023');
  await db.exec('reset role');const foreign=await scalar('select id from public.locations where organisation_id=$1',[otherOrg]);await login(owner);
  await deny('select public.create_team_invitation($1,$2,$3,$4::jsonb)',[org,randomUUID(),'new@example.test',JSON.stringify([{role_code:'finance',location_id:foreign}])],'22023');
 });
 await t.test('owner and self access are protected; stale edits cannot overwrite access',async()=>{
  await login(admin);const directory=await scalar('select public.team_directory($1)',[org]);const ownerRow=directory.members.find(m=>m.user_id===owner),self=directory.members.find(m=>m.user_id===admin),staff=directory.members.find(m=>m.id===member);
  for(const row of [ownerRow,self])await deny('select public.update_team_member($1,$2,$3,false,$4::jsonb)',[org,row.id,row.updated_at,roles]);
  await deny('select public.update_team_member($1,$2,$3,false,$4::jsonb)',[org,member,'2020-01-01',roles],'22023');
  await scalar('select public.update_team_member($1,$2,$3,false,$4::jsonb)',[org,member,staff.updated_at,roles]);
  await login(invitee);assert.deepEqual(await scalar('select public.sales_import_access($1)',[org]),{read:false,write:false});assert.equal(await scalar('select count(*)::int from public.organisations where id=$1',[org]),0);
  // Idempotent acceptance must never reactivate a subsequently deactivated member.
  assert.equal(await scalar('select public.accept_team_invitation($1)',[token]),org);assert.equal(await scalar('select count(*)::int from public.organisations where id=$1',[org]),0);
 });
 await t.test('revoked and expired links cannot grant membership',async()=>{
  await login(owner);const revoked=await scalar('select public.create_team_invitation($1,$2,$3,$4::jsonb)',[org,randomUUID(),'person4@example.test',roles]);await scalar('select public.revoke_team_invitation($1,$2)',[org,revoked.id]);await login(wrong);await deny('select public.accept_team_invitation($1)',[revoked.token],'22023');
  await login(owner);const expired=await scalar('select public.create_team_invitation($1,$2,$3,$4::jsonb)',[org,randomUUID(),'person4@example.test',roles]);await db.exec('reset role');await db.query("update public.team_invitations set expires_at=now()-interval '1 second' where id=$1",[expired.id]);await login(wrong);await deny('select public.accept_team_invitation($1)',[expired.token],'22023');
 });
 await t.test('reactivation applies explicit combined roles and requires a fresh version',async()=>{
  await login(owner);const row=(await scalar('select public.team_directory($1)',[org])).members.find(m=>m.id===member);
  const combined=JSON.stringify([{role_code:'finance',location_id:null},{role_code:'procurement',location_id:null}]);
  await scalar('select public.update_team_member($1,$2,$3,true,$4::jsonb)',[org,member,row.updated_at,combined]);
  await login(invitee);assert.deepEqual(await scalar('select public.sales_import_access($1)',[org]),{read:true,write:false});assert.deepEqual(await scalar('select public.purchase_import_access($1)',[org]),{read:true,write:true,approve_corrections:true});
 });
 await t.test('removing an administrator invalidates invitations they created',async()=>{
  await login(admin);const pending=await scalar('select public.create_team_invitation($1,$2,$3,$4::jsonb)',[org,randomUUID(),'person4@example.test',roles]);await login(owner);const packet=await scalar('select public.team_directory($1)',[org]);const row=packet.members.find(m=>m.user_id===admin);await scalar('select public.update_team_member($1,$2,$3,true,$4::jsonb)',[org,row.id,row.updated_at,roles]);await login(wrong);await deny('select public.accept_team_invitation($1)',[pending.token],'22023');
 });
 await t.test('location-scoped invitations preserve scope and do not grant global reports',async()=>{
  await login(owner);const pending=await scalar('select public.create_team_invitation($1,$2,$3,$4::jsonb)',[org,randomUUID(),'person4@example.test',JSON.stringify([{role_code:'finance',location_id:location}])]);await login(wrong);await scalar('select public.accept_team_invitation($1)',[pending.token]);assert.deepEqual(await scalar('select public.sales_import_access($1)',[org]),{read:false,write:false});assert.equal(await scalar('select count(*)::int from public.locations where organisation_id=$1',[org]),1);
 });
 await t.test('audit trail omits invitation secrets and direct client writes remain denied',async()=>{
  await login(owner);const events=await scalar('select jsonb_agg(to_jsonb(e)) from public.audit_events e where organisation_id=$1',[org]);assert.ok(events.some(e=>e.event_type==='TEAM_INVITATION_ACCEPTED'));assert.equal(JSON.stringify(events).includes(token),false);
  await deny("update public.organisation_memberships set status='inactive' where id=$1",[member]);await deny('delete from public.membership_roles where membership_id=$1',[member]);
  await db.exec('reset role;set role anon');await deny('select public.accept_team_invitation($1)',[token]);
 });
 }finally{await db.close();}
});
