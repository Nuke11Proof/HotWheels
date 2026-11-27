-- Corrige la referencia de Jose conservando su búsqueda, sus notas y su estado.
update public.wants as w
set item = '''84 Audi Sport quattro · 2027 JNY02'
from public.profiles as p
where p.id = w.user_id
  and translate(lower(regexp_replace(btrim(p.nickname), '[[:space:]]+', ' ', 'g')), 'áéíóúü', 'aeiouu') = 'jose malaga'
  and w.status = 'open'
  and w.category = 'basicos'
  and lower(btrim(w.item)) = '''84 audi sport quattro (2nd color) · 2027 jpd60'
  and not exists (
    select 1 from public.wants as other
    where other.user_id = w.user_id
      and other.category = w.category
      and lower(btrim(other.item)) = '''84 audi sport quattro · 2027 jny02'
  );
