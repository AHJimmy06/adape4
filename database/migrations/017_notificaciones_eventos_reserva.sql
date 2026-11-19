-- Eventos nuevos, sin reemitir cancelaciones ni concesiones históricas.
begin;
select pg_advisory_xact_lock_shared(91420261117);
select pg_advisory_xact_lock(8084008);

alter table public.at_notificaciones
  add column if not exists evento_id text not null default 'confirmacion_pago';
alter table public.at_notificaciones drop constraint if exists at_notificaciones_tipo_check;
alter table public.at_notificaciones add constraint at_notificaciones_tipo_check
  check(tipo in ('confirmacion_pago','cancelacion_confirmada','acceso_otorgado'));
alter table public.at_notificaciones drop constraint if exists at_notificaciones_estado_check;
alter table public.at_notificaciones add constraint at_notificaciones_estado_check
  check(estado in ('pendiente','en_proceso','enviado','descartado'));
drop index if exists public.at_notificaciones_destinatario_unico;
create unique index if not exists at_notificaciones_evento_destinatario_unico
  on public.at_notificaciones(pedido_id,tipo,(lower(datos->>'correo')),evento_id);

-- Mismo contenido y dedupe de confirmación015; solo cambia la clave del índice.
create or replace function public.at_encolar_confirmacion_pago()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare comprador public.usuarios%rowtype; reserva public.at_reservas%rowtype; destinatario record;
begin
  if new.estado='pagado' and old.estado is distinct from 'pagado' and new.reserva_id is not null then
    perform pg_advisory_xact_lock_shared(91420261117);
    if exists(select 1 from public.at_notificaciones where pedido_id=new.id and tipo='confirmacion_pago') then
      return new;
    end if;
    select * into comprador from public.usuarios where id=new.usuario_id;
    select * into reserva from public.at_reservas
      where id=new.reserva_id and pedido_id=new.id and usuario_id=new.usuario_id;
    if not found then return new; end if;
    insert into public.at_notificaciones(pedido_id,datos)
      values(new.id,jsonb_build_object('tipo','comprador','nombre',comprador.nombre,'correo',comprador.correo,
        'reserva_id',reserva.id,'vuelo',reserva.vuelo,'asientos',new.asientos,
        'subtotal_centavos',new.subtotal_centavos,'iva_centavos',new.iva_centavos,
        'total_centavos',new.total_centavos,'moneda','USD'))
      on conflict(pedido_id,tipo,(lower(datos->>'correo')),evento_id) do nothing;
    for destinatario in
      select lower(btrim(u.correo)) as correo,min(u.nombre) as nombre,
        jsonb_agg(public.at_correo_asiento_pasajero(s.value,u.nombre,lower(btrim(u.correo)))
          order by s.ordinalidad) as asientos,
        sum((s.value->>'subtotal_centavos')::bigint) as subtotal,
        sum((s.value->>'iva_centavos')::bigint) as iva,
        sum((s.value->>'total_centavos')::bigint) as total
      from jsonb_array_elements(new.asientos) with ordinality as s(value,ordinalidad)
      join public.usuarios u on u.id::text=s.value#>>'{pasajero,usuario_id}' and u.activo
      where s.value#>'{pasajero,asignado}'='true'::jsonb
        and lower(btrim(u.correo))<>lower(btrim(comprador.correo))
      group by lower(btrim(u.correo))
    loop
      insert into public.at_notificaciones(pedido_id,datos)
        values(new.id,jsonb_build_object('tipo','pasajero','nombre',destinatario.nombre,'correo',destinatario.correo,
          'vuelo',public.at_correo_vuelo_pasajero(reserva.vuelo),'asientos',destinatario.asientos,
          'subtotal_centavos',destinatario.subtotal,'iva_centavos',destinatario.iva,
          'total_centavos',destinatario.total,'moneda','USD'))
        on conflict(pedido_id,tipo,(lower(datos->>'correo')),evento_id) do nothing;
    end loop;
  end if;
  return new;
end $$;
revoke all on function public.at_encolar_confirmacion_pago() from public,anon,authenticated,service_role;

create or replace function public.at_encolar_cancelacion_confirmada()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare
  pedido public.at_pedidos%rowtype; reserva public.at_reservas%rowtype;
  comprador public.usuarios%rowtype; afectados jsonb; subtotal bigint; iva bigint; total bigint;
begin
  if new.estado<>'cancelado' or old.estado='cancelado' or new.motivo='pago_tardio'
    or jsonb_array_length(new.asientos)=0 then return new; end if;
  perform pg_advisory_xact_lock_shared(91420261117);
  perform pg_advisory_xact_lock(8084008);
  select * into pedido from public.at_pedidos where id=new.pedido_id;
  select * into reserva from public.at_reservas
    where id=new.reserva_id and pedido_id=pedido.id and usuario_id=pedido.usuario_id;
  if not found then return new; end if;
  select * into comprador from public.usuarios where id=pedido.usuario_id and activo;
  if not found or comprador.correo !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then return new; end if;
  select jsonb_agg(s.value order by s.ordinalidad),
    sum((s.value->>'subtotal_centavos')::bigint),sum((s.value->>'iva_centavos')::bigint),
    sum((s.value->>'total_centavos')::bigint)
    into afectados,subtotal,iva,total
  from jsonb_array_elements(pedido.asientos) with ordinality s(value,ordinalidad)
  where new.asientos ? (s.value->>'codigo');
  -- No anunciar una devolución que no coincide con el desglose congelado.
  if total is distinct from new.importe_centavos or subtotal+iva is distinct from total
    or jsonb_array_length(afectados) is distinct from jsonb_array_length(new.asientos) then return new; end if;
  insert into public.at_notificaciones(pedido_id,tipo,evento_id,datos)
    values(pedido.id,'cancelacion_confirmada',new.id::text,jsonb_build_object(
      'evento','cancelacion_confirmada','nombre',comprador.nombre,'correo',comprador.correo,
      'reserva_id',reserva.id,'cancelacion_id',new.id,'vuelo',reserva.vuelo,'asientos',afectados,
      'subtotal_centavos',subtotal,'iva_centavos',iva,'total_centavos',total,'moneda','USD'))
    on conflict(pedido_id,tipo,(lower(datos->>'correo')),evento_id) do nothing;
  return new;
end $$;
revoke all on function public.at_encolar_cancelacion_confirmada() from public,anon,authenticated,service_role;
create or replace trigger at_notificar_cancelacion
  after update on public.at_cancelaciones for each row
  when(new.estado='cancelado' and old.estado is distinct from new.estado)
  execute function public.at_encolar_cancelacion_confirmada();

create or replace function public.at_encolar_acceso_otorgado()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare
  reserva public.at_reservas%rowtype; pedido public.at_pedidos%rowtype;
  destinatario public.usuarios%rowtype; comprador public.usuarios%rowtype; asiento jsonb;
begin
  if new.usuario_id is null or new.usuario_id is not distinct from old.usuario_id then return new; end if;
  perform pg_advisory_xact_lock_shared(91420261117);
  perform pg_advisory_xact_lock(8084008);
  select * into reserva from public.at_reservas where id=new.reserva_id;
  select * into pedido from public.at_pedidos where id=reserva.pedido_id and estado='pagado';
  if not found then return new; end if;
  select * into comprador from public.usuarios where id=reserva.usuario_id;
  select * into destinatario from public.usuarios where id=new.usuario_id and activo;
  if not found or destinatario.correo !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then return new; end if;
  if not exists(select 1 from public.at_asientos s join public.at_vuelos v on v.id=s.vuelo_id
    where s.pedido_id=pedido.id and s.codigo=new.codigo and v.activo and v.salida_en>now())
    or exists(select 1 from public.at_cancelaciones c where c.pedido_id=pedido.id and c.asientos ? new.codigo)
    then return new; end if;
  select s.value into asiento from jsonb_array_elements(pedido.asientos) s(value) where s.value->>'codigo'=new.codigo;
  if asiento is null then return new; end if;
  insert into public.at_notificaciones(pedido_id,tipo,evento_id,datos)
    values(pedido.id,'acceso_otorgado',new.id::text||':'||new.version::text,jsonb_build_object(
      'evento','acceso_otorgado','acceso_id',new.id,'acceso_version',new.version,
      'destinatario_id',destinatario.id,'nombre',destinatario.nombre,'correo',destinatario.correo,
      'otorgante',comprador.nombre,'vuelo',public.at_correo_vuelo_pasajero(reserva.vuelo),
      'asientos',jsonb_build_array(jsonb_build_object('codigo',new.codigo,
        'clase_codigo',asiento->'clase_codigo','categoria',asiento#>'{pasajero,categoria}',
        'maletas_adicionales',coalesce((asiento#>>'{equipaje,cantidad}')::integer,0)))))
    on conflict(pedido_id,tipo,(lower(datos->>'correo')),evento_id) do nothing;
  return new;
end $$;
revoke all on function public.at_encolar_acceso_otorgado() from public,anon,authenticated,service_role;
create or replace trigger at_notificar_acceso_otorgado
  after update on public.at_accesos_reserva for each row
  when(new.usuario_id is not null and new.usuario_id is distinct from old.usuario_id)
  execute function public.at_encolar_acceso_otorgado();

-- El worker usa el contrato013 sin cambiar leases, tokens, retries ni throttle.
do $$ begin
  if to_regprocedure('public.notificaciones_operar_base_017(text,jsonb)') is null then
    alter function public.notificaciones_operar(text,jsonb) rename to notificaciones_operar_base_017;
  end if;
end $$;
revoke all on function public.notificaciones_operar_base_017(text,jsonb) from public,anon,authenticated,service_role;
create or replace function public.notificaciones_operar(p_accion text,p_datos jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
  if p_accion='tomar' then
    perform pg_advisory_xact_lock_shared(91420261117);
    perform pg_advisory_xact_lock(8084008);
    update public.at_notificaciones n set estado='descartado',error_codigo='acceso_no_vigente',token=null,lease_hasta=null
    where n.tipo='acceso_otorgado'
      and (n.estado='pendiente' or (n.estado='en_proceso' and n.lease_hasta<=clock_timestamp()))
      and not exists(
        select 1 from public.at_accesos_reserva a
        join public.usuarios u on u.id=a.usuario_id and u.activo
        join public.at_reservas r on r.id=a.reserva_id
        join public.at_pedidos p on p.id=r.pedido_id and p.estado='pagado'
        join public.at_vuelos v on v.id=r.vuelo_id and v.activo and v.salida_en>now()
        join public.at_asientos s on s.pedido_id=p.id and s.vuelo_id=v.id and s.codigo=a.codigo
        where a.id::text=n.datos->>'acceso_id' and a.version::text=n.datos->>'acceso_version'
          and u.id::text=n.datos->>'destinatario_id' and lower(btrim(u.correo))=lower(btrim(n.datos->>'correo'))
          and p.id=n.pedido_id
          and not exists(select 1 from public.at_cancelaciones c where c.pedido_id=p.id and c.asientos ? a.codigo));
  end if;
  return public.notificaciones_operar_base_017(p_accion,p_datos);
end $$;
revoke all on function public.notificaciones_operar(text,jsonb) from public,anon,authenticated;
grant execute on function public.notificaciones_operar(text,jsonb) to service_role;
insert into public.aerotech_migraciones(version) values(17) on conflict do nothing;
notify pgrst,'reload schema';
commit;
