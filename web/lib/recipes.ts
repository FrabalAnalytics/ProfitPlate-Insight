export type RecipeOption = { id: string; label: string; code: string; uom_id: string; uom_code: string; dimension: string };
export type RecipeLine = { key: string; kind: "ITEM" | "RECIPE"; target: RecipeOption | null; quantity: string; uom_id: string };
export type RecipePacket = {
 recipe: { id: string; code: string; name: string; location_id?:string|null; recipe_type: "FINAL" | "SUB_RECIPE" };
 version: { id: string; recipe_id: string; version: number; name: string; effective_from: string; notes: string; created_at: string };
 output: { quantity: string; uom_id: string; uom_code: string };
 components: { id: string; kind: "ITEM" | "RECIPE"; target_id: string; label: string; code: string; target_type: string; quantity: string; uom_id: string; uom_code: string; base_uom_id: string; base_uom_code: string; dimension: string; normalised_quantity: string; conversion_id: string | null }[];
 cost_state: "MISSING";
};
export const positiveDecimal = (text: string) => /^(?:0|[1-9]\d{0,13})(?:\.\d{1,6})?$/.test(text) && /[1-9]/.test(text);
/** Display only: round exact decimal strings to at most three places, never source records. */
export function displayQuantity(value:string|number):string{
 const text=String(value),match=/^([+-]?)(\d+)(?:\.(\d*))?(?:e([+-]?\d+))?$/i.exec(text);
 if(!match)return typeof value==='number'?'Unavailable':text;
 const [,sign,whole,fraction='',power='0']=match,exponent=Number(power);
 if(!Number.isSafeInteger(exponent)||Math.abs(exponent)>1000)return 'Unavailable';
 const digits=whole+fraction,point=whole.length+exponent;
 const integer=point<=0?'0':point>=digits.length?digits+'0'.repeat(point-digits.length):digits.slice(0,point);
 const decimals=point<=0?'0'.repeat(-point)+digits:point>=digits.length?'':digits.slice(point);
 let scaled=BigInt(integer)*BigInt(1000)+BigInt(decimals.padEnd(3,'0').slice(0,3));
 if((decimals[3]??'0')>='5')scaled+=BigInt(1);
 if(scaled===BigInt(0)&&/[1-9]/.test(digits))return sign==='-'?'>-0.001':'<0.001';
 const tail=(scaled%BigInt(1000)).toString().padStart(3,'0').replace(/0+$/,'');
 return `${sign==='-'&&scaled>BigInt(0)?'-':''}${scaled/BigInt(1000)}${tail?'.'+tail:''}`;
}
export function validBusinessDate(value: string) {
 try { return /^\d{4}-\d{2}-\d{2}$/.test(value) && new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value; }
 catch { return false; }
}
