-- Metodix · Arreglo de los códigos de club
-- El código de coordinación de los clubes nuevos llevaba letras en minúscula
-- y al escribirlo no coincidía nunca. Ahora todo va en mayúsculas y la
-- comprobación no distingue mayúsculas de minúsculas.

update public.clubs set codigo_coordinacion = upper(codigo_coordinacion),
  codigo_entrenador = upper(codigo_entrenador);

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
    values (trim(p_nombre), public.codigo_aleatorio(base),
            public.codigo_aleatorio(base || '-COORD') || public.codigo_aleatorio(''),
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

create or replace function public.unirse_club(codigo text, nombre text)
returns json language plpgsql security definer set search_path = public as $$
declare c clubs; r text; n text; k text;
begin
  if auth.uid() is null then raise exception 'Sin sesión'; end if;
  k := upper(regexp_replace(coalesce(codigo, ''), '\s', '', 'g'));
  select * into c from clubs where upper(codigo_entrenador) = k;
  if found then
    r := 'entrenador';
  else
    select * into c from clubs where upper(codigo_coordinacion) = k;
    if found then r := 'coord'; else raise exception 'Código de club no válido'; end if;
  end if;
  n := coalesce(nullif(trim(nombre), ''), (select m.nombre from miembros m where m.user_id = auth.uid() and m.nombre <> '' limit 1), '');
  insert into miembros (user_id, club_id, nombre, rol) values (auth.uid(), c.id, n, r)
  on conflict (user_id, club_id) do update set
    rol = case when miembros.rol = 'coord' then 'coord' else excluded.rol end,
    nombre = case when excluded.nombre <> '' then excluded.nombre else miembros.nombre end;
  return json_build_object('club_id', c.id, 'club', c.nombre, 'rol', (select rol from miembros where user_id = auth.uid() and club_id = c.id));
end $$;

select nombre, codigo_entrenador, codigo_coordinacion from public.clubs order by created_at;
