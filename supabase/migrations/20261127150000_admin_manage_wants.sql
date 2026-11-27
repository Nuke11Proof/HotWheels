create table public.admin_want_log (
  id bigint generated always as identity primary key,
  changed_at timestamptz not null default now(),
  action text not null check (action in ('add', 'remove')),
  admin_id uuid not null,
  admin_name text not null,
  member_id uuid not null,
  member_name text not null,
  want_id text not null,
  category text not null,
  item text not null
);

alter table public.admin_want_log enable row level security;
revoke all on public.admin_want_log from public, anon, authenticated;
grant select on public.admin_want_log to authenticated;

create policy admin_want_log_read on public.admin_want_log for select to authenticated
  using (exists (
    select 1 from public.profiles where id = (select auth.uid()) and is_admin is true
  ));

create function public.admin_searches(member uuid default null)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and is_admin is true) then
    raise exception 'Solo los administradores pueden gestionar búsquedas' using errcode = '42501';
  end if;

  if member is null then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname)
      order by p.nickname, p.id), '[]'::jsonb) from public.profiles p);
  end if;

  return (select coalesce(jsonb_agg(jsonb_build_object('id', w.id::text, 'category', w.category,
    'item', w.item, 'notes', w.notes) order by w.item, w.id), '[]'::jsonb)
    from public.wants w where w.user_id = member and w.status = 'open');
end;
$$;

create function public.admin_change_search(member uuid, search_category text default null,
  search_item text default null, remove_id text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  actor public.profiles%rowtype;
  recipient public.profiles%rowtype;
  changed public.wants%rowtype;
  target_id public.wants.id%type;
  operation text;
  model_key text;
begin
  select * into actor from public.profiles where id = auth.uid() and is_admin is true;
  if not found then
    raise exception 'Solo los administradores pueden gestionar búsquedas' using errcode = '42501';
  end if;

  select * into recipient from public.profiles where id = member;
  if not found then
    raise exception 'La cuenta seleccionada ya no está disponible';
  end if;

  if remove_id is null then
    if search_item is null or char_length(btrim(search_item)) not between 1 and 80 or not exists (
      select 1 from public.categories where id = search_category
    ) then
      raise exception 'Selecciona un modelo y una categoría válidos';
    end if;

    model_key := public.whatsapp_item_key(search_category, search_item);
    perform pg_advisory_xact_lock(hashtext(member::text), hashtext(search_category || '|' || model_key));
    if exists (
      select 1 from public.wants where user_id = member and status = 'open'
        and category = search_category and public.whatsapp_item_key(category, item) = model_key
    ) then
      raise exception 'Esta persona ya tiene apuntado ese modelo';
    end if;

    operation := 'add';
    insert into public.wants (user_id, category, item, status)
      values (member, search_category, btrim(search_item), 'open')
      returning * into changed;
  else
    target_id := remove_id;
    operation := 'remove';
    delete from public.wants where id = target_id and user_id = member and status = 'open'
      returning * into changed;
    if not found then
      raise exception 'Esa búsqueda ya no está pendiente para esta persona';
    end if;
  end if;

  insert into public.admin_want_log (action, admin_id, admin_name, member_id, member_name, want_id, category, item)
    values (operation, actor.id, actor.nickname, recipient.id, recipient.nickname, changed.id::text, changed.category, changed.item);
end;
$$;

revoke all on function public.admin_searches(uuid) from public, anon, authenticated;
revoke all on function public.admin_change_search(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.admin_searches(uuid) to authenticated;
grant execute on function public.admin_change_search(uuid, text, text, text) to authenticated;
