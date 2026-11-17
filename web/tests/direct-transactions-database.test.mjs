import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
test('direct invoices and Finance-approved corrections preserve source evidence and enforce transaction roles',async t=>{
 const db=new PGlite(),[owner,finance,procurement,other,scoped,ceo,founder]=Array.from({length:7},()=>randomUUID());
 const value=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
 const deny=(sql,args=[],code='42501')=>assert.rejects(db.query(sql,args),e=>e.code===code);
 let org,otherOrg,location,supplier,item,kg,bag,invoice,lines,purchase,batch,original,correction;
 const stage=(inv=invoice,rows=lines,request=randomUUID())=>value('select public.stage_manual_purchase($1,$2,$3,$4)',[org,request,inv,rows]);
 const batchData=id=>value('select public.get_purchase_import($1,$2)',[org,id]);
 const post=async id=>{const data=await batchData(id);return value('select public.post_purchase_import($1,$2,$3)',[org,id,Object.fromEntries(data.report.documents.filter(d=>!d.duplicate).map(d=>[d.key,d.total]))]);};
 const detail=()=>value('select public.purchase_invoice_detail($1,$2)',[org,purchase]);
 const request=(inv,rows,revision=0,kind='REPLACE',id=randomUUID())=>value('select public.request_purchase_correction($1,$2,$3,$4,$5,$6,$7,$8)',[org,purchase,id,revision,kind,'Correct source invoice evidence',inv,rows]);
 const decide=(id,approve=true,note='Checked supplier evidence')=>value('select public.decide_purchase_correction($1,$2,$3,$4)',[org,id,approve,note]);
 try{
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
  for(const id of[owner,finance,procurement,other,scoped,ceo,founder])await db.query('insert into auth.users values($1,now(),$2)',[id,`${id}@example.test`]);
  for(const name of(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
  for(const id of[other,owner]){await login(id);await value("select public.save_restaurant_setup('Transaction Test','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");const result=await value('select public.complete_restaurant_setup()');if(id===owner)org=result;else otherOrg=result;}
  location=await value('select id from public.locations where organisation_id=$1',[org]);kg=await value("select id from public.units_of_measure where organisation_id=$1 and code='KG'",[org]);bag=await value("select id from public.units_of_measure where organisation_id=$1 and code='BAG'",[org]);
  item=await value("select public.save_catalogue_material($1,null,'RICE','Rice','RAW','',$2,true,true)",[org,kg]);supplier=await value("select public.save_catalogue_supplier($1,null,'SUP','Supplier','','','',true)",[org]);await value("select public.save_material_conversion($1,$2,$3,25,'2020-01-01')",[org,item,bag]);
  await db.exec('reset role');for(const[id,role,scope]of[[finance,'finance',null],[procurement,'procurement',null],[scoped,'finance',location],[ceo,'ceo',null]]){const member=await value('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,id]);await db.query('insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,$3,$4)',[org,member,role,scope]);}await db.query('insert into private.platform_admins(user_id) values($1)',[founder]);await login(finance);
  invoice={supplier_id:supplier,location_id:location,date:'2020-04-15',reference:'DIRECT-1',route:'DIRECT',direct_reason:'Emergency purchase',evidence:'Paper invoice held in office',price_basis:'EXCLUSIVE',total:'210'};lines=[{item_id:item,uom_id:bag,quantity:'2',unit_price:'100',discount:'10',tax:'20'}];
  await t.test('Procurement records directly; Finance records expenses and cannot enter purchases',async()=>{
   assert.equal((await value('select public.purchase_import_access($1)',[org])).write,false);assert.equal((await value('select public.expense_access($1)',[org])).write,true);
   assert.equal((await value('select public.expense_access($1)',[org])).manage_categories,false);
   await assert.rejects(stage(),e=>e.code==='42501');await login(procurement);
   const req=randomUUID();batch=await stage(invoice,lines,req);assert.equal(await stage(invoice,lines,req),batch);assert.equal((await post(batch)).posted,true);assert.equal((await post(batch)).already_posted,true);
   purchase=await value('select id from public.purchase_headers where organisation_id=$1',[org]);original=await detail();assert.equal(original.current.header.total,'210.000000000000');assert.equal(original.current.lines[0].base_quantity,'50.000000000000');
   await db.exec('reset role');assert.equal(await value('select source_status from public.purchase_headers where id=$1',[purchase]),'INVOICED');assert.equal(await value('select count(*)::int from public.inventory_movements where organisation_id=$1',[org]),0);await login(finance);
   await deny("select public.save_catalogue_material($1,null,'FORBIDDEN','No','RAW','',$2,true,true)",[org,kg]);
   await login(procurement);await assert.rejects(stage({...invoice,total:'211'}),e=>e.code==='22023');await assert.rejects(stage({...invoice,reference:'BAD'},[{...lines[0],quantity:'-1'}]),e=>e.code==='22023');
  });
  await t.test('Procurement records directly and submits a correction that does not change current or original values',async()=>{
   await login(procurement);const otherBatch=await stage({...invoice,reference:'DIRECT-2'});await post(otherBatch);
   const inv={...invoice,total:'310'},rows=[{...lines[0],quantity:'3'}],req=randomUUID();correction=await request(inv,rows,0,'REPLACE',req);assert.equal(await request(inv,rows,0,'REPLACE',req),correction);
   assert.equal((await detail()).current.header.total,original.current.header.total);assert.equal((await detail()).corrections[0].state,'PENDING');await deny('select public.decide_purchase_correction($1,$2,true,$3)',[org,correction,'No approval role']);await assert.rejects(request(inv,rows),e=>e.code==='22023');
  });
  await t.test('Only Finance approves; the current projection changes while original rows stay unchanged',async()=>{
   await login(owner);await deny('select public.decide_purchase_correction($1,$2,true,$3)',[org,correction,'Admin alone is not Finance']);
   await login(finance);await decide(correction);await decide(correction);const current=await detail();assert.match(current.current.header.total,/^310(?:\.0+)?$/);assert.equal(current.current.revision,1);assert.equal(current.corrections[0].state,'APPROVED');
   assert.equal(await value('select invoice_total::text from public.purchase_headers where id=$1',[purchase]),'210.000000000000');assert.equal(await value('select quantity::text from public.purchase_lines where purchase_id=$1',[purchase]),'2.000000');
   await login(procurement);await assert.rejects(request(invoice,lines,0),e=>e.code==='22023');
   await deny('select * from public.purchase_corrections');await deny("update public.purchase_headers set invoice_total=1 where id=$1",[purchase]);
  });
  await t.test('Rejections need reasons; changed conversions cannot silently change the proposal at approval',async()=>{
   await login(procurement);const next=await request(invoice,lines,1);await login(owner);await value("select public.save_material_conversion($1,$2,$3,30,'2020-02-01')",[org,item,bag]);await login(finance);await assert.rejects(decide(next),e=>e.code==='22023');await assert.rejects(decide(next,false,''),e=>e.code==='22023');await decide(next,false,'Conversion changed; prepare a fresh correction.');assert.equal((await detail()).current.revision,1);
  });
  await t.test('Approved voids and replacements are auditable; original evidence remains immutable',async()=>{
   await login(procurement);const voidRequest=await request(invoice,lines,1,'VOID');await login(finance);await decide(voidRequest);assert.equal((await detail()).current.voided,true);assert.equal((await detail()).current.revision,2);
   await db.exec('reset role');await deny("update public.purchase_corrections set reason='rewritten' where id=$1",[correction]);await deny('delete from public.purchase_corrections where id=$1',[correction]);await login(finance);
   const history=await value('select public.purchase_invoice_list($1,1)',[org]);assert.equal(history.total,2);assert.equal(history.invoices.find(row=>row.id===purchase).invoice.voided,true);
   await login(owner);assert.equal(await value("select count(*)::int from public.audit_events where organisation_id=$1 and event_type='PURCHASE_CORRECTION_DECIDED'",[org]),3);
  });
  await t.test('Finance cannot stage, post, cancel or propose purchase changes, but retains correction decisions',async()=>{
   await login(procurement);const draft=await stage({...invoice,reference:'DRAFT-FOR-PERMISSIONS'});
   await login(finance);await assert.rejects(stage({...invoice,reference:'FINANCE-DENIED'}),e=>e.code==='42501');await assert.rejects(post(draft),e=>e.code==='42501');await assert.rejects(post(batch),e=>e.code==='42501');await assert.rejects(request(invoice,lines,2),e=>e.code==='42501');
   await deny('select public.cancel_purchase_import($1,$2)',[org,draft]);
   assert.deepEqual(await value('select public.purchase_import_access($1)',[org]),{read:true,write:false,approve_corrections:true});
   assert.equal((await detail()).current.revision,2);
  });
  await t.test('Cross-tenant, scoped, founder, CEO-only and anonymous accounts cannot enter or approve',async()=>{
   for(const id of[other,scoped,founder,ceo]){await login(id);await assert.rejects(stage({...invoice,reference:'DENIED'}),e=>e.code==='42501');await deny('select public.decide_purchase_correction($1,$2,true,$3)',[org,correction,'Denied']);}
   await login(other);await deny('select public.purchase_invoice_detail($1,$2)',[org,purchase]);await login(finance);await deny('select public.purchase_invoice_detail($1,$2)',[otherOrg,purchase]);
   await db.exec('reset role;set role anon');await deny('select public.purchase_invoice_list($1,1)',[org]);
  });
 }finally{await db.close();}
});
