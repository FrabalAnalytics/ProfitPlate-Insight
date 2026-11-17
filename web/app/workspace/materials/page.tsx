import {DataTable,StatusBadge} from "@/app/components/data-table";
import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { ArrowLeft, ArrowRight, Boxes, Building2, Info, Plus, Search, Scale, Truck } from "lucide-react";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { isUuid, itemTypes, type Material, type Supplier, type Unit } from "@/lib/catalogue";
import { WorkspaceShell } from "@/app/components/workspace-shell";
import { CatalogueEditor } from "./catalogue-editor";
import "./catalogue.css";

export const metadata: Metadata = { title: "Materials & suppliers | ProfitPlate Insight" };
export const instant = false;
const pageSize = 25;
type Params = { organisation?: string; tab?: string; q?: string; page?: string; status?: string; new?: string; edit?: string; item?: string; saved?: string };

export default async function MaterialsPage({ searchParams }: { searchParams: Promise<Params> }) {
  const user = await requireUser();
  const access = await getPlatformAccess();
  if (access !== "member") redirect(workspacePath(access));
  const params = await searchParams;
  const supabase = await createClient();
  const { data: organisations, error: organisationError } = await supabase.from("organisations").select("id,name,time_zone").order("name");
  if (organisationError) return <WorkspaceShell email={user.email}><h1 className="workspace-title">We couldn’t load your business.</h1><p className="workspace-description">Please refresh and try again.</p></WorkspaceShell>;
  if (!organisations?.length) redirect("/onboarding");
  const organisation = params.organisation ? organisations.find(org => org.id === params.organisation) : organisations[0];
  if (!organisation) return <WorkspaceShell email={user.email}><h1 className="workspace-title">This business isn’t available to your account.</h1><Link className="auth-back" href="/workspace">Return to your workspace</Link></WorkspaceShell>;
  const orgId = organisation.id;
  const tab = ["materials", "suppliers", "conversions"].includes(params.tab ?? "") ? params.tab! : "materials";
  const query = (extra: Record<string, string> = {}) => {
    const entries = { organisation: orgId, tab, ...extra };
    return `/workspace/materials?${new URLSearchParams(entries).toString()}`;
  };
  const [unitsResult, categoriesResult, permission] = await Promise.all([
    supabase.from("units_of_measure").select("id,code,name,dimension").eq("organisation_id", orgId).order("code"),
    supabase.from("item_categories").select("id,name").eq("organisation_id", orgId).order("name"),
    supabase.rpc("can_manage_catalogue", { p_organisation_id: orgId }),
  ]);
  const canEdit = permission.data === true && !permission.error;
  if (unitsResult.error || categoriesResult.error || permission.error) return <WorkspaceShell email={user.email} restaurantName={organisation.name} organisationId={orgId} sectionLabel="Materials & suppliers"><p className="eyebrow form-eyebrow">DATA & SETUP</p><h1 className="workspace-title">Catalogue setup is temporarily unavailable.</h1><p className="workspace-description">Please try again shortly. The platform administrator may need to finish the catalogue update.</p><a href={query()} className="auth-back">Try again</a></WorkspaceShell>;
  const units = (unitsResult.data ?? []) as Unit[];
  const categories = categoriesResult.data ?? [];
  const unit = (id: string) => units.find(entry => entry.id === id);
  const q = (params.q ?? "").trim().slice(0, 80);
  const page = Math.min(100000, Math.max(1, Number.parseInt(params.page ?? "1", 10) || 1));
  const filter = q ? `%${q.replace(/[\\%_]/g, "\\$&")}%` : "";
  const materialFields = "id,code,name,item_type,category_id,base_uom_id,stock_tracked,is_active";
  const supplierFields = "id,code,name,email,phone,address,is_active";
  let materials: Material[] = [], suppliers: Supplier[] = [];
  let conversions: { id: string; item_id: string; from_uom_id: string; to_uom_id: string; factor: string | number; effective_from: string }[] = [];
  let total = 0, loadError = false;
  let chosenItem: Material | null = null;
  let editing: Material | Supplier | null = null;
  if (tab !== "conversions") {
    let request = supabase.from(tab === "suppliers" ? "suppliers" : "items")
      .select(tab === "suppliers" ? supplierFields : materialFields, { count: "exact" }).eq("organisation_id", orgId).order("name").order("id");
    if (filter) request = request.ilike("name", filter);
    if (params.status === "active" || params.status === "inactive") request = request.eq("is_active", params.status === "active");
    const result = await request.range((page - 1) * pageSize, page * pageSize - 1);
    loadError = !!result.error;
    total = result.count ?? 0;
    if (tab === "materials") materials = (result.data ?? []) as unknown as Material[];
    else suppliers = (result.data ?? []) as unknown as Supplier[];
    if (params.edit && isUuid(params.edit)) {
      const editResult = await supabase.from(tab === "materials" ? "items" : "suppliers")
        .select(tab === "materials" ? materialFields : supplierFields).eq("organisation_id", orgId).eq("id", params.edit).maybeSingle();
      editing = editResult.data as unknown as Material | Supplier | null;
    }
  } else if (params.item && isUuid(params.item)) {
    const result = await supabase.from("items").select(materialFields).eq("organisation_id", orgId).eq("id", params.item).maybeSingle();
    chosenItem = result.data as Material | null;
    if (chosenItem) {
      const result = await supabase.from("item_uom_conversions").select("id,item_id,from_uom_id,to_uom_id,factor,effective_from", { count: "exact" })
        .eq("organisation_id", orgId).eq("item_id", chosenItem.id).order("effective_from", { ascending: false }).range((page - 1) * pageSize, page * pageSize - 1);
      conversions = result.data ?? []; total = result.count ?? 0; loadError = !!result.error;
    }
  }
  let priceCoverage: Record<string, boolean> | null = null;
  let priceAccess = false;
  let priceAccessUnavailable = false;
  if (tab === "materials" && materials.length) {
    const permission = await supabase.rpc("reference_price_access", { p_organisation_id: orgId });
    priceAccessUnavailable = !!permission.error;
    priceAccess = !permission.error && permission.data?.read === true;
    if (priceAccess) {
      const coverage = await supabase.rpc("material_reference_price_coverage", { p_organisation_id: orgId, p_item_ids: materials.map(material => material.id) });
      if (!coverage.error) priceCoverage = coverage.data as Record<string, boolean>;
    }
  }
  const priceLabel = (id: string) => priceCoverage === null ? priceAccess || priceAccessUnavailable ? "Unavailable" : "Restricted" : priceCoverage[id] ? "Estimated" : "Missing price";
  const priceCell = (id: string) => priceCoverage === null ? <span className="cost-missing">{priceLabel(id)}</span> : <Link className="record-edit" href={`/workspace/materials/prices?organisation=${orgId}&item=${id}`}>{priceLabel(id)} <ArrowRight size={12} /></Link>;
  const showEditor = canEdit && (params.new === "1" || !!editing) && (tab !== "conversions" || chosenItem?.is_active);
  const dayParts = new Intl.DateTimeFormat("en", { timeZone: organisation.time_zone, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(new Date());
  const day = ["year", "month", "day"].map(key => dayParts.find(part => part.type === key)?.value).join("-");
  const initial: Record<string, string> = tab === "conversions" ? {
    item_id: chosenItem?.id ?? "", base_uom_id: chosenItem?.base_uom_id ?? "", from_uom_id: units.find(entry => entry.code === "BAG")?.id ?? "", factor: "", effective_from: day,
  } : tab === "materials" ? {
    id: editing?.id ?? "", code: editing?.code ?? "", name: editing?.name ?? "", item_type: (editing as Material)?.item_type ?? "RAW",
    category: categories.find(category => category.id === (editing as Material)?.category_id)?.name ?? "",
    base_uom_id: (editing as Material)?.base_uom_id ?? units.find(entry => entry.code === "KG")?.id ?? "",
    stock_tracked: String((editing as Material)?.stock_tracked ?? true), is_active: String(editing?.is_active ?? true),
  } : {
    id: editing?.id ?? "", code: editing?.code ?? "", name: editing?.name ?? "", email: (editing as Supplier)?.email ?? "", phone: (editing as Supplier)?.phone ?? "", address: (editing as Supplier)?.address ?? "", is_active: String(editing?.is_active ?? true),
  };
  const pagination = total > pageSize || page > 1 ? <div className="catalogue-pagination"><p>{total} matching {tab === "conversions" ? "versions" : tab} · page {page}</p><div>{page > 1 && <Link href={query({ page: String(page - 1), q, status: params.status ?? "all", ...(chosenItem ? { item: chosenItem.id } : {}) })}><ArrowLeft size={14} /> Previous</Link>}{page * pageSize < total && <Link href={query({ page: String(page + 1), q, status: params.status ?? "all", ...(chosenItem ? { item: chosenItem.id } : {}) })}>Next <ArrowRight size={14} /></Link>}</div></div> : null;

  return <WorkspaceShell email={user.email} restaurantName={organisation.name} organisationId={orgId} sectionLabel="Materials & suppliers">
    <Link className="catalogue-back" href={`/workspace?organisation=${orgId}`}><ArrowLeft size={14} /> Business setup</Link>
    <div className="page-heading-row"><div><p className="eyebrow form-eyebrow">DATA & SETUP / CATALOGUE</p><h1 className="workspace-title">The building blocks of every plate.</h1><p className="workspace-description">Organise your materials, suppliers and the units behind your quantities.</p></div>{canEdit && (tab !== "conversions" || chosenItem?.is_active) && <Link className="auth-button catalogue-add" href={query({ new: "1", ...(chosenItem ? { item: chosenItem.id } : {}) })}><Plus size={16} /> {tab === "materials" ? "Add material" : tab === "suppliers" ? "Add supplier" : "Add conversion"}</Link>}</div>
    {!canEdit && <p className="catalogue-readonly"><Info size={16} /> You have read-only catalogue access. An organisation-wide restaurant administrator or procurement manager can make changes.</p>}
    <nav className="catalogue-tabs" aria-label="Catalogue sections">{[["materials", "Materials", Boxes], ["suppliers", "Suppliers", Truck], ["conversions", "Units & conversions", Scale]].map(([key, title, Icon]) => <Link key={String(key)} href={query({ tab: String(key) })} aria-current={tab === key ? "page" : undefined}>{typeof Icon !== "string" && <Icon size={16} />}{String(title)}</Link>)}</nav>
    <p className="catalogue-readonly"><Info size={16} /><span>Ready to add the prices you know? <Link className="record-edit" href={`/workspace/materials/prices?organisation=${orgId}`}>Initial material prices <ArrowRight size={14} /></Link> This step is optional; unpriced materials stay visible as missing.</span></p>
    {params.saved && ["material", "supplier", "conversion"].includes(params.saved) && <p className="welcome-message" role="status">Your {params.saved} has been saved.</p>}
    {showEditor && <CatalogueEditor key={`${tab}-${editing?.id ?? chosenItem?.id ?? "new"}`} kind={tab === "materials" ? "material" : tab === "suppliers" ? "supplier" : "conversion"} organisationId={orgId} initial={initial} units={units} materialName={chosenItem?.name} />}
    {params.edit && !editing && <p className="auth-alert" role="alert">This record isn’t available in this business.</p>}
    {tab !== "conversions" && <form method="get" className="catalogue-filter"><input type="hidden" name="organisation" value={orgId} /><input type="hidden" name="tab" value={tab} /><div><Search size={16} /><label className="sr-only" htmlFor="catalogue-search">Search {tab}</label><input id="catalogue-search" name="q" type="search" placeholder={`Search ${tab} by name…`} defaultValue={q} maxLength={80} /></div><label className="sr-only" htmlFor="catalogue-status">Record status</label><select id="catalogue-status" name="status" defaultValue={params.status ?? "all"}><option value="all">All statuses</option><option value="active">Active</option><option value="inactive">Inactive</option></select><button type="submit" className="secondary-button">Search</button></form>}
    {loadError ? <p className="auth-alert" role="alert">We couldn’t load these records. Please refresh and try again.</p> : tab === "materials" ? <>
      {materials.length ? <DataTable label={`Materials in ${organisation.name}`} columns={[{label:"Material"},{label:"Type / category"},{label:"Base unit"},{label:"Reference price"},{label:"Status"},{label:"Actions"}]} rows={materials.map(material=>({id:material.id,cells:[<span key="name">{material.name}<small>{material.code}</small></span>,<span key="type">{itemTypes.find(([code])=>code===material.item_type)?.[1]}<small>{categories.find(category=>category.id===material.category_id)?.name??"Uncategorised"}</small></span>,unit(material.base_uom_id)?.code,priceCell(material.id),<StatusBadge key="status" tone={material.is_active?"success":"neutral"}>{material.is_active?"Active":"Inactive"}</StatusBadge>,<div key="actions" className="record-actions">{canEdit&&<Link className="inline-link" href={query({edit:material.id})} aria-label={`Edit ${material.name}`}>Edit</Link>}<Link className="inline-link" href={query({tab:"conversions",item:material.id})} aria-label={`Manage units for ${material.name}`}>Units <ArrowRight size={13}/></Link></div>]}))}/> : <Empty icon="material" title={q ? "No matching materials" : "Your material catalogue starts here"} text={q ? "Try another name or clear the search filter." : "Add ingredients, packaging and other materials. Reference prices can be added afterwards; this step is optional."} />}
      {pagination}<p className="catalogue-bottom-note"><Info size={15} /> A saved material is not a costed material. Missing cost information will stay visible.</p>
    </> : tab === "suppliers" ? <>
      {suppliers.length ? <DataTable label={`Suppliers in ${organisation.name}`} columns={[{label:"Supplier"},{label:"Email / phone"},{label:"Address"},{label:"Status"},{label:"Action"}]} rows={suppliers.map(supplier=>({id:supplier.id,cells:[<span key="name">{supplier.name}<small>{supplier.code}</small></span>,<span key="contact">{supplier.email||"No email"}<small>{supplier.phone||"No phone"}</small></span>,supplier.address||"Not provided",<StatusBadge key="status" tone={supplier.is_active?"success":"neutral"}>{supplier.is_active?"Active":"Inactive"}</StatusBadge>,canEdit?<Link key="edit" className="inline-link" href={query({edit:supplier.id})} aria-label={`Edit ${supplier.name}`}>Edit</Link>:"Read-only"]}))}/> : <Empty icon="supplier" title={q ? "No matching suppliers" : "Keep your supplier details together"} text="Add the businesses you purchase from so future procurement records have a clear source." />}{pagination}
    </> : <>
      {params.item && !chosenItem && <p className="auth-alert" role="alert">This material isn’t available in this business.</p>}
      {chosenItem ? <><div className="conversion-context"><div><h2>{chosenItem.name}</h2><p>{chosenItem.code} · Base unit: {unit(chosenItem.base_uom_id)?.name} ({unit(chosenItem.base_uom_id)?.code})</p></div><Link href={query({ tab: "materials" })}>Choose another material <ArrowRight size={14} /></Link></div>{!chosenItem.is_active && <p className="catalogue-readonly">This material is inactive. Existing conversions remain visible; reactivate it before adding another version.</p>}{conversions.length ? <DataTable label="Saved material conversions" columns={[{label:"Purchase unit"},{label:"Base quantity",numeric:true},{label:"Base unit"},{label:"Effective from"}]} rows={conversions.map(conversion=>({id:conversion.id,cells:[`1 ${unit(conversion.from_uom_id)?.code}`,String(conversion.factor).replace(/(\.\d*?)0+$/,"$1").replace(/\.$/,""),unit(conversion.to_uom_id)?.code,String(conversion.effective_from).slice(0,10)]}))}/> : <Empty icon="unit" title="No conversions saved yet" text="A bag, carton or bottle has no assumed size. Add the quantity of this material that one package contains." />}{pagination}</> : <div className="conversion-intro"><Scale size={24} /><h2>Choose a material to define its conversions.</h2><p>Package sizes belong to a specific material. A bag of rice and a bag of flour can have different quantities.</p><Link className="secondary-button" href={query({ tab: "materials" })}>Choose from your materials <ArrowRight size={15} /></Link></div>}
      <section className="unit-dictionary"><div className="section-heading"><h2>Standard unit dictionary</h2><span>READ-ONLY DEFINITIONS</span></div><p>Mass, volume and count units have standard dimensions. Package sizes must be configured per material.</p><DataTable label="Standard unit dictionary" columns={[{label:"Code"},{label:"Unit name"},{label:"Dimension / conversion"}]} rows={units.map(entry=>({id:entry.id,cells:[entry.code,entry.name,entry.dimension==="PACKAGE"?"Item-specific size required":entry.dimension.toLowerCase()]}))}/></section>
    </>}
  </WorkspaceShell>;
}

function Empty({ icon, title, text }: { icon: string; title: string; text: string }) {
  const Icon = icon === "supplier" ? Building2 : icon === "unit" ? Scale : Boxes;
  return <section className="catalogue-empty"><span><Icon size={25} strokeWidth={1.5} /></span><h2>{title}</h2><p>{text}</p></section>;
}
