import type {SetupProfile} from "@/lib/setup";
import {DataTable,StatusBadge} from "@/app/components/data-table";
import type { Metadata } from "next";
import { randomUUID } from "node:crypto";
import Link from "next/link";
import { redirect } from "next/navigation";
import { ArrowLeft, ArrowRight, Info, Plus, Search } from "lucide-react";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { isUuid } from "@/lib/catalogue";
import { displayQuantity, validBusinessDate } from "@/lib/recipes";
import { referenceAmount } from "@/lib/reference-prices";
import { menuChannels, menuTaxSettings, type MenuPacket, type MenuEstimate } from "@/lib/menus";
import { displayPercent } from "@/lib/display";
import { WorkspaceShell } from "@/app/components/workspace-shell";
import { MenuEditor, MenuPriceEditor, MenuStatusButton } from "./menu-forms";
import "../materials/catalogue.css";
import "./menus.css";

export const metadata: Metadata = { title: "Menu & selling prices | ProfitPlate Insight" };
export const instant = false;
type Params = { organisation?: string; item?: string; version?: string; new?: string; edit?: string; price?: string; saved?: string; q?: string; page?: string; location?: string; channel?: string; date?: string };

export default async function MenusPage({ searchParams }: { searchParams: Promise<Params> }) {
 const user = await requireUser();
 const access = await getPlatformAccess();
 if (access !== "member") redirect(workspacePath(access));
 const params = await searchParams, client = await createClient();
 const { data: organisations, error: orgError } = await client.from("organisations").select("id,name,currency_code,time_zone").order("name");
 if (!orgError && !organisations?.length) redirect("/onboarding");
 const org = params.organisation ? organisations?.find(entry => entry.id === params.organisation) : organisations?.[0];
 if (!org || orgError) return <WorkspaceShell email={user.email}><h1 className="workspace-title">This business is unavailable.</h1><Link href="/workspace" className="auth-back">Return to workspace</Link></WorkspaceShell>;
 const shell = { email: user.email, restaurantName: org.name, organisationId: org.id, sectionLabel: "Menu & selling prices" };
 const query = (values: Record<string, string> = {}) => `/workspace/menus?${new URLSearchParams({ organisation: org.id, ...values })}`;
 const { data: permission, error: permissionError } = await client.rpc("menu_access", { p_organisation_id: org.id });
 if (permissionError) return <WorkspaceShell {...shell}><h1 className="workspace-title">Menu setup is not available yet.</h1><p className="workspace-description">The platform administrator may need to finish the menu update, or access is temporarily unavailable.</p><Link className="auth-back" href={`/workspace?organisation=${org.id}`}>Return to business setup</Link></WorkspaceShell>;
 if (permission?.read !== true) return <WorkspaceShell {...shell}><h1 className="workspace-title">Business-wide menu pricing access is restricted.</h1><p className="workspace-description">An organisation-wide administrator, finance member, CEO or procurement manager can view this workspace.</p></WorkspaceShell>;
 const canEdit = permission.write === true;
 const [brandsResult, locationsResult] = await Promise.all([
  client.from("brands").select("id,name").eq("organisation_id", org.id).order("name"),
  client.from("locations").select("id,name,brand_id,is_active").eq("organisation_id", org.id).order("name"),
 ]);
 if (brandsResult.error || locationsResult.error) return <WorkspaceShell {...shell}><h1 className="workspace-title">We could not load menu setup.</h1><a className="auth-back" href={query()}>Refresh to try again</a></WorkspaceShell>;
 const brands = brandsResult.data ?? [], locations = locationsResult.data ?? [];
 const parts = new Intl.DateTimeFormat("en", { timeZone: org.time_zone, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(new Date());
 const day = ["year", "month", "day"].map(key => parts.find(part => part.type === key)?.value).join("-");
 let packet: MenuPacket | null = null, detailError = false;
 if (params.item) {
  if (isUuid(params.item) && (!params.version || isUuid(params.version))) {
   const result = await client.rpc("get_menu_item", { p_organisation_id: org.id, p_menu_id: params.item, p_version_id: params.version || null });
   packet = result.data as MenuPacket | null; detailError = !!result.error || !packet;
  } else detailError = true;
 }
 const editing = canEdit && (params.new === "1" || (params.edit === "1" && packet?.item.is_active));
 const addingPrice = canEdit && params.price === "1" && packet?.item.is_active;
 const validLocations = packet ? locations.filter(location => location.is_active && location.brand_id === packet!.item.brand_id &&(!packet!.item.location_id||packet!.item.location_id===location.id)) : [];
 const date = params.date ?? day, channel = params.channel ?? "DINE_IN", locationId = params.location ?? validLocations[0]?.id ?? "";
 let estimate: MenuEstimate | null = null, estimateError = "";
 if (packet?.version && packet.item.is_active && !editing && !addingPrice) {
  if (!validBusinessDate(date) || !isUuid(locationId)) estimateError = "Choose a valid preview date and an active location belonging to this menu brand.";
  else {
   const result = await client.rpc("menu_food_margin_estimate", { p_organisation_id: org.id, p_version_id: packet.version.id, p_location_id: locationId, p_channel: channel, p_as_of: date });
   if (result.error) estimateError = result.error.code === "22023" ? result.error.message : "The estimate is unavailable. Please refresh and check your access.";
   else estimate = result.data as MenuEstimate;
  }
 }
 const q = (params.q ?? "").trim().slice(0, 80), page = Math.min(100000, Math.max(1, Number.parseInt(params.page ?? "1", 10) || 1));
 let list: { id: string; code: string; name: string; brand_id: string | null; is_active: boolean }[] = [], total = 0, listError = false;
 if (!packet && !editing && !detailError) {
  let request = client.from("menu_items").select("id,code,name,brand_id,is_active,location_id,primary_category,subcategory", { count: "exact" }).eq("organisation_id", org.id).order("name").order("id");
  if (q) request = request.ilike("name", `%${q.replace(/[\\%_]/g, "\\$&")}%`);
  const result = await request.range((page - 1) * 25, page * 25 - 1); list = result.data ?? []; total = result.count ?? 0; listError = !!result.error;
 }
 const profilesResult=list.length?await client.rpc("setup_profiles",{p_organisation_id:org.id,p_kind:"MENU",p_ids:list.map(i=>i.id)}):null;
 const profiles=(profilesResult?.data??{}) as Record<string,SetupProfile>;
 const money = (value: string) => referenceAmount(value, estimate?.currency_code ?? org.currency_code);
 return <WorkspaceShell {...shell}>
  <Link className="catalogue-back" href={`/workspace?organisation=${org.id}`}><ArrowLeft size={14}/> Business setup</Link>
  <div className="page-heading-row"><div><p className="eyebrow form-eyebrow">PROFITABILITY / MENU & PRICES</p><h1 className="workspace-title">Menu & prices</h1></div>{canEdit && !editing && <Link className="auth-button catalogue-add" href={query({ new: "1" })}><Plus size={16}/> Create menu item</Link>}</div>
  <nav className="catalogue-tabs" aria-label="Menu views"><Link href={query()} aria-current={!packet&&!editing?"page":undefined}>Menu catalogue</Link><Link href={`/workspace/menus/profitability?${new URLSearchParams({organisation:org.id,...(locationId?{location:locationId}:{}),channel,date})}`}>Menu profitability</Link></nav>
  {!canEdit && <p className="catalogue-readonly"><Info size={16}/> You have read-only menu access. An organisation-wide restaurant administrator can publish menu versions and selling prices.</p>}
  {params.saved && ["menu", "draft", "price", "status"].includes(params.saved) && <p className="welcome-message" role="status">{params.saved === "menu" ? "Menu version published. Its recipe link is saved." : params.saved === "draft" ? "Incomplete menu item saved. Add its recipe and selling price when available." : params.saved === "price" ? "Selling price saved. Earlier price entries remain in history." : "Menu availability updated. Saved versions and price history are preserved."}</p>}
  {editing ? <MenuEditor key={params.new === "1" ? "new" : packet!.item.id} organisationId={org.id} requestId={randomUUID()} businessDate={day} brands={brands} locations={locations} initial={params.new === "1" ? undefined : packet!}/> : detailError ? <p className="auth-alert" role="alert">This menu item or version is unavailable in this business.</p> : packet ? <>
   <div className="menu-toolbar"><Link className="record-edit" href={query()}><ArrowLeft size={14}/> All menu items</Link>{packet.versions.length > 0 && <form key={packet.version?.id ?? "legacy"} method="get"><input type="hidden" name="organisation" value={org.id}/><input type="hidden" name="item" value={packet.item.id}/><label htmlFor="menu-saved-version">Saved menu version</label><select id="menu-saved-version" name="version" defaultValue={packet.version?.id}>{packet.versions.map(version => <option key={version.id} value={version.id}>Version {version.version} · {String(version.effective_from).slice(0,10)}</option>)}</select><button type="submit" className="secondary-button">View version</button></form>}{canEdit && packet.item.is_active && <Link className="secondary-button" href={query({ item: packet.item.id, ...(packet.version ? { version: packet.version.id } : {}), edit: "1" })}>Create menu version</Link>}{canEdit && <MenuStatusButton organisationId={org.id} packet={packet}/>}</div>
   <section className="menu-panel menu-item-summary"><p className="eyebrow form-eyebrow">{packet.item.code} · {packet.item.is_active ? "ACTIVE" : "INACTIVE"}</p><h2>{packet.version?.name ?? packet.item.name}</h2><p className="menu-intro">{brands.find(brand => brand.id === packet.item.brand_id)?.name ?? "Brand not assigned"}{packet.version?.category ? ` · ${packet.version.category}` : ""}</p>{packet.version && packet.recipe ? <p className="menu-recipe-binding">Each sold item uses <strong>{displayQuantity(packet.version.recipe_quantity)} {packet.recipe.uom_code}</strong> of <Link className="record-edit" href={`/workspace/recipes?organisation=${org.id}&version=${packet.recipe.id}`}>{packet.recipe.label}</Link> ({packet.recipe.code}). Includes its saved ingredient and packaging quantities.</p> : <p className="catalogue-readonly">Incomplete Record: add a final recipe. Cost per serving will populate once its ingredients are priced.</p>}{packet.version?.notes && <p className="menu-intro">{packet.version.notes}</p>}</section>
   {!packet.version&&canEdit&&!addingPrice&&<Link className="secondary-button" href={query({item:packet.item.id,price:"1"})}>Add selling price</Link>}
   {addingPrice ? <MenuPriceEditor organisationId={org.id} packet={packet} requestId={randomUUID()} businessDate={day} currency={org.currency_code} locations={validLocations}/> : packet.version && packet.item.is_active && <section className="menu-panel menu-margin-preview" aria-labelledby="menu-margin-title"><div className="menu-section-heading"><h2 id="menu-margin-title">Estimated food margin</h2>{estimate && <span className="menu-badge">{estimate.cost_state === "ESTIMATED" ? "Estimated" : "Incomplete"}</span>}{canEdit && <Link className="secondary-button" href={query({ item: packet.item.id, ...(packet.version ? { version: packet.version.id } : {}), price: "1" })}>Add selling price <Plus size={14}/></Link>}</div>
    <form key={`${packet.version.id}-${locationId}-${channel}-${date}`} method="get" className="menu-preview-filters"><input type="hidden" name="organisation" value={org.id}/><input type="hidden" name="item" value={packet.item.id}/><input type="hidden" name="version" value={packet.version.id}/><div className="setup-field"><label htmlFor="preview-location">Preview location</label><select id="preview-location" name="location" defaultValue={locationId} required><option value="">Choose a location</option>{validLocations.map(location => <option key={location.id} value={location.id}>{location.name}</option>)}</select></div><div className="setup-field"><label htmlFor="preview-channel">Preview sales channel</label><select id="preview-channel" name="channel" defaultValue={channel}>{menuChannels.map(([code, label]) => <option key={code} value={code}>{label}</option>)}</select></div><div className="setup-field"><label htmlFor="menu-preview-date">Preview date</label><input id="menu-preview-date" name="date" type="date" min={String(packet.version.effective_from).slice(0,10)} max={day} defaultValue={date} required/></div><button className="secondary-button" type="submit">Update margin</button></form>
    {estimateError ? <p role="alert" className="auth-alert">{estimateError}</p> : estimate && <>
     {estimate.price_issue && <p className="menu-missing" role="status">{estimate.price_issue === "EXPIRED_SELLING_PRICE" ? "The latest selling price has expired for this date." : estimate.price_issue === "PRICE_CURRENCY_MISMATCH" ? "The selling price currency does not match this business." : "No selling price is available for this location, channel and date."} Add a usable price to calculate the full margin.</p>}
     {estimate.recipe_estimate.missing_count > 0 && <div className="menu-missing" role="status"><p>Recipe cost incomplete: {estimate.recipe_estimate.missing_count} {estimate.recipe_estimate.missing_count === 1 ? "material needs" : "materials need"} a usable price. The full food margin is unavailable.</p>{estimate.recipe_estimate.lines.filter(line => line.missing_reason).map(line => <Link key={line.item_id} className="record-edit" href={`/workspace/materials/prices?organisation=${org.id}&item=${line.item_id}`}>{line.name} · Review reference price <ArrowRight size={13}/></Link>)}</div>}
     <div className="menu-margin-cards"><article><span>Net selling revenue</span><strong>{estimate.net_revenue === null ? "Unavailable" : money(estimate.net_revenue)}</strong><small>Per sold item, excluding declared tax</small></article><article><span>Estimated ingredient & packaging cost</span><strong>{estimate.estimated_food_cost === null ? "Incomplete" : money(estimate.estimated_food_cost)}</strong><small>From this menu version’s recipe quantity</small></article><article className={estimate.estimated_food_margin?.startsWith("-") ? "menu-negative" : ""}><span>Estimated food margin</span><strong>{estimate.estimated_food_margin === null ? "Unavailable" : money(estimate.estimated_food_margin)}</strong><small>{estimate.food_margin_percent === null ? "Requires a complete recipe cost and selling price" : `${displayPercent(estimate.food_margin_percent)}% of net selling revenue`}</small></article></div>
     {estimate.price && estimate.net_revenue !== null && <div className="menu-tax-breakdown"><p>Customer total: <strong>{money(estimate.customer_total!)}</strong> · Declared tax: <strong>{money(estimate.tax_amount!)}</strong></p><p>{menuTaxSettings.find(([code]) => code === estimate!.price!.tax_setting)?.[1]} · Rate {displayQuantity(estimate.price.tax_percent)}% · Price entry {estimate.price.version} · Starts {estimate.price.effective_from}</p>{estimate.food_cost_percent !== null && <p>Estimated food cost: {displayPercent(estimate.food_cost_percent)}% of net selling revenue.</p>}</div>}
    </>}
    <p className="menu-intro"><Info size={15}/> Live reference-price estimate for one sold item. Adding price corrections or material reference prices can change this preview. This food margin excludes labour, overheads, discounts, service charges and channel fees; it is not actual or operating profit.</p>
   </section>}
   {!packet.item.is_active && <p className="catalogue-readonly">This menu item is inactive. Reactivate it before publishing or previewing new sales margins.</p>}
   <section className="menu-panel menu-price-history"><div className="menu-section-heading"><h2>Selling price history</h2>{canEdit && packet.item.is_active && packet.version && !addingPrice && <Link className="record-edit" href={query({ item: packet.item.id, ...(packet.version ? { version: packet.version.id } : {}), price: "1" })}>Add another price <ArrowRight size={14}/></Link>}</div><p className="menu-intro">Latest 25 saved entries. For each location and channel, the latest effective date takes priority; same-date corrections use the newest entry. Earlier prices do not resume after a newer price expires.</p><DataTable label="Selling price history" columns={[{label:"Entry"},{label:"Outlet / channel"},{label:"Price",numeric:true},{label:"Effective dates"},{label:"Tax basis"},{label:"Notes"}]} rows={packet.prices.map(price=>({id:price.id,cells:[`Entry ${price.version}`,<span key="scope">{locations.find(location=>location.id===price.location_id)?.name??"Saved location"}<small>{menuChannels.find(([code])=>code===price.channel_code)?.[1]}</small></span>,referenceAmount(price.price,price.currency_code),<span key="dates">From {price.effective_from}<small>{price.effective_to?`Through ${price.effective_to}`:"Until superseded"}</small></span>,<span key="tax">{menuTaxSettings.find(([code])=>code===price.tax_setting)?.[1]}<small>{displayQuantity(price.tax_percent)}%</small></span>,price.notes||"Not provided"]}))} empty="No dated selling prices yet. No price is inferred from old legacy values."/></section>
  </> : <>
   <form method="get" className="catalogue-filter"><input type="hidden" name="organisation" value={org.id}/><div><Search size={16}/><label className="sr-only" htmlFor="menu-search">Search menu items</label><input id="menu-search" name="q" type="search" placeholder="Search menu items by name" defaultValue={q} maxLength={80}/></div><button className="secondary-button" type="submit">Search</button></form>
   {listError ? <p className="auth-alert" role="alert">We could not load your menu items. Please refresh and try again.</p> : list.length ? <DataTable label="Menu item catalogue" columns={[{label:"Menu item"},{label:"Code"},{label:"Brand"},{label:"Setup readiness"},{label:"Status"},{label:"Action"}]} rows={list.map(item=>({id:item.id,cells:[item.name,item.code,brands.find(brand=>brand.id===item.brand_id)?.name??"Brand needs review",<span key="readiness"><StatusBadge tone={profiles[item.id]?.missing?.length?"warning":"neutral"}>{profiles[item.id]?profiles[item.id].missing?.length?"Incomplete Record":"Ready":"Unavailable"}</StatusBadge><small>{profiles[item.id]?.missing?.join(", ")}</small><small>{profiles[item.id]?.primary_category??"Category needed"} / {profiles[item.id]?.location_id?locations.find(l=>l.id===profiles[item.id].location_id)?.name:"Business-wide"}</small></span>,<StatusBadge key="state" tone={item.is_active?"success":"neutral"}>{item.is_active?"Active":"Inactive"}</StatusBadge>,<Link key="view" className="inline-link" href={query({item:item.id})} aria-label={`View menu item ${item.name}`}>Recipe, prices & margin <ArrowRight size={14}/></Link>]}))}/> : <section className="catalogue-empty"><h2>{q ? "No matching menu items" : "Start with one dish you sell"}</h2><p>{q ? "Try another menu name." : "Create a final recipe first, then link one portion or measured output to a menu item and add its selling price."}</p><Link className="auth-back" href={`/workspace/recipes?organisation=${org.id}`}>Open recipes <ArrowRight size={14}/></Link></section>}
   {(total > 25 || page > 1) && <div className="catalogue-pagination"><p>{total} menu items · Page {page}</p><div>{page > 1 && <Link href={query({ q, page: String(page - 1) })}>Previous</Link>}{page * 25 < total && <Link href={query({ q, page: String(page + 1) })}>Next <ArrowRight size={14}/></Link>}</div></div>}
  </>}
 </WorkspaceShell>;
}
