import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const compile=s=>`data:text/javascript;base64,${Buffer.from(ts.transpileModule(s,{compilerOptions:{module:ts.ModuleKind.ESNext}}).outputText).toString('base64')}`;
const attention=compile(await readFile(new URL('../lib/workspace-attention.ts',import.meta.url),'utf8'));
const source=(await readFile(new URL('../lib/workspace-welcome.ts',import.meta.url),'utf8')).replaceAll("'./workspace-attention'",JSON.stringify(attention));
const {welcomeTasks,sortWelcomeTasks}=await import(compile(source));
const count={backlog:2,review_waiting:1,posting_waiting:1,calendar_gaps:0,rows:[{state:'UPCOMING',centre:'Main'},{state:'DRAFT',overdue:true,centre:'Main'},{state:'NOT_STARTED',overdue:false,centre:'Kitchen'}]};
test('welcome preserves due, overdue, review and posting queues without turning upcoming counts into tasks',()=>{
 const rows=welcomeTasks('org',null,null,count,count);assert.equal(rows.length,8);assert.equal(rows.find(r=>r.id==='weekly-due').count,1);assert.equal(rows.find(r=>r.id==='weekly-overdue').count,2);assert.match(rows.find(r=>r.id==='monthly-post').href,/frequency=MONTHLY&state=APPROVED/);assert.match(rows.find(r=>r.id==='weekly-review').href,/state=SUBMITTED/);assert.equal(rows.some(r=>r.label.includes('Upcoming')),false);
});
test('waste today and historical centre-days remain distinct, and completed confirmations are not tasks',()=>{
 const waste={today:'2026-11-24',expected_today:2,complete_today:1,overdue:4,missing_owners:0,today_rows:[{can_confirm:true,state:'PENDING',centre:'Kitchen'},{can_confirm:false,state:'COMPLETE_NO_WASTE',centre:'Bar'}]};
 const rows=welcomeTasks('org',null,waste,null,null);assert.equal(rows.find(r=>r.id==='waste-today').count,1);assert.equal(rows.find(r=>r.id==='waste-overdue').unit,'centre-days');waste.today_rows[0].state='COMPLETE_WASTE';assert.equal(welcomeTasks('org',null,waste,null,null).some(r=>r.id==='waste-today'),false);
});
test('unavailable packets never invent zero tasks; queues retain their own units and ordered priority',()=>{
 assert.deepEqual(welcomeTasks('org',null,null,null,null),[]);const rows=welcomeTasks('org',{queues:[{queue:'READY_DISPATCH',count:3,overdue:0},{queue:'INCOMING_TRANSFER',count:1,overdue:1}]},null,null,null);const sorted=sortWelcomeTasks(rows);assert.equal(sorted[0].id,'INCOMING_TRANSFER');assert.equal(sorted[0].count,1);assert.match(sorted[0].href,/queue=INCOMING_TRANSFER/);assert.equal(rows[0].id,'READY_DISPATCH');
});
