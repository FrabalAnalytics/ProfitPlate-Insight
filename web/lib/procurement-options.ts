import "server-only";
import { createClient } from "./supabase/server";
import type { InvoiceOptions } from "./procurement";
export async function procurementOptions(organisation: string): Promise<InvoiceOptions | null> {
 const client=await createClient();
 const [suppliers,locations,items,units]=await Promise.all([
  client.from("suppliers").select("id,name").eq("organisation_id",organisation).eq("is_active",true).order("name").limit(1000),
  client.from("locations").select("id,name").eq("organisation_id",organisation).eq("is_active",true).order("name").limit(1000),
  client.from("items").select("id,name,code,item_type,base_uom_id").eq("organisation_id",organisation).eq("is_active",true).order("name").limit(1000),
  client.from("units_of_measure").select("id,name,code").eq("organisation_id",organisation).order("name").limit(1000),
 ]);
 if([suppliers,locations,items,units].some(result=>result.error))return null;
 return {suppliers:suppliers.data??[],locations:locations.data??[],items:items.data??[],units:units.data??[]};
}
