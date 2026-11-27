import type {StockPacket} from './inventory';
import type {ProcessingStandard} from './processing';

/** Catalogue eligibility is distinct from stock availability; shortages never hide a recipe. */
export function productionReadiness(packet:Pick<StockPacket,'items'|'processing'>,site:string){
 const seen=new Set<string>();
 const ready:ProcessingStandard[]=[],blocked:{standard:ProcessingStandard;missing:string[]}[]=[];
 for(const standard of packet.processing?.standards??[]){
  if(!standard.site_ids.includes(site)||seen.has(standard.recipe_version_id))continue;
  seen.add(standard.recipe_version_id);
  const materials=[...standard.inputs.map(i=>({id:i.item_id,name:i.name})),{id:standard.output_item_id,name:standard.output_name}];
  const missing=materials.filter(m=>{const item=packet.items.find(i=>i.id===m.id);return !item||(item.centre_ids!==undefined&&!item.centre_ids.includes(site));}).map(m=>m.name);
  if(missing.length)blocked.push({standard,missing:[...new Set(missing)]});else ready.push(standard);
 }
 return {ready,blocked};
}
