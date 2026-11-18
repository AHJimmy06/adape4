-- Una confirmación por destinatario; no modifica ni reenvía trabajos históricos.
begin;
select pg_advisory_xact_lock(8084016);

alter table public.at_notificaciones
  drop constraint if exists at_notificaciones_pedido_id_tipo_key;
create unique index if not exists at_notificaciones_destinatario_unico
  on public.at_notificaciones(pedido_id,tipo,(lower(datos->>'correo')));

-- Listas permitidas: el mensaje individual no transporta identificadores internos.
create or replace function public.at_correo_vuelo_pasajero(p_vuelo jsonb)
returns jsonb language sql immutable set search_path=pg_catalog,pg_temp as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'codigo',p_vuelo->'codigo','salida_local',p_vuelo->'salida_local',
    'llegada_local',p_vuelo->'llegada_local','salida_en',p_vuelo->'salida_en',
    'llegada_en',p_vuelo->'llegada_en','ruta',jsonb_build_object(
      'origen',jsonb_build_object(
        'nombre',p_vuelo#>'{ruta,origen,nombre}','iata',p_vuelo#>'{ruta,origen,iata}',
        'ciudad',p_vuelo#>'{ruta,origen,ciudad}','pais',p_vuelo#>'{ruta,origen,pais}',
        'zona_horaria',p_vuelo#>'{ruta,origen,zona_horaria}'),
      'destino',jsonb_build_object(
        'nombre',p_vuelo#>'{ruta,destino,nombre}','iata',p_vuelo#>'{ruta,destino,iata}',
        'ciudad',p_vuelo#>'{ruta,destino,ciudad}','pais',p_vuelo#>'{ruta,destino,pais}',
        'zona_horaria',p_vuelo#>'{ruta,destino,zona_horaria}'))));
$$;

create or replace function public.at_correo_asiento_pasajero(p_asiento jsonb,p_nombre text,p_correo text)
returns jsonb language sql immutable set search_path=pg_catalog,pg_temp as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'codigo',p_asiento->'codigo','clase_codigo',p_asiento->'clase_codigo','clase_nombre',p_asiento->'clase_nombre',
    'pasajero',jsonb_build_object('nombre',p_nombre,'correo',p_correo,'asignado',true,
      'categoria',p_asiento#>'{pasajero,categoria}'),
    'equipaje',jsonb_build_object('cantidad',p_asiento#>'{equipaje,cantidad}',
      'precio_unitario_centavos',p_asiento#>'{equipaje,precio_unitario_centavos}',
      'subtotal_centavos',p_asiento#>'{equipaje,subtotal_centavos}',
      'iva_centavos',p_asiento#>'{equipaje,iva_centavos}','total_centavos',p_asiento#>'{equipaje,total_centavos}'),
    'tarifa_subtotal_centavos',p_asiento->'tarifa_subtotal_centavos',
    'tarifa_iva_centavos',p_asiento->'tarifa_iva_centavos','tarifa_total_centavos',p_asiento->'tarifa_total_centavos',
    'subtotal_centavos',p_asiento->'subtotal_centavos','iva_centavos',p_asiento->'iva_centavos',
    'total_centavos',p_asiento->'total_centavos'));
$$;
revoke all on function public.at_correo_vuelo_pasajero(jsonb)
  from public,anon,authenticated,service_role;
revoke all on function public.at_correo_asiento_pasajero(jsonb,text,text)
  from public,anon,authenticated,service_role;

create or replace function public.at_encolar_confirmacion_pago()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare
  comprador public.usuarios%rowtype;
  reserva public.at_reservas%rowtype;
  destinatario record;
begin
  if new.estado='pagado' and old.estado is distinct from 'pagado' and new.reserva_id is not null then
    perform pg_advisory_xact_lock_shared(91420261117);
    -- Una incidencia posterior no convierte el mismo pago en una nueva emisión.
    -- También evita completar retrospectivamente destinatarios de trabajos legacy.
    if exists(select 1 from public.at_notificaciones
              where pedido_id=new.id and tipo='confirmacion_pago') then
      return new;
    end if;
    select * into comprador from public.usuarios where id=new.usuario_id;
    select * into reserva from public.at_reservas
      where id=new.reserva_id and pedido_id=new.id and usuario_id=new.usuario_id;
    if not found then return new; end if;
    -- El comprador conserva el comprobante completo, incluso si también viaja.
    insert into public.at_notificaciones(pedido_id,datos)
      values(new.id,jsonb_build_object(
        'tipo','comprador','nombre',comprador.nombre,'correo',comprador.correo,
        'reserva_id',reserva.id,'vuelo',reserva.vuelo,'asientos',new.asientos,
        'subtotal_centavos',new.subtotal_centavos,'iva_centavos',new.iva_centavos,
        'total_centavos',new.total_centavos,'moneda','USD'))
      on conflict(pedido_id,tipo,(lower(datos->>'correo'))) do nothing;

    -- Se consulta la identidad vigente por ID confiable congelado por la migración014.
    -- Un correo o nombre alterado en el snapshot nunca elige el destinatario.
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
        values(new.id,jsonb_build_object(
          'tipo','pasajero','nombre',destinatario.nombre,'correo',destinatario.correo,
          'vuelo',public.at_correo_vuelo_pasajero(reserva.vuelo),
          'asientos',destinatario.asientos,'subtotal_centavos',destinatario.subtotal,
          'iva_centavos',destinatario.iva,'total_centavos',destinatario.total,'moneda','USD'))
        on conflict(pedido_id,tipo,(lower(datos->>'correo'))) do nothing;
    end loop;
  end if;
  return new;
end;
$$;
revoke all on function public.at_encolar_confirmacion_pago()
  from public,anon,authenticated,service_role;
insert into public.aerotech_migraciones(version) values(15) on conflict do nothing;
notify pgrst,'reload schema';
commit;
