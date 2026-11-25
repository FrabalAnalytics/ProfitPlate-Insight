import type {StockDocument} from "./inventory";
export function stockProgress(doc:Pick<StockDocument,"kind"|"state"|"actions"|"posting_policy">){
 if(doc.kind==="WASTE"&&["REQUESTED","APPROVED"].includes(doc.state))return {title:"Submitter name needed",detail:"The original recorder adds the submitter name to complete this waste entry. No approval is required."};
 if(doc.kind==="PRODUCTION"&&["REQUESTED","APPROVED"].includes(doc.state))return {title:"Processing not yet recorded",detail:"This older entry has not changed stock. The original recorder can complete it in the Material Processing Log without approval."};
 if(doc.kind==="PRODUCTION"&&doc.state==="POSTED")return {title:"Processing completed",detail:"Inputs were deducted and actual output added at this centre. No further action is needed."};
 const transfer=doc.kind==="TRANSFER"||doc.kind==="ISSUE";
 switch(doc.state){
 case "REQUESTED":return {title:"Submitted: awaiting approval",detail:"Stock has not changed. A different authorised colleague must approve this record."};
 case "APPROVED":return {title:"Approved successfully",detail:transfer?"Stock has not moved. Next: Inventory dispatches, then the receiving centre accepts the transfer.":doc.actions.post?"Stock has not changed. Next: select Post stock quantities below to complete this record.":"Stock has not changed. Next: the Inventory Manager opens this same record and selects Post stock quantities."};
 case "DISPATCHED":return {title:"Dispatched: awaiting receiver acceptance",detail:doc.posting_policy==="ON_DISPATCH"?"This historical transfer already deducted source stock. Acceptance will not deduct it again.":"Stock is reserved at source. The receiving centre must accept before stock moves."};
 case "POSTED":return {title:doc.kind==="WASTE"?"Waste recorded":"Stock posted successfully",detail:"Stock balances and the ledger are updated. This record is complete; no further posting is needed."};
 case "RECEIVED":return {title:"Transfer completed",detail:"Accepted stock has left the source and been added to the receiving centre."};
 case "PARTIAL":return {title:"Transfer partly accepted",detail:"Only accepted quantities moved. Review the rejected remainder and follow-up."};
 case "CANCELLED":return {title:"Request cancelled",detail:"This request is closed."};
 case "REJECTED":return {title:"Request rejected",detail:"Review the decision note and any required follow-up."};
 default:return null;
 }
}
