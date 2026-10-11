-- =====================================================================
-- GnvRuteHelper · Ajuste 05 · Frecuencia de visita (7, 14, 21 o 28 días)
--   · Cada cliente tiene una frecuencia. Si no se indica, es semanal (7).
--   · La app sabe la fecha de la última visita "Hecha" de cada cliente
--     y solo lo muestra cuando le vuelve a tocar.
--   · El panel de oficina deja de recibir datos de seguimiento
--     (visitas del día, horas, dispositivos, notas): solo gestión de rutas.
-- Pegar entero en SQL Editor > New query > Run. Se puede repetir sin problema.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. NUEVA COLUMNA: frecuencia del cliente (vacía = semanal)
-- ---------------------------------------------------------------------
alter table public.clientes add column if not exists frecuencia smallint;
alter table public.clientes drop constraint if exists clientes_frecuencia_check;
alter table public.clientes add constraint clientes_frecuencia_check check (frecuencia in (7, 14, 21, 28));

-- Para encontrar rápido la última visita hecha de cada cliente
create index if not exists visitas_hechas_idx on public.visitas (cliente_id, fecha desc) where estado = 'done';

-- Convierte lo que venga del Excel o del panel en 7, 14, 21 o 28 (o nada si viene vacío). Uso interno.
create or replace function public._frecuencia(p text) returns smallint
language sql immutable set search_path = '' as $$
  select case
    when p is null or trim(p) = '' then null
    when trim(p) in ('7', '14', '21', '28') then trim(p)::smallint
    else null
  end
$$;

-- ---------------------------------------------------------------------
-- 2. APP DEL COMERCIAL: la ruta del día trae la frecuencia y la última visita
--    "ultima" = último día ANTERIOR a hoy en que se marcó Hecho.
--    (Lo de hoy ya lo sabe la app por las visitas del día.)
-- ---------------------------------------------------------------------
create or replace function public.ruta_de_hoy(p_token uuid) returns json
language plpgsql stable security definer set search_path = '' as $$
declare v_ruta uuid := public._ruta_de(p_token); v_hoy date := public._hoy();
begin
  return json_build_object(
    'ruta', (select json_build_object('codigo', codigo, 'nombre', nombre) from public.rutas where id = v_ruta),
    'fecha', v_hoy,
    'clientes', coalesce((select json_agg(json_build_object(
        'id', c.id, 'codigo', c.codigo, 'nombre', c.nombre, 'direccion', c.direccion,
        'poblacion', c.poblacion, 'telefono', c.telefono, 'dia_visita', c.dia_visita,
        'lat', c.lat, 'lng', c.lng, 'geo', c.geo,
        'frecuencia', coalesce(c.frecuencia, 7),
        'ultima', (select max(v.fecha) from public.visitas v
                    where v.cliente_id = c.id and v.estado = 'done' and v.fecha < v_hoy)) order by c.nombre)
      from public.clientes c where c.ruta_id = v_ruta and c.activo), '[]'::json),
    'visitas', coalesce((select json_agg(json_build_object('cliente_id', v.cliente_id, 'estado', v.estado, 'hora', v.hora))
      from public.visitas v join public.clientes c on c.id = v.cliente_id
      where c.ruta_id = v_ruta and v.fecha = v_hoy), '[]'::json),
    'notas', coalesce((select json_agg(json_build_object('id', n.id, 'cliente_id', n.cliente_id, 'texto', n.texto,
        'autor', n.autor, 'creada', n.creada) order by n.creada desc)
      from public.notas n join public.clientes c on c.id = n.cliente_id
      where c.ruta_id = v_ruta), '[]'::json)
  );
end $$;

-- ---------------------------------------------------------------------
-- 3. CARGA DEL EXCEL: guarda también la frecuencia.
--    Si el Excel no trae frecuencia, se respeta la que ya tuviera el cliente.
-- ---------------------------------------------------------------------
create or replace function public._importar_ruta(v_ruta uuid, p_clientes jsonb) returns json
language plpgsql security definer set search_path = '' as $$
declare v_n int; v_baja int;
begin
  if jsonb_array_length(p_clientes) > 2000 then raise exception 'DEMASIADOS_CLIENTES'; end if;
  with datos as (
    select distinct on (1) coalesce(nullif(trim(x->>'codigo'), ''), md5(lower(x->>'nombre') || lower(coalesce(x->>'direccion', '')))) as codigo,
           trim(x->>'nombre') as nombre, trim(coalesce(x->>'direccion', '')) as direccion,
           trim(coalesce(x->>'poblacion', '')) as poblacion, trim(coalesce(x->>'telefono', '')) as telefono,
           nullif(x->>'dia_visita', '')::smallint as dia_visita,
           public._frecuencia(x->>'frecuencia') as frecuencia,
           nullif(x->>'lat', '')::double precision as lat, nullif(x->>'lng', '')::double precision as lng,
           nullif(x->>'geo', '') as geo
      from jsonb_array_elements(p_clientes) x
     where coalesce(trim(x->>'nombre'), '') <> ''
  ), up as (
    insert into public.clientes as c (ruta_id, codigo, nombre, direccion, poblacion, telefono, dia_visita, frecuencia, lat, lng, geo, activo, actualizado)
    select v_ruta, codigo, nombre, direccion, poblacion, telefono, dia_visita, frecuencia, lat, lng, geo, true, now() from datos
    on conflict (ruta_id, codigo) do update set
      nombre = excluded.nombre, poblacion = excluded.poblacion, telefono = excluded.telefono,
      dia_visita = excluded.dia_visita, activo = true, actualizado = now(),
      frecuencia = coalesce(excluded.frecuencia, c.frecuencia),
      lat = case when c.direccion is distinct from excluded.direccion then excluded.lat else coalesce(c.lat, excluded.lat) end,
      lng = case when c.direccion is distinct from excluded.direccion then excluded.lng else coalesce(c.lng, excluded.lng) end,
      geo = case when c.direccion is distinct from excluded.direccion then excluded.geo else coalesce(c.geo, excluded.geo) end,
      direccion = excluded.direccion
    returning c.codigo
  )
  select count(*) into v_n from up;
  update public.clientes set activo = false, actualizado = now()
   where ruta_id = v_ruta and activo
     and codigo not in (select coalesce(nullif(trim(x->>'codigo'), ''), md5(lower(x->>'nombre') || lower(coalesce(x->>'direccion', ''))))
                          from jsonb_array_elements(p_clientes) x);
  get diagnostics v_baja = row_count;
  return json_build_object('importados', v_n, 'dados_de_baja', v_baja);
end $$;

-- ---------------------------------------------------------------------
-- 4. PANEL: editar la frecuencia desde la ficha del cliente
-- ---------------------------------------------------------------------
create or replace function public.oficina_guardar_cliente(p_token uuid, p_id uuid, p_datos jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public._of_usuario(p_token);
  if not exists (select 1 from public.clientes where id = p_id) then raise exception 'CLIENTE_NO_EXISTE'; end if;
  update public.clientes set
    nombre     = coalesce(nullif(trim(p_datos->>'nombre'), ''), nombre),
    direccion  = coalesce(p_datos->>'direccion', direccion),
    poblacion  = coalesce(p_datos->>'poblacion', poblacion),
    telefono   = coalesce(p_datos->>'telefono', telefono),
    dia_visita = case when p_datos ? 'dia_visita' then nullif(p_datos->>'dia_visita', '')::smallint else dia_visita end,
    frecuencia = case when p_datos ? 'frecuencia' then public._frecuencia(p_datos->>'frecuencia') else frecuencia end,
    lat        = case when p_datos ? 'lat' then nullif(p_datos->>'lat', '')::double precision else lat end,
    lng        = case when p_datos ? 'lng' then nullif(p_datos->>'lng', '')::double precision else lng end,
    geo        = case when p_datos ? 'geo' then nullif(p_datos->>'geo', '') else geo end,
    activo     = coalesce((p_datos->>'activo')::boolean, activo),
    actualizado = now()
  where id = p_id;
end $$;

-- ---------------------------------------------------------------------
-- 5. PANEL SIN SEGUIMIENTO
--    Lista de rutas y detalle de una ruta: solo datos de gestión.
--    Ya no se envían visitas del día, horas, dispositivos conectados ni notas.
-- ---------------------------------------------------------------------
create or replace function public.oficina_resumen(p_token uuid) returns json
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public._of_usuario(p_token);
  return json_build_object(
    'rutas', coalesce((select json_agg(x order by x.codigo) from (
      select r.codigo, r.nombre,
        (r.bloqueada_hasta is not null and r.bloqueada_hasta > now()) as bloqueada,
        (select count(*) from public.clientes c where c.ruta_id = r.id and c.activo) as clientes,
        (select count(*) from public.clientes c where c.ruta_id = r.id and c.activo and (c.lat is null or c.lng is null)) as sin_ubicar,
        (select json_agg((select count(*) from public.clientes c where c.ruta_id = r.id and c.activo and c.dia_visita = d) order by d)
           from generate_series(1, 7) d) as por_dia,
        (select max(i.fecha) from public.importaciones i where i.ruta_id = r.id) as ultima_carga
      from public.rutas r) x), '[]'::json)
  );
end $$;

create or replace function public.oficina_ruta(p_token uuid, p_codigo text) returns json
language plpgsql stable security definer set search_path = '' as $$
declare v_ruta uuid := public._of_ruta(p_codigo);
begin
  perform public._of_usuario(p_token);
  return json_build_object(
    'ruta', (select json_build_object('codigo', r.codigo, 'nombre', r.nombre,
              'bloqueada', (r.bloqueada_hasta is not null and r.bloqueada_hasta > now()))
             from public.rutas r where r.id = v_ruta),
    'clientes', coalesce((select json_agg(json_build_object('id', c.id, 'codigo', c.codigo, 'nombre', c.nombre, 'direccion', c.direccion,
        'poblacion', c.poblacion, 'telefono', c.telefono, 'dia_visita', c.dia_visita, 'frecuencia', coalesce(c.frecuencia, 7),
        'lat', c.lat, 'lng', c.lng, 'geo', c.geo, 'activo', c.activo)
        order by c.activo desc, c.dia_visita nulls last, c.nombre)
      from public.clientes c where c.ruta_id = v_ruta), '[]'::json)
  );
end $$;

-- ---------------------------------------------------------------------
-- 6. PERMISOS (los mismos de siempre; se repiten por seguridad)
-- ---------------------------------------------------------------------
revoke execute on function public._frecuencia(text), public._importar_ruta(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.ruta_de_hoy(uuid), public.oficina_guardar_cliente(uuid, uuid, jsonb),
  public.oficina_resumen(uuid), public.oficina_ruta(uuid, text) from public;
grant execute on function public.ruta_de_hoy(uuid)                          to anon, authenticated;
grant execute on function public.oficina_guardar_cliente(uuid, uuid, jsonb) to anon, authenticated;
grant execute on function public.oficina_resumen(uuid)                      to anon, authenticated;
grant execute on function public.oficina_ruta(uuid, text)                   to anon, authenticated;
