import 'server-only';
import {createClient} from './supabase/server';
import type {SalesChannelPacket} from './channels';
export async function restaurantChannels(organisation:string):Promise<SalesChannelPacket|null>{const client=await createClient(),r=await client.rpc('sales_channels',{p_organisation_id:organisation});return r.error?null:r.data;}
