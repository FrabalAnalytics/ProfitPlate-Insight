export type SetupAction={id:string;kind:string;title:string;detail:string;responsible:string;centre_owner:string|null;path:string;params:Record<string,string>};
export type SetupActions={total:number;remaining:number;summary:{kind:string;total:number}[];next:SetupAction|null;rows:SetupAction[]};
export function workflowLink(org:string,path:string,params:Record<string,string>={}){
 const [route,query]=path.split('?');const search=new URLSearchParams(query);search.set('organisation',org);for(const [key,value] of Object.entries(params))search.set(key,value);return `${route}?${search}`;
}
export const setupAreas={ALL:'All setup tasks',CENTRES:'Stock centres',MATERIALS:'Materials and costs',OPENINGS:'Opening stock',PROCESSING:'Processing baselines',OTHER:'Other setup'};
export type CorrectionQueue={review:number;post:number;waiting:number;total:number;rows:{id:string;reference:string;kind:string;state:string;centre:string;created_at:string;own:boolean;can_review:boolean;can_post:boolean;next_action:string;reviewers:string[]}[]};
export type ClosePacket={can_setup:boolean;month:string;through:string;ended:boolean;site_id:string|null;centres:{id:string;name:string}[];checks:{id:string;label:string;pending:number;path:string;params:Record<string,string>}[];pending:number;evidence:string;saved:null|{id:string;at:string;name:string;current:boolean;confirmations:Record<string,boolean>;note:string;ready:boolean}};
