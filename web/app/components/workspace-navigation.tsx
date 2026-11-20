"use client";
import Link from "next/link";import {useEffect,useRef,type ReactNode} from "react";
import {LayoutDashboard,Boxes,ShoppingCart,ChartNoAxesCombined,FileSpreadsheet,BookOpen,Users,Settings2,ChevronDown,ClipboardList} from "lucide-react";
import {contextQuery,type NavigationAccess,type ReportingContext} from "@/lib/overview";
import "./workspace-navigation.css";
function NavGroup({name,active,initial,storageKey,pathname,children}:{name:string;active:boolean;initial:boolean;storageKey:string;pathname:string;children:ReactNode}){
 const ref=useRef<HTMLDetailsElement>(null),ready=useRef(false);
 useEffect(()=>{const node=ref.current;if(!node)return;try{const saved=localStorage.getItem(storageKey);node.open=active?true:saved===null?initial:saved==="open";}catch{node.open=active||initial;}ready.current=true;node.dataset.ready="true";},[active,initial,storageKey,pathname]);
 return <details className="workspace-nav-group" ref={ref} open={active||initial} onToggle={event=>{if(ready.current)try{localStorage.setItem(storageKey,event.currentTarget.open?"open":"closed");}catch{}}}><summary>{name}<ChevronDown size={14} aria-hidden="true"/></summary><div>{children}</div></details>;
}
export function WorkspaceNavigation({organisation,email,roles,access,pathname,context,onNavigate}:{organisation:string;email?:string;roles:string[];access:NavigationAccess;pathname:string;context?:ReportingContext;onNavigate:()=>void}){
 const financeOnly=roles.includes("finance")&&!roles.some(r=>["ceo","restaurant_admin","procurement","inventory_manager","inventory","operations","stock_department","kitchen_manager","bar_lead","stock_receiver","stock_dispatcher"].includes(r));
 const ceo=roles.includes("ceo"),finance=roles.includes("finance"),minimal=ceo||finance;
 const group=(name:string,active:boolean,children:ReactNode,initial=false)=><NavGroup name={name} active={active} initial={initial} pathname={pathname} storageKey={`profitplate-nav:${organisation}:${email??"member"}:${name}`} key={name}>{children}</NavGroup>;
 const item=(label:string,path:string,Icon:typeof Boxes,active:boolean)=><Link href={`${path}${path.includes("?")?"&":"?"}organisation=${organisation}`} title={label} aria-current={active?"page":undefined} onClick={onNavigate}><Icon size={18}/><span>{label}</span></Link>;
 return <>
  {item("My workspace","/workspace",LayoutDashboard,pathname==="/workspace")}
  {access.overview&&<Link href={`/workspace/overview?${contextQuery(organisation,context)}`} aria-current={pathname.startsWith("/workspace/overview")?"page":undefined} title="Executive overview" onClick={onNavigate}><LayoutDashboard size={18}/><span>Executive overview</span></Link>}
  {(access.orders||access.purchases)&&group("Purchasing",pathname.startsWith("/workspace/purchases"),<>
   {access.orders&&item("Purchase Orders","/workspace/purchases/orders",Boxes,pathname.startsWith("/workspace/purchases/orders"))}
   {access.orders&&item("Goods Received Notes","/workspace/purchases/receipts",Boxes,pathname.startsWith("/workspace/purchases/receipts"))}
   {access.purchases&&item("Supplier invoices","/workspace/purchases/invoices",ShoppingCart,pathname.startsWith("/workspace/purchases")&&!pathname.startsWith("/workspace/purchases/orders")&&!pathname.startsWith("/workspace/purchases/receipts"))}
  </>,!minimal)}
  {(access.sales||access.inventory||access.expenses)&&group(financeOnly?"Finance records":"Daily operations",pathname.startsWith("/workspace/sales")||pathname.startsWith("/workspace/inventory")||pathname.startsWith("/workspace/expenses"),<>
   {access.sales&&<Link href={`/workspace/sales?${contextQuery(organisation,context)}`} title="Sales & summary" aria-current={pathname.startsWith("/workspace/sales")?"page":undefined} onClick={onNavigate}><ChartNoAxesCombined size={18}/><span>Sales & summary</span></Link>}
   {access.inventory&&!financeOnly&&item("Inventory & movements","/workspace/inventory",Boxes,pathname==="/workspace/inventory")}
   {access.inventory&&roles.some(r=>['restaurant_admin','inventory_manager','inventory','operations','stock_department','kitchen_manager','bar_lead'].includes(r))&&item("Material Plan","/workspace/inventory/plans",ClipboardList,pathname.startsWith("/workspace/inventory/plans"))}
   {access.inventory&&!financeOnly&&item("Material Processing Log","/workspace/inventory/processing",Boxes,pathname.startsWith("/workspace/inventory/processing"))}
   {access.inventory&&item(financeOnly?"Waste across centres":"Waste Log",financeOnly?"/workspace/inventory/waste?kind=WASTE":"/workspace/inventory/waste",Boxes,pathname.startsWith("/workspace/inventory/waste"))}
   {access.expenses&&<Link href={`/workspace/expenses?${contextQuery(organisation,context)}`} title="Labour & expenses" aria-current={pathname.startsWith("/workspace/expenses")?"page":undefined} onClick={onNavigate}><FileSpreadsheet size={18}/><span>Labour & expenses</span></Link>}
  </>,!minimal)}
  {(access.recipes||access.menus)&&group("Profitability",pathname.startsWith("/workspace/recipes")||pathname.startsWith("/workspace/menus"),<>{access.recipes&&item("Recipes & scaling","/workspace/recipes",BookOpen,pathname.startsWith("/workspace/recipes"))}{access.menus&&item("Menu & prices","/workspace/menus",FileSpreadsheet,pathname.startsWith("/workspace/menus"))}</>)}
  {(access.overview||access.history)&&group("Reports",pathname.startsWith("/workspace/records")||pathname.startsWith("/workspace/reports"),<>{access.overview&&<Link href={`/workspace/reports?${contextQuery(organisation,context)}`} title="Management reports" aria-current={pathname.startsWith("/workspace/reports")?"page":undefined} onClick={onNavigate}><FileSpreadsheet size={18}/><span>Management reports</span></Link>}{access.history&&item("Historical reports","/workspace/records",FileSpreadsheet,pathname.startsWith("/workspace/records"))}</>,!minimal)}
  {(access.catalogue||access.team)&&group(access.team?"Business administration":"Reference data",pathname.startsWith("/workspace/materials")||pathname.startsWith("/workspace/team")||pathname.startsWith("/workspace/setup"),<>{access.catalogue&&item("Materials & suppliers","/workspace/materials",Boxes,pathname.startsWith("/workspace/materials"))}{access.team&&item("Users & roles","/workspace/team",Users,pathname.startsWith("/workspace/team"))}{access.team&&item("Data & Setup","/workspace/setup",Settings2,pathname.startsWith("/workspace/setup"))}</>,!minimal)}
 </>;
}
