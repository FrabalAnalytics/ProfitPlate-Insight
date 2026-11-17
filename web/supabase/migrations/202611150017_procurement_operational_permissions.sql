-- Apply ONCE after 016. Procurement owns purchase operations; Finance reviews corrections.
begin;
create or replace function private.pp_purchase_write(target_org uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.pp_catalogue_write(target_org);
$$;
-- Existing operational administrator access remains. A Finance-only role cannot
-- stage/post/cancel imports, enter invoices or propose procurement corrections.
-- Finance correction decisions use the separate private.pp_finance guard.
revoke all on function private.pp_purchase_write(uuid) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
