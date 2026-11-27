import type {ProcessingStandard} from './processing';
export type ProductionMode='INPUT'|'BATCHES'|'TARGET';
export const productionQuantity=(value:number)=>Number(value.toFixed(12)).toString();
export function productionPlan(standard:ProcessingStandard|undefined,mode:ProductionMode,quantity:string,actuals:Record<string,string>={}){
 const amount=Number(quantity),factor=standard?(mode==='BATCHES'?amount:amount/Number(mode==='TARGET'?standard.expected_output:standard.primary_quantity)):0;
 const expected=standard?(mode==='TARGET'?amount:Number(standard.expected_output)*factor):0;
 const valid=!!standard&&quantity!==''&&Number.isFinite(factor)&&factor>0&&Number.isFinite(expected)&&expected>0&&expected<1e26;
 const inputs=standard?.inputs.map(i=>{const planned=valid?productionQuantity(Number(i.quantity)*factor):'';return {...i,planned,quantity:mode==='INPUT'&&i.item_id===standard.primary_item_id?quantity:actuals[i.item_id]??planned};})??[];
 return {valid,expected:valid?expected:null,factor,inputs};
}
