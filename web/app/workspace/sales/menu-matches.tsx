'use client';
import {useEffect,useId,useState} from 'react';
import type {SalesBatch,SalesMappings,SalesMenuChoice} from '@/lib/sales-imports';
import {findSalesMenus} from './actions';
import {DataTable} from '@/app/components/data-table';

export function SalesMenuReview({rows}:{rows:SalesBatch['report']['rows']}){
 const[page,setPage]=useState(0),matches=[...new Map(rows.filter(r=>r.prepared).map(r=>[JSON.stringify([r.source.Menu_Name??r.source.Menu_Code,r.prepared!.menu_version_id,r.prepared!.location_name,r.source.Sale_Date,r.prepared!.stock_centre,r.prepared!.menu_match_basis]),r])).values()],pages=Math.ceil(matches.length/10);
 if(!matches.length)return null;
 return <section className="purchase-panel"><h2>Check menus and stock centres</h2><DataTable label="Matched menus and stock centres" columns={[{label:'From POS'},{label:'Selling menu / recipe'},{label:'Outlet / stock centre'},{label:'Match'}]} rows={matches.slice(page*10,(page+1)*10).map(r=>({id:String(r.row),cells:[r.source.Menu_Name??r.source.Menu_Code,<span key="menu">{r.prepared!.menu_name}<small>{r.prepared!.recipe_name??'Saved recipe'} / version {r.prepared!.menu_version}</small></span>,<span key="centre">{r.prepared!.location_name}<small>{r.prepared!.stock_centre??'No stock centre assigned on the sales date'}</small><small>{r.source.Sale_Date}</small></span>,r.prepared!.menu_match_basis??'Saved menu link']}))}/>{pages>1&&<nav className="catalogue-pagination" aria-label="Menu match review pages"><button type="button" className="secondary-button" disabled={page===0} onClick={()=>setPage(page-1)}>Previous matches</button><span>Page {page+1} of {pages}</span><button type="button" className="secondary-button" disabled={page+1>=pages} onClick={()=>setPage(page+1)}>Next matches</button></nav>}<p className="setup-help">A missing stock centre does not block the sales figures; its stock consumption stays pending for review.</p></section>;
}

export function SalesMenuMatches({org,batch,maps,onChange,disabled}:{org:string;batch:SalesBatch;maps:SalesMappings;onChange:(value:SalesMappings)=>void;disabled:boolean}){
 const groups=new Map<string,SalesBatch['report']['rows']>();
 for(const row of batch.report.rows){
  const r=row.source,label=r.Menu_Name??r.Menu_Code??'',key=JSON.stringify([r.Source_System,r.Location_Code,r.Sale_Date,r.Menu_Name===undefined?label:label.trim().replace(/\s+/g,' ').toLowerCase()]);
  groups.set(key,[...(groups.get(key)??[]),row]);
 }
 return <details className="purchase-mappings"><summary>Match selling menus ({groups.size})</summary><p>Choose by menu name, recipe and stock centre. Confirmed POS-name matches are remembered for their source, outlet and sales date when you save reviewed sales.</p>{[...groups].map(([key,rows])=>{
  const source=rows[0].source,label=source.Menu_Name??source.Menu_Code,chosen=maps.menu_rows?.[String(rows[0].row)]??maps.menu_items[label]??rows[0].prepared?.menu_code??'';
  return <MenuMatchGroup key={key} org={org} label={label} source={source.Source_System} location={maps.locations[source.Location_Code]??source.Location_Code} day={source.Sale_Date} rows={rows} chosen={chosen} disabled={disabled} onSelect={code=>{
   const menu_rows={...maps.menu_rows},menu_items={...maps.menu_items};
   // Preserve any earlier batch-wide explicit mappings in the other rows before changing this group.
   for(const row of batch.report.rows){const raw=row.source.Menu_Name??row.source.Menu_Code;if(!menu_rows[String(row.row)]&&menu_items[raw])menu_rows[String(row.row)]=menu_items[raw];}
   delete menu_items[label];for(const row of rows){if(code)menu_rows[String(row.row)]=code;else delete menu_rows[String(row.row)];}
   onChange({...maps,menu_items,menu_rows});
  }}/>;
 })}</details>;
}
function MenuMatchGroup({org,label,source,location,day,rows,chosen,disabled,onSelect}:{org:string;label:string;source:string;location:string;day:string;rows:SalesBatch['report']['rows'];chosen:string;disabled:boolean;onSelect:(code:string)=>void}){
 const[open,setOpen]=useState(false);
 return <details className="sales-menu-match" onToggle={e=>setOpen(e.currentTarget.open)}><summary><strong>{label}</strong><span>{rows[0].prepared?.menu_name??'Choose selling menu'}</span></summary><p>{source} / {location} / {day} / {rows.length} lines</p>{open&&<MenuPicker org={org} label={label} location={location} day={day} chosen={chosen} initialName={rows[0].prepared?.menu_name} disabled={disabled} onSelect={onSelect}/>}</details>;
}
function MenuPicker({org,label,location,day,chosen,initialName,disabled,onSelect}:{org:string;label:string;location:string;day:string;chosen:string;initialName?:string;disabled:boolean;onSelect:(code:string)=>void}){
 const id=useId(),[search,setSearch]=useState(''),[page,setPage]=useState(0),[loading,setLoading]=useState(true),[result,setResult]=useState<{options:SalesMenuChoice[];more:boolean;error?:string}>({options:[],more:false});
 useEffect(()=>{let active=true;const timer=setTimeout(async()=>{setLoading(true);try{const next=await findSalesMenus(org,location,day,search,page);if(active)setResult(next);}catch{if(active)setResult({options:[],more:false,error:'Menus could not be loaded. Search again to retry.'});}finally{if(active)setLoading(false);}},200);return()=>{active=false;clearTimeout(timer);};},[org,location,day,search,page]);
 const selected=result.options.find(m=>m.code===chosen);
 return <div className="sales-menu-picker"><div className="setup-field"><label htmlFor={`${id}-search`}>Search menu names for {label}</label><input id={`${id}-search`} type="search" maxLength={80} value={search} onChange={e=>{setSearch(e.target.value);setPage(0);}} disabled={disabled}/></div><div className="setup-field"><label htmlFor={`${id}-menu`}>Selling menu for {label}</label><select id={`${id}-menu`} value={chosen} onChange={e=>onSelect(e.target.value)} disabled={disabled||loading} aria-busy={loading}><option value="">{loading?'Loading menus...':'Use automatic or saved match'}</option>{chosen&&!selected&&<option value={chosen}>{initialName??'Previously selected menu'} ({chosen})</option>}{result.options.map(m=><option key={m.id} value={m.code}>{m.name} / {m.subcategory||m.primary_category||'Uncategorised'} / {m.recipe_name} / {m.centre??'Centre not assigned'} ({m.code}){m.is_active?'':' - inactive'}</option>)}</select></div>{selected&&<p className="setup-help">Recipe: {selected.recipe_name}. Stock centre: {selected.centre??'Not assigned on this sales date'}. Saved menu version {selected.version}.</p>}{result.error&&<p role="alert" className="field-error">{result.error}</p>}<div className="menu-picker-pages"><span>{loading?'Loading...':`${result.options.length} menus on this page`}</span><div>{page>0&&<button type="button" className="secondary-button" onClick={()=>setPage(page-1)} disabled={disabled||loading}>Previous menus</button>}{result.more&&<button type="button" className="secondary-button" onClick={()=>setPage(page+1)} disabled={disabled||loading}>More menus</button>}</div></div></div>;
}
