"use client";
import {useSearchParams} from "next/navigation";
import Link from "next/link";import {useEffect,useRef,useSyncExternalStore,type ReactNode} from "react";
import {LayoutDashboard,Boxes,ShoppingCart,ChartNoAxesCombined,FileSpreadsheet,BookOpen,Users,Settings2,ChevronDown,ClipboardList} from "lucide-react";
import {contextQuery,type NavigationAccess,type ReportingContext} from "@/lib/overview";
import {reviewRoles} from '@/lib/management-reviews';
import "./workspace-navigation.css";
const navigationStates=new Map<string,{path:string;open:boolean}>();
const navigationEvent='profitplate-navigation-change';
function subscribeNavigation(notify:()=>void){
 const storage=()=>{navigationStates.clear();notify();};
 window.addEventListener(navigationEvent,notify);window.addEventListener('storage',storage);
 return()=>{window.removeEventListener(navigationEvent,notify);window.removeEventListener('storage',storage);};
}
function NavGroup({name,active,initial,storageKey,pathname,children}:{name:string;active:boolean;initial:boolean;storageKey:string;pathname:string;children:ReactNode}){
 const ref=useRef<HTMLDetailsElement>(null);
 const open=useSyncExternalStore(subscribeNavigation,()=>{
  const savedState=navigationStates.get(storageKey);if(savedState?.path===pathname)return savedState.open;
  let next=active||initial;try{const saved=localStorage.getItem(storageKey);next=active?true:saved===null?initial:saved==='open';}catch{}
  navigationStates.set(storageKey,{path:pathname,open:next});return next;
 },()=>active||initial);
 useEffect(()=>{if(ref.current)ref.current.dataset.ready='true';},[]);
 return <details className="workspace-nav-group" ref={ref} open={open}><summary onClick={event=>{event.preventDefault();const next=!open;navigationStates.set(storageKey,{path:pathname,open:next});try{localStorage.setItem(storageKey,next?'open':'closed');}catch{}window.dispatchEvent(new Event(navigationEvent));}}>{name}<ChevronDown size={14} aria-hidden="true"/></summary><div>{children}</div></details>;
}

export function WorkspaceNavigation({organisation,email,roles,access,pathname,context,onNavigate}:{organisation:string;email?:string;roles:string[];access:NavigationAccess;pathname:string;context?:ReportingContext;onNavigate:()=>void}){
 const monthlyView=useSearchParams().get("frequency")==="MONTHLY";
 const financeOnly=roles.includes("finance")&&!roles.some(r=>["ceo","restaurant_admin","procurement","inventory_manager","inventory","operations","stock_department","kitchen_manager","bar_lead","stock_receiver","stock_dispatcher"].includes(r));
 const stockReports=roles.some(r=>["restaurant_admin","ceo","finance","inventory_manager","inventory","operations","stock_department","kitchen_manager","bar_lead","stock_receiver","stock_dispatcher"].includes(r));
 const group=(name:string,active:boolean,children:ReactNode,initial=false)=><NavGroup name={name} active={active} initial={initial} pathname={pathname} storageKey={`profitplate-nav:${organisation}:${email??"member"}:${name}`} key={name}>{children}</NavGroup>;
 const item=(label:string,path:string,Icon:typeof Boxes,active:boolean)=><Link href={`${path}${path.includes("?")?"&":"?"}organisation=${organisation}`} title={label} aria-current={active?"page":undefined} onClick={onNavigate}><Icon size={18}/><span>{label}</span></Link>;
 return <>
  {item("My workspace","/workspace",LayoutDashboard,pathname==="/workspace")}
  {(access.orders||access.purchases)&&group("Purchasing",pathname.startsWith("/workspace/purchases"),<>
   {access.orders&&item("Purchase Orders","/workspace/purchases/orders",Boxes,pathname.startsWith("/workspace/purchases/orders"))}
   {access.orders&&item("Goods Received Notes","/workspace/purchases/receipts",Boxes,pathname.startsWith("/workspace/purchases/receipts"))}
   {access.purchases&&item("Supplier invoices","/workspace/purchases/invoices",ShoppingCart,pathname.startsWith("/workspace/purchases")&&!pathname.startsWith("/workspace/purchases/orders")&&!pathname.startsWith("/workspace/purchases/receipts"))}
  </>)}
  {(access.inventory||stockReports)&&group("Stock & production",pathname.startsWith("/workspace/inventory")||pathname.startsWith("/workspace/requisitions"),<>
   {access.inventory&&!financeOnly&&item("Inventory & movements","/workspace/inventory",Boxes,pathname==="/workspace/inventory")}
   {(access.inventory||roles.includes("ceo"))&&item("Requisitions","/workspace/requisitions",ClipboardList,pathname.startsWith("/workspace/requisitions"))}
   {access.inventory&&roles.some(r=>['restaurant_admin','inventory_manager','inventory','operations','stock_department','kitchen_manager','bar_lead'].includes(r))&&item("Material Plan","/workspace/inventory/plans",ClipboardList,pathname.startsWith("/workspace/inventory/plans"))}
   {access.inventory&&!financeOnly&&item("Material Processing Log","/workspace/inventory/processing",Boxes,pathname.startsWith("/workspace/inventory/processing"))}
   {access.inventory&&item(financeOnly?"Waste across centres":"Waste Log",financeOnly?"/workspace/inventory/waste?kind=WASTE":"/workspace/inventory/waste",Boxes,pathname.startsWith("/workspace/inventory/waste"))}
   {roles.some(r=>['ceo','finance','restaurant_admin','operations'].includes(r))&&item('Balance reviews','/workspace/inventory/corrections',ClipboardList,pathname.startsWith('/workspace/inventory/corrections'))}
   {stockReports&&item("Current stock value","/workspace/inventory/value",Boxes,pathname.startsWith("/workspace/inventory/value"))}
   {stockReports&&item("Stock movement statement","/workspace/inventory/statements",Boxes,pathname.startsWith("/workspace/inventory/statements"))}
   {stockReports&&item("Weekly stock counts","/workspace/inventory/counts",ClipboardList,pathname.startsWith("/workspace/inventory/counts")&&!monthlyView)}
   {stockReports&&item("Monthly stock counts","/workspace/inventory/counts?frequency=MONTHLY",ClipboardList,pathname.startsWith("/workspace/inventory/counts")&&monthlyView)}
  </>)}
  {(access.recipes||access.menus)&&group("Profitability",pathname.startsWith("/workspace/recipes")||pathname.startsWith("/workspace/menus"),<>{access.recipes&&item("Recipes & scaling","/workspace/recipes",BookOpen,pathname.startsWith("/workspace/recipes"))}{access.menus&&item("Menu & prices","/workspace/menus",FileSpreadsheet,pathname.startsWith("/workspace/menus"))}</>)}
  {(access.sales||access.expenses)&&group("Finance",pathname.startsWith("/workspace/sales")||pathname.startsWith("/workspace/expenses"),<>
   {access.sales&&<Link href={`/workspace/sales?${contextQuery(organisation,context)}`} title="Sales & summary" aria-current={pathname.startsWith("/workspace/sales")?"page":undefined} onClick={onNavigate}><ChartNoAxesCombined size={18}/><span>Sales & summary</span></Link>}
   {access.expenses&&<Link href={`/workspace/expenses?${contextQuery(organisation,context)}`} title="Labour & expenses" aria-current={pathname.startsWith("/workspace/expenses")?"page":undefined} onClick={onNavigate}><FileSpreadsheet size={18}/><span>Labour & expenses</span></Link>}
  </>)}
  {(access.overview||access.history||roles.some(r=>reviewRoles.includes(r)))&&group("Reports",pathname.startsWith("/workspace/records")||pathname.startsWith("/workspace/reports")||pathname.startsWith("/workspace/reviews")||pathname.startsWith("/workspace/overview")||pathname.startsWith("/workspace/performance"),<>
   {(access.overview||roles.includes('operations'))&&item(roles.includes('operations')&&!roles.includes('ceo')?"Operational overview":"Business performance","/workspace/performance",LayoutDashboard,pathname.startsWith("/workspace/performance"))}
   {access.overview&&<Link href={`/workspace/overview?${contextQuery(organisation,context)}`} aria-current={pathname.startsWith("/workspace/overview")?"page":undefined} title="Executive overview" onClick={onNavigate}><LayoutDashboard size={18}/><span>Executive overview</span></Link>}
   {roles.some(r=>reviewRoles.includes(r))&&<>{item("Management Review","/workspace/reviews",LayoutDashboard,pathname==="/workspace/reviews"||pathname.startsWith("/workspace/reviews/history"))}{item("Action register","/workspace/reviews/actions",ClipboardList,pathname.startsWith("/workspace/reviews/actions"))}</>}
   {roles.some(r=>['ceo','finance','restaurant_admin','operations'].includes(r))&&item('Monthly close','/workspace/reviews/close',ClipboardList,pathname.startsWith('/workspace/reviews/close'))}
   {access.overview&&<Link href={`/workspace/reports?${contextQuery(organisation,context)}`} title="Management reports" aria-current={pathname.startsWith("/workspace/reports")?"page":undefined} onClick={onNavigate}><FileSpreadsheet size={18}/><span>Management reports</span></Link>}
   {access.history&&item("Historical reports","/workspace/records",FileSpreadsheet,pathname.startsWith("/workspace/records"))}
  </>)}
  {(access.catalogue||access.team||access.stockSetup)&&group(access.team?"Administration":access.stockSetup?"Stock administration":"Reference data",pathname.startsWith("/workspace/materials")||pathname.startsWith("/workspace/team")||pathname.startsWith("/workspace/setup"),<>{access.catalogue&&item("Materials & suppliers","/workspace/materials",Boxes,pathname.startsWith("/workspace/materials"))}{access.team&&item("Users & roles","/workspace/team",Users,pathname.startsWith("/workspace/team"))}{access.stockSetup&&!access.team&&item("Centres & team access","/workspace/setup/centres",Settings2,pathname.startsWith("/workspace/setup/centres"))}{access.team&&item("Data & Setup","/workspace/setup",Settings2,pathname.startsWith("/workspace/setup"))}</>)}
 </>;
}
