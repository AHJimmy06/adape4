-- Permisos vigentes separados del comprobante y de los importes de la compra.
begin;
select pg_advisory_xact_lock_shared(91420261117);
select pg_advisory_xact_lock(8084008);

create table if not exists public.at_accesos_reserva (
  id uuid primary key default gen_random_uuid(),
  reserva_id uuid not null references public.at_reservas(id),
  codigo text not null,
  usuario_id uuid references public.usuarios(id),
  version integer not null default 1 check(version>0),
  actualizado_en timestamptz not null default now(),
  unique(reserva_id,codigo)
);
create index if not exists at_accesos_reserva_usuario
  on public.at_accesos_reserva(usuario_id) where usuario_id is not null;
alter table public.at_accesos_reserva enable row level security;
revoke all on table public.at_accesos_reserva from public,anon,authenticated,service_role;

-- ON CONFLICT conserva las revocaciones: NULL es una decisión, no un fallback.
create or replace function public.at_inicializar_accesos_reserva(p_reserva uuid)
returns void language sql security definer set search_path=pg_catalog,public,pg_temp as $$
  insert into public.at_accesos_reserva(reserva_id,codigo,usuario_id)
  select r.id,s.value->>'codigo',u.id
  from public.at_reservas r join public.at_pedidos p on p.id=r.pedido_id
  cross join lateral jsonb_array_elements(p.asientos) s(value)
  left join public.usuarios u on u.id::text=s.value#>>'{pasajero,usuario_id}'
    and s.value#>'{pasajero,asignado}'='true'::jsonb
  where r.id=p_reserva and p.estado='pagado' and s.value->>'codigo' is not null
  on conflict(reserva_id,codigo) do nothing;
$$;
revoke all on function public.at_inicializar_accesos_reserva(uuid)
  from public,anon,authenticated,service_role;

create or replace function public.at_inicializar_accesos_pagados()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
  if new.estado='pagado' and new.reserva_id is not null then
    perform public.at_inicializar_accesos_reserva(new.reserva_id);
  end if;
  return new;
end;
$$;
revoke all on function public.at_inicializar_accesos_pagados()
  from public,anon,authenticated,service_role;
create or replace trigger at_inicializar_accesos_pago
  after update on public.at_pedidos for each row
  when(new.estado='pagado' and old.estado is distinct from new.estado)
  execute function public.at_inicializar_accesos_pagados();

do $$
declare reserva uuid;
begin
  for reserva in select r.id from public.at_reservas r
    join public.at_pedidos p on p.id=r.pedido_id where p.estado='pagado'
  loop
    perform public.at_inicializar_accesos_reserva(reserva);
  end loop;
end $$;

do $$ begin
  if to_regprocedure('public.sistema_operar_base_016(text,uuid,jsonb)') is null then
    alter function public.sistema_operar(text,uuid,jsonb) rename to sistema_operar_base_016;
  end if;
end $$;
revoke all on function public.sistema_operar_base_016(text,uuid,jsonb)
  from public,anon,authenticated,service_role;

create or replace function public.sistema_operar(p_accion text,p_usuario uuid default null,p_datos jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare
  reserva public.at_reservas%rowtype;
  pedido public.at_pedidos%rowtype;
  vuelo public.at_vuelos%rowtype;
  acceso public.at_accesos_reserva%rowtype;
  asignatario public.usuarios%rowtype;
  correo_destino text; codigo_asiento text; resultado jsonb;
begin
  if p_accion not in ('accesos_reserva','asignar_acceso_reserva','asientos_compartidos') then
    return public.sistema_operar_base_016(p_accion,p_usuario,p_datos);
  end if;
  perform pg_advisory_xact_lock_shared(91420261117);
  if p_usuario is null or not exists(select 1 from public.usuarios where id=p_usuario and activo) then
    raise exception 'PROHIBIDO: La cuenta no está disponible';
  end if;
  perform pg_advisory_xact_lock(8084008);

  if p_accion='asientos_compartidos' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',a.id,'codigo',a.codigo,'clase_codigo',s.value->'clase_codigo',
      'categoria',coalesce(s.value#>>'{pasajero,categoria}','adulto'),
      'maletas_adicionales',coalesce((s.value#>>'{equipaje,cantidad}')::integer,0),
      'vuelo',public.at_correo_vuelo_pasajero(r.vuelo))
      order by r.creado_en desc,a.codigo),'[]'::jsonb) into resultado
    from public.at_accesos_reserva a
    join public.at_reservas r on r.id=a.reserva_id
    join public.at_pedidos p on p.id=r.pedido_id and p.estado='pagado'
    cross join lateral jsonb_array_elements(p.asientos) s(value)
    where a.usuario_id=p_usuario and r.usuario_id<>p_usuario and s.value->>'codigo'=a.codigo
      and exists(select 1 from public.at_asientos real
        where real.pedido_id=p.id and real.vuelo_id=r.vuelo_id and real.codigo=a.codigo)
      and not exists(select 1 from public.at_cancelaciones c
        where c.pedido_id=p.id and c.asientos ? a.codigo);
    return jsonb_build_object('asientos',resultado);
  end if;

  select * into reserva from public.at_reservas
    where id=(p_datos->>'id')::uuid and usuario_id=p_usuario;
  if not found then raise exception 'NO_ENCONTRADO: Reserva'; end if;
  select * into pedido from public.at_pedidos where id=reserva.pedido_id;
  select * into vuelo from public.at_vuelos where id=reserva.vuelo_id;

  if p_accion='asignar_acceso_reserva' then
    if jsonb_typeof(p_datos) is distinct from 'object'
      or exists(select 1 from jsonb_object_keys(p_datos) k(clave) where clave not in ('id','asiento','correo','version'))
      or not (p_datos ?& array['id','asiento','correo','version'])
      or jsonb_typeof(p_datos->'asiento') is distinct from 'string'
      or jsonb_typeof(p_datos->'version') is distinct from 'number'
      or (p_datos->>'version') !~ '^[1-9][0-9]{0,8}$'
      or jsonb_typeof(p_datos->'correo') not in ('string','null') then
      raise exception 'INVALIDO: Datos de acceso inválidos';
    end if;
    codigo_asiento:=p_datos->>'asiento';
    select * into acceso from public.at_accesos_reserva
      where reserva_id=reserva.id and at_accesos_reserva.codigo=codigo_asiento for update;
    if not found then raise exception 'NO_ENCONTRADO: Asiento'; end if;
    if acceso.version<>(p_datos->>'version')::integer then
      raise exception 'CONFLICTO: La asignación cambió';
    end if;
    if pedido.estado<>'pagado' or not vuelo.activo or vuelo.salida_en<=now()
      or not exists(select 1 from public.at_asientos real
        where real.pedido_id=pedido.id and real.vuelo_id=vuelo.id and real.codigo=codigo_asiento)
      or exists(select 1 from public.at_cancelaciones c
        where c.pedido_id=pedido.id and c.asientos ? codigo_asiento) then
      raise exception 'CONFLICTO: El asiento no admite cambios de acceso';
    end if;
    if p_datos->'correo'<>'null'::jsonb then
      correo_destino:=lower(btrim(p_datos->>'correo'));
      if length(correo_destino)>254 or correo_destino !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
        raise exception 'INVALIDO: Cuenta destinataria no disponible';
      end if;
      select * into asignatario from public.usuarios u where u.correo=correo_destino and u.activo for share;
      if not found then raise exception 'INVALIDO: Cuenta destinataria no disponible'; end if;
    end if;
    if acceso.usuario_id is distinct from asignatario.id then
      update public.at_accesos_reserva set usuario_id=asignatario.id,
        version=version+1,actualizado_en=now() where id=acceso.id;
    end if;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'codigo',a.codigo,'clase_codigo',s.value->'clase_codigo','version',a.version,
    'editable',pedido.estado='pagado' and vuelo.activo and vuelo.salida_en>now()
      and exists(select 1 from public.at_asientos real
        where real.pedido_id=pedido.id and real.vuelo_id=vuelo.id and real.codigo=a.codigo)
      and not exists(select 1 from public.at_cancelaciones c
        where c.pedido_id=pedido.id and c.asientos ? a.codigo),
    'usuario',case when u.id is null then null else jsonb_build_object('nombre',u.nombre,'correo',u.correo) end)
    order by a.codigo),'[]'::jsonb) into resultado
  from public.at_accesos_reserva a
  cross join lateral jsonb_array_elements(pedido.asientos) s(value)
  left join public.usuarios u on u.id=a.usuario_id
  where a.reserva_id=reserva.id and s.value->>'codigo'=a.codigo;
  return jsonb_build_object('reserva_id',reserva.id,'asientos',resultado);
end;
$$;
revoke all on function public.sistema_operar(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.sistema_operar(text,uuid,jsonb) to service_role;
insert into public.aerotech_migraciones(version) values(16) on conflict do nothing;
notify pgrst,'reload schema';
commit;
