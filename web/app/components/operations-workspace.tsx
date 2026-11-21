import Link from 'next/link';
import {createClient} from '@/lib/supabase/server';
import {CurrentStockCard} from './current-stock-card';
import {WeeklyCountStatus,type WeeklyWorkspacePacket} from './weekly-count-status';
import {WasteWorkspaceStatus} from './waste-workspace-status';
import {DataTable,StatusBadge} from './data-table';
import {referenceAmount} from '@/lib/reference-prices';
import {displayPercent} from '@/lib/display';
import type {ExecutiveBriefing} from '@/lib/executive-briefing';
import type {WasteWorkspacePacket} from '@/lib/waste-accountability';
import './operations-workspace.css';

type OperationsPacket={today:string;queues:{task:string;count:number;overdue:number}[];rows:{id:string;reference:string;task:string;state:string;centre:string;date:string;path:string;params:Record<string,string>}[]};
type Outlet={id:string;name:string};
export async function OperationsWorkspace({organisation,timeZone,currency,waste,weekly,wasteError,weeklyError}:{organisation:string;timeZone:string;currency:string;waste:WasteWorkspacePacket|null;weekly:WeeklyWorkspacePacket|null;wasteError:boolean;weeklyError:boolean}){
 const client=await createClient();
 const [attention,access]=await Promise.all([client.rpc('operations_workspace',{p_organisation_id:organisation}),client.rpc('operations_access',{p_organisation_id:organisation})]);
 const packet=attention.data as OperationsPacket|null,outlets=(access.data?.outlets??[]) as Outlet[];
 const today=packet?.today??new Intl.DateTimeFormat('en-CA',{timeZone,year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 const menus=await Promise.all(outlets.map(async outlet=>({outlet,result:await client.rpc('selling_menu_profitability',{p_organisation_id:organisation,p_location_id:outlet.id,p_channel:'STANDARD',p_as_of:today,p_search:'',p_page:1,p_status:'AT_RISK',p_major:'ALL',p_subcategory:''})})));
 const menuError=!!access.error||menus.some(m=>m.result.error),risk=menus.reduce((n,m)=>n+Number(m.result.data?.summary?.at_risk??0),0);
 const prices=await Promise.all(outlets.map(async outlet=>({outlet,result:await client.rpc('operations_price_warnings',{p_organisation_id:organisation,p_outlet_id:outlet.id,p_from:today.slice(0,7)+'-01',p_to:today})})));
 const priceError=!!access.error||prices.some(p=>p.result.error||p.result.data?.unavailable);
 const query=(path:string,extra:Record<string,string>={})=>`${path}?${new URLSearchParams({organisation,...extra})}`;
 return <div className="operations-workspace">
  <section className="operations-priorities" aria-label="Operational priorities">
   <Link href={query('/workspace/inventory/waste/daily')}><span>Waste reports overdue</span><strong>{wasteError?'Unavailable':waste?.overdue??0}</strong><small>Centre-days requiring follow-up</small></Link>
   <Link href={query('/workspace/inventory/counts')}><span>Weekly counts overdue</span><strong>{weeklyError?'Unavailable':weekly?.backlog??0}</strong><small>{weeklyError?'Check count reporting':`${weekly?.review_waiting??0} awaiting review`}</small></Link>
   <Link href={query('/workspace/menus/profitability',{status:'AT_RISK'})}><span>Menus above cost target</span><strong>{menuError?'Unavailable':risk}</strong><small>Menu / outlet comparisons</small></Link>
  </section>
  <section className="operations-panel" aria-label="Needs Attention"><div className="operations-heading"><h2>Needs Attention</h2><Link href={query('/workspace/records')}>Open operational reports</Link></div>
   {attention.error?<p role="alert">Operational follow-up could not be loaded. Refresh and check database update 055.</p>:<>
    <div className="operations-queues">{packet?.queues.map(q=><a key={q.task} href="#operations-follow-up"><span>{q.task}</span><strong>{q.count}</strong>{q.overdue>0&&q.task!=='Processing outside yield tolerance'&&<small>{q.overdue} waiting over 24 hours</small>}</a>)}{!packet?.queues.length&&<p>No stock or purchasing follow-up waiting.</p>}</div>
    {!!packet?.rows.length&&<details id="operations-follow-up"><summary>Oldest follow-up records</summary><DataTable label="Operational follow-up" columns={[{label:'Record'},{label:'Follow-up'},{label:'Centre / outlet'},{label:'Status'}]} rows={packet.rows.map(r=>({id:r.task+r.id,cells:[<Link key="record" href={query(r.path,r.params)} className="inline-link">{r.reference}</Link>,r.task,r.centre,<StatusBadge key="state" tone="warning">{r.state.replaceAll('_',' ').toLowerCase()}</StatusBadge>]}))}/><p className="purchase-help">Up to 12 oldest records. Use operational reports for full history. Processing exceptions cover the last seven business dates.</p></details>}
   </>}
  </section>
  <CurrentStockCard org={organisation} timeZone={timeZone}/>
  <div className="operations-compliance"><WasteWorkspaceStatus organisation={organisation} packet={waste} error={wasteError} executive/><WeeklyCountStatus organisation={organisation} packet={weekly} error={weeklyError}/></div>
  <details className="operations-panel"><summary>Menu target exceptions by outlet</summary>{menuError&&<p role="alert">Some menu comparisons could not be loaded. Totals remain unavailable until all permitted outlets load.</p>}<DataTable label="Menu accountability by outlet" columns={[{label:'Outlet'},{label:'Above target',numeric:true},{label:'Costing incomplete',numeric:true},{label:'Action'}]} rows={menus.map(({outlet,result})=>({id:outlet.id,cells:[outlet.name,result.error?'Unavailable':result.data?.summary?.at_risk??0,result.error?'Unavailable':result.data?.summary?.incomplete??0,<Link key="menu" href={query('/workspace/menus/profitability',{location:outlet.id,status:'AT_RISK'})}>Review menu margins</Link>]}))}/></details>
  <details className="operations-panel"><summary>Purchase price warnings this month</summary>{priceError&&<p role="alert">Some purchase price comparisons are unavailable. Narrow the period in purchasing reports or refresh to retry.</p>}<DataTable label="Operations purchase price warnings" columns={[{label:'Material / PO'},{label:'Outlet'},{label:'Previous / quoted unit price'},{label:'Increase',numeric:true}]} rows={prices.flatMap(({outlet,result})=>((result.data as ExecutiveBriefing['po_exposure'])?.rows??[]).map(r=>({id:r.line_id,cells:[<span key="po">{r.name}<small><Link href={query('/workspace/records',{type:'PO',q:r.reference,from:today.slice(0,7)+'-01',to:today})}>{r.reference}</Link></small></span>,outlet.name,<span key="prices">{referenceAmount(r.baseline_unit_cost,currency)} / {referenceAmount(r.quote_unit_cost,currency)}<small>Per {r.unit}</small></span>,r.change_percent==null?'Unavailable':`${displayPercent(r.change_percent)}%`]})))} empty="No comparable price increases in this period."/><p className="purchase-help">Issued PO quotes are early warnings, not confirmed purchase costs. Up to five priority material lines per permitted outlet are shown.</p></details>
  <nav className="workspace-home-tasks" aria-label="Operations tools">{[['Material Plan','/workspace/inventory/plans'],['Production & yield','/workspace/inventory/processing'],['Waste analysis','/workspace/inventory/waste/analysis'],['Stock movements','/workspace/inventory/statements'],['Historical reports','/workspace/records']].map(([label,path])=><Link key={path} href={query(path)}>{label}</Link>)}</nav>
 </div>;
}
