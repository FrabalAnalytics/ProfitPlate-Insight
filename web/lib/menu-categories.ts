export type CostBasis='FOOD'|'DRINK'|'NON_FOOD';
export type MenuCategory={major:string;major_name?:string;cost_basis?:CostBasis;target_percent?:string|null;name:string;is_active:boolean};
export type MenuMajor={code:string;name:string;cost_basis:CostBasis;target_percent:string|null;is_active:boolean};
export type CategoryPacket={manage:boolean;revision:number;categories:MenuCategory[];majors?:MenuMajor[]};
export function majorLabel(code:string,categories:MenuCategory[]=[]){return categories.find(c=>c.major===code)?.major_name??({FOOD:'Food',DRINK:'Drink',PACKAGING:'Packaging',UNCLASSIFIED:'Unclassified'} as Record<string,string>)[code]??code;}
export function categoryMajors(categories:MenuCategory[]){return [...new Map(categories.map(c=>[c.major,{code:c.major,name:majorLabel(c.major,categories),active:categories.some(row=>row.major===c.major&&row.is_active)}])).values()];}
export const standardChannels=JSON.stringify([{code:'STANDARD',name:'Standard selling price',is_active:true}]);
export function parseMenuCategories(value:string,allowEmpty=false):MenuCategory[]{
 const rows:unknown=JSON.parse(value);if(!Array.isArray(rows)||rows.length>100)throw new Error('Use up to 100 subcategories.');
 const seen=new Set<string>(),majors=new Map<string,string>(),names=new Map<string,string>();const result=rows.map(r=>{
  if(!r||typeof r.major!=='string'||!/^[A-Z0-9][A-Z0-9_-]{0,39}$/.test(r.major)||['ALL','UNCLASSIFIED'].includes(r.major)||typeof r.name!=='string'||!r.name.trim()||r.name.trim().length>60||/[\x00-\x1f\x7f]/.test(r.name)||typeof r.is_active!=='boolean')throw new Error('Enter a main category and subcategory name.');
  const label=r.major_name??majorLabel(r.major),basis=r.cost_basis??({FOOD:'FOOD',DRINK:'DRINK',PACKAGING:'NON_FOOD'} as Record<string,string>)[r.major],target=r.target_percent??null;
  if(typeof label!=='string'||!label.trim()||label.trim().length>60||/[\x00-\x1f\x7f]/.test(label)||!['FOOD','DRINK','NON_FOOD'].includes(basis))throw new Error('Give each main category a name and reporting treatment.');
  if(target!==null&&target!==''&&(typeof target!=='string'||!/^\d{1,3}(?:\.\d{1,6})?$/.test(target)||Number(target)>100))throw new Error('Enter a cost target from 0 to 100, or leave it blank.');
  const key=r.major+':'+r.name.trim().toLowerCase();if(seen.has(key))throw new Error('Use unique subcategories within each main category.');seen.add(key);
  const settings=JSON.stringify([label.trim(),basis,target||null]);if(majors.has(r.major)&&majors.get(r.major)!==settings)throw new Error('Use consistent details for each main category.');majors.set(r.major,settings);
  if(names.has(label.trim().toLowerCase())&&names.get(label.trim().toLowerCase())!==r.major)throw new Error('Main category names must be unique.');names.set(label.trim().toLowerCase(),r.major);
  return {...r,major_name:label.trim(),cost_basis:basis,target_percent:target||null,name:r.name.trim()} as MenuCategory;
 });
 if(majors.size>30)throw new Error('Use up to 30 main categories.');
 if(!allowEmpty&&!result.some(r=>r.is_active))throw new Error('Add at least one menu subcategory.');return result;
}
