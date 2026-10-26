-- Montre (Xiaomi Smart Band via app Santé) : à lancer une seule fois dans Supabase → SQL Editor → Run.

-- 1. Les données reçues de la montre (une ligne par jour)
create table if not exists public.carnet_health (
  user_id     uuid not null references auth.users(id) on delete cascade,
  day         date not null,
  active_kcal integer,
  rest_kcal   integer,
  steps       integer,
  updated_at  timestamptz not null default now(),
  primary key (user_id, day)
);
alter table public.carnet_health enable row level security;
drop policy if exists "health: lecture" on public.carnet_health;
create policy "health: lecture" on public.carnet_health
  for select to authenticated using (user_id = auth.uid());
grant select on public.carnet_health to authenticated;

-- 2. Le code de liaison secret utilisé par le raccourci iPhone
create table if not exists public.carnet_tokens (
  user_id    uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  token      text not null unique,
  created_at timestamptz not null default now()
);
alter table public.carnet_tokens enable row level security;
drop policy if exists "tokens: mon code" on public.carnet_tokens;
create policy "tokens: mon code" on public.carnet_tokens
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update, delete on public.carnet_tokens to authenticated;

-- 3. La porte d'entrée appelée par le raccourci (n'accepte que ton code)
create or replace function public.push_health(p_token text, p_day text default null, p_kcal text default null, p_rest text default null, p_steps text default null)
returns text language plpgsql security definer set search_path = public as $$
declare
  uid uuid;
  n_kcal numeric := nullif(replace(regexp_replace(coalesce(p_kcal,''),'[^0-9,.\-]','','g'),',','.'),'')::numeric;
  n_rest numeric := nullif(replace(regexp_replace(coalesce(p_rest,''),'[^0-9,.\-]','','g'),',','.'),'')::numeric;
  n_steps numeric := nullif(replace(regexp_replace(coalesce(p_steps,''),'[^0-9,.\-]','','g'),',','.'),'')::numeric;
  d date := coalesce(nullif(trim(coalesce(p_day,'')),'')::date, (now() at time zone 'Europe/Paris')::date);
begin
  if p_token is null or length(p_token) < 32 then raise exception 'code invalide'; end if;
  select user_id into uid from public.carnet_tokens where token = p_token;
  if uid is null then raise exception 'code invalide'; end if;
  insert into public.carnet_health(user_id, day, active_kcal, rest_kcal, steps, updated_at)
  values (uid, d, round(n_kcal), round(n_rest), round(n_steps), now())
  on conflict (user_id, day) do update set
    active_kcal = coalesce(excluded.active_kcal, carnet_health.active_kcal),
    rest_kcal   = coalesce(excluded.rest_kcal,   carnet_health.rest_kcal),
    steps       = coalesce(excluded.steps,       carnet_health.steps),
    updated_at  = now();
  return 'ok';
end $$;
revoke all on function public.push_health(text, text, text, text, text) from public;
grant execute on function public.push_health(text, text, text, text, text) to anon, authenticated;
