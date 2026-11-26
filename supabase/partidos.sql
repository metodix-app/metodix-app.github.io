-- =========================================================
-- Metodix · Partidos (calendario y valoración de jugadores)
-- Los partidos se guardan en docs con path 'partidos/<id>'
-- y data->>'equipo' = id del equipo.
--   · Coordinación: todo (política "coordinacion todo").
--   · Entrenador: solo los partidos de los equipos que tiene
--     asignados en config/asignaciones.
-- =========================================================
create or replace function public.entreno_equipo(c uuid, eq text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from docs
    where club_id = c and path = 'config/asignaciones'
      and coalesce(data->'entrenadores'->(auth.uid()::text), '[]'::jsonb) ? eq
  ) and public.es_miembro(c)
$$;
grant execute on function public.entreno_equipo(uuid, text) to authenticated;

drop policy if exists "partidos de mis equipos" on public.docs;
create policy "partidos de mis equipos" on public.docs for all to authenticated
  using (path like 'partidos/%' and public.entreno_equipo(club_id, data->>'equipo'))
  with check (path like 'partidos/%' and public.entreno_equipo(club_id, data->>'equipo'));
