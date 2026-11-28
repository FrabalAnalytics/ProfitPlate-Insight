"use client";
import {majorLabel} from "@/lib/menu-categories";
import {useId,useState} from 'react';
export function CategoryFilters({major,subcategory,categories}:{major:string;subcategory:string;categories:{major:string;major_name?:string;name:string;is_active?:boolean}[]}){
 const id=useId(),[selected,setSelected]=useState(major),[sub,setSub]=useState(subcategory);
 return <><label className="sr-only" htmlFor={`${id}-major`}>Major category</label><select id={`${id}-major`} name="major" value={selected} onChange={e=>{setSelected(e.target.value);setSub('');}}><option value="ALL">All categories</option>{Array.from(new Set(categories.map(c=>c.major))).map(code=><option key={code} value={code}>{majorLabel(code,categories.map(c=>({...c,is_active:c.is_active??true})))}</option>)}<option value="UNCLASSIFIED">Unclassified</option></select><label className="sr-only" htmlFor={`${id}-sub`}>Menu subcategory</label><select id={`${id}-sub`} name="subcategory" value={sub} onChange={e=>setSub(e.target.value)}><option value="">All subcategories</option>{Array.from(new Set(categories.filter(c=>selected==='ALL'||c.major===selected).map(c=>c.name))).sort().map(name=><option key={name} value={name}>{name}</option>)}</select></>;
}
