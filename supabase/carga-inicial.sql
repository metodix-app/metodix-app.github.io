
-- ---------- Administrador de Metodix ----------
insert into public.admins (email) values ('carlsan4444@gmail.com') on conflict do nothing;

-- ---------- Datos iniciales desde el repositorio ----------
create extension if not exists http with schema extensions;

insert into public.config_general (id, data)
select 'general', (select content from extensions.http_get('https://raw.githubusercontent.com/metodix-app/metodix-app.github.io/multiclub/supabase/datos/config-general.json'))::jsonb
on conflict (id) do update set data = excluded.data, updated_at = now();

insert into public.docs (club_id, path, data)
select c.id, 'config/club', (select content from extensions.http_get('https://raw.githubusercontent.com/metodix-app/metodix-app.github.io/multiclub/supabase/datos/config-cimadevilla.json'))::jsonb
from public.clubs c where c.nombre = 'Cimadevilla CF'
on conflict (club_id, path) do update set data = excluded.data, updated_at = now();

insert into public.ejercicios (id, club_id, grupo, orden, estado, data)
select x->>'id', case when (x->>'solo_club')::boolean then (select id from public.clubs where nombre = 'Cimadevilla CF') else null end,
       x->>'grupo', (x->>'orden')::int, 'publicado', x->'data'
from jsonb_array_elements((select content from extensions.http_get('https://raw.githubusercontent.com/metodix-app/metodix-app.github.io/multiclub/supabase/datos/banco-inicial.json'))::jsonb) x
on conflict (id) do nothing;

select json_build_object(
  'ejercicios', (select count(*) from public.ejercicios),
  'comunes', (select count(*) from public.ejercicios where club_id is null),
  'solo_cimadevilla', (select count(*) from public.ejercicios where club_id is not null),
  'config_general', (select count(*) from public.config_general),
  'config_cimadevilla', (select count(*) from public.docs where path = 'config/club'),
  'admins', (select count(*) from public.admins))::text as resultado;
