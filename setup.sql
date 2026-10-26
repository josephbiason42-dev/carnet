-- À lancer une seule fois dans Supabase : SQL Editor → New query → coller → Run.
create table if not exists public.carnet_docs (
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  key        text not null,
  body       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, key)
);

alter table public.carnet_docs enable row level security;

-- Chaque compte ne voit et ne modifie que ses propres données.
drop policy if exists "carnet: mes données" on public.carnet_docs;
create policy "carnet: mes données" on public.carnet_docs
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

grant select, insert, update, delete on public.carnet_docs to authenticated;
