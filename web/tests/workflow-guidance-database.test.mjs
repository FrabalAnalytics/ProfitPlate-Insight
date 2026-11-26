import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from './helpers/active-restaurant-db.mjs';
test('guided readiness, unified openings, balance handoffs and operational monthly close' ,async t=>{
 const db=new PGlite(),[admin,manager,finance,other]=Array.from({length:4},()=>randomUUID());
 const val=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
 const deny=(work,code='42501')=>assert.rejects(work,e=>e.code===code);
 let org,main,kitchen,rice,fish,kg,token,first;
 const doc=(site=main,note='Verified physical opening stock')=>({kind:'OPENING',destination_id:site,date:'2026-01-01',note});
 const qty=(item=rice,n='10')=>[{item_id:item,quantity:n}];
 const direct=(request=token,header=doc(),lines=qty())=>val('select public.record_admin_opening($1,$2,$3,$4)',[org,request,header,lines]);
 const action=(id,op,note='Checked physical quantities')=>val('select public.stock_document_action($1,$2,$3,$4,null)',[org,id,op,note]);
 const packet=id=>val("select public.stock_workspace_v2($1,null,1,'ALL','',$2)",[org,id]);
 try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
 for(const id of[admin,manager,finance,other])await db.query('insert into auth.users values($1,now(),$2)',[id,`${id}@example.test`]);
 for(const name of(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
 await login(admin);await val("select public.save_restaurant_setup('Direct opening test','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");org=await val('select public.complete_restaurant_setup()');kg=await val("select id from public.units_of_measure where organisation_id=$1 and code='KG'",[org]);rice=await val("select public.save_catalogue_material($1,null,'RICE','Rice','RAW','',$2,true,true)",[org,kg]);fish=await val("select public.save_catalogue_material($1,null,'FISH','Fish','RAW','',$2,true,true)",[org,kg]);
 await db.exec('reset role');for(const[id,role]of[[manager,'inventory_manager'],[finance,'finance']]){const member=await val('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,id]);await db.query('insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,$3)',[org,member,role]);}await login(admin);
 main=await val("select public.save_stock_configuration($1,'LOCATION',$2)",[org,{code:'MAIN',name:'Main Store',kind:'STORE'}]);kitchen=await val("select public.save_stock_configuration($1,'LOCATION',$2)",[org,{code:'KIT',name:'Kitchen',kind:'KITCHEN'}]);token=randomUUID();


 const today=new Date().toISOString().slice(0,10),month=today.slice(0,7)+'-01';
 const readiness=(kind='ALL',page=1)=>val('select public.setup_next_actions($1,$2,$3)',[org,kind,page]);
 const queue=(state='ALL',page=1)=>val('select public.stock_correction_queue($1,$2,$3)',[org,state,page]);
 const close=(m=month,site=null)=>val('select public.monthly_close_checklist($1,$2,$3)',[org,m,site]);
 const save=(p,confirm={sales:true,invoices:true,expenses:true},request=randomUUID(),note='Source registers checked for this selected scope')=>val('select public.save_monthly_close_review($1,$2,$3,$4,$5,$6,$7)',[org,p.month,p.site_id,request,p.evidence,confirm,note]);
 const inspect=async(sql,args=[])=>{await db.exec('reset role');try{return await val(sql,args);}finally{await db.exec('set role authenticated');}};
 await t.test('setup gaps identify material/centre and the action link, with real totals',async()=>{
  const p=await readiness('OPENINGS');assert.equal(p.total,4);assert.equal(p.rows.length,4);assert.equal(p.rows[0].responsible,'Administrator');assert.equal(p.rows[0].params.new,'OPENING');assert.ok(p.rows[0].params.opening_item);assert.ok(p.remaining>=p.total);assert.equal((await readiness('OPENINGS',2)).rows.length,0);assert.equal((await readiness('OPENINGS',2)).total,4);
  const all=await readiness();assert.ok(all.next);await login(manager);await deny(readiness());await login(admin);
 });
 await t.test('one opening batch records positive quantities and verified zeros, with safe retries',async()=>{
  token=randomUUID();first=await direct(token,doc(),[{item_id:rice,quantity:'12.4'},{item_id:fish,quantity:'0'}]);assert.ok(first);assert.equal(await direct(token,doc(),[{item_id:rice,quantity:'12.4'},{item_id:fish,quantity:'0'}]),first);
  assert.equal(Number(await inspect('select sum(quantity) from public.stock_ledger where document_id=$1',[first])),12.4);assert.equal(Number(await inspect('select count(*) from public.zero_opening_confirmations where organisation_id=$1 and item_id=$2 and stock_location_id=$3',[org,fish,main])),1);
  assert.equal((await readiness('OPENINGS')).total,2);await deny(direct(randomUUID(),doc(),qty(fish,'2')),'22023');await deny(direct(token,doc(),qty(rice,'13')),'22023');
 });
 await t.test('zero-only opening is a recorded confirmation without a movement document',async()=>{
  const req=randomUUID();assert.equal(await direct(req,doc(kitchen),qty(fish,'0')),null);assert.equal(await direct(req,doc(kitchen),qty(fish,'0')),null);assert.equal((await readiness('OPENINGS')).total,1);
  await deny(direct(randomUUID(),doc(kitchen),[{item_id:rice,quantity:'3'},{item_id:fish,quantity:'0'}]),'22023');assert.equal(Number(await inspect('select count(*) from public.stock_ledger where organisation_id=$1 and location_id=$2',[org,kitchen])),0);
  await deny(direct(randomUUID(),doc(kitchen),qty(rice,'-1')),'22023');await deny(direct(randomUUID(),doc(kitchen),qty(rice,'')),'22023');
 });
 await t.test('reviewed import explicitly opts into centre assignment and preview never saves it',async()=>{
  const member=await val('select id from public.organisation_memberships where organisation_id=$1 and user_id=$2',[org,admin]);const site=await val('select public.save_stock_centre($1,$2)',[org,{code:'STRICT',name:'Restricted centre',kind:'STORE',restrict_materials:true,responsible:member,processing_enabled:false}]);
  const row={action:'CREATE',material_code:'OIL',material_name:'Cooking oil',material_type:'RAW',category:'Oils',base_unit:'KG',stock_tracked:'true',weekly_count_required:'true',supply_source:'PURCHASED',requires_processing:'false',last_purchase_unit_price:'100',last_purchase_date:today,centre_code:'STRICT',opening_quantity:'2',opening_date:today};
  const preview=rows=>val("select public.preview_master_import($1,'MATERIAL',null,$2)",[org,rows]);let p=await preview([row]);assert.equal(p.valid,false);assert.match(p.rows[0].error,/not assigned/);
  const rows=[{...row,_assign_centres:'true'}];p=await preview(rows);assert.equal(p.valid,true,JSON.stringify(p));assert.match(p.rows[0].warning,/ASSIGN to STRICT/);assert.equal(await val("select count(*)::int from public.items where organisation_id=$1 and code='OIL'",[org]),0);
  const req=randomUUID();assert.equal(await val("select public.post_master_import($1,'MATERIAL',null,$2,$3,$4)",[org,req,rows,p]),1);assert.equal(await val("select public.post_master_import($1,'MATERIAL',null,$2,$3,$4)",[org,req,rows,p]),0);
  const oil=await val("select id from public.items where organisation_id=$1 and code='OIL'",[org]);assert.equal(await inspect('select private.pp_centre_material($1,$2,$3)',[org,site,oil]),true);
  await deny(direct(randomUUID(),doc(site),qty(oil,'2')),'22023');const imports=await val('select public.import_opening_queue($1)',[org]);const batch=imports.find(b=>b.centre==='Restricted centre');assert.ok(batch);await val('select public.record_imported_opening($1,$2)',[org,batch.id]);assert.equal(await inspect('select private.pp_opening_ready($1,$2,$3)',[org,oil,site]),true);
 });
 let correction;
 await t.test('creator sees waiting; Finance sees independent approval and then posting',async()=>{
  correction=await val('select public.request_stock_correction($1,$2,$3,$4)',[org,randomUUID(),{kind:'COUNT',source_id:main,date:today,note:'Physical stock rechecked independently'},qty(rice,'11')]);
  let p=await queue();assert.equal(p.waiting,1);assert.equal(p.review,0);assert.equal(p.rows.find(r=>r.id===correction).own,true);assert.ok(p.rows.find(r=>r.id===correction).reviewers.length);await deny(action(correction,'APPROVE'));
  await login(manager);p=await queue();assert.equal(p.total,0);await login(finance);p=await queue();assert.equal(p.review,1);assert.equal(p.rows[0].can_review,true);assert.equal((await queue('ACTION',2)).total,1);assert.equal((await queue('ACTION',2)).rows.length,0);
  const old=await val('select public.workspace_attention($1,null,1)',[org]);assert.equal(old.queues.some(q=>q.queue==='REQUEST_APPROVAL'),false);await action(correction,'APPROVE');assert.equal((await queue()).post,1);await login(admin);
 });
 await t.test('monthly checklist exposes incomplete source coverage, schedules and outstanding adjustments',async()=>{
  await db.exec('reset role');await db.query('delete from private.monthly_count_programmes where organisation_id=$1',[org]);await login(admin);const p=await close();assert.ok(p.pending>0);assert.equal(p.ended,false);assert.equal(p.checks.find(c=>c.id==='adjustments').pending,1);assert.equal(p.checks.find(c=>c.id==='calendar').pending,3);assert.equal(p.checks.find(c=>c.id==='counts').pending,3);assert.equal(p.saved,null);
  const id=randomUUID();const saved=await save(p,{sales:false,invoices:true,expenses:false},id);assert.equal(await save(p,{sales:false,invoices:true,expenses:false},id),saved);const q=await close();assert.equal(q.saved.current,true);assert.equal(q.saved.ready,false);assert.equal(q.saved.confirmations.sales,false);await deny(save(p,{sales:true,invoices:true,expenses:true},id),'22023');
  await deny(save(p,{sales:true},randomUUID()),'22023');await deny(save(p,{sales:true,invoices:true,expenses:true},randomUUID(),'x'),'22023');
 });
 await t.test('source changes invalidate prior confirmations and stale submissions',async()=>{
  const p=await close();await action(correction,'POST');const q=await close();assert.equal(q.saved.current,false);assert.notEqual(p.evidence,q.evidence);assert.equal(q.checks.find(c=>c.id==='adjustments').pending,0);await deny(save(p),'22023');await save(q);assert.equal((await close()).saved.current,true);
 });
 await t.test('complete prior month reviews remain non-posting and retain audit evidence',async()=>{
  await db.exec('reset role');await db.query("insert into private.weekly_counts(organisation_id,site_id,count_date,cutoff,deadline,time_zone,state,created_by,monthly_date,reporting_month) select $1,id,'2020-01-02',now(),now(),'Africa/Lagos','REVIEWED',$2,'2020-01-02','2020-01-01' from public.stock_locations where organisation_id=$1",[org,admin]);
  await db.query("insert into private.monthly_count_programmes(organisation_id,site_id,effective_from,active,count_day,count_cutoff,time_zone,submission_hours) select $1,id,'2020-01-01',true,1,'10:00','Africa/Lagos',24 from public.stock_locations where organisation_id=$1",[org]);
  await db.query("insert into private.waste_schedules(organisation_id,site_id,effective_from,revision,operating_days,cutoff,day_offset,time_zone,required) select $1,id,'2020-01-01',1,array[0,1,2,3,4,5,6],'23:59',0,'Africa/Lagos',false from public.stock_locations where organisation_id=$1 on conflict do nothing",[org]);await login(admin);
  const p=await close('2020-01-01');assert.equal(p.ended,true);assert.equal(p.checks.find(c=>c.id==='counts').pending,0);const before=await inspect('select count(*)::int from public.stock_ledger where organisation_id=$1',[org]);await save(p);assert.equal(await inspect('select count(*)::int from public.stock_ledger where organisation_id=$1',[org]),before);assert.ok((await close('2020-01-01')).saved.id);assert.equal((await close('2020-01-01')).saved.ready,true);
 });
 await t.test('assigned Operations scope cannot expose or approve another centre; revocation removes handoffs',async()=>{
  const ops=randomUUID();await db.exec('reset role');await db.query('insert into auth.users values($1,now(),$2)',[ops,'scoped-operations@example.test']);const member=await val("insert into public.organisation_memberships(organisation_id,user_id,display_name) values($1,$2,'Scoped Operations') returning id",[org,ops]);await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,'operations')",[org,member]);await db.query("insert into public.stock_member_access(organisation_id,membership_id,mode,updated_by) values($1,$2,'ASSIGNED',$3)",[org,member,admin]);await db.query("insert into public.stock_member_locations(organisation_id,membership_id,location_id,can_request,can_handle,can_approve) values($1,$2,$3,false,false,false)",[org,member,kitchen]);await login(admin);
  const make=site=>val('select public.request_stock_correction($1,$2,$3,$4)',[org,randomUUID(),{kind:'COUNT',source_id:site,date:today,note:'Physical recount for scoped handoff check'},qty(rice,'3')]);const foreign=await make(main),local=await make(kitchen);let q=await queue();assert.ok(q.rows.find(r=>r.id===local).reviewers.includes('Scoped Operations'));assert.equal(q.rows.find(r=>r.id===foreign).reviewers.includes('Scoped Operations'),false);
  await login(ops);const p=await close();assert.deepEqual(p.centres.map(s=>s.id),[kitchen]);await deny(close(month,main));q=await queue();assert.deepEqual(q.rows.map(r=>r.id),[local]);assert.equal(q.review,1);await deny(action(foreign,'APPROVE'));await action(local,'APPROVE');
  await db.exec('reset role');await db.query('delete from public.membership_roles where organisation_id=$1 and membership_id=$2',[org,member]);await login(ops);await deny(queue());await deny(close());await login(admin);assert.equal((await queue()).rows.find(r=>r.id===foreign).reviewers.includes('Scoped Operations'),false);
 });
 await t.test('close and setup cannot be read by Inventory, outsiders, inactive tenants or anonymous callers',async()=>{
  await login(manager);await deny(close());await deny(save({month,site_id:null,evidence:'x'}));await login(other);await deny(readiness());await deny(queue());await deny(close());await login(admin);await deny(close('2099-01-01'),'22023');await deny(close(month,randomUUID()));await db.exec('reset role');await db.exec('alter table public.organisations disable trigger restaurant_state_control');await db.query("update public.organisations set access_state='INACTIVE' where id=$1",[org]);await login(admin);await deny(close());await deny(queue());await deny(readiness());await db.exec('reset role;set role anon');await deny(close());await deny(queue());
 });
 }finally{await db.close();}
});
