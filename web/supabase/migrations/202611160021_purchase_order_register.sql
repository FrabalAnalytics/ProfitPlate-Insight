-- Apply once after 020. Read-only register with delivery filters before pagination.
begin;
create function public.list_purchase_order_register(p_organisation_id uuid,p_page integer,p_status text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not (private.pp_reference_price_read(p_organisation_id) or private.pp_inventory_access(p_organisation_id)) then
  raise exception 'Purchase access denied.' using errcode='42501'; end if;
 if p_page is null or p_page not between 1 and 100000 or p_status is null or p_status not in ('ALL','DRAFT','ISSUED','PENDING','PARTIAL','COMPLETED') then
  raise exception 'Choose a valid order page and status.' using errcode='22023'; end if;
 with visible as materialized (
  select o.id,o.reference,o.status,o.document_date,o.payload,o.created_at,
   case when o.status='DRAFT' then 'DRAFT'
    when coalesce(progress.complete,false) then 'COMPLETED'
    when coalesce(progress.started,false) then 'PARTIAL' else 'PENDING' end as delivery_status
  from public.purchase_orders o
  cross join lateral (
   select bool_and(q.accepted>=q.quantity) as complete,bool_or(q.accepted>0) as started
   from (
    select l.quantity,coalesce((select sum(r.accepted) from public.goods_receipt_lines r
     where r.organisation_id=o.organisation_id and r.order_line_id=l.id
     and not private.pp_receipt_voided(o.organisation_id,r.receipt_id)),0) as accepted
    from public.purchase_order_lines l where l.organisation_id=o.organisation_id and l.order_id=o.id
   ) q
  ) progress
  where o.organisation_id=p_organisation_id and private.pp_order_read(p_organisation_id,o.id)
 ), filtered as (
  select * from visible where p_status='ALL' or (p_status='ISSUED' and status='ISSUED') or delivery_status=p_status
 ), paged as (
  select * from filtered order by created_at desc,id limit 20 offset (p_page-1)*20
 )
 select jsonb_build_object('total',(select count(*) from filtered),'orders',coalesce((select jsonb_agg(
  jsonb_build_object('id',id,'reference',reference,'status',status,'delivery_status',delivery_status,
   'date',document_date,'header',payload->'header') order by created_at desc,id) from paged),'[]'::jsonb)) into result;
 return result;
end;$$;
revoke all on function public.list_purchase_order_register(uuid,integer,text) from public,anon;
grant execute on function public.list_purchase_order_register(uuid,integer,text) to authenticated;
notify pgrst,'reload schema';
commit;
