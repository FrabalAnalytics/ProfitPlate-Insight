import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { isUuid } from "@/lib/catalogue";
import { validBusinessDate } from "@/lib/recipes";
import { referenceAmount } from "@/lib/reference-prices";
import { displayPercent } from "@/lib/display";
import { menuChannels, type MenuProfitability, type MenuEstimate } from "@/lib/menus";
import { WorkspaceShell } from "@/app/components/workspace-shell";
import { DataTable, StatusBadge } from "@/app/components/data-table";
import "../../materials/catalogue.css";
import "../menus.css";

export const metadata: Metadata = {title: "Menu profitability | ProfitPlate Insight"};
export const instant = false;
type Params = {organisation?:string;location?:string;channel?:string;date?:string;q?:string;page?:string};

function readiness(estimate:MenuEstimate|null) {
 if (!estimate) return "No effective recipe-linked version";
 if (estimate.recipe_estimate.missing_count>0) return `${estimate.recipe_estimate.missing_count} material ${estimate.recipe_estimate.missing_count===1?"price":"prices"} missing or unusable`;
 if (estimate.price_issue) return ({MISSING_SELLING_PRICE:"Missing selling price",EXPIRED_SELLING_PRICE:"Selling price expired",PRICE_CURRENCY_MISMATCH:"Selling price currency mismatch"} as Record<string,string>)[estimate.price_issue]??"Selling price unavailable";
 return estimate.cost_state==="ESTIMATED"?"Estimated":"Incomplete cost inputs";
}

export default async function MenuProfitabilityPage({searchParams}:{searchParams:Promise<Params>}) {
 const user=await requireUser(),access=await getPlatformAccess();
 if(access!=="member") redirect(workspacePath(access));
 const params=await searchParams,client=await createClient();
 const organisations=await client.from("organisations").select("id,name,currency_code,time_zone").order("name").order("id");
 const org=params.organisation?organisations.data?.find(item=>item.id===params.organisation):organisations.data?.[0];
 if(organisations.error||!org) return <WorkspaceShell email={user.email}><h1 className="workspace-title">This business is unavailable.</h1><Link href="/workspace">Return to workspace</Link></WorkspaceShell>;
 const shell={email:user.email,restaurantName:org.name,organisationId:org.id,sectionLabel:"Menu profitability"};
 const permission=await client.rpc("menu_access",{p_organisation_id:org.id});
 if(permission.error||permission.data?.read!==true) return <WorkspaceShell {...shell}><h1 className="workspace-title">Menu profitability is restricted or unavailable.</h1><p className="workspace-description">Your account needs business-wide menu financial access.</p></WorkspaceShell>;
 const locations=await client.from("locations").select("id,name,is_active").eq("organisation_id",org.id).eq("is_active",true).order("name").order("id");
 const parts=new Intl.DateTimeFormat("en",{timeZone:org.time_zone,year:"numeric",month:"2-digit",day:"2-digit"}).formatToParts(new Date());
 const today=["year","month","day"].map(key=>parts.find(part=>part.type===key)?.value).join("-");
 const location=params.location??locations.data?.[0]?.id??"",channel=params.channel??"DINE_IN",date=params.date??today,q=(params.q??"").trim().slice(0,80),page=Number(params.page??"1");
 const context={organisation:org.id,location,channel,date,q};
 const href=(extra:Record<string,string>={})=>`/workspace/menus/profitability?${new URLSearchParams({...context,...extra})}`;
 let error="",packet:MenuProfitability|null=null;
 if(locations.error) error="Outlets could not be loaded. Refresh to try again.";
 else if(!locations.data?.length) error="Add an active outlet before comparing menu profitability.";
 else if(!isUuid(location)||!locations.data.some(item=>item.id===location)||!validBusinessDate(date)||date>today||!menuChannels.some(([code])=>code===channel)||!Number.isInteger(page)||page<1||page>100000) error="Choose an active outlet, valid channel and page, and a date that is not in the future.";
 else {
  const result=await client.rpc("menu_profitability",{p_organisation_id:org.id,p_location_id:location,p_channel:channel,p_as_of:date,p_search:q,p_page:page});
  if(result.error) error=result.error.code==="PGRST202"?"Menu profitability is not available yet. Ask your administrator to finish setup.":result.error.code==="22023"?result.error.message:"Menu profitability could not be loaded. Check your connection and access, then refresh.";
  else packet=result.data as MenuProfitability;
 }
 const money=(value:string|null|undefined)=>value==null?"Unavailable":referenceAmount(value,packet?.currency_code??org.currency_code);
 const percent=(value:string|null|undefined)=>value==null?"Unavailable":`${displayPercent(value)}%`;
 const outlet=locations.data?.find(item=>item.id===location)?.name??"Selected outlet";
 return <WorkspaceShell {...shell}>
  <div className="page-heading-row"><div><p className="eyebrow form-eyebrow">PROFITABILITY / MENU COMPARISON</p><h1 className="workspace-title">Menu profitability</h1><p className="workspace-description">Compare the cost and estimated food profit of one serving of each menu item.</p></div></div>
  <nav className="catalogue-tabs" aria-label="Menu views"><Link href={`/workspace/menus?organisation=${org.id}`}>Menu catalogue</Link><Link href={href()} aria-current="page">Menu profitability</Link></nav>
  <form method="get" className="menu-profitability-filters" key={`${location}:${channel}:${date}:${q}`}>
   <input type="hidden" name="organisation" value={org.id}/>
   <div className="setup-field"><label htmlFor="profitability-outlet">Profitability outlet</label><select id="profitability-outlet" name="location" defaultValue={location} required><option value="" disabled>Choose outlet</option>{locations.data?.map(item=><option key={item.id} value={item.id}>{item.name}</option>)}</select></div>
   <div className="setup-field"><label htmlFor="profitability-channel">Profitability channel</label><select id="profitability-channel" name="channel" defaultValue={channel}>{menuChannels.map(([code,label])=><option key={code} value={code}>{label}</option>)}</select></div>
   <div className="setup-field"><label htmlFor="profitability-date">Profitability date</label><input id="profitability-date" name="date" type="date" defaultValue={date} max={today} required/></div>
   <div className="setup-field"><label htmlFor="profitability-search">Search menu name or code</label><input id="profitability-search" name="q" type="search" defaultValue={q} maxLength={80} placeholder="All active menu items"/></div>
   <button className="secondary-button">Update profitability</button>
  </form>
  {error?<p className="auth-alert" role="alert">{error}</p>:packet&&<section className="menu-panel menu-profitability-register" aria-labelledby="profitability-table-title">
   <div className="register-heading"><div><h2 id="profitability-table-title">Profitability by menu item</h2><p className="menu-intro">{outlet} · {menuChannels.find(([code])=>code===channel)?.[1]} · {date} · {packet.currency_code}</p></div><span className="register-count">{packet.total} {packet.total===1?"menu item":"menu items"}</span></div>
   <p className="menu-intro">Prices and percentages exclude tax. Each row uses the recipe-linked menu version effective on the selected date. Only active items belonging to this outlet’s brand appear.</p>
   {packet.unassigned_menu_count>0&&<p className="menu-missing">{packet.unassigned_menu_count} active menu items have no brand assignment and are excluded from this outlet comparison. Review them in the menu catalogue.</p>}
   <DataTable label="Menu profitability comparison" columns={[{label:"Menu item"},{label:"Est. cost / serving",numeric:true},{label:"Selling price (excl. tax)",numeric:true},{label:"Food cost %",numeric:true},{label:"Est. food profit / serving",numeric:true},{label:"Est. food GP margin %",numeric:true},{label:"Contribution margin"},{label:"Cost / price readiness"},{label:"Action"}]} rows={packet.rows.map(row=>({id:row.id,cells:[<span key="menu">{row.name}<small>{row.code}{row.version?` · v${row.version}`:""}</small></span>,money(row.estimate?.estimated_food_cost),<span key="price">{money(row.estimate?.net_revenue)}{row.estimate?.customer_total&&row.estimate.tax_amount&&!/^0(?:\.0+)?$/.test(row.estimate.tax_amount)&&<small>Incl. tax: {money(row.estimate.customer_total)}</small>}</span>,percent(row.estimate?.food_cost_percent),<span key="profit" className={row.estimate?.estimated_food_margin?.startsWith("-")?"menu-loss-value":""}>{money(row.estimate?.estimated_food_margin)}</span>,<span key="margin" className={row.estimate?.food_margin_percent?.startsWith("-")?"menu-loss-value":""}>{percent(row.estimate?.food_margin_percent)}</span>,<span key="contribution">Unavailable<small>Other variable costs not connected</small></span>,<StatusBadge key="state" tone={row.estimate?.cost_state==="ESTIMATED"?"success":"warning"}>{readiness(row.estimate)}</StatusBadge>,<Link key="detail" className="inline-link" aria-label={`View profitability for ${row.name}`} href={`/workspace/menus?${new URLSearchParams({organisation:org.id,item:row.id,...(row.version_id?{version:row.version_id}:{}),location,channel,date})}`}>View breakdown</Link>]}))} empty="No active menu items match this outlet and search."/>
   <div className="register-footer"><span>Page {page} · {packet.total} matching {packet.total===1?"menu item":"menu items"}</span><nav className="invoice-nav" aria-label="Profitability pages">{page>1&&<Link className="secondary-button" href={href({page:String(page-1)})}>Previous menu items</Link>}{page*25<packet.total&&<Link className="secondary-button" href={href({page:String(page+1)})}>Next menu items</Link>}</nav></div>
   <details className="workspace-disclosure"><summary>How to read these estimates</summary><p>Cost per serving uses the saved recipe quantity for one sold menu item, including ingredient and direct packaging reference prices. Food cost % is that cost divided by the net selling price. Estimated food profit is net selling price less that cost; estimated food gross margin % is that profit divided by net selling price.</p><p>These are live reference-price food estimates. Later reference-price corrections can change a historical-date preview. Labour, overheads, waste, discounts, service charges and channel fees are excluded. Contribution margin is unavailable until all required variable costs are connected. Missing inputs never become zero.</p></details>
  </section>}
 </WorkspaceShell>;
}
