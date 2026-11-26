begin;

alter table public.wants
  add column if not exists notes text
  check (char_length(notes) <= 300);

create table if not exists public.categories (
  id text primary key default gen_random_uuid()::text,
  label text not null check (char_length(btrim(label)) between 1 and 60),
  position integer not null default 100
);

create unique index if not exists categories_label_unique
  on public.categories (lower(btrim(label)));

insert into public.categories (id, label, position) values
  ('basicos', '🚗 Básicos', 10),
  ('team_transport', '🚛 Team Transport', 20),
  ('premium', '💛 Premium', 30),
  ('collector', '🔴 Collector', 40),
  ('reservas', '🔰 Reservas', 50)
on conflict (id) do nothing;

alter table public.categories enable row level security;
grant select on public.categories to authenticated;
grant insert (label) on public.categories to authenticated;

drop policy if exists categories_read on public.categories;
create policy categories_read on public.categories for select to authenticated
  using (true);

drop policy if exists categories_admin_insert on public.categories;
create policy categories_admin_insert on public.categories for insert to authenticated
  with check (exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and is_admin
  ));

alter table public.products enable row level security;
grant insert (category, name) on public.products to authenticated;

drop policy if exists products_admin_insert on public.products;
create policy products_admin_insert on public.products for insert to authenticated
  with check (true);

-- La política restrictiva se aplica también si existe otra política permisiva.
drop policy if exists products_restrict_insert on public.products;
create policy products_restrict_insert on public.products as restrictive for insert to public
  with check (exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and is_admin
  ) and exists (
    select 1 from public.categories where id = products.category::text
  ));

-- El rol de una cuenta solo se gestiona desde el servidor o el panel de Supabase.
create or replace function public.guard_profile_admin()
returns trigger language plpgsql security invoker
set search_path = ''
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      if new.is_admin is true then
        raise exception 'No puedes asignar permisos de administrador' using errcode = '42501';
      end if;
    elsif new.is_admin is distinct from old.is_admin then
      raise exception 'No puedes cambiar permisos de administrador' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists guard_profile_admin on public.profiles;
create trigger guard_profile_admin before insert or update on public.profiles
  for each row execute function public.guard_profile_admin();

commit;
