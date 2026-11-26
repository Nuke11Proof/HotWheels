insert into public.categories (id, label, position)
values ('silver', 'Silver Series', 25)
on conflict do nothing;
