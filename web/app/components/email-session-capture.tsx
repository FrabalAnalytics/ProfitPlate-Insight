"use client";
import {useEffect,useState} from "react";
import {getSupabaseConfig} from "@/lib/supabase/config";
export function EmailSessionCapture(){
 const[error,setError]=useState(false);
 useEffect(()=>{const p=new URLSearchParams(window.location.hash.slice(1)),access=p.get("access_token"),refresh=p.get("refresh_token");if(!access||!refresh)return;
  const recovery=p.get("type")==="recovery";history.replaceState(history.state,"",window.location.pathname+window.location.search);
  void (async()=>{const {createBrowserClient}=await import("@supabase/ssr"),{url,key}=getSupabaseConfig(),client=createBrowserClient(url,key,{auth:{detectSessionInUrl:false}});
   const {error}=await client.auth.setSession({access_token:access,refresh_token:refresh});if(error)setError(true);else window.location.replace(recovery?"/reset-password":"/join");
  })().catch(()=>setError(true));
 },[]);
 return error?<p role="alert" className="auth-alert">This email link could not sign you in. Request a new link or sign in with your password.</p>:null;
}
