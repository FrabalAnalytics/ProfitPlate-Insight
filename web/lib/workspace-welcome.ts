import type {AttentionPacket} from './workspace-attention';
import {attentionLabels} from './workspace-attention';
import type {WasteWorkspacePacket} from './waste-accountability';
import type {WeeklyRow} from './inventory-accountability';
export type WelcomeTask={id:string;label:string;detail:string;count:number;unit:string;href:string;priority:number;action?:string};
export type CountWelcome={backlog:number;review_waiting:number;posting_waiting?:number;calendar_gaps:number;rows:WeeklyRow[]};
export function welcomeTasks(org:string,attention:AttentionPacket|null,waste:WasteWorkspacePacket|null,weekly:CountWelcome|null,monthly:CountWelcome|null){
 const rows:WelcomeTask[]=[];
 const add=(id:string,label:string,count:number,unit:string,href:string,priority=2,detail='')=>{if(count>0)rows.push({id,label,count,unit,href,priority,detail});};
 for(const q of attention?.queues??[])add(q.queue,attentionLabels[q.queue]??q.queue,q.count,'records',`/workspace/tasks?${new URLSearchParams({organisation:org,queue:q.queue})}`,q.overdue?0:2,q.overdue?`${q.overdue} waiting over 24 hours`:'');
 if(waste){
  add('waste-overdue','Waste reports overdue',waste.overdue,'centre-days',`/workspace/inventory/waste/daily?organisation=${org}&state=OVERDUE`,0,'Earlier reporting dates');
  const own=(waste.today_rows??[]).filter(r=>r.can_confirm&&!r.state.startsWith('COMPLETE_')&&r.state!=='CLOSED'&&r.state!=='OVERDUE');
  const ownOverdue=(waste.today_rows??[]).filter(r=>r.can_confirm&&r.state==='OVERDUE');
  if(own.length){add('waste-today',"Confirm today's waste",own.length,'centres',`/workspace/inventory/waste/daily?organisation=${org}&day=${waste.today}`,1,own.map(r=>r.centre).slice(0,3).join(', '));}
  else if(!ownOverdue.length&&!(waste.today_rows??[]).some(r=>r.can_confirm))add('waste-today','Waste confirmations pending today',Math.max(0,waste.expected_today-waste.complete_today-(waste.today_rows??[]).filter(r=>r.state==='OVERDUE').length),'centres',`/workspace/inventory/waste/daily?organisation=${org}&day=${waste.today}`,1,'Waste recorded or no waste');
  add('waste-owners','Centres need a responsible owner',waste.missing_owners,'centres',`/workspace/inventory/waste/daily?organisation=${org}`,1,'Ask the restaurant administrator to assign an owner');
 }
 for(const [p,monthlyView] of [[weekly,false],[monthly,true]] as const){if(!p)continue;const name=monthlyView?'Monthly':'Weekly',base=`/workspace/inventory/counts?organisation=${org}${monthlyView?'&frequency=MONTHLY':''}`,key=monthlyView?'monthly':'weekly';
  add(`${key}-overdue`,`${name} counts overdue`,p.backlog,'counts',base,0);
  const due=p.rows.filter(r=>['NOT_STARTED','DRAFT'].includes(r.state)&&!r.overdue);
  add(`${key}-due`,`${name} counts due`,due.length,'counts',base,1,due.map(r=>r.centre).slice(0,3).join(', '));
  add(`${key}-review`,`${name} counts awaiting review`,p.review_waiting,'counts',base+'&state=SUBMITTED',1);
  add(`${key}-post`,`${name} counts approved - awaiting posting`,p.posting_waiting??0,'counts',base+'&state=APPROVED',1);
  add(`${key}-calendar`,`${name} count calendar incomplete`,p.calendar_gaps,'centres',base,1,'Ask the restaurant administrator to complete the schedule');
 }
 return rows;
}
export function sortWelcomeTasks(rows:WelcomeTask[]){return [...rows].sort((a,b)=>a.priority-b.priority||b.count-a.count||a.label.localeCompare(b.label));}
