export type ExpenseCategoryChoice={code:string;name:string;kind:'LABOUR'|'OPERATING';is_active:boolean;id?:string};
export function parseExpenseCategories(source:string):ExpenseCategoryChoice[]{
 let rows:unknown;try{rows=JSON.parse(source);}catch{throw new Error('Check your expense categories.');}
 if(!Array.isArray(rows)||rows.length>100)throw new Error('Use up to 100 expense categories.');
 const codes=new Set<string>(),names=new Set<string>();
 return rows.map((value:ExpenseCategoryChoice)=>{
  if(!value||typeof value.code!=='string'||typeof value.name!=='string'||!['LABOUR','OPERATING'].includes(value.kind)||typeof value.is_active!=='boolean')throw new Error('Check each expense category.');
  const row={...value,code:value.code.trim().toUpperCase(),name:value.name.trim()};
  if(!/^[A-Z0-9][A-Z0-9_-]{0,39}$/.test(row.code)||!row.name||row.name.length>90||/[\x00-\x1f\x7f]/.test(row.name))throw new Error('Enter a category name and a short code using letters, numbers, underscores or hyphens.');
  const name=row.kind+':'+row.name.toLowerCase();if(codes.has(row.code)||names.has(name))throw new Error('Category names and codes must be unique.');codes.add(row.code);names.add(name);return row;
 });
}
