import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from './helpers/active-restaurant-db.mjs';
test('Management review packs and named follow-up respect scopes and preserve stock',async t=>{
 const db=new PGlite(),[owner,ops,scoped,inventory,outsider]=Array.from({length:5},()=>randomUUID());
 const val=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const login=async id=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
 const denied=work=>assert.rejects(work,e=>e.code==='42501');
 let org,outlet,other,main,kitchen,opsMember,scopedMember,fish,kg;
 try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
 for(const id of[owner,ops,scoped,inventory,outsider])await db.query('insert into auth.users values($1,now(),$2)',[id,`${id}@example.test`]);
 for(const name of(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${name}`,import.meta.url),'utf8'));
 await login(owner);await val("select public.save_restaurant_setup('Operations Test','FINE_DINING','NG','NGN','Brand','Outlet','Africa/Lagos','',3)");org=await val('select public.complete_restaurant_setup()');outlet=await val('select id from public.locations where organisation_id=$1',[org]);kg=await val("select id from public.units_of_measure where organisation_id=$1 and code='KG'",[org]);
 await db.exec('reset role');const brand=await val('select brand_id from public.locations where id=$1',[outlet]);other=await val("insert into public.locations(organisation_id,brand_id,code,name,timezone) values($1,$2,'OTHER','Other outlet','Africa/Lagos') returning id",[org,brand]);
 for(const[id,role,scope]of[[ops,'operations',null],[scoped,'operations',outlet],[inventory,'inventory_manager',null]]){const m=await val('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,id]);await db.query('insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,$3,$4)',[org,m,role,scope]);if(id===ops)opsMember=m;if(id===scoped)scopedMember=m;}
 await login(owner);const ownerMember=await val('select id from public.organisation_memberships where organisation_id=$1 and user_id=$2',[org,owner]);fish=await val("select public.save_catalogue_material($1,null,'FISH','Fish','RAW','Fish',$2,true,true)",[org,kg]);
 main=await val('select public.save_stock_centre($1,$2)',[org,{code:'MAIN',name:'Main Store',kind:'STORE',outlet_id:other,responsible:ownerMember}]);kitchen=await val('select public.save_stock_centre($1,$2)',[org,{code:'KITCHEN',name:'Kitchen',kind:'KITCHEN',outlet_id:outlet,responsible:ownerMember}]);
 const today=await val("select (now() at time zone 'Africa/Lagos')::date::text");

 await t.test('daily, weekly and monthly reviews compile against current records',async()=>{
  for(const period of ['DAILY','WEEKLY','MONTHLY']){
   const p=await val('select public.management_review_pack($1,$2)',[org,period]);assert.equal(p.context.period,period);assert.ok(p.context.from<=p.context.to);assert.equal(p.context.complete,true);assert.ok(p.current.counts.monthly);assert.ok(p.current.production);assert.ok(p.financial);assert.deepEqual(p.warnings,[]);
  }
 });
 const pack=(period='DAILY',anchor=null,scope=null,site=null)=>val('select public.management_review_pack($1,$2,$3,$4,$5)',[org,period,anchor,scope,site]);
 const rejects=work=>assert.rejects(work,e=>e.code==='22023');
 const raw=async(sql,args=[])=>{await db.exec('reset role');try{return await val(sql,args);}finally{await db.exec('set role authenticated');}};
 let deptMember,dept,actionId,snapshot;
 await t.test('periods honour local business dates, configured week start and unequal calendar months',async()=>{
  await db.exec('reset role');await db.query('update public.organisations set reporting_week_start=3 where id=$1',[org]);await login(owner);
  const week=await pack('WEEKLY','2024-03-15');assert.equal(week.context.from,'2024-03-13');assert.equal(week.context.to,'2024-03-19');assert.equal(week.context.previous_from,'2024-03-06');
  const month=await pack('MONTHLY','2024-03-15');assert.equal(month.context.to,'2024-03-31');assert.equal(month.context.previous_to,'2024-02-29');assert.equal(month.context.days,31);assert.equal(month.context.previous_days,29);
  const day=await pack('DAILY',today);assert.equal(day.context.complete,false);assert.equal(day.context.from,today);await rejects(pack('ANNUAL'));await rejects(pack('DAILY','9999-01-01'));
 });
 await t.test('scoped Operations does not gain business financial data or another centre',async()=>{
  await login(scoped);const p=await pack('DAILY',today);assert.equal(p.financial,null);assert.equal(p.expenses,null);assert.equal(p.access.centres.length,1);assert.equal(p.access.centres[0].id,kitchen);assert.equal(p.stock_now.centre_count,1);assert.equal(p.stock_now.centres[0].id,kitchen);assert.equal(p.access.financial,false);
  await denied(pack('DAILY',today,other));await denied(pack('DAILY',today,null,main));await denied(pack('DAILY',today,other,kitchen));
  await login(owner);
 });
 await t.test('Procurement sees purchasing scope without menu, sales or stock datasets',async()=>{
  const id=randomUUID();await db.exec('reset role');await db.query('insert into auth.users values($1,now(),$2)',[id,'procurement@example.test']);const membership=await val('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[org,id]);await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,'procurement')",[org,membership]);await login(id);const p=await pack('DAILY',today);assert.equal(p.financial,null);assert.equal(p.stock_now,null);assert.equal(p.access.centres.length,0);assert.deepEqual(p.menus,[]);assert.equal(p.access.purchasing,true);await login(owner);
 });
 await t.test('follow-up creation is named, scoped, audited and safely repeatable',async()=>{
  dept=randomUUID();await db.exec('reset role');await db.query('insert into auth.users values($1,now(),$2)',[dept,'department@example.test']);deptMember=await val('insert into public.organisation_memberships(organisation_id,user_id,display_name) values($1,$2,\'Ada\') returning id',[org,dept]);await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,'stock_department',$3)",[org,deptMember,outlet]);await db.query("insert into public.stock_member_access(organisation_id,membership_id,mode,updated_by) values($1,$2,'ASSIGNED',$3)",[org,deptMember,owner]);await db.query('insert into public.stock_member_locations(organisation_id,membership_id,location_id,can_request,can_handle,can_approve,can_dispatch,can_receive) values($1,$2,$3,true,false,false,false,true)',[org,deptMember,kitchen]);await login(owner);
  const request=randomUUID(),data={topic:'COUNT',site_id:kitchen,outlet_id:outlet,title:'Investigate fish count difference',description:'Count reference: test evidence',assignee_id:deptMember,due_date:'2024-03-15',priority:'HIGH',state:'OPEN',note:'Check accepted transfers and source quantities.'};
  actionId=await val('select public.save_management_action($1,null,0,$2,$3)',[org,request,data]);assert.equal(await val('select public.save_management_action($1,null,0,$2,$3)',[org,request,data]),actionId);await rejects(val('select public.save_management_action($1,null,0,$2,$3)',[org,request,{...data,title:'Changed request'}]));
  const packet=await val("select public.management_actions($1,'OVERDUE',1,$2)",[org,actionId]);assert.match(packet.rows[0].assignee,/^Ada/);assert.equal(packet.rows[0].state,'OPEN');assert.equal(packet.rows[0].overdue,true);assert.equal(packet.events.length,1);assert.equal(Number(await raw('select count(*) from private.management_action_events where action_id=$1',[actionId])),1);
 });
 const detail=()=>val("select public.management_actions($1,'ALL',1,$2)",[org,actionId]);
 const update=async(state,note,extra={})=>{const a=(await detail()).rows[0];return val('select public.save_management_action($1,$2,$3,$4,$5)',[org,actionId,a.revision,randomUUID(),{...a,state,note,...extra}]);};
 await t.test('assigned colleagues update progress but cannot reassign, close, or edit evidence scope',async()=>{
  await login(dept);let a=(await detail()).rows[0];assert.equal(a.can_manage,false);assert.equal(a.can_progress,true);await update('IN_PROGRESS','Checking the original count and transfers.');await denied(update('CLOSED','Self close'));await denied(update('IN_PROGRESS','Change assignee',{assignee_id:ownerMember}));await denied(update('IN_PROGRESS','Move scope',{site_id:main,outlet_id:other}));
  await update('RESOLVED','Transfer was entered after counting; supporting reference checked.');assert.equal((await detail()).rows[0].state,'RESOLVED');await login(owner);await update('CLOSED','Reviewed supporting evidence; follow-up complete.');a=(await detail()).rows[0];assert.equal(a.state,'CLOSED');await rejects(update('IN_PROGRESS','Cannot edit closed action'));await update('OPEN','Reopened for another evidence check.');
 });
 await t.test('stale updates, invalid assignees and out-of-scope records are rejected',async()=>{
  const a=(await detail()).rows[0],data={...a,state:'IN_PROGRESS',note:'First concurrent update.'};await val('select public.save_management_action($1,$2,$3,$4,$5)',[org,actionId,a.revision,randomUUID(),data]);await rejects(val('select public.save_management_action($1,$2,$3,$4,$5)',[org,actionId,a.revision,randomUUID(),{...data,note:'Stale update'}]));
  await rejects(update('IN_PROGRESS','Invalid owner',{assignee_id:randomUUID()}));await login(scoped);await denied(val('select public.management_action_options($1,$2,$3,\'STOCK\')',[org,main,other]));await login(dept);await denied(val('select public.management_action_options($1,$2,$3,\'STOCK\')',[org,main,other]));await login(owner);
 });
 await t.test('calendar sales comparisons use the preceding month rather than an equal-day rolling window',async()=>{
  const pcs=await val("select id from public.units_of_measure where organisation_id=$1 and code='PCS'",[org]),prices=[{material_code:'FISH',quantity:'1',unit_code:'KG',total_price:'3000',price_date:'2020-01-01',source_note:'Fictional initial cost'}],preview=await val('select public.preview_material_reference_prices($1,$2)',[org,prices]);await val("select public.save_material_reference_prices($1,$2,'MANUAL',$3,$4)",[org,randomUUID(),prices,preview]);
  const recipe=await val("select public.publish_recipe_version($1,null,$2,'FISH_DISH','Fish dish','FINAL','2020-01-01',1,$3,'',$4)",[org,randomUUID(),pcs,[{kind:'ITEM',target_id:fish,quantity:'0.2',uom_id:kg}]]);await val("select public.publish_menu_item_version($1,null,$2,'FISH_PLATE','Fish plate',$3,'Mains',$4,1,'2020-01-01','')",[org,randomUUID(),brand,recipe]);
  const header='Organisation_Code,Source_System,Location_Code,Sale_Date,Transaction_Ref,Line_Ref,Menu_Name,Quantity,Gross_Sales,Discount,Tax,Net_Sales,Channel_Code,Line_Type,Parent_Line_Ref,Status';
  for(const[day,qty]of[['2024-02-15',1],['2024-03-15',2]]){const csv=header+'\n'+`ORG,POS,PRIMARY,${day},${day},1,Fish plate,${qty},${qty*6000},0,0,${qty*6000},DINE_IN,NORMAL,,PAID`,id=await val("select public.stage_sales_import($1,$2,'review.csv',$3,'ORG','EXCLUSIVE','NGN','{}')",[org,randomUUID(),csv]),report=await val('select public.get_sales_import($1,$2)',[org,id]);assert.equal(report.report.ready,1);await val('select public.post_sales_import($1,$2,$3)',[org,id,Object.fromEntries(report.report.receipts.map(r=>[r.key,r.total]))]);}
  const p=await pack('MONTHLY','2024-03-01');assert.equal(p.financial_previous.quantity,'1.000000');assert.equal(Number(p.financial_previous.net_revenue),6000);assert.equal(Number(p.financial.summary.net_revenue),12000);assert.equal(Number(p.financial.summary.estimated_food_margin),10800);assert.equal(p.live.pending_consumption,2);assert.equal(p.live.last_sale_date,'2024-03-15');
 });
 await t.test('personal saved reviews freeze figures, are idempotent, and cannot cross accounts',async()=>{
  const request=randomUUID();snapshot=await val("select public.save_management_review($1,'DAILY',$2,null,null,$3)",[org,today,request]);assert.equal(await val("select public.save_management_review($1,'DAILY',$2,null,null,$3)",[org,today,request]),snapshot);
  const saved=await val('select public.management_review_history($1,$2)',[org,snapshot]);const frozen=JSON.stringify(saved.payload);await update('RESOLVED','Updated after the saved review.');
  await db.exec('reset role');const doc=await val("insert into public.stock_documents(organisation_id,request_id,input_hash,reference,kind,state,source_id,document_date,note,lines,created_by) values($1,$2,'fixture','WASTE-AFTER-SAVE','WASTE','POSTED',$3,$4,'Fixture report evidence','[]',$5) returning id",[org,randomUUID(),kitchen,today,owner]);await db.query("insert into private.waste_value_snapshots(organisation_id,document_id,item_id,source,quantity,unit_cost,estimated_value,cost_basis) values($1,$2,$3,'WASTE',2,3000,6000,'TEST_SNAPSHOT')",[org,doc,fish]);await login(owner);
  assert.equal((await pack('DAILY',today)).current.waste.entries,saved.payload.current.waste.entries+1);assert.equal(JSON.stringify((await val('select public.management_review_history($1,$2)',[org,snapshot])).payload),frozen);assert.equal((await val('select public.management_review_history($1)',[org])).total,1);
  await login(ops);await denied(val('select public.management_review_history($1,$2)',[org,snapshot]));await login(owner);
 });
 await t.test('Inventory waste stays within owned centres; action scope cannot bypass it',async()=>{
  await db.exec('reset role');const im=await val('select id from public.organisation_memberships where organisation_id=$1 and user_id=$2',[org,inventory]);await db.query('update public.stock_locations set responsible_membership_id=$1 where id=$2',[im,kitchen]);await login(inventory);const p=await pack('DAILY',today);assert.equal(p.current.waste.centres,1);await denied(val("select public.management_action_options($1,$2,$3,'WASTE')",[org,main,other]));await login(owner);
 });
 await t.test('saved operational reviews cannot retain revoked purchase or reference-price access',async()=>{
  await db.exec('reset role');await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,'procurement')",[org,deptMember]);await login(dept);
  const id=await val("select public.save_management_review($1,'DAILY',$2,null,null,$3)",[org,today,randomUUID()]);assert.equal((await val('select public.management_review_history($1,$2)',[org,id])).payload.access.reference_financial,true);
  await db.exec('reset role');await db.query("delete from public.membership_roles where organisation_id=$1 and membership_id=$2 and role_code='procurement'",[org,deptMember]);await login(dept);await denied(val('select public.management_review_history($1,$2)',[org,id]));await login(owner);
 });
 await t.test('losing responsibility for a centre revokes old stock-value snapshots without losing ordinary stock read access',async()=>{
  await db.exec('reset role');const im=await val('select id from public.organisation_memberships where organisation_id=$1 and user_id=$2',[org,inventory]);await db.query('update public.stock_locations set responsible_membership_id=$1 where id=$2',[deptMember,kitchen]);await login(dept);
  const id=await val("select public.save_management_review($1,'DAILY',$2,null,null,$3)",[org,today,randomUUID()]);assert.equal((await val('select public.management_review_history($1,$2)',[org,id])).payload.stock_now.centre_count,1);
  await db.exec('reset role');await db.query('update public.stock_locations set responsible_membership_id=$1 where id=$2',[im,kitchen]);await login(dept);assert.equal((await val('select public.management_review_access($1)',[org])).centres.length,1);await denied(val('select public.management_review_history($1,$2)',[org,id]));await login(owner);
 });
 await t.test('centre assignments narrow Operations reviews and lost access blocks snapshots',async()=>{
  await db.exec('reset role');await db.query("insert into public.stock_member_access(organisation_id,membership_id,mode,updated_by) values($1,$2,'ASSIGNED',$3)",[org,opsMember,owner]);await db.query('insert into public.stock_member_locations(organisation_id,membership_id,location_id,can_request,can_handle,can_approve,can_dispatch,can_receive) values($1,$2,$3,false,false,false,false,false)',[org,opsMember,kitchen]);await login(ops);const restricted=await pack('DAILY',today);assert.equal(restricted.stock_now.centre_count,1);for(const section of ['waste','processing','movements'])assert.equal(section in restricted.financial,false);await denied(pack('DAILY',today,null,main));
  await db.exec('reset role');await db.query("update public.organisation_memberships set status='inactive' where id=$1",[scopedMember]);await login(scoped);await denied(pack());await login(owner);
  await db.exec('reset role');await db.query("delete from public.membership_roles where organisation_id=$1 and membership_id=$2",[org,ownerMember]);await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,'stock_department',$3)",[org,ownerMember,outlet]);await login(owner);await denied(val('select public.management_review_history($1,$2)',[org,snapshot]));
 });
 await t.test('anonymous and cross-tenant reads are denied, private data stays private, and reviews/actions never post stock',async()=>{
  await login(outsider);await denied(pack());await denied(val("select public.management_actions($1,'ALL')",[org]));await db.exec('reset role;set role anon');await denied(pack());await db.exec('reset role;set role authenticated');await denied(val('select * from private.management_actions'));await db.exec('reset role');assert.equal(Number(await val('select count(*) from public.stock_ledger where organisation_id=$1',[org])),0);
 });
 }finally{await db.close();}
});
