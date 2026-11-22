import Link from "next/link";
import { redirect } from "next/navigation";
import { requireUser, getPlatformAccess, workspacePath } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { WorkspaceShell } from "@/app/components/workspace-shell";
import { DataTable } from "@/app/components/data-table";
import { displayQuantity } from "@/lib/recipes";
import { SubmitOpeningForm } from "./form";
import "../../materials/catalogue.css";
import "../inventory.css";
import "../../imports/imports.css";
type Batch = {id: string; centre: string; date: string; can_submit: boolean; lines: {name: string; code: string; quantity: string; unit: string}[]};
export const instant = false;
export default async function Page({searchParams}: {searchParams: Promise<{organisation?: string; saved?: string}>}) {
 const user = await requireUser(), access = await getPlatformAccess(); if (access !== "member") redirect(workspacePath(access));
 const p = await searchParams, client = await createClient();
 const orgs = await client.from("organisations").select("id,name").order("name");
 const org = p.organisation ? orgs.data?.find(o => o.id === p.organisation) : orgs.data?.[0]; if (!org) redirect("/workspace");
 const result = await client.rpc("import_opening_queue", {p_organisation_id: org.id});
 return <WorkspaceShell email={user.email} restaurantName={org.name} organisationId={org.id} sectionLabel="Imported opening stock"><Link className="catalogue-back" href={`/workspace/inventory?organisation=${org.id}`}>Back to inventory</Link><h1 className="workspace-title">Imported opening stock</h1><p className="workspace-description">Check the quantities prepared during material import. Positive openings need independent review and posting; verified zeros are confirmed without a stock movement.</p>{p.saved === "zero" && <p role="status" className="stock-success">Zero openings confirmed. No stock quantities were added.</p>}{result.error ? <p role="alert">Openings could not be loaded. Check your stock access and database update 057.</p> : !(result.data as Batch[])?.length ? <section className="stock-panel"><p>No imported openings are awaiting submission.</p></section> : (result.data as Batch[]).map(b => <section className="stock-panel" key={b.id}><h2>{b.centre}</h2><p className="stock-help">Opening date: {b.date}</p><div className="import-opening-table"><DataTable label={`${b.centre} imported openings`} columns={[{label: "Material"}, {label: "Unit"}, {label: "Opening quantity", numeric: true}]} rows={b.lines.map(l => ({id: l.code, cells: [<span key="name">{l.name}<small>{l.code}</small></span>, l.unit, displayQuantity(l.quantity)]}))}/></div>{b.can_submit ? <SubmitOpeningForm org={org.id} batch={b.id}/> : <p className="stock-help">An authorised Inventory user at this centre must submit these quantities. Batches containing zero openings require Inventory Manager access.</p>}</section>)}</WorkspaceShell>;
}
