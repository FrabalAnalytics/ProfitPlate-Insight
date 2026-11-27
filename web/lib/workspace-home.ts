import type { NavigationAccess } from "./overview";
type Role = { role_code: string; location_id: string | null };
type Task = { title: string; description: string; action: string; path: string };

export function workspaceRolePolicy(roles:Role[]){
 const has=(...codes:string[])=>roles.some(r=>codes.includes(r.role_code)),business=(code:string)=>roles.some(r=>r.role_code===code&&r.location_id===null);
 const admin=business('restaurant_admin'),executive=business('ceo'),stockManager=business('inventory_manager'),stockWork=has('inventory_manager','inventory','operations','stock_department','kitchen_manager','bar_lead','stock_receiver','stock_dispatcher');
 return {admin,executive,stockManager,stockWork,financeOnly:has('finance')&&!has('restaurant_admin','ceo','procurement')&&!stockWork,procurementOnly:has('procurement')&&!has('restaurant_admin','ceo','finance')&&!stockWork,stockOnly:stockWork&&!has('restaurant_admin','ceo','finance','procurement'),canBusinessSetup:admin,canStockSetup:admin||stockManager};
}
export function workspaceNavigation(roles: Role[], access: NavigationAccess): NavigationAccess {
 const p=workspaceRolePolicy(roles),nav={...access,stockSetup:p.canStockSetup};
 if(p.executive&&roles.every(r=>r.role_code==='ceo'))return {...nav,purchases:false,orders:false,inventory:false,sales:false,expenses:false};
 if(p.financeOnly)return {...nav,team:false,catalogue:false,recipes:false};
 if(p.procurementOnly)return {...nav,overview:false,expenses:false,sales:false,inventory:false,team:false,recipes:false,menus:false};
 if(p.stockOnly&&roles.some(r=>r.role_code==='operations'))return {...nav,overview:false,expenses:false,sales:false,team:false};
 if(p.stockOnly)return {...nav,overview:false,expenses:false,sales:false,purchases:false,team:false,catalogue:roles.some(r=>r.role_code==='operations')&&nav.catalogue,recipes:roles.some(r=>r.role_code==='operations')&&nav.recipes,menus:false};
 return nav;
}

// Membership roles determine the welcome; server capabilities determine links.
export function workspaceHome(roles: Role[], access: NavigationAccess) {
  access = workspaceNavigation(roles, access);
  const has = (code: string) => roles.some(role => role.role_code === code);
  const businessRole = (code: string) => roles.some(role => role.role_code === code && role.location_id === null);
  const title = has("ceo") ? "Executive workspace" : businessRole("inventory_manager") ? "Inventory Manager workspace" : has("operations") ? "Operations Manager workspace" : has("finance") ? "Finance workspace" : has("procurement") ? "Procurement workspace" : has("kitchen_manager") ? "Kitchen Manager workspace" : has("bar_lead") ? "Bar Lead workspace" : has("stock_department") ? "Department stock workspace" : has("stock_receiver") ? "Stock receiving workspace" : has("stock_dispatcher") ? "Stock dispatch workspace" : has("inventory") ? "Inventory / Receiving workspace" : has("restaurant_admin") ? "Administration workspace" : "Operations Manager workspace";
  const tasks: Task[] = [];
  if(access.history)tasks.push({title:"Operational reports",description:"Filter earlier records by date, location and status; trace the source or export the permitted history.",action:"Open operational reports",path:"/workspace/records"});
  const policy=workspaceRolePolicy(roles);
  if (access.inventory&&!policy.financeOnly) tasks.push({title:"Inventory & movements",description:has("stock_department")?"Request materials, accept or reject incoming stock, and return excess to Main Store.":"Review stock balances, reservations, requisitions and confirmed movements.",action:"Open inventory & movements",path:"/workspace/inventory"});
  if(access.inventory&&roles.some(r=>['restaurant_admin','inventory_manager','inventory','operations','stock_department','kitchen_manager','bar_lead'].includes(r.role_code)))tasks.push({title:'Material Plan',description:'Combine recipe targets into material requirements and current stock gaps.',action:'Create material plan',path:'/workspace/inventory/plans'});
  if (access.inventory && businessRole("inventory_manager")) {
    tasks.push({title:"Stock approvals",description:"Review department requests, opening balances, counts and production. A different colleague must approve your own requests.",action:"Review stock requests",path:"/workspace/inventory?view=movements"});
    tasks.push({title:"Centres & team access",description:"Choose who runs each stock centre and what their team can do.",action:"Manage centres & team access",path:"/workspace/setup/centres"});
  }
  if(access.inventory&&roles.some(r=>r.role_code==='finance'))tasks.push({title:'Waste across centres',description:'Review processing loss and other waste by date and centre.',action:'Review centre waste',path:'/workspace/inventory/waste?kind=WASTE'});
  if(access.inventory&&policy.stockWork)tasks.push({title:'Waste Log',description:'Record and review waste at your permitted centres.',action:'Open Waste Log',path:'/workspace/inventory/waste'});
  const purchasing = businessRole("procurement") || businessRole("restaurant_admin");
  const finance = businessRole("finance") || businessRole("restaurant_admin");
  if (access.purchases && purchasing) {
    tasks.push({title:"Purchase Orders",description:"Prepare and issue purchase orders. Inventory confirms deliveries separately.",action:"Open Purchase Orders",path:"/workspace/purchases/orders"});
    tasks.push({title:"Supplier invoices",description:"Record supplier bills and request corrections. Delivery confirmation is recorded separately.",action:"Record supplier invoice",path:"/workspace/purchases/invoices?new=1"});
  }
  if (access.orders && (has("inventory")||has("stock_receiver")||businessRole("inventory_manager")) && !tasks.some(task => task.path === "/workspace/purchases/receipts")) tasks.push({title:"Goods Received Notes",description:"Confirm accepted and rejected quantities against issued orders for your locations. A different colleague must receive orders you prepared or issued.",action:"Open Goods Received Notes",path:"/workspace/purchases/receipts"});
  if (access.expenses && finance) tasks.push({title:"Expenses",description:"Record labour and operating expenses directly.",action:"Record expense",path:"/workspace/expenses"});
  if (access.purchases && businessRole("finance")) tasks.push({title:"Invoice reviews",description:"Review invoice exceptions and approve submitted purchase corrections.",action:"Review supplier invoices",path:"/workspace/purchases/invoices"});
  if (access.overview) tasks.push({title:"Business performance",description:"Review sales, costs and available margin estimates.",action:"Open business performance",path:"/workspace/performance"});
  if (access.overview) tasks.push({title:"Management review",description:businessRole("ceo") || businessRole("restaurant_admin") ? "Review and approve submitted management reports." : "Prepare and submit management reports for approval.",action:"Open management review",path:"/workspace/reviews"});
  if (access.recipes) tasks.push({title:"Recipes & costing",description:"Review recipes, scaling and available ingredient cost estimates.",action:"Open recipes",path:"/workspace/recipes"});
  if (access.menus) tasks.push({title:"Menu & prices",description:"Review menu prices and available recipe margins.",action:"Open menu & prices",path:"/workspace/menus"});
  if (access.sales) tasks.push({title:"Sales & summary",description:"Review recorded sales and available spreadsheet imports.",action:"Open sales imports",path:"/workspace/sales"});
  if (access.catalogue) tasks.push({title:"Materials & suppliers",description:"Access the materials, units and suppliers available to your account.",action:"Open catalogue",path:"/workspace/materials"});
  if (access.purchases && purchasing) tasks.push({title:"Purchase imports",description:"Import and reconcile purchase data from spreadsheets.",action:"Open purchase imports",path:"/workspace/purchases"});
  if (access.team) tasks.push({title:"Business administration",description:"Review business setup and manage team access.",action:"Open Data & Setup",path:"/workspace/setup"});
  if (has("ceo")) tasks.sort((a, b) => Number(b.path === "/workspace/performance" || b.path === "/workspace/reviews") - Number(a.path === "/workspace/performance" || a.path === "/workspace/reviews"));
  else if (has("restaurant_admin") && !has("finance") && !has("procurement")) tasks.sort((a, b) => Number(b.path === "/workspace/setup") - Number(a.path === "/workspace/setup"));
  if (businessRole("ceo")) return {title,description:"See what changed, the profitability impact, where it happened and who needs to act.",tasks:tasks.filter(task=>["/workspace/performance","/workspace/reviews"].includes(task.path))};
  const priority=has('finance')?['Review supplier invoices','Record expense','Review centre waste','Open management review','Open sales imports','Open operational reports']:has('procurement')?['Open Purchase Orders','Record supplier invoice','Open operational reports','Open catalogue']:policy.stockManager?['Open inventory & movements','Open Goods Received Notes','Review stock requests','Open Waste Log','Manage centres & team access']:['Open inventory & movements','Open Waste Log','Open operational reports'];
  tasks.sort((a,b)=>{const ai=priority.indexOf(a.action),bi=priority.indexOf(b.action);return(ai<0?99:ai)-(bi<0?99:bi);});
  return {title, description:has('finance')?'Review invoices, costs and waste across your permitted centres.':has('procurement')?'Manage orders, supplier invoices and delivery evidence.':'Your tasks and stock records.',tasks};
}
