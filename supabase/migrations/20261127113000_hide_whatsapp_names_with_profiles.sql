create or replace function public.list_whatsapp_names()
returns table (name_key text, name text)
language sql stable security definer set search_path = ''
as $$
  select p.name_key, p.name
  from public.whatsapp_people p
  where auth.uid() is not null
    and p.claimed_by is null
    and not exists (
      select 1
      from public.whatsapp_people own
      where own.claimed_by = auth.uid()
    )
    and not exists (
      select 1
      from public.profiles profile
      where translate(lower(btrim(profile.nickname)), 'áéíóúü', 'aeiouu') = p.name_key
    )
  order by p.name;
$$;

revoke all on function public.list_whatsapp_names() from public, anon, authenticated;
grant execute on function public.list_whatsapp_names() to authenticated;
