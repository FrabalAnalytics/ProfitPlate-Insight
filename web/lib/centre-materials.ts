export type CentreMaterial={id:string;name:string;code:string;unit:string|null;active:boolean;assigned:boolean;held:string};
export type CentreCatalogue={centre:string;active:boolean;revision:number;legacy:boolean;items:CentreMaterial[]};
export function materialAtCentre(item:{centre_ids?:string[]}|undefined,site:string){return !!site&&!!item&&(item.centre_ids===undefined||item.centre_ids.includes(site));}
