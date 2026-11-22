import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile,readdir} from 'node:fs/promises';import {randomUUID} from 'node:crypto';import {PGlite} from './helpers/active-restaurant-db.mjs';
test('POs, partial GRNs and invoice matching preserve operational/Finance boundaries and source evidence',async t=>{
 const db=new PGlite(),[owner,procurement,finance,other,scoped,inventory,inventoryScoped]=Array.from({length:7},()=>randomUUID());
 const value=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
 const deny=(sql,args=[],code='42501')=>assert.rejects(db.query(sql,args),e=>e.code===code);
 let org,otherOrg,supplier,location,item,kg,order,line,grn1,purchase,purchase2,document,inputs,voidRequest;
 const get=()=>value('select public.get_purchase_order($1,$2)',[org,order]);
 const register=(status='ALL',page=1)=>value('select public.list_purchase_order_register($1,$2,$3)',[org,page,status]);
 const receipt=async(reference,accepted,rejected='0',reason='',request=randomUUID())=>{
  await login(inventory);
  try{return await value('select public.record_goods_receipt($1,$2,$3,$4,$5,true)',[org,order,request,{date:'2020-10-02',delivery_reference:reference,notes:'Confirmed delivery'},[{order_line_id:line,accepted,rejected,reason}]]);}finally{await login(procurement);}
 };
 const record=async(ref,qty='5',route='PO',extra={})=>{
  const invoice={supplier_id:supplier,location_id:location,date:'2020-10-02',reference:ref,price_basis:'EXCLUSIVE',total:String(BigInt(qty)*100n),route,order_id:order,direct_reason:'Emergency purchase',evidence:'Supplier paper invoice held in office',...extra};
  const rows=[{item_id:item,uom_id:kg,quantity:qty,unit_price:'100',discount:'0',tax:'0',po_line_id:line}];
  const batch=await value('select public.stage_manual_purchase($1,$2,$3,$4)',[org,randomUUID(),invoice,rows]);const data=await value('select public.get_purchase_import($1,$2)',[org,batch]);await value('select public.post_purchase_import($1,$2,$3)',[org,batch,Object.fromEntries(data.report.documents.map(d=>[d.key,d.total]))]);return value('select id from public.purchase_headers where organisation_id=$1 and purchase_ref=$2',[org,ref]);
 };
 const match=id=>value('select public.purchase_invoice_matching($1,$2)',[org,id]);
 const review=async(id,decision='ACKNOWLEDGED',request=randomUUID(),fingerprint=null)=>value('select public.review_invoice_exceptions($1,$2,$3,$4,$5,$6,true)',[org,id,request,fingerprint??(await match(id)).fingerprint,decision,'Checked supplier evidence; this records review, not payment.']);
 try{
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
  for(const id of[owner,procurement,finance,other,scoped,inventory,inventoryScoped])await db.query('insert into auth.users values($1,now(),$2)',[id,`${id}@example.test`]);
  for(const name of(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
  for(const id of[other,owner]){await login(id);await value("select public.save_restaurant_setup('Procurement Test','QSR','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");const result=await value('select public.complete_restaurant_setup()');if(id===owner)org=result;else otherOrg=result;}
  location=await value('select id from public.locations where organisation_id=$1',[org]);kg=await value("select id from public.units_of_measure where organisation_id=$1 and code='KG'",[org]);item=await value("select public.save_catalogue_material($1,null,'RICE','Rice','RAW','',$2,true,true)",[org,kg]);supplier=await value("select public.save_catalogue_supplier($1,null,'SUP','Supplier','','','',true)",[org]);
  await db.exec('reset role');for(const[id,role,scope]of[[procurement,'procurement',null],[finance,'finance',null],[scoped,'procurement',location],[inventory,'inventory',null],[inventoryScoped,'inventory',location]]){const m=await value('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,id]);await db.query('insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,$3,$4)',[org,m,role,scope]);}await login(procurement);
  document={supplier_id:supplier,location_id:location,date:'2020-10-01',needed_by:'2020-10-02',price_basis:'EXCLUSIVE',total:'1000',notes:'Weekly supplies'};inputs=[{item_id:item,uom_id:kg,quantity:'10',unit_price:'100',discount:'0',tax:'0'}];
  await t.test('Procurement saves retry-safe drafts and issues directly; Finance cannot operate POs',async()=>{
   const req=randomUUID();order=await value('select public.save_purchase_order($1,null,$2,0,$3,$4)',[org,req,document,inputs]);assert.equal(await value('select public.save_purchase_order($1,null,$2,0,$3,$4)',[org,req,document,inputs]),order);assert.equal((await get()).order.status,'DRAFT');
   await deny('select public.issue_purchase_order($1,$2,1,false)',[org,order],'22023');await login(finance);await deny('select public.issue_purchase_order($1,$2,1,true)',[org,order]);await deny('select public.save_purchase_order($1,null,$2,0,$3,$4)',[org,randomUUID(),document,inputs]);await login(procurement);
   await value('select public.issue_purchase_order($1,$2,1,true)',[org,order]);await value('select public.issue_purchase_order($1,$2,1,true)',[org,order]);const data=await get();assert.equal(data.order.status,'ISSUED');line=data.lines[0].id;assert.equal(data.lines[0].accepted,'0');await deny('select public.save_purchase_order($1,$2,$3,2,$4,$5)',[org,order,randomUUID(),document,inputs],'22023');
  });
  await t.test('only Inventory may receive; Procurement and administrators have no receiving bypass',async()=>{
   assert.equal((await register('PENDING')).orders.find(row=>row.id===order).delivery_status,'PENDING');
   const args=[org,order,randomUUID(),{date:'2020-10-02',delivery_reference:'DENIED'},[{order_line_id:line,accepted:'1',rejected:'0',reason:''}]];
   for(const actor of[procurement,finance,owner]){await login(actor);await deny('select public.record_goods_receipt($1,$2,$3,$4,$5,true)',args);assert.equal((await value('select public.purchase_order_access($1,$2)',[org,order])).receive,false);}
   await login(inventory);const permissions=await value('select public.purchase_order_access($1,$2)',[org,order]);assert.equal(permissions.receive,true);assert.equal(permissions.write,false);assert.equal(permissions.invoices,false);
   const nav=await value('select public.workspace_navigation_access($1)',[org]);assert.equal(nav.orders,true);assert.equal(nav.purchases,false);assert.equal(nav.overview,false);
   await deny('select public.save_purchase_order($1,null,$2,0,$3,$4)',[org,randomUUID(),document,inputs]);await deny('select public.issue_purchase_order($1,$2,1,true)',[org,order]);
   await assert.rejects(record('INVENTORY-CANNOT-BILL'),e=>e.code==='42501');
   await db.exec('reset role');const membership=await value('select id from public.organisation_memberships where organisation_id=$1 and user_id=$2',[org,procurement]);
   await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,'inventory')",[org,membership]);await login(procurement);
   assert.equal((await value('select public.purchase_order_access($1,$2)',[org,order])).receive,false);await assert.rejects(db.query('select public.record_goods_receipt($1,$2,$3,$4,$5,true)',args),e=>e.code==='42501'&&/different Inventory colleague/.test(e.message));
   // A different issuer still cannot make the original preparer its receiver.
   const po=await value('select public.save_purchase_order($1,null,$2,0,$3,$4)',[org,randomUUID(),document,inputs]);await login(inventory);await deny('select public.get_purchase_order($1,$2)',[org,po]);assert.equal((await value('select public.list_purchase_orders($1,1)',[org])).orders.some(row=>row.id===po),false);
   await login(owner);await value('select public.issue_purchase_order($1,$2,1,true)',[org,po]);await login(procurement);assert.equal((await value('select public.purchase_order_access($1,$2)',[org,po])).receive,false);
   await assert.rejects(db.query('select public.record_goods_receipt($1,$2,$3,$4,$5,true)',[org,po,...args.slice(2)]),e=>e.code==='42501'&&/different Inventory colleague/.test(e.message));
   await db.exec('reset role');await db.query("delete from public.membership_roles where membership_id=$1 and role_code='inventory'",[membership]);await login(procurement);
  });
  await t.test('location-scoped Inventory sees and receives only issued orders at its assigned location',async()=>{
   await login(inventoryScoped);assert.equal((await value('select public.purchase_order_access($1,$2)',[org,order])).receive,true);
   await db.exec('reset role');const brand=await value('select id from public.brands where organisation_id=$1 limit 1',[org]);
   const elsewhere=await value("insert into public.locations(organisation_id,brand_id,name,code,timezone) values($1,$2,'Other outlet','OTHER','Africa/Lagos') returning id",[org,brand]);
   await login(procurement);const po=await value('select public.save_purchase_order($1,null,$2,0,$3,$4)',[org,randomUUID(),{...document,location_id:elsewhere},inputs]);await value('select public.issue_purchase_order($1,$2,1,true)',[org,po]);
   await login(inventoryScoped);assert.equal((await value('select public.purchase_order_access($1,$2)',[org,po])).read,false);await deny('select public.get_purchase_order($1,$2)',[org,po]);assert.equal((await value('select public.list_purchase_orders($1,1)',[org])).orders.some(row=>row.id===po),false);
   await deny('select public.record_goods_receipt($1,$2,$3,$4,$5,true)',[org,po,randomUUID(),{date:'2020-10-02',delivery_reference:'WRONG-LOCATION'},[{order_line_id:line,accepted:'1',rejected:'0',reason:''}]]);
   await deny('select public.get_purchase_order($1,$2)',[otherOrg,order]);await login(procurement);
  });
  await t.test('partial deliveries preserve accepted/rejected quantities, do not post invoices or stock and cannot over-receive',async()=>{
   const request=randomUUID();grn1=await receipt('DN-1','4','1','Damaged bag',request);assert.equal(await receipt('DN-1','4','1','Damaged bag',request),grn1);assert.equal((await get()).lines[0].accepted,'4.000000');await assert.rejects(receipt('dn-1','4'),e=>e.code==='22023');await assert.rejects(receipt('DN-BAD','7'),e=>e.code==='22023');await assert.rejects(receipt('DN-NO-REASON','0','1'),e=>e.code==='22023');assert.equal((await get()).receipts.length,1);
   assert.equal((await register('PARTIAL')).orders.find(row=>row.id===order).delivery_status,'PARTIAL');
   await receipt('DN-2','6');assert.equal((await get()).lines[0].accepted,'10.000000');assert.equal(await value('select count(*)::int from public.purchase_headers where organisation_id=$1',[org]),0);
   assert.equal((await register('COMPLETED')).orders.find(row=>row.id===order).delivery_status,'COMPLETED');
   await db.exec('reset role');assert.equal(await value('select count(*)::int from public.inventory_movements where organisation_id=$1',[org]),0);await login(procurement);
  });
  await t.test('a bill matches ordered/accepted quantities; multiple bills cannot hide cumulative over-billing',async()=>{
   purchase=await record('PO-BILL-1');let data=await match(purchase);assert.equal(data.status,'MATCHED');assert.match(data.comparisons[0].ordered,/^10(?:\.0+)?$/);assert.match(data.comparisons[0].accepted,/^10(?:\.0+)?$/);assert.match(data.comparisons[0].billed,/^5(?:\.0+)?$/);
   purchase2=await record('PO-BILL-2','6');data=await match(purchase2);assert.equal(data.status,'NEEDS_FINANCE_REVIEW');assert.match(JSON.stringify(data.exceptions),/cumulative billed quantity exceeds/);await assert.rejects(review(purchase2),e=>e.code==='42501');
   await login(finance);const req=randomUUID(),fingerprint=data.fingerprint;const result=await review(purchase2,'ACKNOWLEDGED',req,fingerprint);assert.equal(await review(purchase2,'ACKNOWLEDGED',req,fingerprint),result);assert.equal((await match(purchase2)).status,'EXCEPTIONS_REVIEWED');await login(procurement);
  });
  await t.test('inclusive quotation terms compare exact net prices and tax rates, and issued-PO search retains a selected older order',async()=>{
   const doc={...document,price_basis:'INCLUSIVE',total:'220'},rows=[{...inputs[0],quantity:'2',unit_price:'110',tax:'20'}];
   const po=await value('select public.save_purchase_order($1,null,$2,0,$3,$4)',[org,randomUUID(),doc,rows]);await value('select public.issue_purchase_order($1,$2,1,true)',[org,po]);const data=await value('select public.get_purchase_order($1,$2)',[org,po]),poLine=data.lines[0].id;
   await login(inventory);await value('select public.record_goods_receipt($1,$2,$3,$4,$5,true)',[org,po,randomUUID(),{date:'2020-10-02',delivery_reference:'INCLUSIVE-DN'},[{order_line_id:poLine,accepted:'2',rejected:'0',reason:''}]]);await login(procurement);
   for(const [reference,price,tax]of[['INCLUSIVE-MATCH','110','10'],['INCLUSIVE-EXCEPTION','130','20']]){
    const invoice={supplier_id:supplier,location_id:location,date:'2020-10-02',reference,price_basis:'INCLUSIVE',total:price,route:'PO',order_id:po},billLines=[{item_id:item,uom_id:kg,quantity:'1',unit_price:price,discount:'0',tax,po_line_id:poLine}];
    const batch=await value('select public.stage_manual_purchase($1,$2,$3,$4)',[org,randomUUID(),invoice,billLines]),preview=await value('select public.get_purchase_import($1,$2)',[org,batch]);await value('select public.post_purchase_import($1,$2,$3)',[org,batch,Object.fromEntries(preview.report.documents.map(d=>[d.key,d.total]))]);
    const id=await value('select id from public.purchase_headers where organisation_id=$1 and purchase_ref=$2',[org,reference]),result=await match(id);
    if(reference==='INCLUSIVE-MATCH')assert.equal(result.status,'MATCHED');else {assert.equal(result.status,'NEEDS_FINANCE_REVIEW');assert.match(JSON.stringify(result.exceptions),/price after discount/);assert.match(JSON.stringify(result.exceptions),/tax per base unit/);assert.doesNotMatch(JSON.stringify(result.exceptions),/quantity exceeds/);}
   }
   const choices=await value('select public.purchase_order_choices($1,$2,null)',[org,data.order.reference]);assert.equal(choices.length,1);assert.equal(choices[0].id,po);const selected=await value('select public.purchase_order_choices($1,$2,$3)',[org,data.order.reference,order]);assert.equal(selected[0].id,order);assert.equal(selected.length,2);
  });
  await t.test('an approved invoice correction invalidates old links and Finance review until Procurement re-links',async()=>{
   const invoice={supplier_id:supplier,location_id:location,date:'2020-10-02',reference:'PO-BILL-2',price_basis:'EXCLUSIVE',total:'500'},rows=[{...inputs[0],quantity:'5'}];
   const correction=await value('select public.request_purchase_correction($1,$2,$3,0,$4,$5,$6,$7)',[org,purchase2,randomUUID(),'REPLACE','Correct billed quantity',invoice,rows]);await login(finance);await value("select public.decide_purchase_correction($1,$2,true,'Checked corrected invoice')",[org,correction]);assert.equal((await match(purchase2)).status,'ACTION_REQUIRED');await assert.rejects(review(purchase2),e=>e.code==='22023');
   await login(procurement);await value('select public.set_invoice_procurement_context($1,$2,$3,1,$4,$5)',[org,purchase2,randomUUID(),{route:'PO',order_id:order},[{line:1,order_line_id:line}]]);assert.equal((await match(purchase2)).status,'MATCHED');
  });
  await t.test('no-PO purchases require reason/evidence and Finance acknowledgement remains separate from payment',async()=>{
   await assert.rejects(record('NO-REASON','1','DIRECT',{direct_reason:''}),e=>e.code==='22023');const direct=await record('DIRECT-EXCEPTION','1','DIRECT');assert.equal((await match(direct)).status,'NEEDS_FINANCE_REVIEW');await login(finance);await review(direct);assert.equal((await match(direct)).status,'EXCEPTIONS_REVIEWED');assert.equal((await match(direct)).context.reason,'Emergency purchase');await login(procurement);
  });
  await t.test('GRN voids require Finance, retain source evidence and invalidate dependent matching',async()=>{
   await deny('select public.review_goods_receipt_void($1,$2,$3,$4,$5,$6)',[org,grn1,randomUUID(),'Wrong receipt','REQUEST','']);await login(inventory);
   voidRequest=await value('select public.review_goods_receipt_void($1,$2,$3,$4,$5,$6)',[org,grn1,randomUUID(),'Receipt entered incorrectly','REQUEST','']);await login(procurement);assert.equal((await match(purchase)).status,'ACTION_REQUIRED');await deny('select public.review_goods_receipt_void($1,$2,$3,$4,$5,$6)',[org,grn1,voidRequest,'','APPROVE','Checked']);
   await login(finance);const oldFingerprint=(await match(purchase2)).fingerprint;await value('select public.review_goods_receipt_void($1,$2,$3,$4,$5,$6)',[org,grn1,voidRequest,'','APPROVE','Confirmed receipt error']);await value('select public.review_goods_receipt_void($1,$2,$3,$4,$5,$6)',[org,grn1,voidRequest,'','APPROVE','Confirmed receipt error']);assert.equal((await get()).receipts.length,2);assert.equal((await get()).receipts.find(r=>r.id===grn1).voided,true);assert.equal((await get()).lines[0].accepted,'6.000000');await assert.rejects(review(purchase2,'ACKNOWLEDGED',randomUUID(),oldFingerprint),e=>e.code==='22023');assert.equal((await match(purchase2)).status,'NEEDS_FINANCE_REVIEW');
  });
  await t.test('register filters all records before pagination, reopens voided deliveries and respects role/location scopes',async()=>{
   await login(procurement);
   assert.equal((await register('PARTIAL')).orders.find(row=>row.id===order).delivery_status,'PARTIAL');
   assert.ok(!(await register('COMPLETED')).orders.some(row=>row.id===order));
   const baseline=(await register('DRAFT')).total;
   for(let i=0;i<21;i++)await value('select public.save_purchase_order($1,null,$2,0,$3,$4)',[org,randomUUID(),document,inputs]);
   const first=await register('DRAFT'),second=await register('DRAFT',2);
   assert.equal(first.total,baseline+21);assert.equal(first.orders.length,20);
   assert.equal(second.total,first.total);assert.equal(second.orders.length,first.total-20);
   assert.equal(new Set([...first.orders,...second.orders].map(row=>row.id)).size,first.total);
   assert.ok(first.orders.every(row=>row.status==='DRAFT'));
   assert.equal((await register('COMPLETED')).orders[0].delivery_status,'COMPLETED');
   await deny('select public.list_purchase_order_register($1,0,$2)',[org,'ALL'],'22023');
   await deny('select public.list_purchase_order_register($1,1,$2)',[org,'APPROVED'],'22023');
   await login(inventoryScoped);assert.equal((await register('DRAFT')).total,0);
   const visible=await register();for(const row of visible.orders){assert.equal(row.status,'ISSUED');const po=await value('select public.get_purchase_order($1,$2)',[org,row.id]);assert.equal(po.order.payload.header.location_id,location);}
   await login(other);await deny('select public.list_purchase_order_register($1,1,$2)',[org,'ALL']);
   await db.exec('reset role;set role anon');await deny('select public.list_purchase_order_register($1,1,$2)',[org,'ALL']);await login(procurement);
  });
  await t.test('issued/confirmed evidence and tenant boundaries cannot be bypassed through tables or RPCs',async()=>{
   await db.exec('reset role');await deny("update public.purchase_orders set notes='overwrite' where id=$1",[order]);await deny('delete from public.goods_receipt_lines where receipt_id=$1',[grn1]);await login(procurement);await deny('select * from public.invoice_procurement_contexts');
   for(const id of[other,scoped]){await login(id);await deny('select public.get_purchase_order($1,$2)',[org,order]);await deny('select public.record_goods_receipt($1,$2,$3,$4,$5,true)',[org,order,randomUUID(),{date:'2020-10-02',delivery_reference:'DENIED'},[{order_line_id:line,accepted:'1',rejected:'0',reason:''}]]);}
   await login(finance);await deny('select public.set_invoice_procurement_context($1,$2,$3,0,$4,$5)',[org,purchase,randomUUID(),{route:'DIRECT',reason:'No',evidence:'No'},[]]);await deny('select public.get_purchase_order($1,$2)',[otherOrg,order]);await db.exec('reset role;set role anon');await deny('select public.list_purchase_orders($1,1)',[org]);
  });
 }finally{await db.close();}
});
