create table public.whatsapp_people (
  name_key text primary key,
  name text not null check (char_length(name) between 1 and 80),
  claimed_by uuid unique references auth.users(id) on delete set null
);

create table public.whatsapp_searches (
  name_key text not null references public.whatsapp_people(name_key) on delete cascade,
  category text not null references public.categories(id),
  item text not null check (char_length(item) between 1 and 80),
  item_key text not null,
  notes text check (char_length(notes) <= 300),
  primary key (name_key, category, item_key)
);

alter table public.whatsapp_people enable row level security;
alter table public.whatsapp_searches enable row level security;
revoke all on public.whatsapp_people, public.whatsapp_searches from public, anon, authenticated;

create function public.whatsapp_item_key(category text, item text)
returns text language sql immutable set search_path = ''
as $$
  select case
    when category = 'team_transport' and normalized in ('tt rexy', 'team transport rexy')
      then 'team transport rexy'
    when category = 'basicos' and normalized in ('nissan r34 negro 2026', 'nissan skyline gt-r (bnr34) · 2026 jjl88')
      then 'nissan skyline gt-r (bnr34) · 2026 jjl88'
    when category = 'basicos' and normalized in ('porsche gt3 rs azul 2027', 'porsche 911 gt3 rs · 2027 jnx83')
      then 'porsche 911 gt3 rs · 2027 jnx83'
    when category = 'premium' and normalized in ('supra chase', 'toyota supra chase · 2026 jhw78')
      then 'toyota supra chase · 2026 jhw78'
    when category = 'premium' and normalized in ('charger chase', '1970 dodge charger r/t chase · 2026 jhw74')
      then '1970 dodge charger r/t chase · 2026 jhw74'
    when category = 'premium' and normalized in ('eclipse chase', '1995 mitsubishi eclipse chase · 2026 jhw68')
      then '1995 mitsubishi eclipse chase · 2026 jhw68'
    when category = 'premium' and normalized in ('ferrari enzo', 'enzo ferrari · 2026 jhw22')
      then 'enzo ferrari · 2026 jhw22'
    else normalized
  end
  from (select lower(btrim(item)) as normalized) value
$$;

create function public.import_whatsapp_searches(entries jsonb)
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  added integer;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and is_admin is true) then
    raise exception 'Solo los administradores pueden importar listas' using errcode = '42501';
  end if;
  if entries is null or jsonb_typeof(entries) <> 'array' or jsonb_array_length(entries) not between 1 and 500 then
    raise exception 'La lista debe contener entre 1 y 500 búsquedas';
  end if;

  perform pg_advisory_xact_lock(142187, 61011);
  insert into public.whatsapp_people (name_key, name)
    select translate(lower(btrim(e.name)), 'áéíóúü', 'aeiouu'), btrim(e.name)
    from jsonb_to_recordset(entries) as e(name text)
    on conflict do nothing;

  with new_rows as (
    insert into public.whatsapp_searches (name_key, category, item, item_key, notes)
      select translate(lower(btrim(e.name)), 'áéíóúü', 'aeiouu'), e.category, btrim(e.item),
        public.whatsapp_item_key(e.category, e.item), nullif(btrim(e.notes), '')
      from jsonb_to_recordset(entries) as e(name text, category text, item text, notes text)
      on conflict do nothing
      returning *
  ), assigned as (
    insert into public.wants (user_id, category, item, notes)
      select p.claimed_by, n.category, n.item, n.notes
      from new_rows n join public.whatsapp_people p using (name_key)
      where p.claimed_by is not null and not exists (
        select 1 from public.wants w where w.user_id = p.claimed_by
          and w.category = n.category and public.whatsapp_item_key(w.category, w.item) = n.item_key
      )
      on conflict do nothing
      returning id
  )
  select count(*) into added from new_rows;
  return added;
end;
$$;

create function public.list_whatsapp_names()
returns table (name_key text, name text)
language sql stable security definer set search_path = ''
as $$
  select p.name_key, p.name
  from public.whatsapp_people p
  where auth.uid() is not null and p.claimed_by is null
    and not exists (select 1 from public.whatsapp_people own where own.claimed_by = auth.uid())
  order by p.name;
$$;

create function public.claim_whatsapp_searches(selected_name text)
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  account uuid := auth.uid();
  added integer;
begin
  if account is null or not exists (select 1 from public.profiles where id = account) then
    raise exception 'Inicia sesión para recuperar tus búsquedas' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(142187, 61011);
  if exists (select 1 from public.whatsapp_people where claimed_by = account) then
    raise exception 'Tu cuenta ya está vinculada a un nombre';
  end if;

  update public.whatsapp_people set claimed_by = account
    where name_key = selected_name and claimed_by is null;
  if not found then
    raise exception 'Ese nombre ya no está disponible';
  end if;

  insert into public.wants (user_id, category, item, notes)
    select account, s.category, s.item, s.notes
    from public.whatsapp_searches s
    where s.name_key = selected_name and not exists (
      select 1 from public.wants w where w.user_id = account and w.category = s.category
        and public.whatsapp_item_key(w.category, w.item) = s.item_key
    )
    on conflict do nothing;
  get diagnostics added = row_count;
  return added;
end;
$$;

revoke all on function public.whatsapp_item_key(text, text) from public, anon, authenticated;
revoke all on function public.import_whatsapp_searches(jsonb) from public, anon, authenticated;
revoke all on function public.list_whatsapp_names() from public, anon, authenticated;
revoke all on function public.claim_whatsapp_searches(text) from public, anon, authenticated;
grant execute on function public.import_whatsapp_searches(jsonb) to authenticated;
grant execute on function public.list_whatsapp_names() to authenticated;
grant execute on function public.claim_whatsapp_searches(text) to authenticated;
