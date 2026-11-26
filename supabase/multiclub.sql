-- =====================================================================
-- Metodix · paso a multiclub
--   · administradores de Metodix (por encima de todos los clubes)
--   · banco de ejercicios en la base de datos (común o solo de un club)
--   · configuración general (equipos y mesociclos) para clubes sin la suya
--   · escudo de cada club y alta de clubes desde el panel de administrador
--   · las propuestas de ejercicios de todos los clubes llegan al administrador
-- =====================================================================

-- ---------- Administradores ----------
create table if not exists public.admins (
  email text primary key,
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;
revoke all on public.admins from anon, authenticated;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from admins where lower(email) = lower(coalesce(auth.email(), '')))
$$;
grant execute on function public.is_admin() to authenticated;

-- ---------- Clubes: escudo ----------
alter table public.clubs add column if not exists escudo text not null default '';

create or replace function public.mi_cuenta() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('club_id', m.club_id, 'club', c.nombre, 'rol', m.rol, 'nombre', m.nombre,
                           'color1', c.color_principal, 'color2', c.color_acento, 'escudo', c.escudo,
                           'admin', public.is_admin())
  from miembros m join clubs c on c.id = m.club_id
  where m.user_id = auth.uid()
$$;

-- ---------- Configuración general (la usan los clubes sin programación propia) ----------
create table if not exists public.config_general (
  id text primary key,
  data jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.config_general enable row level security;
drop policy if exists "leer config general" on public.config_general;
create policy "leer config general" on public.config_general for select to authenticated using (true);
drop policy if exists "admin config general" on public.config_general;
create policy "admin config general" on public.config_general for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
grant select, insert, update, delete on public.config_general to authenticated;
revoke all on public.config_general from anon;

-- ---------- Banco de ejercicios ----------
--   club_id nulo = banco común (todos los clubes); con club = solo ese club
--   estado: 'revision' (preparado por Claude, solo lo ve el administrador) o 'publicado'
create table if not exists public.ejercicios (
  id text primary key,
  club_id uuid references public.clubs on delete cascade,
  grupo text not null default 'propio',
  orden integer not null default 100000,
  estado text not null default 'publicado' check (estado in ('revision', 'publicado')),
  propuesta text,
  data jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.ejercicios enable row level security;
drop policy if exists "leer ejercicios" on public.ejercicios;
create policy "leer ejercicios" on public.ejercicios for select to authenticated
  using (public.is_admin() or (estado = 'publicado' and (club_id is null or club_id = public.mi_club())));
drop policy if exists "admin ejercicios" on public.ejercicios;
create policy "admin ejercicios" on public.ejercicios for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
grant select, insert, update, delete on public.ejercicios to authenticated;
revoke all on public.ejercicios from anon;

-- ---------- Propuestas: el administrador las ve y las gestiona en todos los clubes ----------
drop policy if exists "admin propuestas" on public.docs;
create policy "admin propuestas" on public.docs for all to authenticated
  using (public.is_admin() and path like 'cuentas/%/propuestas/%')
  with check (public.is_admin() and path like 'cuentas/%/propuestas/%');

-- Lista de propuestas de todos los clubes, con el nombre del club
create or replace function public.admin_propuestas() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Solo administración'; end if;
  return coalesce((select json_agg(json_build_object('club_id', d.club_id, 'club', c.nombre, 'path', d.path, 'data', d.data) order by d.updated_at desc)
    from docs d join clubs c on c.id = d.club_id where d.path like 'cuentas/%/propuestas/%'), '[]'::json);
end $$;
grant execute on function public.admin_propuestas() to authenticated;

create or replace function public.admin_guardar_propuesta(p_club uuid, p_path text, p_data jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Solo administración'; end if;
  if p_path not like 'cuentas/%/propuestas/%' then raise exception 'Ruta no válida'; end if;
  update docs set data = p_data, updated_at = now() where club_id = p_club and path = p_path;
end $$;
grant execute on function public.admin_guardar_propuesta(uuid, text, jsonb) to authenticated;

-- ---------- Clubes: listado, alta y edición (solo administración) ----------
create or replace function public.admin_clubes() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Solo administración'; end if;
  return coalesce((select json_agg(json_build_object(
      'id', c.id, 'nombre', c.nombre, 'color1', c.color_principal, 'color2', c.color_acento, 'escudo', c.escudo,
      'codigo_entrenador', c.codigo_entrenador, 'codigo_coordinacion', c.codigo_coordinacion,
      'miembros', (select count(*) from miembros m where m.club_id = c.id),
      'coordinadores', (select count(*) from miembros m where m.club_id = c.id and m.rol = 'coord'),
      'config', (select data from docs d where d.club_id = c.id and d.path = 'config/club')
    ) order by c.created_at) from clubs c), '[]'::json);
end $$;
grant execute on function public.admin_clubes() to authenticated;

create or replace function public.codigo_aleatorio(prefijo text) returns text
language sql volatile as $$
  select prefijo || '-' || string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1), '')
  from generate_series(1, 4) g(i)
$$;

create or replace function public.admin_guardar_club(p_id uuid, p_nombre text, p_color1 text, p_color2 text,
  p_escudo text, p_equipos jsonb) returns json
language plpgsql security definer set search_path = public as $$
declare c clubs; cfg jsonb; base text;
begin
  if not public.is_admin() then raise exception 'Solo administración'; end if;
  if coalesce(trim(p_nombre), '') = '' then raise exception 'Falta el nombre del club'; end if;
  if p_id is null then
    base := upper(regexp_replace(translate(trim(p_nombre), 'áéíóúÁÉÍÓÚñÑüÜ', 'aeiouAEIOUnNuU'), '[^A-Za-z0-9]', '', 'g'));
    base := left(coalesce(nullif(base, ''), 'CLUB'), 10);
    insert into clubs (nombre, codigo_entrenador, codigo_coordinacion, color_principal, color_acento, escudo)
    values (trim(p_nombre), public.codigo_aleatorio(base), public.codigo_aleatorio(base || '-COORD') || substr(md5(random()::text), 1, 4),
            coalesce(nullif(p_color1, ''), '#0B5CAD'), coalesce(nullif(p_color2, ''), '#D52B1E'), coalesce(p_escudo, ''))
    returning * into c;
  else
    update clubs set nombre = trim(p_nombre), color_principal = coalesce(nullif(p_color1, ''), color_principal),
      color_acento = coalesce(nullif(p_color2, ''), color_acento), escudo = coalesce(p_escudo, escudo)
    where id = p_id returning * into c;
    if not found then raise exception 'Club no encontrado'; end if;
  end if;
  if p_equipos is not null then
    select data into cfg from docs where club_id = c.id and path = 'config/club';
    cfg := coalesce(cfg, '{}'::jsonb) || jsonb_build_object('teams', p_equipos);
    insert into docs (club_id, path, data) values (c.id, 'config/club', cfg)
    on conflict (club_id, path) do update set data = excluded.data, updated_at = now();
  end if;
  return json_build_object('id', c.id, 'codigo_entrenador', c.codigo_entrenador, 'codigo_coordinacion', c.codigo_coordinacion);
end $$;
grant execute on function public.admin_guardar_club(uuid, text, text, text, text, jsonb) to authenticated;

revoke execute on function public.admin_propuestas() from anon;
revoke execute on function public.admin_guardar_propuesta(uuid, text, jsonb) from anon;
revoke execute on function public.admin_clubes() from anon;
revoke execute on function public.admin_guardar_club(uuid, text, text, text, text, jsonb) from anon;
