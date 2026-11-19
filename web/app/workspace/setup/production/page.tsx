import {workspacePolicy} from "@/lib/workspace-policy-server";
import Link from 'next/link';
import {requireUser,getPlatformAccess,workspacePath} from '@/lib/auth';
import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
import {WorkspaceShell} from '@/app/components/workspace-shell';
import {DataTable,StatusBadge} from '@/app/components/data-table';
import {StockOutputBinding} from '../../inventory/forms';
import {GuidedBaselineForm} from './guided-baseline-form';import {ProcessingStandardForm} from './standard-form';import type {ProcessingSetup} from '@/lib/processing';
import type {StockPacket} from '@/lib/inventory';
import {referenceAmount} from '@/lib/reference-prices';
import {displayQuantity} from '@/lib/recipes';
import {materialCostIssue,type MaterialCost} from '@/lib/material-costs';
import '../../materials/catalogue.css';import '../../inventory/inventory.css';import './production.css';
export const instant=false;
export default async function ProductionSetup({searchParams}:{searchParams:Promise<{organisation?:string;page?:string;sp?:string}>}){
 const user=await requireUser(),access=await getPlatformAccess();if(access!=='member')redirect(workspacePath(access));
 const p=await searchParams,client=await createClient(),orgs=await client.from('organisations').select('id,name,time_zone').order('name'),org=p.organisation?orgs.data?.find(o=>o.id===p.organisation):orgs.data?.[0];
 if(!org)return <WorkspaceShell email={user.email}><h1>Business unavailable</h1></WorkspaceShell>;if(!(await workspacePolicy(org.id)).canStockSetup)redirect(`/workspace?organisation=${org.id}`);
 const result=await client.rpc('stock_workspace_v2',{p_organisation_id:org.id,p_location_id:null,p_page:1,p_status:'ALL',p_search:'',p_document_id:null}),packet=result.data as StockPacket|null;
 const page=Math.max(1,Math.min(100000,Number.parseInt(p.page??'1',10)||1)),outputs=packet?.items.filter(i=>['SEMI_FINISHED','FINISHED'].includes(i.item_type))??[],visible=outputs.slice((page-1)*10,page*10);
 const setupResult=await client.rpc('processing_setup',{p_organisation_id:org.id}),setup=setupResult.data as ProcessingSetup|null;
 const [materials,units,admin]=await Promise.all([client.from('items').select('id,code,name,base_uom_id,requires_processing,item_type,supply_class,stock_tracked,is_active').eq('organisation_id',org.id).order('name'),client.from('units_of_measure').select('id,code').eq('organisation_id',org.id),client.rpc('team_access',{p_organisation_id:org.id})]);
 const standardPage=Math.max(1,Math.min(100000,Number.parseInt(p.sp??'1',10)||1));
 const canProduce=packet?.locations.some(s=>s.request)??false;
 const today=new Intl.DateTimeFormat('en-CA',{timeZone:org.time_zone,year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 const permission=packet?await client.rpc('reference_price_access',{p_organisation_id:org.id}):null;
 const costsResult=permission?.data?.read&&visible.length?await client.rpc('material_cost_estimates',{p_organisation_id:org.id,p_ids:visible.map(i=>i.id),p_as_of:today}):null,costs=(costsResult?.data??{}) as Record<string,MaterialCost>;
 return <WorkspaceShell email={user.email} restaurantName={org.name} organisationId={org.id} sectionLabel="Processed materials">
  <Link className="catalogue-back" href={`/workspace/setup?organisation=${org.id}`}>Back to setup</Link>
  <h1 className="workspace-title">Processing baselines</h1>
  <p className="workspace-description">Set expected input and output quantities before recording batches.</p>
  <nav className="processing-steps"><Link href={`/workspace/setup/centres?organisation=${org.id}`}>1. Stock centres</Link><strong>2. Output SKU & processing baseline</strong><Link href={`/workspace/inventory/processing?organisation=${org.id}`}>3. Production & waste history</Link></nav>
  {result.error||!packet?<p role="alert">Inventory setup access is required.</p>:<>
   {setup?.processing_centre_id&&admin.data===true?<section className="stock-panel"><GuidedBaselineForm org={org.id} request={crypto.randomUUID()} materials={materials.data??[]} units={units.data??[]} today={today} centre={setup.sites.find(s=>s.id===setup.processing_centre_id)?.name??'your processing unit'}/></section>:<p className="stock-help">To use guided baseline setup, assign the stock centre owners and <Link className="inline-link" href={`/workspace/setup/centres?organisation=${org.id}`}>choose the business processing unit</Link> first. Your existing recipes and output links remain available below.</p>}
   <details className="stock-panel"><summary>Existing recipes: link a produced SKU</summary><h2>Your next step: link recipe to produced SKU</h2>
    <p>If your two materials and processing recipe are already saved, use the form below: choose the published processing recipe, choose its output SKU, then select <strong>Link recipe stock output</strong>.</p>
    <p className="stock-help">For snapper: 40 kg of whole fish produces 120 pieces of cut fish. Estimated cost per piece = total input cost / 120. You do not need to enter a separate price for a processed SKU.</p>
    {packet.manage&&<StockOutputBinding organisation={org.id} packet={packet}/>}</details>
   {setup?.manage&&<details className="stock-panel" id="processing-standard"><summary>Existing recipes: save or revise a processing baseline</summary><ProcessingStandardForm org={org.id} packet={packet} setup={setup} request={crypto.randomUUID()}/></details>}
   {setup?.standards.length? <section className="stock-panel"><h2>Approved processing baselines</h2><DataTable label="Processing baselines" columns={[{label:'Process'},{label:'Main input'},{label:'Expected output'},{label:'Permitted centres'},{label:'Specification'}]} rows={setup.standards.slice((standardPage-1)*10,standardPage*10).map(s=>({id:s.id,cells:[`${s.recipe_name} / revision ${s.revision}`,`${displayQuantity(s.primary_quantity)} ${s.primary_unit} ${s.primary_name}`,`${displayQuantity(s.expected_output)} ${s.output_unit} ${s.output_name}`,s.site_ids.map(id=>setup.sites.find(c=>c.id===id)?.name??'Centre').join(', '),`${s.output_spec} / tolerance ${displayQuantity(s.tolerance_percent)}%`]}))}/><nav className="invoice-nav" aria-label="Processing baseline pages">{standardPage>1&&<Link href={`?organisation=${org.id}&sp=${standardPage-1}`}>Previous baselines</Link>}{standardPage*10<setup.standards.length&&<Link href={`?organisation=${org.id}&sp=${standardPage+1}`}>Next baselines</Link>}</nav></section>:<p className="stock-help">After linking the produced SKU, save the processing baseline and permitted centres before recording a batch.</p>}
   <section className="stock-panel"><h2>Processed SKU costs</h2>
    {costsResult?.error&&<p role="alert">Processed costs are unavailable. Ask your administrator to complete the processing-cost update, then refresh.</p>}
    <DataTable label="Processing recipe master data" columns={[{label:'Produced material'},{label:'Processing recipe'},{label:'Standard batch'},{label:'Estimated cost / unit',numeric:true},{label:'Status'}]} rows={visible.map(i=>{
     const cost=costs[i.id],binding=packet.recipes.find(r=>r.item_id===i.id),version=cost?.recipe_version_id??binding?.id;
     return{id:i.id,cells:[<span key="item">{i.name}<small>{i.code} / {i.unit}</small></span>,version?<Link key="recipe" className="inline-link" href={`/workspace/recipes?organisation=${org.id}&version=${version}`}>{cost?.recipe_name??binding?.name}</Link>:'Choose a recipe below',cost?.recipe_output_quantity?`${displayQuantity(cost.recipe_output_quantity)} ${i.unit}`:binding?`${displayQuantity(binding.yield)} ${binding.unit}`:'Not linked',cost?.unit_cost?`${referenceAmount(cost.unit_cost,cost.currency_code)} / ${i.unit}`:permission?.data?.read?materialCostIssue(cost?.missing_reason):'Financial access required',<StatusBadge key="status" tone={cost?.unit_cost?'success':'warning'}>{cost?.unit_cost?'Estimated':cost?materialCostIssue(cost.missing_reason):binding?'Linked':'Output link needed'}</StatusBadge>]};
    })} empty="Create a tracked semi-finished or finished material to connect its processing recipe."/>
    <nav className="invoice-nav" aria-label="Processing output pages">{page>1&&<Link href={`?organisation=${org.id}&page=${page-1}`}>Previous outputs</Link>}{page*10<outputs.length&&<Link href={`?organisation=${org.id}&page=${page+1}`}>Next outputs</Link>}</nav>
    <p className="stock-help">Costs use the latest linked recipe version effective on {today}. Linking does not add or deduct stock. After checking the recipe and ensuring input stock is available, submit the actual quantities in the Material Processing Log. Stock updates at that centre without approval.</p>
    {canProduce?<Link className="secondary-button" href={`/workspace/inventory/processing/new?organisation=${org.id}`}>Record material processing</Link>:packet.locations.length>0?<><p className="stock-help">An authorised colleague at the processing centre records processing. Your current access allows reviewing its setup and history.</p><Link className="secondary-button" href={`/workspace/inventory?organisation=${org.id}&view=movements`}>View production records</Link></>:<><p className="stock-help">Add a processing stock location and establish the whole-fish stock before recording your first batch.</p><Link className="secondary-button" href={`/workspace/setup/centres?organisation=${org.id}`}>Set up a processing stock location</Link></>}
   </section>
   <details className="stock-panel"><summary>Set up materials and processing from the beginning</summary><ol className="production-setup-steps"><li>Create the purchased input SKU with its base unit, such as Whole Snapper Fish (KG).</li><li>Create the output as a tracked Semi-finished or Finished material with supply source Processed, such as Snapper Cut (PCS).</li><li>Publish a sub-recipe: for example, 40 KG of whole fish yields 120 PCS.</li><li>Use the link form above to connect the recipe to Snapper Cut.</li></ol><p className="stock-help">Record measured trim/waste separately. The recipe supports one output SKU; it does not assume a weight for each piece.</p><nav className="invoice-nav"><Link className="secondary-button" href={`/workspace/materials?organisation=${org.id}`}>Set up material SKUs</Link><Link className="secondary-button" href={`/workspace/recipes?organisation=${org.id}`}>Set up processing recipes</Link></nav></details>
  </>}
 </WorkspaceShell>;
}
