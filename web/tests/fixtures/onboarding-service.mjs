// Local-only Supabase substitute. Auth is simulated; database/RLS/RPCs are real
// PostgreSQL (PGlite) running the tracked migrations. Never deploy this file.
import { createServer } from "node:http";
import { createHmac } from "node:crypto";
import { readFile, readdir } from "node:fs/promises";
import { PGlite } from "@electric-sql/pglite";

const db = new PGlite();
await db.exec(`create role anon; create role authenticated; create schema auth;
create table auth.users(id uuid primary key,email_confirmed_at timestamptz,email text);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema public,auth to authenticated,anon; grant execute on function auth.uid() to authenticated,anon;`);
for (const migration of (await readdir(new URL("../../supabase/migrations/", import.meta.url))).filter(name => name.endsWith(".sql")).sort())
  await db.exec(await readFile(new URL(`../../supabase/migrations/${migration}`, import.meta.url), "utf8"));
const emailRequests=[];
const users = [
  {id:"00000000-0000-0000-0000-000000000023",email:"channels-owner@example.test"},
  {id:"00000000-0000-0000-0000-000000000020",email:"invited-kitchen@example.test"},
  {id:"00000000-0000-0000-0000-000000000021",email:"invited-verify@example.test"},
  {id:"00000000-0000-0000-0000-000000000022",email:"invited-email-failure@example.test"},
  {id:"00000000-0000-0000-0000-000000000017",email:"training-owner@example.test"},
  {id:"00000000-0000-0000-0000-000000000018",email:"training-chef@example.test"},
  {id:"00000000-0000-0000-0000-000000000019",email:"training-manager@example.test"},
  { id: "00000000-0000-0000-0000-000000000015", email: "kitchen-process@example.test" },
  { id: "00000000-0000-0000-0000-000000000016", email: "bar-process@example.test" },
  { id: "00000000-0000-0000-0000-000000000014", email: "inventory-manager@example.test" },
  { id: "00000000-0000-0000-0000-000000000012", email: "department-kitchen@example.test" },
  { id: "00000000-0000-0000-0000-000000000013", email: "department-bar@example.test" },
  { id: "00000000-0000-0000-0000-000000000011", email: "stock-receiver@example.test" },
  { id: "00000000-0000-0000-0000-000000000010", email: "receiving-invite@example.test" },
  { id: "00000000-0000-0000-0000-000000000009", email: "inventory@example.test" },
  { id: "00000000-0000-0000-0000-000000000001", email: "founder@example.test" },
  { id: "00000000-0000-0000-0000-000000000002", email: "owner@example.test" },
  { id: "00000000-0000-0000-0000-000000000003", email: "other@example.test" },
  { id: "00000000-0000-0000-0000-000000000005", email: "catalogue@example.test" },
  { id: "00000000-0000-0000-0000-000000000006", email: "reader@example.test" },
  { id: "00000000-0000-0000-0000-000000000007", email: "staff@example.test" },
  { id: "00000000-0000-0000-0000-000000000008", email: "procurement@example.test" },
];
for (const user of users) await db.query("insert into auth.users values ($1,now(),$2)", [user.id,user.email]);
await db.query("insert into private.platform_admins(user_id) values ($1)", [users.find(user => user.email === "founder@example.test").id]);
const token = user => {
  const encode = value => Buffer.from(JSON.stringify(value)).toString("base64url");
  const body = `${encode({ alg: "HS256", typ: "JWT" })}.${encode({ sub: user.id, aud: "authenticated", role: "authenticated", email: user.email, exp: Math.floor(Date.now() / 1000) + 3600 })}`;
  return `${body}.${createHmac("sha256", "local-test-only").update(body).digest("base64url")}`;
};
const authUser = user => ({ ...user, aud: "authenticated", role: "authenticated", app_metadata: {}, user_metadata: {}, email_confirmed_at: new Date().toISOString(), created_at: new Date().toISOString() });
const session = user => ({ access_token: token(user), refresh_token: `refresh-${user.id}`, token_type: "bearer", expires_in: 3600, user: authUser(user) });
let queue = Promise.resolve();
function asUser(user, work) {
  const next = queue.then(() => db.transaction(async tx => {
    await tx.exec("set local role authenticated");
    await tx.query("select set_config('request.jwt.claim.sub',$1,true)", [user.id]);
    return work(tx);
  }));
  queue = next.catch(() => {});
  return next;
}

const catalogueOwner = users.find(user => user.email === "catalogue@example.test");
await asUser(catalogueOwner, async tx => {
  await tx.query("select public.save_restaurant_setup('Catalogue Test Restaurant','QSR','NG','NGN','Catalogue Brand','Main outlet','Africa/Lagos','',3)");
  const org = (await tx.query("select public.complete_restaurant_setup() as id")).rows[0].id;
  await tx.query("select public.save_menu_categories($1,0,$2)",[org,JSON.stringify([{major:'FOOD',name:'Mains',is_active:true},{major:'FOOD',name:'Sides',is_active:true},{major:'DRINK',name:'Soft drinks',is_active:true}])]);
  await tx.query("select public.save_catalogue_supplier($1,null,'SUP-IMPORT','Import Test Foods','','','',true)", [org]);
  const kg = (await tx.query("select id from public.units_of_measure where organisation_id=$1 and code='KG'", [org])).rows[0].id;
  for (let index = 1; index <= 26; index++) await tx.query("select public.save_catalogue_material($1,null,$2,$3,'RAW','Core',$4,true,true)", [org, `SAMPLE${index}`, `Ingredient ${String(index).padStart(2, "0")}`, kg]);
  const pcs = (await tx.query("select id from public.units_of_measure where organisation_id=$1 and code='PCS'", [org])).rows[0].id;
  for (const [code,name,priced] of [["MENU-MATERIAL","Menu priced ingredient",true],["MENU-UNPRICED","Menu missing ingredient",false]]) {
    const item=(await tx.query("select public.save_catalogue_material($1,null,$2,$3,'RAW','Menu test',$4,true,true)",[org,code,name,kg])).rows[0].save_catalogue_material;
    const recipeId=(await tx.query("select public.publish_recipe_version($1,null,$2,$3,$4,'FINAL','2020-01-01',1,$5,'',$6::jsonb) as id",[org,crypto.randomUUID(),priced?"MENU-RECIPE":"MENU-MISSING-RECIPE",priced?"Menu cost recipe":"Menu unpriced recipe",pcs,JSON.stringify([{kind:"ITEM",target_id:item,quantity:"1",uom_id:kg}])])).rows[0].id;
    if(priced){
      const brand=(await tx.query("select id from public.brands where organisation_id=$1 limit 1",[org])).rows[0].id;
      await tx.query("select public.publish_menu_item_version($1,null,$2,'SALES-MENU','Sales test dish',$3,'Mains',$4,1,'2020-01-01','Fictional sales fixture')",[org,crypto.randomUUID(),brand,recipeId]);
      const prices=[{material_code:code,quantity:"1",unit_code:"KG",total_price:"900",price_date:"2020-01-01",source_note:"Fictional menu cost fixture"}];
      const prepared=(await tx.query("select public.preview_material_reference_prices($1,$2::jsonb) as data",[org,JSON.stringify(prices)])).rows[0].data;
      await tx.query("select public.save_material_reference_prices($1,$2,'MANUAL',$3::jsonb,$4::jsonb)",[org,crypto.randomUUID(),JSON.stringify(prices),JSON.stringify(prepared)]);
    }
  }
  await tx.query("select public.save_catalogue_material($1,null,'TEST-BOX','Test packaging','PACKAGING','Packaging',$2,true,true)", [org,pcs]);
  const missingMaterial=(await tx.query("select public.save_catalogue_material($1,null,'SALES-UNCOSTED','Sales unpriced ingredient','RAW','Sales test',$2,true,true)",[org,kg])).rows[0].save_catalogue_material;
  const missingRecipe=(await tx.query("select public.publish_recipe_version($1,null,$2,'SALES-UNPRICED-RECIPE','Sales unpriced recipe','FINAL','2020-01-01',1,$3,'',$4::jsonb) as id",[org,crypto.randomUUID(),pcs,JSON.stringify([{kind:"ITEM",target_id:missingMaterial,quantity:"1",uom_id:kg}])])).rows[0].id;
  const salesBrand=(await tx.query("select id from public.brands where organisation_id=$1 limit 1",[org])).rows[0].id;
  await tx.query("select public.publish_menu_item_version($1,null,$2,'SALES-NOCOST','Sales uncosted dish',$3,'Mains',$4,1,'2020-01-01','Fictional missing-cost sales')",[org,crypto.randomUUID(),salesBrand,missingRecipe]);

});
await asUser(catalogueOwner,async tx=>{
 const org=(await tx.query('select id from public.organisations where owner_id=$1',[catalogueOwner.id])).rows[0].id;
 await tx.query('select public.save_cost_targets($1,null,40,25)',[org]);
 for(const menu of(await tx.query('select id from public.menu_items where organisation_id=$1',[org])).rows)await tx.query("select public.save_setup_profile($1,'MENU',$2,null,'FOOD','Mains',false,'PURCHASED')",[org,menu.id]);
});
const catalogueOrg = (await db.query("select id from public.organisations where owner_id=$1", [catalogueOwner.id])).rows[0].id;
const readerId = users.find(user => user.email === "reader@example.test").id;
const readerMember = (await db.query("insert into public.organisation_memberships(organisation_id,user_id) values ($1,$2) returning id", [catalogueOrg, readerId])).rows[0].id;
await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code) values ($1,$2,'finance')", [catalogueOrg, readerMember]);

const procurementId=users.find(user=>user.email==='procurement@example.test').id;
const procurementMember=(await db.query('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[catalogueOrg,procurementId])).rows[0].id;
await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,'procurement')",[catalogueOrg,procurementMember]);
const inventoryId=users.find(user=>user.email==='inventory@example.test').id;
const inventoryMember=(await db.query('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[catalogueOrg,inventoryId])).rows[0].id;
await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,'inventory')",[catalogueOrg,inventoryMember]);
const stockReceiverMember=(await db.query('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[catalogueOrg,users.find(u=>u.email==='stock-receiver@example.test').id])).rows[0].id;
const stockOutlet=(await db.query('select id from public.locations where organisation_id=$1 limit 1',[catalogueOrg])).rows[0].id;
await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,'inventory',$3)",[catalogueOrg,stockReceiverMember,stockOutlet]);
for(const email of ['department-kitchen@example.test','department-bar@example.test']){
 const membership=(await db.query('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[catalogueOrg,users.find(u=>u.email===email).id])).rows[0].id;
 await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,'inventory',$3)",[catalogueOrg,membership,stockOutlet]);
}
const managerMember=(await db.query('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[catalogueOrg,users.find(u=>u.email==='inventory-manager@example.test').id])).rows[0].id;
await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code) values($1,$2,'inventory_manager')",[catalogueOrg,managerMember]);
for(const email of ['kitchen-process@example.test','bar-process@example.test']){
 const m=(await db.query('insert into public.organisation_memberships(organisation_id,user_id) values($1,$2) returning id',[catalogueOrg,users.find(u=>u.email===email).id])).rows[0].id;
 await db.query("insert into public.membership_roles(organisation_id,membership_id,role_code,location_id) values($1,$2,'stock_department',$3)",[catalogueOrg,m,stockOutlet]);
}
createServer(async (request, response) => {
  const send = (status, data, headers = {}) => { response.writeHead(status, { "Content-Type": "application/json", "Cache-Control": "no-store", ...headers }); response.end(JSON.stringify(data)); };
  try {
    let text = "";
    for await (const chunk of request) text += chunk;
    const body = text ? JSON.parse(text) : {};
    const url = new URL(request.url, "http://localhost");
    const bearer = request.headers.authorization?.replace("Bearer ", "");
    let user;
    if (bearer) {
      const [header, payload, signature] = bearer.split(".");
      if (signature === createHmac("sha256", "local-test-only").update(`${header}.${payload}`).digest("base64url")) {
        const claims = JSON.parse(Buffer.from(payload, "base64url").toString());
        if (claims.exp > Date.now() / 1000) user = users.find(candidate => candidate.id === claims.sub);
      }
    }
    if (url.pathname === "/auth/v1/token") {
      const account = users.find(candidate => candidate.email === body.email);
      return account && body.password === "TestPassword123!" ? send(200, session(account)) : send(400, { code: "invalid_credentials", msg: "Invalid credentials" });
    }
    if(url.pathname==="/auth/v1/otp"){emailRequests.push({email:body.email,redirect_to:url.searchParams.get("redirect_to"),code_challenge:body.code_challenge??null});return body.email==="invited-email-failure@example.test"?send(429,{code:"over_email_send_rate_limit",error_code:"over_email_send_rate_limit",msg:"Email rate limit exceeded"}):send(200,{});}
    if(url.pathname==="/auth/v1/verify"&&body.token_hash==="test-verified-invitation")return send(200,session(users.find(u=>u.email==="invited-verify@example.test")));
    if (url.pathname === "/auth/v1/signup") return send(200, { id: "00000000-0000-0000-0000-000000000004", email: body.email, identities: [], app_metadata: {}, user_metadata: {}, created_at: new Date().toISOString() });
    if (url.pathname === "/auth/v1/user") return user ? send(200, authUser(user)) : send(401, { code: "bad_jwt", msg: "Invalid token" });
    if (url.pathname === "/auth/v1/logout") return send(200, {});
    if(url.pathname==="/__test/email-requests"&&user?.email==="catalogue@example.test")return send(200,emailRequests);
    if (!user) return send(401, { code: "42501", message: "Authentication required" });
    if (url.pathname.startsWith("/rest/v1/rpc/")) {
      const functionName = url.pathname.split("/").at(-1);
      const definitions = {
        is_platform_admin: [], complete_restaurant_setup: [], complete_restaurant_setup_with_calendar: [], account_restaurant_access: [],
        save_setup_calendar: ['p_week_start','p_count_day','p_cutoff'],
        save_reporting_calendar: ['p_organisation_id','p_timezone','p_week_start','p_count_day','p_cutoff'],
        reporting_calendar: ['p_organisation_id'],
        set_restaurant_access: ['p_organisation_id','p_expected_state','p_state','p_reason','p_confirmed'],
        material_monthly_prices: ['p_organisation_id','p_month','p_search','p_page'],
        material_cost_estimates: ['p_organisation_id','p_ids','p_as_of'],
        processing_setup: ['p_organisation_id'],
        processing_output_choices: ['p_organisation_id','p_search','p_version_id'],
        processing_recipe_inputs: ['p_organisation_id','p_version_id'],
        save_stock_centre: ['p_organisation_id','p_value'],
        save_stock_centre_with_access: ['p_organisation_id','p_value','p_enable_owner','p_revision','p_owner_tasks'],
        save_processing_standard: ['p_organisation_id','p_request_id','p_value'],
        complete_waste_record: ['p_organisation_id','p_document_id','p_submitter_name'],
        centre_waste_report: ['p_organisation_id','p_site_id','p_from','p_to','p_kind','p_page','p_state','p_export'],
        submit_material_processing: ['p_organisation_id','p_submission_id','p_value'],
        complete_processing_record: ['p_organisation_id','p_document_id','p_submitter_name'],
        processing_activity: ['p_organisation_id','p_site_id','p_from','p_to','p_kind','p_page','p_state'],
        save_management_report: ["p_organisation_id","p_from","p_to","p_location_id","p_request_id","p_title"],
        stage_manual_purchase: ["p_organisation_id","p_request_id","p_invoice","p_lines"],
        purchase_order_access: ["p_organisation_id","p_order_id"],
        save_purchase_order: ["p_organisation_id","p_order_id","p_request_id","p_revision","p_document","p_lines"],
        issue_purchase_order: ["p_organisation_id","p_order_id","p_revision","p_confirmed"],
        record_goods_receipt: ["p_organisation_id","p_order_id","p_request_id","p_document","p_lines","p_confirmed"],
        review_goods_receipt_void: ["p_organisation_id","p_receipt_id","p_request_id","p_reason","p_decision","p_note"],
        get_purchase_order: ["p_organisation_id","p_order_id"],list_purchase_orders: ["p_organisation_id","p_page"],list_purchase_order_register: ["p_organisation_id","p_page","p_status"],purchase_order_choices: ["p_organisation_id","p_search","p_selected"],
        set_invoice_procurement_context: ["p_organisation_id","p_purchase_id","p_request_id","p_invoice_revision","p_context","p_mappings"],
        purchase_invoice_matching: ["p_organisation_id","p_purchase_id"],
        review_invoice_exceptions: ["p_organisation_id","p_purchase_id","p_request_id","p_fingerprint","p_decision","p_note","p_confirmed"],
        purchase_invoice_list: ["p_organisation_id","p_page"], purchase_invoice_detail: ["p_organisation_id","p_purchase_id"],
        request_purchase_correction: ["p_organisation_id","p_purchase_id","p_request_id","p_revision","p_kind","p_reason","p_invoice","p_lines"],
        decide_purchase_correction: ["p_organisation_id","p_correction_id","p_approve","p_note"],
        review_management_report: ["p_organisation_id","p_report_id","p_request_id","p_expected_revision","p_action","p_note","p_acknowledged"],
        get_management_report_review: ["p_organisation_id","p_report_id","p_page"],
        get_management_report: ["p_organisation_id","p_report_id"], list_management_reports: ["p_organisation_id","p_page"],
        expense_access: ["p_organisation_id"], list_expense_categories: ["p_organisation_id"],
        create_expense_category: ["p_organisation_id","p_code","p_name","p_kind"],
        stage_expense_import: ["p_organisation_id","p_request_id","p_filename","p_csv","p_source_org"],
        get_expense_import: ["p_organisation_id","p_batch_id"], expense_import_source: ["p_organisation_id","p_batch_id"],
        expense_import_history: ["p_organisation_id","p_page"], post_expense_import: ["p_organisation_id","p_batch_id","p_source_control"],
        void_expense_entry: ["p_organisation_id","p_entry_id","p_reason"],
        review_expense_coverage: ["p_organisation_id","p_from","p_to","p_location_id","p_kind","p_confirmed"],
        expense_period_report: ["p_organisation_id","p_from","p_to","p_location_id","p_page"],
        workspace_navigation_access: ["p_organisation_id"],
        stock_workspace: ["p_organisation_id", "p_location_id", "p_page"],
        stock_workspace_v2: ["p_organisation_id","p_location_id","p_page","p_status","p_search","p_document_id"],
        opening_readiness: ["p_organisation_id","p_page"],
        setup_workspace: ["p_organisation_id"],
        setup_profiles: ["p_organisation_id","p_kind","p_ids"],
        save_cost_targets: ["p_organisation_id","p_location_id","p_food","p_beverage"],
        confirm_zero_opening: ["p_organisation_id","p_item_id","p_site_id","p_date","p_note"],
        save_setup_profile: ["p_organisation_id","p_kind","p_id","p_location_id","p_primary","p_subcategory","p_weekly","p_supply"],
        save_material_setup: ["p_organisation_id","p_value"],
        save_menu_setup: ["p_organisation_id","p_request_id","p_value"],
        publish_recipe_setup: ["p_organisation_id","p_request_id","p_value","p_components"],
        workspace_attention: ["p_organisation_id","p_queue","p_page"],
        mark_workspace_grns_reviewed: ["p_organisation_id","p_receipts"],
        platform_workspace: ["p_search","p_state","p_page","p_organisation_id"],
        stock_workspace_alerts: ["p_organisation_id"],
        stock_access_directory: ["p_organisation_id"],
        save_stock_member_access: ["p_organisation_id", "p_membership_id", "p_revision", "p_mode", "p_assignments"],
        save_stock_configuration: ["p_organisation_id", "p_kind", "p_value"],
        po_last_purchase_price: ["p_organisation_id","p_item_id","p_uom_id","p_as_of"],
        request_stock_document: ["p_organisation_id", "p_request_id", "p_document", "p_lines"],
        stock_document_action: ["p_organisation_id", "p_document_id", "p_action", "p_note", "p_received"],
        executive_overview: ["p_organisation_id","p_from","p_to","p_location_id"],
        executive_profitability_briefing: ["p_organisation_id","p_from","p_to","p_location_id"],
        operational_report_options: ["p_organisation_id","p_type"],
        operational_report: ["p_organisation_id","p_type","p_from","p_to","p_outlet_id","p_stock_location_id","p_status","p_search","p_page","p_export"],
        purchasing_report_options: ["p_organisation_id","p_type"],
        purchasing_history_report: ["p_organisation_id","p_type","p_view","p_from","p_to","p_outlet_id","p_supplier_id","p_item_id","p_user_id","p_status","p_receiving","p_search","p_page","p_export"],
        save_member_name: ["p_organisation_id","p_membership_id","p_name"],
        pending_team_invitations: [],accept_pending_team_invitation:["p_invitation_id"],team_invitation_email:["p_organisation_id","p_invitation_id","p_status"],
        invite_team_member_with_centres:["p_organisation_id","p_request_id","p_email","p_name","p_assignments","p_stock_access"],
        invite_named_team_member: ["p_organisation_id","p_request_id","p_email","p_name","p_assignments"],
        set_processing_unit: ["p_organisation_id","p_centre_id"],
        save_processing_centres: ["p_organisation_id","p_centre_ids","p_revision"],
        material_plan_options: ["p_organisation_id","p_site_id","p_date"],
        generate_material_plan: ["p_organisation_id","p_site_id","p_date","p_rows","p_basis"],
        save_material_processing_baseline: ["p_organisation_id","p_request_id","p_value"],
        team_access: ["p_organisation_id"],
        team_directory: ["p_organisation_id","p_search","p_page","p_invite_page"],
        create_team_invitation: ["p_organisation_id","p_request_id","p_email","p_assignments"],
        revoke_team_invitation: ["p_organisation_id","p_invitation_id"],
        update_team_member: ["p_organisation_id","p_membership_id","p_expected_updated_at","p_active","p_assignments"],
        inspect_team_invitation: ["p_token"], accept_team_invitation: ["p_token"],
        save_restaurant_setup: ["p_business_name", "p_concept", "p_country_code", "p_currency_code", "p_brand_name", "p_location_name", "p_timezone", "p_address", "p_step"],
        purchase_import_access: ["p_organisation_id"],
        stage_purchase_import: ["p_organisation_id", "p_request_id", "p_filename", "p_csv", "p_source_org", "p_price_basis", "p_mappings"],
        post_purchase_import: ["p_organisation_id", "p_batch_id", "p_controls"],
        purchase_import_history: ["p_organisation_id", "p_page"],
        get_purchase_import: ["p_organisation_id", "p_batch_id"],
        purchase_import_source: ["p_organisation_id", "p_batch_id"],
        cancel_purchase_import: ["p_organisation_id", "p_batch_id"],
        sales_import_access: ["p_organisation_id"],
        stage_sales_import: ["p_organisation_id", "p_request_id", "p_filename", "p_csv", "p_source_org", "p_net_basis", "p_currency", "p_mappings"],
        post_sales_import: ["p_organisation_id", "p_batch_id", "p_controls"],
        sales_import_history: ["p_organisation_id", "p_page"],
        get_sales_import: ["p_organisation_id", "p_batch_id"],
        sales_import_source: ["p_organisation_id", "p_batch_id"],
        cancel_sales_import: ["p_organisation_id", "p_batch_id"],
        sales_period_summary: ["p_organisation_id", "p_from", "p_to", "p_location_id"],
        menu_access: ["p_organisation_id"],
        sales_channels: ["p_organisation_id"],
        save_sales_channels: ["p_organisation_id","p_revision","p_channels"],
        save_setup_sales_channels: ["p_channels"],
        complete_restaurant_setup_with_channels: [],
        menu_profitability_scope: ["p_organisation_id","p_location_id","p_channel","p_as_of"],
        waste_reporting_setup:['p_organisation_id'],save_waste_reporting_schedule:['p_organisation_id','p_site_id','p_revision','p_effective_from','p_days','p_cutoff','p_day_offset'],
        waste_daily_report:['p_organisation_id','p_site_id','p_from','p_to','p_state','p_page','p_export'],waste_compliance_workspace:['p_organisation_id'],waste_day_history:['p_organisation_id','p_site_id','p_day'],
        confirm_waste_day:['p_organisation_id','p_site_id','p_day','p_outcome','p_submitter','p_revision','p_evidence','p_request_id','p_reason'],waste_analysis:['p_organisation_id','p_site_id','p_from','p_to'],
        menu_categories:['p_organisation_id'],save_menu_categories:['p_organisation_id','p_revision','p_categories'],save_setup_menu_categories:['p_categories'],complete_restaurant_setup_with_categories:[],
        selling_menu_profitability:['p_organisation_id','p_location_id','p_channel','p_as_of','p_search','p_page','p_status','p_major','p_subcategory'],menu_margin_for_scope:['p_organisation_id','p_version_id','p_location_id','p_channel','p_as_of'],save_menu_entry:['p_organisation_id','p_request_id','p_value'],
        preview_menu_catalogue_import:['p_organisation_id','p_location_id','p_rows'],post_menu_catalogue_import:['p_organisation_id','p_location_id','p_request_id','p_rows','p_preview'],
        profitability_items_dashboard: ["p_organisation_id","p_location_id","p_channel","p_as_of","p_search","p_page","p_status","p_kind"],
        menu_profitability_dashboard: ["p_organisation_id","p_location_id","p_channel","p_as_of","p_search","p_page","p_status"],
        menu_profitability: ["p_organisation_id","p_location_id","p_channel","p_as_of","p_search","p_page"],
        search_menu_recipes: ["p_organisation_id", "p_search", "p_page"],
        publish_menu_item_version: ["p_organisation_id", "p_menu_id", "p_request_id", "p_code", "p_name", "p_brand_id", "p_category", "p_recipe_version_id", "p_recipe_quantity", "p_effective_from", "p_notes"],
        set_menu_item_active: ["p_organisation_id", "p_menu_id", "p_active"],
        save_menu_selling_price: ["p_organisation_id", "p_menu_id", "p_request_id", "p_location_id", "p_channel", "p_price", "p_tax_setting", "p_tax_percent", "p_effective_from", "p_effective_to", "p_notes"],
        get_menu_item: ["p_organisation_id", "p_menu_id", "p_version_id"],
        menu_food_margin_estimate: ["p_organisation_id", "p_version_id", "p_location_id", "p_channel", "p_as_of"],
        can_manage_catalogue: ["p_organisation_id"],
        reference_price_access: ["p_organisation_id"],
        material_reference_price_coverage: ["p_organisation_id", "p_item_ids"],
        preview_material_reference_prices: ["p_organisation_id", "p_rows"],
        save_material_reference_prices: ["p_organisation_id", "p_request_id", "p_source", "p_rows", "p_preview"],
        list_material_reference_prices: ["p_organisation_id", "p_search", "p_page", "p_item_id"],
        save_catalogue_material: ["p_organisation_id", "p_id", "p_code", "p_name", "p_item_type", "p_category", "p_base_uom_id", "p_stock_tracked", "p_is_active"],
        save_catalogue_supplier: ["p_organisation_id", "p_id", "p_code", "p_name", "p_email", "p_phone", "p_address", "p_is_active"],
        save_material_conversion: ["p_organisation_id", "p_item_id", "p_from_uom_id", "p_factor", "p_effective_from"],
        can_manage_recipes: ["p_organisation_id"],
        publish_recipe_version: ["p_organisation_id", "p_recipe_id", "p_request_id", "p_code", "p_name", "p_recipe_type", "p_effective_from", "p_yield_quantity", "p_yield_uom_id", "p_notes", "p_components"],
        search_recipe_components: ["p_organisation_id", "p_kind", "p_search", "p_page"],
        get_recipe_version: ["p_organisation_id", "p_version_id"],
        recipe_reference_cost_estimate: ["p_organisation_id", "p_version_id", "p_as_of", "p_output_quantity"],
        recipe_material_requirements: ["p_organisation_id", "p_version_id", "p_output_quantity"],
      };
      const keys = definitions[functionName];
      if (!keys) return send(404, { code: "PGRST202", message: "Function missing" });
      const rows = await asUser(user, tx => tx.query(`select public.${functionName}(${keys.map((_, index) => `$${index + 1}`).join(",")}) as value`, keys.map(key => body[key])));
      return send(200, rows.rows[0].value);
    }
    const table = url.pathname.replace("/rest/v1/", "");
    const columns = {
      organisations: ["id", "name", "currency_code", "country_code", "concept", "time_zone"],
      organisation_memberships: ["id", "organisation_id", "user_id", "status", "display_name"],
      membership_roles: ["id", "organisation_id", "membership_id", "role_code", "location_id"],
      brands: ["id", "name", "organisation_id"],
      locations: ["id", "name", "code", "timezone", "address", "is_active", "brand_id", "organisation_id"],
      restaurant_setup_drafts: ["user_id", "business_name", "concept", "country_code", "currency_code", "brand_name", "location_name", "timezone", "address", "reporting_week_start", "count_day", "count_cutoff", "sales_channels", "menu_categories", "step", "completed_organisation_id"],
      units_of_measure: ["id", "organisation_id", "code", "name", "dimension"],
      item_categories: ["id", "organisation_id", "name"],
      items: ["id", "organisation_id", "code", "name", "item_type", "category_id", "base_uom_id", "stock_tracked", "is_active", "location_id", "weekly_count_required", "supply_class", "requires_processing"],
      suppliers: ["id", "organisation_id", "code", "name", "email", "phone", "address", "is_active"],
      item_uom_conversions: ["id", "organisation_id", "item_id", "from_uom_id", "to_uom_id", "factor", "effective_from"],
      menu_items: ["id", "organisation_id", "code", "name", "brand_id", "is_active", "location_id", "primary_category", "subcategory"],
      menu_item_versions: ["id", "organisation_id", "menu_item_id"],
      recipes: ["id", "organisation_id", "code", "name", "recipe_type", "location_id"],
      recipe_versions: ["id", "organisation_id", "recipe_id", "version", "name", "effective_from"],
    }[table];
    if (!columns) return send(404, { code: "42P01", message: "Unknown table" });
    const selected = (url.searchParams.get("select") || "").split(",");
    if (selected.some(column => !columns.includes(column))) return send(400, { message: "Unknown column" });
    const filters = [], values = [];
    for (const column of columns) {
      const value = url.searchParams.get(column);
      if (value?.startsWith("eq.")) { values.push(value.slice(3)); filters.push(`${column}=$${values.length}`); }
      else if (value?.startsWith("ilike.")) { values.push(value.slice(6)); filters.push(`${column} ilike $${values.length}`); }
    }
    const where = filters.length ? ` where ${filters.join(" and ")}` : "";
    const order = (url.searchParams.get("order") || "").split(",").filter(Boolean).map(entry => {
      const [column,direction] = entry.split(".");
      if (!columns.includes(column)) throw new Error("Invalid test ordering");
      return `${column} ${direction === "desc" ? "desc" : "asc"}`;
    });
    const limit = Math.min(1000, Math.max(0, Number(url.searchParams.get("limit") ?? 1000)));
    const offset = Math.max(0, Number(url.searchParams.get("offset") ?? 0));
    const result = await asUser(user, async tx => ({
      rows: (await tx.query(`select ${selected.join(",")} from public.${table}${where}${order.length ? ` order by ${order.join(",")}` : ""} limit ${limit} offset ${offset}`, values)).rows,
      total: (await tx.query(`select count(*)::int as total from public.${table}${where}`, values)).rows[0].total,
    }));
    if (request.headers.accept?.includes("application/vnd.pgrst.object+json")) {
      return result.rows.length === 1 ? send(200, result.rows[0]) : send(406, { code: "PGRST116", message: "Expected one row" });
    }
    return send(200, result.rows, { "Content-Range": `${offset}-${offset + result.rows.length - 1}/${result.total}` });
  } catch (error) { send(400, { code: error.code ?? "TEST_ERROR", message: error.message }); }
}).listen(54398, "127.0.0.1", () => console.log("MOCK_READY"));
