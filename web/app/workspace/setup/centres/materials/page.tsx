import {randomUUID} from 'node:crypto';
import Link from 'next/link';
import {redirect} from 'next/navigation';
import {requireUser,getPlatformAccess,workspacePath} from '@/lib/auth';
import {createClient} from '@/lib/supabase/server';
import {workspacePolicy} from '@/lib/workspace-policy-server';
import {isUuid} from '@/lib/catalogue';
import type {CentreCatalogue} from '@/lib/centre-materials';
import {WorkspaceShell} from '@/app/components/workspace-shell';
import {CentreMaterialsForm} from './form';
import '../../../inventory/inventory.css';import '../../../materials/catalogue.css';
export const instant=false;
export default async function Page({searchParams}:{searchParams:Promise<{organisation?:string;site?:string;saved?:string}>}){
 const user=await requireUser(),access=await getPlatformAccess();if(access!=='member')redirect(workspacePath(access));const p=await searchParams,client=await createClient(),orgs=await client.from('organisations').select('id,name').order('name'),org=p.organisation?orgs.data?.find(o=>o.id===p.organisation):orgs.data?.[0];if(!org)redirect('/workspace');
 if(!(await workspacePolicy(org.id)).canStockSetup)redirect(`/workspace?organisation=${org.id}`);
 const r=p.site&&isUuid(p.site)?await client.rpc('centre_material_catalogue',{p_organisation_id:org.id,p_site_id:p.site}):null,packet=r?.data as CentreCatalogue|null;
 return <WorkspaceShell email={user.email} organisationId={org.id} restaurantName={org.name} sectionLabel="Centre materials"><Link className="catalogue-back" href={`/workspace/setup/centres?organisation=${org.id}`}>Back to stock centres</Link><h1 className="workspace-title">{packet?`${packet.centre} materials`:'Centre materials'}</h1><p className="workspace-description">Choose the materials this centre may hold, request, process or record as waste.</p>{p.saved==='1'&&<p role="status" className="stock-success">Centre material list saved. Stock quantities and history are unchanged.</p>}{packet&&!r?.error?<CentreMaterialsForm key={`${p.site}:${packet.revision}`} org={org.id} site={p.site!} packet={packet} token={randomUUID()}/>:<p role="alert" className="auth-alert">The centre material list is unavailable. Choose a valid centre and check the latest database update.</p>}</WorkspaceShell>;
}
