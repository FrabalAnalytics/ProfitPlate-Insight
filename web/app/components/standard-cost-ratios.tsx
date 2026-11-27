import type {Overview} from '@/lib/overview';
import type {ExpenseReport} from '@/lib/expenses';
import {standardCostRatios} from '@/lib/management-report';
import {displayPercent} from '@/lib/display';
import './standard-cost-ratios.css';

export function StandardCostRatios({summary,costs}:{summary:Overview['summary']|null|undefined;costs:ExpenseReport|null}){
 const ratios=standardCostRatios(summary,costs);
 return <section className="standard-cost-ratios" aria-label="Standard cost ratios"><header><h2>Cost ratios</h2><p>Same report period, scope and recorded net sales.</p></header><div className="standard-cost-ratio-grid">{ratios.map(r=><article key={r.id} aria-label={r.label} className={r.id==='prime'?'standard-prime-ratio':''}><div><h3>{r.label}</h3><span className={r.value==null?'ratio-state ratio-missing':'ratio-state'}>{r.status==='ESTIMATED'?'Estimated':r.status==='REVIEWED'?'Reviewed coverage':'Needs data'}</span></div><strong>{r.value==null?'Unavailable':`${displayPercent(r.value)}%`}</strong><p>{r.note}</p></article>)}</div><details className="standard-ratio-basis"><summary>How these percentages are calculated</summary><ul>{ratios.map(r=><li key={r.id}><strong>{r.label}:</strong> {r.formula}.</li>)}</ul><p>Net sales exclude declared tax and reflect source discounts. Food and prime cost use recipe-based ingredient and direct packaging estimates, rather than actual inventory COGS. Labour follows expense recognition dates. Central costs are included in all-location totals and excluded from individual outlets. A stock-centre view has no separate sales or labour allocation.</p></details></section>;
}
