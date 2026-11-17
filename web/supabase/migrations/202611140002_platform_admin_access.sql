-- Run this NEW migration in Supabase SQL Editor. It preserves your founder row.
begin;

create schema if not exists private;
create table if not exists private.platform_admins (
  user_id uuid primary key references auth.users(id),
  created_at timestamptz not null default now()
);
alter table private.platform_admins enable row level security;
revoke all on private.platform_admins from public, anon, authenticated;

-- Checks only the caller's identity; cannot look up or promote another user.
create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from private.platform_admins
    where user_id = (select auth.uid())
  );
$$;

revoke all on function public.is_platform_admin() from public, anon;
grant execute on function public.is_platform_admin() to authenticated;

-- Make the new RPC available to Supabase's REST API after this transaction.
notify pgrst, 'reload schema';

commit;
