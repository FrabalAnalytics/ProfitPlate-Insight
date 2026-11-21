"use client";
import { useTransition } from "react";
import { useRouter } from "next/navigation";

export function ExecutiveRefresh({label="Refresh briefing"}:{label?:string}) {
 const router=useRouter(),[pending,startTransition]=useTransition();
 return <button type="button" className="secondary-button" disabled={pending} onClick={()=>startTransition(()=>router.refresh())}>{pending?"Refreshing…":label}</button>;
}
