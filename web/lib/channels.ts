export type SalesChannel={code:string;name:string;is_active:boolean};
export type SalesChannelPacket={manage:boolean;revision:number;channels:SalesChannel[]};
export function parseChannelRows(text:string,allowEmpty=false):SalesChannel[]{
 if(text.length>16384)throw new Error('Use up to 30 sales channels.');
 const rows:unknown=JSON.parse(text);if(!Array.isArray(rows)||rows.length>30)throw new Error('Use up to 30 sales channels.');
 const codes=new Set<string>(),names=new Set<string>();
 const result=rows.map((r:Record<string,unknown>)=>{if(!r||typeof r!=='object'||typeof r.code!=='string'||typeof r.name!=='string'||!/^([A-Z0-9][A-Z0-9_-]{0,39})$/.test(r.code)||r.code==='ALL'||!r.name.trim()||r.name.trim().length>80||/[\x00-\x1f\x7f]/.test(r.name)||(r.is_active!==undefined&&typeof r.is_active!=='boolean'))throw new Error('Enter a channel name and a unique code. ALL is reserved.');const name=r.name.trim();if(codes.has(r.code)||names.has(name.toLowerCase()))throw new Error('Channel names and codes must be unique.');codes.add(r.code);names.add(name.toLowerCase());return {code:r.code,name,is_active:r.is_active!==false};});
 if(!allowEmpty&&!result.some(r=>r.is_active))throw new Error('Choose at least one sales channel.');return result;
}
