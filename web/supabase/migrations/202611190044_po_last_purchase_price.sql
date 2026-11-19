-- Read-only price comparison while raising a PO; no prices or order values are changed.
begin;
create function public.po_last_purchase_price(p_organisation_id uuid,p_item_id uuid,p_uom_id uuid,p_as_of date default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare material public.items;target public.units_of_measure;base public.units_of_measure;
 cutoff date;factor numeric;last_row record;reference public.material_reference_prices;
begin
 if not private.pp_purchase_write(p_organisation_id) then raise exception 'Purchase-order entry access required.' using errcode='42501';end if;
 select least(coalesce(p_as_of,(now() at time zone time_zone)::date),(now() at time zone time_zone)::date) into cutoff from public.organisations where id=p_organisation_id;
 select * into material from public.items where organisation_id=p_organisation_id and id=p_item_id and is_active;
 select * into target from public.units_of_measure where organisation_id=p_organisation_id and id=p_uom_id;
 if material.id is null or target.id is null then raise exception 'Choose a material and unit in this business.' using errcode='22023';end if;
 select * into base from public.units_of_measure where organisation_id=p_organisation_id and id=material.base_uom_id;
 if target.dimension='PACKAGE' then
  select c.factor into factor from public.item_uom_conversions c where c.organisation_id=p_organisation_id and c.item_id=p_item_id and c.from_uom_id=p_uom_id and c.effective_from<=cutoff order by c.effective_from desc limit 1;
 elsif target.dimension=base.dimension then factor:=target.canonical_factor/base.canonical_factor;end if;
 if factor is null then return jsonb_build_object('status','CONVERSION_REQUIRED','unit_code',target.code);end if;
 -- Apply the latest approved replacement/void before choosing the latest purchase date.
 with replacements as materialized (
  select distinct on(c.purchase_id) c.purchase_id,c.proposal value from public.purchase_corrections c
  where c.organisation_id=p_organisation_id and c.state='APPROVED' order by c.purchase_id,c.decided_at desc,c.id desc
 ), invoice_rows as (
  select h.id,h.purchase_date as purchased_on,h.created_at,p.source_row::bigint row_number,
   h.purchase_ref reference,s.name supplier,h.currency_code currency,h.price_basis,
   p.unit_price/nullif(p.conversion_factor,0) per_base
  from public.purchase_headers h join public.purchase_lines p on p.organisation_id=h.organisation_id and p.purchase_id=h.id
  join public.suppliers s on s.organisation_id=h.organisation_id and s.id=h.supplier_id
  where h.organisation_id=p_organisation_id and p.item_id=p_item_id and h.purchase_date<=cutoff
  and not exists(select 1 from replacements r where r.purchase_id=h.id)
  union all
  select h.id,(r.value->'header'->>'date')::date,h.created_at,n,
   r.value->'header'->>'reference',r.value->'header'->>'supplier_name',r.value->'header'->>'currency',r.value->'header'->>'price_basis',
   (l->>'unit_price')::numeric/nullif((l->>'conversion_factor')::numeric,0)
  from replacements r join public.purchase_headers h on h.organisation_id=p_organisation_id and h.id=r.purchase_id
  cross join lateral jsonb_array_elements(r.value->'lines') with ordinality rows(l,n)
  where not coalesce((r.value->>'voided')::boolean,false) and l->>'item_id'=p_item_id::text and (r.value->'header'->>'date')::date<=cutoff
 ) select * into last_row from invoice_rows where per_base is not null order by purchased_on desc,created_at desc,id desc,row_number desc limit 1;
 if found then
  return jsonb_build_object('status','FOUND','source','INVOICE','unit_price',round(last_row.per_base*factor,12)::text,
   'unit_code',target.code,'currency',last_row.currency,'date',last_row.purchased_on,'supplier',last_row.supplier,
   'reference',last_row.reference,'price_basis',last_row.price_basis);
 end if;
 -- An onboarding price is a fallback, explicitly distinct from an actual purchase invoice.
 select * into reference from public.material_reference_prices p where p.organisation_id=p_organisation_id and p.item_id=p_item_id and p.price_date<=cutoff order by p.price_date desc,p.version desc limit 1;
 if found then return jsonb_build_object('status','FOUND','source','INITIAL_PRICE','unit_price',round(reference.cost_per_base_unit*factor,12)::text,
  'unit_code',target.code,'currency',reference.currency_code,'date',reference.price_date,'price_basis','REFERENCE');end if;
 return jsonb_build_object('status','NOT_FOUND','unit_code',target.code);
end $$;
revoke all on function public.po_last_purchase_price(uuid,uuid,uuid,date) from public,anon;
grant execute on function public.po_last_purchase_price(uuid,uuid,uuid,date) to authenticated;
commit;
