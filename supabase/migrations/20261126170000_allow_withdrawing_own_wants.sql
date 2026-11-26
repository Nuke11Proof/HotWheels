grant delete on public.wants to authenticated;

create policy wants_withdraw_own_open on public.wants
  for delete to authenticated
  using (user_id = (select auth.uid()) and status = 'open');
