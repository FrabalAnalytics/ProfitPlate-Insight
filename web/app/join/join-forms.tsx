"use client";
import { useActionState,useEffect,useState,useSyncExternalStore,type ReactNode } from "react";
import { rememberInvitation,acceptInvitation } from "./actions";
import { validInvitationToken,type TeamState } from "@/lib/team";

const subscribeToHydration=()=>()=>{};
const clientSnapshot=()=>true;
const serverSnapshot=()=>false;
export function InvitationCapture({children}:{children:ReactNode}) {
 const hydrated=useSyncExternalStore(subscribeToHydration,clientSnapshot,serverSnapshot);
 return hydrated?<BrowserInvitationCapture>{children}</BrowserInvitationCapture>:children;
}
function BrowserInvitationCapture({children}:{children:ReactNode}) {
 const [token]=useState(()=>window.location.hash.slice(1)),[state,action,pending]=useActionState(rememberInvitation,{});
 const invalid=!!token&&!validInvitationToken(token);
 useEffect(()=>{if(token)history.replaceState(history.state,"",window.location.pathname+window.location.search);},[token]);
 if(invalid)return <p role="alert">This invitation link is incomplete. Ask your administrator for a new link.</p>;
 if(!token)return children;
 return <><h1>Your team invitation</h1><p>Continue to review the invitation. You will need to sign in with the invited email address.</p><form action={action}><input type="hidden" name="token" value={token}/><button className="auth-button" disabled={pending}>{pending?"Preparing…":"Review invitation"}</button></form>{state.error&&<p role="alert" className="auth-alert">{state.error}</p>}</>;
}
export function AcceptInvitationForm() {
 const [state,action,pending]=useActionState<TeamState,FormData>(acceptInvitation,{});
 return <form action={action}><label className="team-confirm"><input type="checkbox" name="confirm" required/> I reviewed this business and the permissions being granted.</label><button className="auth-button" disabled={pending}>{pending?"Joining…":"Accept invitation"}</button>{state.error&&<p role="alert" className="auth-alert">{state.error}</p>}</form>;
}
