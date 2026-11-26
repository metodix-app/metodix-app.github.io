-- Metodix · Los clubes nuevos reciben una copia de la programación general de mesociclos
create or replace function public.admin_guardar_club(p_id uuid, p_nombre text, p_color1 text, p_color2 text,
  p_escudo text, p_equipos jsonb) returns json
language plpgsql security definer set search_path = public as $$
declare c clubs; cfg jsonb; base text; nuevo boolean := p_id is null;
begin
  if not public.is_admin() then raise exception 'Solo administración'; end if;
  if coalesce(trim(p_nombre), '') = '' then raise exception 'Falta el nombre del club'; end if;
  if nuevo then
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
  select data into cfg from docs where club_id = c.id and path = 'config/club';
  cfg := coalesce(cfg, '{}'::jsonb);
  if p_equipos is not null then cfg := cfg || jsonb_build_object('teams', p_equipos); end if;
  if jsonb_array_length(coalesce(cfg->'mesos', '[]'::jsonb)) = 0 then
    cfg := cfg || jsonb_build_object('mesos', coalesce((select data->'mesos' from config_general where id = 'general'), '[]'::jsonb));
  end if;
  insert into docs (club_id, path, data) values (c.id, 'config/club', cfg)
  on conflict (club_id, path) do update set data = excluded.data, updated_at = now();
  return json_build_object('id', c.id, 'codigo_entrenador', c.codigo_entrenador, 'codigo_coordinacion', c.codigo_coordinacion);
end $$;

-- Clubes que ya existen sin mesociclos propios: copia de la programación general
update public.docs d set data = d.data || jsonb_build_object('mesos', g.data->'mesos'), updated_at = now()
from public.config_general g
where g.id = 'general' and d.path = 'config/club'
  and jsonb_array_length(coalesce(d.data->'mesos', '[]'::jsonb)) = 0;

select c.nombre, jsonb_array_length(coalesce(d.data->'mesos','[]')) as mesociclos from public.clubs c
left join public.docs d on d.club_id = c.id and d.path = 'config/club' order by c.created_at;
