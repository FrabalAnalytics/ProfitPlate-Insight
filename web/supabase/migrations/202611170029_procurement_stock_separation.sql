-- Apply once after 028. Procurement purchasing access stays separate from stock requests.
begin;
create or replace function private.pp_stock_site(org uuid, site uuid, mode text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.stock_locations s where s.organisation_id=org and s.id=site and case
 when mode='read' then private.pp_stock_manager(org) or private.pp_stock_role(org,'ceo',null) or private.pp_stock_role(org,'finance',s.outlet_id)
  or ((private.pp_stock_role(org,'inventory',s.outlet_id) or private.pp_stock_role(org,'operations',s.outlet_id)) and private.pp_stock_assignment(org,site,'read'))
  or private.pp_stock_process(org,site,'stock_department','read') or private.pp_stock_process(org,site,'stock_receiver','read') or private.pp_stock_process(org,site,'stock_dispatcher','read')
 when mode='request' then private.pp_inventory_manager(org) or ((private.pp_stock_role(org,'inventory',s.outlet_id) or private.pp_stock_role(org,'operations',s.outlet_id)) and private.pp_stock_assignment(org,site,'request')) or private.pp_stock_process(org,site,'stock_department','request')
 when mode='approve' then private.pp_inventory_manager(org) or ((private.pp_stock_role(org,'inventory',s.outlet_id) or private.pp_stock_role(org,'operations',s.outlet_id)) and private.pp_stock_assignment(org,site,'approve'))
 when mode='inventory' then private.pp_inventory_manager(org) or (private.pp_stock_role(org,'inventory',s.outlet_id) and private.pp_stock_assignment(org,site,'inventory'))
 when mode='dispatch' then private.pp_inventory_manager(org) or (private.pp_stock_role(org,'inventory',s.outlet_id) and private.pp_stock_assignment(org,site,'dispatch')) or private.pp_stock_process(org,site,'stock_dispatcher','dispatch')
 when mode='receive' then (private.pp_inventory_manager(org) and s.kind in ('STORE','WAREHOUSE')) or (private.pp_stock_role(org,'inventory',s.outlet_id) and private.pp_stock_assignment(org,site,'receive')) or private.pp_stock_process(org,site,'stock_department','receive') or private.pp_stock_process(org,site,'stock_receiver','receive')
 else false end);
$$;
create or replace function private.pp_stock_read(org uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organisation_memberships m join public.membership_roles r on r.organisation_id=m.organisation_id and r.membership_id=m.id where m.organisation_id=org and m.user_id=auth.uid() and m.status='active' and r.role_code in ('ceo','restaurant_admin','finance','inventory','inventory_manager','operations','stock_department','stock_receiver','stock_dispatcher'));
$$;
revoke all on function private.pp_stock_site(uuid,uuid,text),private.pp_stock_read(uuid) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
