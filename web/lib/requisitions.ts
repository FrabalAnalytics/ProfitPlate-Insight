import type {StockPacket} from './inventory';
export const requisitionQueues={APPROVAL:'To approve',DISPATCH:'To dispatch',ACCEPTANCE:'To accept',FOLLOW_UP:'Needs follow-up'} as const;
export const requisitionFilters={ALL:'All statuses',PENDING:'Pending approval',APPROVED:'Ready to dispatch',AWAITING_RECEIPT:'Awaiting acceptance',COMPLETED:'Completed',INCOMPLETE:'Incomplete',REJECTED:'Rejected',CANCELLED:'Cancelled',FOLLOW_UP:'Needs follow-up'} as const;
export type RequisitionPacket=StockPacket&{queues:Record<keyof typeof requisitionQueues,number>};
export function unacceptedQuantity(requested:string,accepted:string){
 const scale=BigInt('1000000000000');
 const units=(value:string)=>{const [whole,part='']=value.split('.');return BigInt(whole)*scale+BigInt(part.padEnd(12,'0'));};
 const remainder=units(requested)-units(accepted),fraction=(remainder%scale).toString().padStart(12,'0').replace(/0+$/,'');
 return `${remainder/scale}${fraction?`.${fraction}`:''}`;
}
