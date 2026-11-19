"use client";
import {useTransition,useState,useSyncExternalStore,type ReactNode} from "react";
import {useRouter} from "next/navigation";
const subscribe=()=>()=>{},clientReady=()=>true,serverReady=()=>false;
export function MenuPreviewFilters({children}:{children:ReactNode}){
 const ready=useSyncExternalStore(subscribe,clientReady,serverReady),router=useRouter(),[pending,startTransition]=useTransition(),[dirty,setDirty]=useState(false);
 function apply(form:HTMLFormElement){if(!form.checkValidity())return;const params=new URLSearchParams();new FormData(form).forEach((v,k)=>params.set(k,String(v)));const path=`/workspace/menus?${params}`;
  startTransition(()=>{setDirty(false);if(window.location.pathname+window.location.search===path)router.refresh();else router.replace(path,{scroll:false});});
 }
 return <form method="get" className="menu-preview-filters" data-updating={pending||dirty?"true":"false"} aria-busy={pending} data-ready={ready?"true":"false"} onChange={e=>{if(e.target instanceof HTMLSelectElement){setDirty(true);apply(e.currentTarget);}}} onInput={e=>{if(e.target instanceof HTMLInputElement&&e.target.type==="date"){setDirty(true);apply(e.currentTarget);}}} onSubmit={e=>{e.preventDefault();apply(e.currentTarget);}}><fieldset className="menu-preview-fields" disabled={pending||!ready}>{children}</fieldset>{(pending||dirty)&&<p className="menu-preview-pending" role="status">{pending?"Updating margin...":"Choose valid preview values to update the margin."}</p>}</form>;
}
