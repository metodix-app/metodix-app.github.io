-- =====================================================================
-- Metodix · una misma cuenta puede pertenecer a varios clubes
--   · miembros pasa a tener una fila por (usuario, club)
--   · las reglas ya no usan «mi club» sino «¿soy miembro / coordinador de ESTE club?»
--   · mis_clubes(): lista de clubes de la cuenta para el menú de usuario
-- =====================================================================

alter table public.miembros drop constraint if exists miembros_pkey;
alter table public.miembros add primary key (user_id, club_id);

create or replace function public.es_miembro(c uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from miembros where user_id = auth.uid() and club_id = c)
$$;
create or replace function public.soy_coord_en(c uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from miembros where user_id = auth.uid() and club_id = c and rol = 'coord')
$$;
grant execute on function public.es_miembro(uuid) to authenticated;
grant execute on function public.soy_coord_en(uuid) to authenticated;

-- Compatibilidad: el primer club de la cuenta
create or replace function public.mi_club() returns uuid
language sql stable security definer set search_path = public as $$
  select club_id from miembros where user_id = auth.uid() order by created_at limit 1
$$;

-- Reglas por club
drop policy if exists "ver miembros" on public.miembros;
create policy "ver miembros" on public.miembros for select to authenticated
  using (user_id = auth.uid() or public.soy_coord_en(club_id));

drop policy if exists "coordinacion todo" on public.docs;
create policy "coordinacion todo" on public.docs for all to authenticated
  using (public.soy_coord_en(club_id)) with check (public.soy_coord_en(club_id));

drop policy if exists "leer configuracion" on public.docs;
create policy "leer configuracion" on public.docs for select to authenticated
  using (public.es_miembro(club_id) and path like 'config/%');

drop policy if exists "lo mio" on public.docs;
create policy "lo mio" on public.docs for all to authenticated
  using (public.es_miembro(club_id) and (path like 'cuentas/' || auth.uid()::text || '/%' or path = 'solicitudes/' || auth.uid()::text))
  with check (public.es_miembro(club_id) and (path like 'cuentas/' || auth.uid()::text || '/%' or path = 'solicitudes/' || auth.uid()::text));

drop policy if exists "leer ejercicios" on public.ejercicios;
create policy "leer ejercicios" on public.ejercicios for select to authenticated
  using (public.is_admin() or (estado = 'publicado' and (club_id is null or public.es_miembro(club_id))));

drop policy if exists "coordinacion invitaciones" on public.invitaciones;
create policy "coordinacion invitaciones" on public.invitaciones for all to authenticated
  using (public.soy_coord_en(club_id)) with check (public.soy_coord_en(club_id));

-- Unirse a un club con su código (se puede estar en varios)
create or replace function public.unirse_club(codigo text, nombre text)
returns json language plpgsql security definer set search_path = public as $$
declare c clubs; r text; n text;
begin
  if auth.uid() is null then raise exception 'Sin sesión'; end if;
  select * into c from clubs where codigo_entrenador = upper(trim(codigo));
  if found then
    r := 'entrenador';
  else
    select * into c from clubs where codigo_coordinacion = upper(trim(codigo));
    if found then r := 'coord'; else raise exception 'Código de club no válido'; end if;
  end if;
  n := coalesce(nullif(trim(nombre), ''), (select m.nombre from miembros m where m.user_id = auth.uid() and m.nombre <> '' limit 1), '');
  insert into miembros (user_id, club_id, nombre, rol) values (auth.uid(), c.id, n, r)
  on conflict (user_id, club_id) do update set
    rol = case when miembros.rol = 'coord' then 'coord' else excluded.rol end,
    nombre = case when excluded.nombre <> '' then excluded.nombre else miembros.nombre end;
  return json_build_object('club_id', c.id, 'club', c.nombre, 'rol', (select rol from miembros where user_id = auth.uid() and club_id = c.id));
end $$;

-- Alta por correo: entra en el club de la invitación (aunque ya esté en otros)
create or replace function public.aceptar_invitacion() returns json
language plpgsql security definer set search_path = public as $$
declare i invitaciones; uid text; a jsonb; ents jsonb; eqs jsonb;
begin
  if auth.uid() is null then return null; end if;
  select * into i from invitaciones where lower(email) = lower(auth.email()) and user_id is null order by created_at desc limit 1;
  if not found then return null; end if;
  uid := auth.uid()::text;
  insert into miembros (user_id, club_id, nombre, rol) values (auth.uid(), i.club_id, i.nombre, 'entrenador')
  on conflict (user_id, club_id) do update set
    nombre = case when miembros.nombre = '' then excluded.nombre else miembros.nombre end;
  select data into a from docs where club_id = i.club_id and path = 'config/asignaciones';
  a := coalesce(a, '{}'::jsonb);
  ents := coalesce(a->'entrenadores', '{}'::jsonb);
  eqs := coalesce(ents->uid, '[]'::jsonb);
  if not eqs ? i.equipo then eqs := eqs || to_jsonb(i.equipo); end if;
  a := a || jsonb_build_object('entrenadores', ents || jsonb_build_object(uid, eqs), 't', (extract(epoch from now()) * 1000)::bigint);
  insert into docs (club_id, path, data) values (i.club_id, 'config/asignaciones', a)
  on conflict (club_id, path) do update set data = excluded.data, updated_at = now();
  update invitaciones set user_id = auth.uid() where club_id = i.club_id and email = i.email;
  return json_build_object('club_id', i.club_id, 'equipo', i.equipo);
end $$;

-- Clubes de la cuenta (para el menú de usuario)
create or replace function public.mis_clubes() returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('club_id', m.club_id, 'club', c.nombre, 'rol', m.rol, 'nombre', m.nombre,
    'color1', c.color_principal, 'color2', c.color_acento, 'escudo', c.escudo, 'admin', public.is_admin()) order by m.created_at), '[]'::json)
  from miembros m join clubs c on c.id = m.club_id where m.user_id = auth.uid()
$$;
grant execute on function public.mis_clubes() to authenticated;
revoke execute on function public.mis_clubes() from anon;

-- Compatibilidad: primer club
create or replace function public.mi_cuenta() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('club_id', m.club_id, 'club', c.nombre, 'rol', m.rol, 'nombre', m.nombre,
                           'color1', c.color_principal, 'color2', c.color_acento, 'escudo', c.escudo,
                           'admin', public.is_admin())
  from miembros m join clubs c on c.id = m.club_id
  where m.user_id = auth.uid() order by m.created_at limit 1
$$;

-- Salir de un club (no se puede salir del último club ni si eres su único coordinador)
create or replace function public.salir_club(c uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from miembros where user_id = auth.uid()) <= 1 then raise exception 'Es tu único club'; end if;
  if exists (select 1 from miembros where user_id = auth.uid() and club_id = c and rol = 'coord')
     and (select count(*) from miembros where club_id = c and rol = 'coord') <= 1 then
    raise exception 'Eres el único coordinador de este club';
  end if;
  delete from miembros where user_id = auth.uid() and club_id = c;
end $$;
grant execute on function public.salir_club(uuid) to authenticated;
revoke execute on function public.salir_club(uuid) from anon;

select 'varios clubes ok' as resultado;
