import type { NavigationAccess } from "./overview";
type Role = { role_code: string; location_id: string | null };
type Task = { title: string; description: string; action: string; path: string };

export function workspaceNavigation(roles: Role[], access: NavigationAccess): NavigationAccess {
  const procurement = roles.some(role => role.role_code === "procurement");
  const otherModuleRole = roles.some(role => ["ceo", "finance", "restaurant_admin", "operations"].includes(role.role_code));
  const stockRole=roles.some(role=>["ceo","finance","restaurant_admin","operations","inventory_manager","inventory","stock_department","kitchen_manager","bar_lead","stock_receiver","stock_dispatcher"].includes(role.role_code));
  return procurement ? {...access,...(!otherModuleRole?{recipes:false,menus:false}:{}),...(!stockRole?{inventory:false}:{})} : access;
}

// Membership roles determine the welcome; server capabilities determine links.
export function workspaceHome(roles: Role[], access: NavigationAccess) {
  access = workspaceNavigation(roles, access);
  const has = (code: string) => roles.some(role => role.role_code === code);
  const businessRole = (code: string) => roles.some(role => role.role_code === code && role.location_id === null);
  const title = has("ceo") ? "Executive workspace" : businessRole("inventory_manager") ? "Inventory Manager workspace" : has("finance") ? "Finance workspace" : has("procurement") ? "Procurement workspace" : has("kitchen_manager") ? "Kitchen Manager workspace" : has("bar_lead") ? "Bar Lead workspace" : has("stock_department") ? "Department stock workspace" : has("stock_receiver") ? "Stock receiving workspace" : has("stock_dispatcher") ? "Stock dispatch workspace" : has("inventory") ? "Inventory / Receiving workspace" : has("restaurant_admin") ? "Administration workspace" : "Operations workspace";
  const tasks: Task[] = [];
  if(access.history)tasks.push({title:"Historical reports",description:"Filter earlier records by date, location and status; trace the source or export the permitted history.",action:"Open historical reports",path:"/workspace/records"});
  if (access.inventory) tasks.push({title:"Inventory & movements",description:has("stock_department")?"Request materials, accept or reject incoming stock, and return excess to Main Store.":"Review stock balances, reservations, requisitions and confirmed movements.",action:"Open inventory & movements",path:"/workspace/inventory"});
  if (access.inventory && businessRole("inventory_manager")) {
    tasks.push({title:"Stock approvals",description:"Review department requests, opening balances, counts, waste and production. A different colleague must approve your own requests.",action:"Review stock requests",path:"/workspace/inventory?view=movements"});
    tasks.push({title:"Centres & team access",description:"Choose who runs each stock centre and what their team can do.",action:"Manage centres & team access",path:"/workspace/setup/centres"});
  }
  const purchasing = businessRole("procurement") || businessRole("restaurant_admin");
  const finance = businessRole("finance") || businessRole("restaurant_admin");
  if (access.purchases && purchasing) {
    tasks.push({title:"Purchase Orders",description:"Prepare and issue purchase orders. Inventory confirms deliveries separately.",action:"Open Purchase Orders",path:"/workspace/purchases/orders"});
    tasks.push({title:"Supplier invoices",description:"Record supplier bills and request corrections. Delivery confirmation is recorded separately.",action:"Record supplier invoice",path:"/workspace/purchases/invoices?new=1"});
  }
  if (access.orders && (has("inventory")||has("stock_receiver")||businessRole("inventory_manager")) && !tasks.some(task => task.path === "/workspace/purchases/receipts")) tasks.push({title:"Goods Received Notes",description:"Confirm accepted and rejected quantities against issued orders for your locations. A different colleague must receive orders you prepared or issued.",action:"Open Goods Received Notes",path:"/workspace/purchases/receipts"});
  if (access.expenses && finance) tasks.push({title:"Expenses",description:"Record labour and operating expenses directly.",action:"Record expense",path:"/workspace/expenses"});
  if (access.purchases && businessRole("finance")) tasks.push({title:"Invoice reviews",description:"Review invoice exceptions and approve submitted purchase corrections.",action:"Review supplier invoices",path:"/workspace/purchases/invoices"});
  if (access.overview) tasks.push({title:"Business performance",description:"Review sales, costs and available margin estimates.",action:"Open executive overview",path:"/workspace/overview"});
  if (access.overview) tasks.push({title:"Management reports",description:businessRole("ceo") || businessRole("restaurant_admin") ? "Review and approve submitted management reports." : "Prepare and submit management reports for approval.",action:"Open management reports",path:"/workspace/reports"});
  if (access.recipes) tasks.push({title:"Recipes & costing",description:"Review recipes, scaling and available ingredient cost estimates.",action:"Open recipes",path:"/workspace/recipes"});
  if (access.menus) tasks.push({title:"Menu & prices",description:"Review menu prices and available recipe margins.",action:"Open menu & prices",path:"/workspace/menus"});
  if (access.sales) tasks.push({title:"Sales & summary",description:"Review recorded sales and available spreadsheet imports.",action:"Open sales imports",path:"/workspace/sales"});
  if (access.catalogue) tasks.push({title:"Materials & suppliers",description:"Access the materials, units and suppliers available to your account.",action:"Open catalogue",path:"/workspace/materials"});
  if (access.purchases && purchasing) tasks.push({title:"Purchase imports",description:"Import and reconcile purchase data from spreadsheets.",action:"Open purchase imports",path:"/workspace/purchases"});
  if (access.team) tasks.push({title:"Business administration",description:"Review business setup and manage team access.",action:"Open Data & Setup",path:"/workspace/setup"});
  if (has("ceo")) tasks.sort((a, b) => Number(b.path === "/workspace/overview" || b.path === "/workspace/reports") - Number(a.path === "/workspace/overview" || a.path === "/workspace/reports"));
  else if (has("restaurant_admin") && !has("finance") && !has("procurement")) tasks.sort((a, b) => Number(b.path === "/workspace/setup") - Number(a.path === "/workspace/setup"));
  if (businessRole("ceo")) return {title,description:"See what changed, the profitability impact, where it happened and who needs to act.",tasks:tasks.filter(task=>["/workspace/overview","/workspace/reports"].includes(task.path))};
  return {title, description: "Start with the tasks available to your assigned roles. Your access applies within the business and location scopes shown below.", tasks};
}
