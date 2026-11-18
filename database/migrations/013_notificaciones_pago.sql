-- Cola privada y aditiva: no reenvía pagos anteriores ni modifica liquidaciones.
begin;
select pg_advisory_xact_lock(8084013);

create table if not exists public.at_notificaciones (
  id uuid primary key default gen_random_uuid(),
  pedido_id uuid not null references public.at_pedidos(id),
  tipo text not null default 'confirmacion_pago' check(tipo='confirmacion_pago'),
  datos jsonb not null check(jsonb_typeof(datos)='object'),
  estado text not null default 'pendiente' check(estado in ('pendiente','en_proceso','enviado')),
  intentos integer not null default 0 check(intentos>=0),
  proximo_intento timestamptz not null default now(),
  token uuid, lease_hasta timestamptz,
  proveedor_id text, error_codigo text,
  creado_en timestamptz not null default now(), enviado_en timestamptz,
  unique(pedido_id,tipo)
);
create index if not exists at_notificaciones_pendientes
  on public.at_notificaciones(estado,proximo_intento,creado_en);
create table if not exists public.at_notificaciones_control (
  id boolean primary key default true check(id),
  permite_en timestamptz not null default '-infinity'
);
insert into public.at_notificaciones_control(id) values(true) on conflict do nothing;

alter table public.at_notificaciones enable row level security;
alter table public.at_notificaciones_control enable row level security;
revoke all on public.at_notificaciones,public.at_notificaciones_control
  from public,anon,authenticated,service_role;

create or replace function public.at_encolar_confirmacion_pago()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
begin
  -- La reserva ya existe en esta misma transacción. El destinatario nunca viene del cliente.
  if new.estado='pagado' and old.estado is distinct from 'pagado' and new.reserva_id is not null then
    insert into public.at_notificaciones(pedido_id,datos)
    select new.id,jsonb_build_object(
      'nombre',u.nombre,'correo',u.correo,'reserva_id',r.id,'vuelo',r.vuelo,
      'asientos',new.asientos,'subtotal_centavos',new.subtotal_centavos,
      'iva_centavos',new.iva_centavos,'total_centavos',new.total_centavos,'moneda','USD')
    from public.usuarios u join public.at_reservas r
      on r.id=new.reserva_id and r.pedido_id=new.id and r.usuario_id=u.id
    where u.id=new.usuario_id
    on conflict(pedido_id,tipo) do nothing;
  end if;
  return new;
end;
$$;
revoke all on function public.at_encolar_confirmacion_pago()
  from public,anon,authenticated,service_role;
create or replace trigger at_notificar_pago
  after update on public.at_pedidos for each row
  when(new.estado='pagado' and old.estado is distinct from new.estado)
  execute function public.at_encolar_confirmacion_pago();

create or replace function public.notificaciones_operar(p_accion text,p_datos jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare
  trabajo public.at_notificaciones%rowtype;
  instante timestamptz;
  espera integer;
  resultado boolean;
begin
  if jsonb_typeof(p_datos) is distinct from 'object' then
    raise exception 'INVALIDO: Datos de notificación inválidos';
  end if;
  if p_accion='tomar' then
    -- Serializa workers de distintos procesos sin mantener el lock durante HTTP.
    if not pg_try_advisory_xact_lock(8084014) then return null; end if;
    instante:=clock_timestamp();
    perform 1 from public.at_notificaciones_control where id=true for update;
    if exists(select 1 from public.at_notificaciones_control where id=true and permite_en>instante)
       or exists(select 1 from public.at_notificaciones where estado='en_proceso' and lease_hasta>instante) then
      return null;
    end if;
    select * into trabajo from public.at_notificaciones
      where (estado='pendiente' and proximo_intento<=instante)
         or (estado='en_proceso' and lease_hasta<=instante)
      order by creado_en,id for update skip locked limit 1;
    if not found then return null; end if;
    update public.at_notificaciones
      set estado='en_proceso',token=gen_random_uuid(),lease_hasta=instante+interval '90 seconds',
          intentos=intentos+1
      where id=trabajo.id returning * into trabajo;
    update public.at_notificaciones_control set permite_en=instante+interval '12 seconds' where id=true;
    return jsonb_build_object('id',trabajo.id,'token',trabajo.token,'datos',trabajo.datos);
  elsif p_accion='terminar' then
    if jsonb_typeof(p_datos->'ok') is distinct from 'boolean' then
      raise exception 'INVALIDO: Falta resultado de la notificación';
    end if;
    select * into trabajo from public.at_notificaciones
      where id=(p_datos->>'id')::uuid and token=(p_datos->>'token')::uuid
        and estado='en_proceso' and lease_hasta>clock_timestamp()
      for update;
    -- La comprobación se repite tras obtener el lock: un lease vencido no confirma.
    if not found or trabajo.lease_hasta<=clock_timestamp() then return 'false'::jsonb; end if;
    resultado:=(p_datos->>'ok')::boolean;
    if resultado then
      update public.at_notificaciones
        set estado='enviado',enviado_en=clock_timestamp(),proveedor_id=left(p_datos->>'proveedor_id',200),
            error_codigo=null,token=null,lease_hasta=null
        where id=trabajo.id;
    else
      espera:=greatest(30,least(86400,coalesce((p_datos->>'reintentar_segundos')::integer,
                      least(3600,30*power(2,least(trabajo.intentos-1,7))::integer))));
      update public.at_notificaciones
        set estado='pendiente',proximo_intento=clock_timestamp()+make_interval(secs=>espera),
            error_codigo=case when p_datos->>'error_codigo' ~ '^[a-z0-9_]{1,80}$'
                              then p_datos->>'error_codigo' else 'envio_no_confirmado' end,
            token=null,lease_hasta=null
        where id=trabajo.id;
    end if;
    return 'true'::jsonb;
  end if;
  raise exception 'INVALIDO: Operación de notificación desconocida';
end;
$$;
revoke all on function public.notificaciones_operar(text,jsonb) from public,anon,authenticated;
grant execute on function public.notificaciones_operar(text,jsonb) to service_role;
insert into public.aerotech_migraciones(version) values(13) on conflict do nothing;
notify pgrst,'reload schema';
commit;
