import Link from 'next/link';
import {createClient} from '@/lib/supabase/server';
import {referenceAmount} from '@/lib/reference-prices';
import {displayPercent} from '@/lib/display';
import {validBusinessDate} from '@/lib/recipes';
import {isUuid} from '@/lib/catalogue';
import {workspaceNavigation} from '@/lib/workspace-home';
import {welcomeTasks,sortWelcomeTasks} from '@/lib/workspace-welcome';
import type {AttentionPacket} from '@/lib/workspace-attention';
import type {WasteWorkspacePacket} from '@/lib/waste-accountability';
import type {WeeklyWorkspacePacket} from './weekly-count-status';
import type {Overview,NavigationAccess} from '@/lib/overview';
import type {ExecutiveBriefing} from '@/lib/executive-briefing';
import type {FollowUpPacket} from '@/lib/management-reviews';
import {reviewRoles} from '@/lib/management-reviews';
import {CurrentStockCard} from './current-stock-card';
import {WelcomeAttention} from './welcome-attention';

type Props={organisation:string;roles:{role_code:string;location_id:string|null}[];navigation:NavigationAccess;timeZone:string;today:string;currency:string;from:string;to:string;location:string;executive:boolean;operations:boolean;attention:AttentionPacket|null;attentionError:boolean;waste:WasteWorkspacePacket|null;wasteError:boolean;weekly:WeeklyWorkspacePacket|null;weeklyError:boolean;monthly:WeeklyWorkspacePacket|null;monthlyError:boolean;salesPending:number;salesError:boolean};
export async function WorkspaceWelcome(p:Props){
 const {organisation:org,roles,executive,operations}=p,nav=workspaceNavigation(roles,p.navigation),client=await createClient();
 const financial=nav.overview&&!operations,valid=validBusinessDate(p.from)&&validBusinessDate(p.to)&&p.from<=p.to&&(!p.location||isUuid(p.location));
 const review=roles.some(r=>reviewRoles.includes(r.role_code));
 const admin=roles.some(r=>r.role_code==='restaurant_admin'&&r.location_id===null)&&!executive;
 const [performance,actions,op,menu,briefing,setup]=await Promise.all([
  financial&&valid?client.rpc('executive_overview',{p_organisation_id:org,p_from:p.from,p_to:p.to,p_location_id:p.location||null}):null,
  review?client.rpc('management_actions',{p_organisation_id:org,p_state:'ACTIVE',p_page:1,p_id:null}):null,
  operations?client.rpc('operations_workspace',{p_organisation_id:org}):null,
  executive?client.rpc('owner_menu_attention',{p_organisation_id:org,p_outlet_id:p.location||null}):null,
  executive&&valid?client.rpc('executive_profitability_briefing',{p_organisation_id:org,p_from:p.from,p_to:p.to,p_location_id:p.location||null}):null,
  admin?client.rpc('setup_workspace',{p_organisation_id:org}):null,
 ]);
 const rows=welcomeTasks(org,p.attention,p.waste,p.weekly,p.monthly),issues:string[]=[];
 const path=(route:string,params:Record<string,string>={})=>`${route}?${new URLSearchParams({organisation:org,...params})}`;
 const add=(id:string,label:string,count:number,unit:string,href:string,priority=2,detail='')=>{if(count>0)rows.push({id,label,count,unit,href,priority,detail});};
 if(p.attentionError)issues.push('Some stock or purchasing tasks could not be loaded.');
 if(p.wasteError)issues.push('Waste reporting status is unavailable.');
 if(p.weeklyError)issues.push('Weekly count status is unavailable.');
 if(p.monthlyError)issues.push('Monthly count status is unavailable.');
 if(p.salesError)issues.push('Sales stock-consumption status is unavailable.');
 add('sales-stock','Sales consumption needs review',p.salesPending,'sales lines',path('/workspace/inventory/sales-consumption'),1,'Stock balances may be incomplete');
 const follow=actions?.data as FollowUpPacket|null;
 if(actions?.error&&actions.error.code!=='42501')issues.push('Assigned follow-ups could not be loaded.');
 add('follow-ups','Assigned follow-ups',follow?.total??0,'actions',path('/workspace/reviews/actions'),follow?.summary.overdue?0:2,follow?`${follow.summary.overdue} overdue / ${follow.summary.resolved} awaiting closure`:'');
 const operation=op?.data as {queues:{task:string;count:number;overdue:number}[]}|null;
 if(op?.error)issues.push('Operational follow-up could not be loaded.');
 for(const q of operation?.queues??[])add('operations-'+q.task,q.task,q.count,'records',path('/workspace/performance'),q.overdue?0:2,q.overdue?`${q.overdue} waiting over 24 hours`:'Stock and purchasing follow-up');
 const flags=menu?.data as {at_risk:number;incomplete:number;targets_missing:number;scopes:{id:string;at_risk:number;incomplete:number;targets_missing:number}[]}|null;
 if(menu?.error)issues.push('Menu margin exceptions could not be loaded.');
 for(const [key,label,status] of [['at_risk','Menu cost-target exceptions','AT_RISK'],['incomplete','Menu costing incomplete','INCOMPLETE'],['targets_missing','Menu targets missing','TARGET_NOT_SET']] as const){const scope=flags?.scopes.find(s=>s[key]>0)?.id;add('menu-'+key,label,flags?.[key]??0,'menu / outlet comparisons',path('/workspace/menus/profitability',{status,...(scope?{location:scope}:{})}),1);}
 const owner=briefing?.data as ExecutiveBriefing|null;
 if(briefing?.error)issues.push('Purchase-price and stock-handover warnings could not be loaded.');
 add('price-pressure','PO price increases',owner?.po_exposure?.open??0,'material lines',path('/workspace/performance',{from:p.from,to:p.to,...(p.location?{location:p.location}:{})})+'#executive-po-prices',1,'Issued quotes / potential cost pressure');
 add('stock-handover','Stock handovers over 24h',owner?.movements.overdue??0,'movements',path('/workspace/inventory',{view:'movements',status:'FOLLOW_UP'}),0);
 const overview=performance?.data as Overview|null;
 add('missing-costs','Sales lines need costs',overview?.summary.missing_lines??0,'sales lines',path('/workspace/overview',{from:p.from,to:p.to,...(p.location?{location:p.location}:{})}),1,'Margin estimates are incomplete');
 const progress=setup?.data?.progress as {completed:number;total:number}|undefined;
 if(setup?.error)issues.push('Setup readiness could not be loaded.');
 if(progress&&progress.completed<progress.total)add('setup','Complete restaurant setup',progress.total-progress.completed,'stages',path('/workspace/setup'),2,'Finish the remaining setup requirements');
 // Scoped Operations keeps its own menu/outlet permissions; it receives no sales totals.
 let opsRisk:number|null=null;
 if(operations){const access=await client.rpc('operations_access',{p_organisation_id:org});const outlets=(access.data?.outlets??[]) as {id:string;name:string}[];
  const checks=await Promise.all(outlets.map(async outlet=>({outlet,r:await client.rpc('selling_menu_profitability',{p_organisation_id:org,p_location_id:outlet.id,p_channel:'STANDARD',p_as_of:p.today,p_search:'',p_page:1,p_status:'AT_RISK',p_major:'ALL',p_subcategory:''}),price:await client.rpc('operations_price_warnings',{p_organisation_id:org,p_outlet_id:outlet.id,p_from:p.today.slice(0,7)+'-01',p_to:p.today})})));
  if(access.error||checks.some(c=>c.r.error))issues.push('Some menu margin exceptions are unavailable.');else opsRisk=checks.reduce((n,c)=>n+Number(c.r.data?.summary?.at_risk??0),0);
  for(const c of checks){add('ops-menu-'+c.outlet.id,'Menus above cost target',Number(c.r.data?.summary?.at_risk??0),'menus',path('/workspace/menus/profitability',{location:c.outlet.id,status:'AT_RISK'}),1,c.outlet.name);add('ops-price-'+c.outlet.id,'Purchase price increases',Number(c.price.data?.open??0),'material lines',path('/workspace/performance'),1,c.outlet.name);if(c.price.error||c.price.data?.unavailable)issues.push(`Purchase-price checks unavailable for ${c.outlet.name}.`);}
 }
 const next=[...(p.weekly?.rows??[]).filter(r=>r.state==='UPCOMING').map(r=>({row:r,monthly:false})),...(p.monthly?.rows??[]).filter(r=>r.state==='UPCOMING').map(r=>({row:r,monthly:true}))].sort((a,b)=>a.row.cutoff.localeCompare(b.row.cutoff))[0];
 const periodLabel=valid?`${p.from} to ${p.to}`:'Invalid reporting dates';
 return <>
 <section className="welcome-metrics" aria-label={executive?'CEO performance metrics':'Workspace summary'}>
 {(nav.inventory||financial||operations)&&<CurrentStockCard org={org} timeZone={p.timeZone} compact/>}
 {financial&&<><article className="welcome-metric"><span>Recorded net sales</span><strong>{overview?.summary.lines?referenceAmount(overview.summary.net_revenue,p.currency):overview?'No sales recorded':'Unavailable'}</strong><small>{periodLabel}</small><Link href={path('/workspace/overview',{from:p.from,to:p.to,...(p.location?{location:p.location}:{})})}>View sales</Link></article><article className="welcome-metric"><span>Est. gross profit margin</span><strong>{overview?.summary.lines&&overview.summary.food_margin_percent!==null?`${displayPercent(overview.summary.food_margin_percent)}%`:'Unavailable'}</strong><small>{overview?.summary.missing_lines?`${overview.summary.missing_lines} sales lines need costs`:'Ingredients and packaging basis'}</small><Link href={path('/workspace/overview',{from:p.from,to:p.to,...(p.location?{location:p.location}:{})})}>View margins</Link></article></>}
 {operations&&<article className="welcome-metric"><span>Menus above cost target</span><strong>{opsRisk??'Unavailable'}</strong><small>Your permitted outlets / current estimates</small><Link href={path('/workspace/performance')}>View operational overview</Link></article>}
 {progress&&<article className="welcome-metric"><span>Setup readiness</span><strong>{progress.completed} / {progress.total}</strong><small>Stages ready</small><Link href={path('/workspace/setup')}>Continue setup</Link></article>}
 </section>
 {financial&&(!valid||performance?.error)&&<p className="auth-alert" role="alert">{!valid?'Choose valid reporting dates in the performance report.':'Financial summaries could not be loaded. Open the performance report or refresh.'}</p>}
 <WelcomeAttention rows={sortWelcomeTasks(rows)} issues={[...new Set(issues)]} label={executive?'Executive needs attention':'Needs Attention'}/>
 {next&&<p className="welcome-upcoming">Next {next.monthly?'monthly':'weekly'} count: <Link href={path('/workspace/inventory/counts',{...(next.monthly?{frequency:'MONTHLY'}:{}),site:next.row.site_id})}>{next.row.centre} / {new Intl.DateTimeFormat('en-GB',{timeZone:next.row.time_zone,day:'numeric',month:'short'}).format(new Date(next.row.cutoff))}</Link></p>}
 </>;
}
