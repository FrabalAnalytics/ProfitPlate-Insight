// Operational suites need approved restaurants. Use the real Founder API after
// fixture registration; activation tests import raw PGlite and verify Pending itself.
import {PGlite as BasePGlite} from '@electric-sql/pglite';
import {randomUUID} from 'node:crypto';
export class PGlite extends BasePGlite {
 async query(sql,...args){
  const result=await super.query(sql,...args);
  if(this.approvingFixture||!/^\s*select\s+public\.complete_restaurant_setup\w*\(/i.test(sql)||!result.rows?.length)return result;
  const org=Object.values(result.rows[0])[0];
  if(typeof org!=='string'||!/^[0-9a-f-]{36}$/.test(org))return result;
  this.approvingFixture=true;
  const context=(await super.query("select current_setting('role') role,current_setting('request.jwt.claim.sub',true) actor")).rows[0];
  try{
   await super.exec('reset role');
   if(!(await super.query("select to_regprocedure('private.pp_registration_begin()') is not null enabled")).rows[0].enabled)return result;
   if((await super.query('select access_state from public.organisations where id=$1',[org])).rows[0]?.access_state!=='PENDING')return result;
   if(!this.fixtureFounder){
    this.fixtureFounder=randomUUID();
    await super.query('insert into auth.users(id,email_confirmed_at) values($1,now())',[this.fixtureFounder]);
    await super.query('insert into private.platform_admins(user_id) values($1)',[this.fixtureFounder]);
   }
   await super.query("select set_config('request.jwt.claim.sub',$1,false)",[this.fixtureFounder]);
   await super.exec('set role authenticated');
   await super.query("select public.set_restaurant_access($1,'PENDING','ACTIVE','Approve operational test fixture',true)",[org]);
  }finally{
   await super.exec('reset role');
   await super.query("select set_config('request.jwt.claim.sub',$1,false)",[context.actor??'']);
   if(context.role==='authenticated'||context.role==='anon')await super.exec(`set role ${context.role}`);
   this.approvingFixture=false;
  }
  return result;
 }
}
