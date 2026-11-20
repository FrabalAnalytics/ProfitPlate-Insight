export type MenuCategory={major:'FOOD'|'DRINK';name:string;is_active:boolean};
export type CategoryPacket={manage:boolean;revision:number;categories:MenuCategory[]};
export const standardChannels=JSON.stringify([{code:'STANDARD',name:'Standard selling price',is_active:true}]);
export function parseMenuCategories(value:string,allowEmpty=false):MenuCategory[]{
 const rows:unknown=JSON.parse(value);if(!Array.isArray(rows)||rows.length>100)throw new Error('Use up to 100 subcategories.');
 const seen=new Set<string>();const result=rows.map(r=>{if(!r||!['FOOD','DRINK'].includes(r.major)||typeof r.name!=='string'||!r.name.trim()||r.name.trim().length>60||/[\x00-\x1f\x7f]/.test(r.name)||typeof r.is_active!=='boolean')throw new Error('Choose Food or Drink and enter a subcategory name.');const key=r.major+':'+r.name.trim().toLowerCase();if(seen.has(key))throw new Error('Use unique subcategories within Food or Drink.');seen.add(key);return {...r,name:r.name.trim()} as MenuCategory;});
 if(!allowEmpty&&!result.some(r=>r.is_active))throw new Error('Add at least one menu subcategory.');return result;
}
