-- Esquema para Supabase/PostgreSQL. La clave de servicio se usa solo desde Flask.
create extension if not exists pgcrypto;

create table if not exists public.usuarios (
    id uuid primary key default gen_random_uuid(),
    nombre text not null check (length(trim(nombre)) between 1 and 120),
    correo text not null unique,
    password_hash text not null,
    rol text not null default 'USER' constraint usuarios_rol_check check (rol in ('ADMIN', 'USER')),
    creado_en timestamptz not null default now()
);

create table if not exists public.vuelos (
    id uuid primary key default gen_random_uuid(),
    origen text not null,
    destino text not null,
    fecha date not null,
    hora_salida time not null,
    hora_llegada time,
    precio numeric(10, 2) not null check (precio >= 0),
    asientos_disponibles integer not null check (asientos_disponibles >= 0),
    activo boolean not null default true,
    version integer not null default 1 constraint vuelos_version_positiva check (version >= 1),
    creado_en timestamptz not null default now(),
    check (origen <> destino)
);

create table if not exists public.reservas (
    id uuid primary key default gen_random_uuid(),
    usuario_id uuid not null references public.usuarios(id),
    vuelo_id uuid not null references public.vuelos(id),
    cantidad integer not null check (cantidad >= 1),
    subtotal numeric(10, 2) not null check (subtotal >= 0),
    iva numeric(10, 2) not null check (iva >= 0),
    porcentaje_iva numeric(5, 2) not null default 15.00 check (porcentaje_iva between 0.00 and 100.00),
    total numeric(10, 2) not null check (total >= 0),
    estado text not null default 'activa' check (estado in ('activa', 'cancelada')),
    creado_en timestamptz not null default now(),
    cancelada_en timestamptz
);

alter table public.reservas
    add column if not exists subtotal numeric(10, 2),
    add column if not exists iva numeric(10, 2),
    add column if not exists porcentaje_iva numeric(5, 2);

update public.reservas
   set subtotal = coalesce(subtotal, total),
       iva = coalesce(iva, 0.00),
       porcentaje_iva = case
           when subtotal is null or iva is null then 0.00
           else coalesce(porcentaje_iva, 0.00)
       end
 where subtotal is null or iva is null or porcentaje_iva is null;

alter table public.reservas
    alter column subtotal set not null,
    alter column iva set not null,
    alter column porcentaje_iva set default 15.00,
    alter column porcentaje_iva set not null;

create index if not exists reservas_usuario_creado_idx
    on public.reservas (usuario_id, creado_en desc);

create table if not exists public.tokens (
    id uuid primary key,
    usuario_id uuid not null references public.usuarios(id) on delete cascade,
    expira_en timestamptz not null,
    creado_en timestamptz not null default now()
);

create index if not exists tokens_usuario_idx on public.tokens (usuario_id);

alter table public.usuarios enable row level security;
alter table public.vuelos enable row level security;
alter table public.reservas enable row level security;
alter table public.tokens enable row level security;

revoke all on table public.usuarios, public.vuelos, public.reservas, public.tokens from public, anon, authenticated;
grant all on table public.usuarios, public.vuelos, public.reservas, public.tokens to service_role;

create or replace function public.reservar_vuelo(
    p_vuelo_id uuid,
    p_usuario_id uuid,
    p_cantidad integer
) returns public.reservas
language plpgsql
set search_path = public
as $$
declare
    vuelo_actualizado public.vuelos;
    reserva_creada public.reservas;
    subtotal_reserva numeric(10, 2);
    iva_reserva numeric(10, 2);
    porcentaje_reserva numeric(5, 2) := 15.00;
begin
    if p_cantidad is null or p_cantidad < 1 then
        raise exception using errcode = '22023', message = 'CANTIDAD_INVALIDA';
    end if;

    update public.vuelos
       set asientos_disponibles = asientos_disponibles - p_cantidad
     where id = p_vuelo_id
       and asientos_disponibles >= p_cantidad
     returning * into vuelo_actualizado;

    if not found then
        if not exists (select 1 from public.vuelos where id = p_vuelo_id) then
            raise exception using errcode = 'P0001', message = 'VUELO_INEXISTENTE';
        end if;
        raise exception using errcode = 'P0001', message = 'ASIENTOS_INSUFICIENTES';
    end if;

    subtotal_reserva := round(vuelo_actualizado.precio * p_cantidad, 2);
    iva_reserva := round(subtotal_reserva * porcentaje_reserva / 100, 2);

    insert into public.reservas (
        usuario_id, vuelo_id, cantidad, subtotal, iva, porcentaje_iva, total
    )
    values (
        p_usuario_id, p_vuelo_id, p_cantidad, subtotal_reserva, iva_reserva,
        porcentaje_reserva, subtotal_reserva + iva_reserva
    )
    returning * into reserva_creada;

    return reserva_creada;
end;
$$;

create or replace function public.cancelar_reserva(
    p_reserva_id uuid,
    p_usuario_id uuid
) returns public.reservas
language plpgsql
set search_path = public
as $$
declare
    reserva_cancelada public.reservas;
begin
    update public.reservas
       set estado = 'cancelada', cancelada_en = now()
     where id = p_reserva_id
       and usuario_id = p_usuario_id
       and estado = 'activa'
     returning * into reserva_cancelada;

    if not found then
        raise exception using errcode = 'P0001', message = 'RESERVA_NO_ENCONTRADA';
    end if;

    update public.vuelos
       set asientos_disponibles = asientos_disponibles + reserva_cancelada.cantidad
     where id = reserva_cancelada.vuelo_id;

    return reserva_cancelada;
end;
$$;

revoke all on function public.reservar_vuelo(uuid, uuid, integer) from public, anon, authenticated;
revoke all on function public.cancelar_reserva(uuid, uuid) from public, anon, authenticated;
grant execute on function public.reservar_vuelo(uuid, uuid, integer) to service_role;
grant execute on function public.cancelar_reserva(uuid, uuid) to service_role;

-- Estado final del CRUD concurrente, tambien aplicable a una instalacion existente.
begin;

-- Se conserva el historial: eliminar desactiva; version detecta editores obsoletos.
alter table public.vuelos
    add column if not exists activo boolean not null default true,
    add column if not exists version integer not null default 1;

do $$
begin
    if not exists (select 1 from pg_constraint where conrelid = 'public.vuelos'::regclass
                   and conname = 'vuelos_version_positiva') then
        alter table public.vuelos add constraint vuelos_version_positiva check (version >= 1);
    end if;
end;
$$;

create or replace function public.incrementar_version_vuelo()
returns trigger language plpgsql set search_path = public as $$
begin
    -- Incluye cambios de inventario al reservar y cancelar; nunca confiar en NEW.version.
    new.version := old.version + 1;
    return new;
end;
$$;

drop trigger if exists vuelos_incrementar_version on public.vuelos;
create trigger vuelos_incrementar_version
    before update on public.vuelos
    for each row execute function public.incrementar_version_vuelo();

create or replace function public.modificar_vuelo(
    p_vuelo_id uuid, p_version integer, p_datos jsonb
) returns public.vuelos
language plpgsql set search_path = public as $$
declare
    vuelo_actual public.vuelos;
begin
    if p_version is null or p_version < 1 then
        raise exception using errcode = '22023', message = 'VERSION_INVALIDA';
    end if;
    select * into vuelo_actual from public.vuelos
     where id = p_vuelo_id and activo for update;
    if not found then
        raise exception using errcode = 'P0001', message = 'VUELO_INEXISTENTE';
    end if;
    if vuelo_actual.version <> p_version then
        raise exception using errcode = 'P0001', message = 'VUELO_MODIFICADO';
    end if;

    if exists (select 1 from public.reservas where vuelo_id = p_vuelo_id and estado = 'activa') then
        raise exception using errcode = 'P0001', message = 'VUELO_CON_RESERVAS';
    end if;

    update public.vuelos
       set origen = p_datos->>'origen', destino = p_datos->>'destino',
           fecha = (p_datos->>'fecha')::date,
           hora_salida = (p_datos->>'hora_salida')::time,
           hora_llegada = (p_datos->>'hora_llegada')::time,
           precio = (p_datos->>'precio')::numeric,
           asientos_disponibles = (p_datos->>'asientos_disponibles')::integer
     where id = p_vuelo_id
     returning * into vuelo_actual;
    return vuelo_actual;
end;
$$;

create or replace function public.eliminar_vuelo(p_vuelo_id uuid, p_version integer)
returns public.vuelos
language plpgsql set search_path = public as $$
declare
    vuelo_actual public.vuelos;
begin
    if p_version is null or p_version < 1 then
        raise exception using errcode = '22023', message = 'VERSION_INVALIDA';
    end if;
    select * into vuelo_actual from public.vuelos
     where id = p_vuelo_id and activo for update;
    if not found then
        raise exception using errcode = 'P0001', message = 'VUELO_INEXISTENTE';
    end if;
    if vuelo_actual.version <> p_version then
        raise exception using errcode = 'P0001', message = 'VUELO_MODIFICADO';
    end if;
    -- Consulta posterior al bloqueo: ve las reservas confirmadas por quien obtuvo
    -- primero el bloqueo del vuelo. No toma bloqueos de reservas en orden inverso.
    if exists (select 1 from public.reservas where vuelo_id = p_vuelo_id and estado = 'activa') then
        raise exception using errcode = 'P0001', message = 'VUELO_CON_RESERVAS';
    end if;
    update public.vuelos set activo = false where id = p_vuelo_id
     returning * into vuelo_actual;
    return vuelo_actual;
end;
$$;

create or replace function public.reservar_vuelo(
    p_vuelo_id uuid,
    p_usuario_id uuid,
    p_cantidad integer
) returns public.reservas
language plpgsql
set search_path = public
as $$
declare
    vuelo_actualizado public.vuelos;
    reserva_creada public.reservas;
    subtotal_reserva numeric(10, 2);
    iva_reserva numeric(10, 2);
    porcentaje_reserva numeric(5, 2) := 15.00;
begin
    if p_cantidad is null or p_cantidad < 1 then
        raise exception using errcode = '22023', message = 'CANTIDAD_INVALIDA';
    end if;

    update public.vuelos
       set asientos_disponibles = asientos_disponibles - p_cantidad
     where id = p_vuelo_id
       and activo
       and asientos_disponibles >= p_cantidad
     returning * into vuelo_actualizado;

    if not found then
        if not exists (select 1 from public.vuelos where id = p_vuelo_id and activo) then
            raise exception using errcode = 'P0001', message = 'VUELO_INEXISTENTE';
        end if;
        raise exception using errcode = 'P0001', message = 'ASIENTOS_INSUFICIENTES';
    end if;

    subtotal_reserva := round(vuelo_actualizado.precio * p_cantidad, 2);
    iva_reserva := round(subtotal_reserva * porcentaje_reserva / 100, 2);

    insert into public.reservas (
        usuario_id, vuelo_id, cantidad, subtotal, iva, porcentaje_iva, total
    )
    values (
        p_usuario_id, p_vuelo_id, p_cantidad, subtotal_reserva, iva_reserva,
        porcentaje_reserva, subtotal_reserva + iva_reserva
    )
    returning * into reserva_creada;

    return reserva_creada;
end;
$$;

revoke all on function public.incrementar_version_vuelo() from public, anon, authenticated;
revoke all on function public.modificar_vuelo(uuid, integer, jsonb) from public, anon, authenticated;
revoke all on function public.eliminar_vuelo(uuid, integer) from public, anon, authenticated;
revoke all on function public.reservar_vuelo(uuid, uuid, integer) from public, anon, authenticated;
grant execute on function public.incrementar_version_vuelo() to service_role;
grant execute on function public.modificar_vuelo(uuid, integer, jsonb) to service_role;
grant execute on function public.eliminar_vuelo(uuid, integer) to service_role;
grant execute on function public.reservar_vuelo(uuid, uuid, integer) to service_role;

commit;

begin;
alter table public.vuelos add column if not exists tiene_reservas boolean not null default false;
create or replace function public.actualizar_indicador_reservas_vuelo()
returns trigger language plpgsql set search_path = public as $$
declare
    id_anterior uuid;
    id_actual uuid;
begin
    if TG_OP <> 'INSERT' then id_anterior := old.vuelo_id; end if;
    if TG_OP <> 'DELETE' then id_actual := new.vuelo_id; end if;
    perform 1 from public.vuelos where id in (id_anterior, id_actual) order by id for update;
    update public.vuelos v
       set tiene_reservas = exists (select 1 from public.reservas r where r.vuelo_id=v.id and r.estado='activa')
     where v.id in (id_anterior, id_actual)
       and v.tiene_reservas is distinct from exists (select 1 from public.reservas r where r.vuelo_id=v.id and r.estado='activa');
    return null;
end;
$$;
drop trigger if exists reservas_actualizar_indicador_vuelo on public.reservas;
create trigger reservas_actualizar_indicador_vuelo after insert or update or delete on public.reservas
for each row execute function public.actualizar_indicador_reservas_vuelo();
update public.vuelos v set tiene_reservas=exists(select 1 from public.reservas r where r.vuelo_id=v.id and r.estado='activa')
where v.tiene_reservas is distinct from exists(select 1 from public.reservas r where r.vuelo_id=v.id and r.estado='activa');
revoke all on function public.actualizar_indicador_reservas_vuelo() from public, anon, authenticated;
grant execute on function public.actualizar_indicador_reservas_vuelo() to service_role;
notify pgrst, 'reload schema';
commit;

-- SISTEMA INTEGRAL 008: fresh installs only; existing deployments apply migration008 once.
-- 008: explicitly authorized one-time application-domain reset, not auth/storage.
-- Apply once after review. usuarios/tokens/password hashes/roles are preserved.
begin;
create table if not exists public.aerotech_migraciones(version integer primary key, aplicado_en timestamptz not null default now());
do $$ begin
 perform pg_advisory_xact_lock(8084008);
 if exists(select 1 from public.aerotech_migraciones where version=8) then
  raise exception 'MIGRACION_008_YA_APLICADA: no se repetirá el borrado';
 end if;
end $$;
delete from public.reservas;
delete from public.vuelos;
insert into public.aerotech_migraciones(version) values(8);

create table public.at_aeropuertos (
 id uuid primary key default gen_random_uuid(), version integer not null default 1,
 activo boolean not null default true, iata text not null unique check(iata ~ '^[A-Z]{3}$'),
 datos jsonb not null, check((datos->>'latitud')::numeric between -90 and 90),
 check((datos->>'longitud')::numeric between -180 and 180)
);
create table public.at_aviones (
 id uuid primary key default gen_random_uuid(), version integer not null default 1,
 activo boolean not null default true, matricula text not null unique,
 datos jsonb not null, check((datos->>'capacidad_total')::integer between 1 and 1000)
);
create table public.at_rutas (
 id uuid primary key default gen_random_uuid(), version integer not null default 1,
 activo boolean not null default true, origen_id uuid not null references public.at_aeropuertos(id),
 destino_id uuid not null references public.at_aeropuertos(id), check(origen_id<>destino_id), unique(origen_id,destino_id)
);
create table public.at_vuelos (
 id uuid primary key default gen_random_uuid(), version integer not null default 1,
 activo boolean not null default true, codigo text not null unique,
 ruta_id uuid not null references public.at_rutas(id), avion_id uuid not null references public.at_aviones(id),
 salida_en timestamptz not null, llegada_en timestamptz not null, datos jsonb not null,
 creado_en timestamptz not null default now(), check(llegada_en>salida_en)
);
create table public.at_pedidos (
 id uuid primary key default gen_random_uuid(), usuario_id uuid not null references public.usuarios(id),
 vuelo_id uuid not null references public.at_vuelos(id), clave_operacion uuid not null,
 solicitud jsonb not null, estado text not null default 'preparando_pago'
 check(estado in('preparando_pago','pendiente_pago','pagado','expirado','cancelado','revision_pago')),
 asientos jsonb not null, subtotal_centavos integer not null check(subtotal_centavos>=50),
 iva_centavos integer not null check(iva_centavos>=0), total_centavos integer not null,
 creado_en timestamptz not null default now(), vence_en timestamptz not null default now()+interval '35 minutes',
 session_id text unique, checkout_url text, stripe_vence_en timestamptz, payment_intent text unique,
 reserva_id uuid, incidencia text, unique(usuario_id,clave_operacion),
 check(total_centavos=subtotal_centavos+iva_centavos)
);
create table public.at_asientos (
 id uuid primary key default gen_random_uuid(), vuelo_id uuid not null references public.at_vuelos(id),
 codigo text not null, fila integer not null check(fila>0), columna text not null check(columna ~ '^[A-Z]$'),
 clase_codigo text not null, clase_nombre text not null, precio_centavos integer not null check(precio_centavos>=50),
 pedido_id uuid references public.at_pedidos(id), unique(vuelo_id,codigo)
);
create table public.at_reservas (
 id uuid primary key default gen_random_uuid(), pedido_id uuid not null unique references public.at_pedidos(id),
 usuario_id uuid not null references public.usuarios(id), vuelo_id uuid not null references public.at_vuelos(id),
 vuelo jsonb not null, creado_en timestamptz not null default now()
);
alter table public.at_pedidos add constraint at_pedido_reserva_fk foreign key(reserva_id) references public.at_reservas(id);
create table public.at_cancelaciones (
 id uuid primary key default gen_random_uuid(), reserva_id uuid references public.at_reservas(id),
 pedido_id uuid not null references public.at_pedidos(id), usuario_id uuid not null references public.usuarios(id),
 clave_operacion uuid not null, asientos jsonb not null, importe_centavos integer not null check(importe_centavos>0),
 estado text not null default 'reembolso_pendiente' check(estado in('reembolso_pendiente','cancelado','fallido','revision')),
 refund_id text unique, intento integer not null default 1, ultima_clave_retry uuid, motivo text, creado_en timestamptz not null default now(), unique(usuario_id,clave_operacion)
);
create table public.at_eventos (
 id text primary key, tipo text not null, creado_en timestamptz not null default now()
);
create index at_asientos_pedido on public.at_asientos(pedido_id);
create index at_pedidos_usuario on public.at_pedidos(usuario_id,creado_en desc);
create index at_cancelaciones_pedido on public.at_cancelaciones(pedido_id);

-- Serialize domain mutations at one advisory transaction lock. This deliberate
-- single-airline academic tradeoff also protects schedule phantom rows, catalog
-- references and financial retries. Unique seat FK ownership is the final guard.
create function public.at_guardar_horario() returns trigger language plpgsql set search_path=public as $$
begin
 perform pg_advisory_xact_lock(8084008);
 if new.activo and exists(select 1 from public.at_vuelos v where v.id<>new.id and v.activo
   and v.avion_id=new.avion_id and tstzrange(v.salida_en,v.llegada_en,'[)') && tstzrange(new.salida_en,new.llegada_en,'[)')) then
  raise exception 'CONFLICTO: El avión ya tiene otro vuelo en ese horario';
 end if;
 return new;
end $$;
create trigger at_horario before insert or update on public.at_vuelos for each row execute function public.at_guardar_horario();

create function public.at_catalogo(p_tipo text, p_id uuid) returns jsonb language plpgsql stable set search_path=public as $$
declare x jsonb;
begin
 if p_tipo='aeropuertos' then
  select datos || jsonb_build_object('id',id,'version',version,'activo',activo,'iata',iata) into x from public.at_aeropuertos where id=p_id;
 elsif p_tipo='aviones' then
  select datos || jsonb_build_object('id',id,'version',version,'activo',activo,'matricula',matricula) into x from public.at_aviones where id=p_id;
 elsif p_tipo='rutas' then
  select jsonb_build_object('id',r.id,'version',r.version,'activo',r.activo,'origen_id',r.origen_id,'destino_id',r.destino_id,
   'origen',public.at_catalogo('aeropuertos',r.origen_id),'destino',public.at_catalogo('aeropuertos',r.destino_id),
   'nombre',(select iata from public.at_aeropuertos where id=r.origen_id)||' → '||(select iata from public.at_aeropuertos where id=r.destino_id))
   into x from public.at_rutas r where r.id=p_id;
 elsif p_tipo='vuelos' then
  select v.datos || jsonb_build_object('id',v.id,'version',v.version,'activo',v.activo,'codigo',v.codigo,
   'ruta',public.at_catalogo('rutas',v.ruta_id),'avion',public.at_catalogo('aviones',v.avion_id),
   'ruta_id',v.ruta_id,'avion_id',v.avion_id,'salida_en',v.salida_en,'llegada_en',v.llegada_en,
   'fecha',left(v.datos->>'salida_local',10),'hora_salida',substring(v.datos->>'salida_local',12,5),
   'hora_llegada',substring(v.datos->>'llegada_local',12,5),
   'origen',(a.datos->>'ciudad')||', '||(a.datos->>'pais'),'destino',(b.datos->>'ciudad')||', '||(b.datos->>'pais'),
   'precio_desde_centavos',(select min(precio_centavos) from public.at_asientos where vuelo_id=v.id),
   'asientos_disponibles',(select count(*) from public.at_asientos where vuelo_id=v.id and pedido_id is null),
   'tiene_reservas',exists(select 1 from public.at_asientos where vuelo_id=v.id and pedido_id is not null),
   'tarifas',(select jsonb_agg(t || jsonb_build_object('disponibles',(select count(*) from public.at_asientos s where s.vuelo_id=v.id
        and s.clase_codigo=t->>'clase_codigo' and s.pedido_id is null))) from jsonb_array_elements(v.datos->'tarifas') t))
  into x from public.at_vuelos v join public.at_rutas r on r.id=v.ruta_id join public.at_aeropuertos a on a.id=r.origen_id
   join public.at_aeropuertos b on b.id=r.destino_id where v.id=p_id;
 end if;
 return x;
end $$;

create function public.at_pedido_json(p_id uuid) returns jsonb language sql stable set search_path=public as $$
 select to_jsonb(p)-'usuario_id'-'solicitud'-'session_id'-'payment_intent'-'incidencia' || jsonb_build_object('moneda','usd','mensaje',p.incidencia)
 from public.at_pedidos p where p.id=p_id;
$$;
create function public.at_reserva_json(p_id uuid) returns jsonb language sql stable set search_path=public as $$
 select jsonb_build_object('id',r.id,'vuelo_id',r.vuelo_id,'vuelo',r.vuelo,'creado_en',r.creado_en,'legada',false,
 'estado',case when not exists(select 1 from public.at_asientos s where s.pedido_id=p.id) then 'cancelada' else 'activa' end,
 'cantidad',jsonb_array_length(p.asientos),'cantidad_activa',(select count(*) from public.at_asientos where pedido_id=p.id),
 'cantidad_cancelada',jsonb_array_length(p.asientos)-(select count(*) from public.at_asientos where pedido_id=p.id),
 'subtotal_centavos',p.subtotal_centavos,'iva_centavos',p.iva_centavos,'total_centavos',p.total_centavos,
 'reembolsado_centavos',coalesce((select sum(importe_centavos) from public.at_cancelaciones where pedido_id=p.id and estado='cancelado'),0),
 'asientos',(select jsonb_agg(s || jsonb_build_object('estado',case
   when exists(select 1 from public.at_cancelaciones c where c.pedido_id=p.id and c.asientos ? (s->>'codigo') and c.estado='cancelado') then 'cancelado'
   when exists(select 1 from public.at_cancelaciones c where c.pedido_id=p.id and c.asientos ? (s->>'codigo')) then 'reembolso_pendiente' else 'activo' end))
    from jsonb_array_elements(p.asientos) s),
 'cancelaciones',coalesce((select jsonb_agg(to_jsonb(c)-'usuario_id'-'payment_intent') from public.at_cancelaciones c where c.reserva_id=r.id),'[]'::jsonb))
 from public.at_reservas r join public.at_pedidos p on p.id=r.pedido_id where r.id=p_id;
$$;

create function public.at_generar_asientos(p_vuelo uuid,p_avion jsonb,p_tarifas jsonb) returns void
language plpgsql set search_path=public as $$
declare cls jsonb; n integer; col text; price integer;
begin
 delete from public.at_asientos where vuelo_id=p_vuelo;
 for cls in select value from jsonb_array_elements(p_avion->'clases') loop
  select (t->>'precio_centavos')::integer into price from jsonb_array_elements(p_tarifas) t where t->>'clase_codigo'=cls->>'codigo';
  for n in (cls->>'fila_inicio')::integer..((cls->>'fila_inicio')::integer+(cls->>'filas')::integer-1) loop
   for col in select jsonb_array_elements_text(value) from jsonb_array_elements(cls->'columnas') loop
    insert into public.at_asientos(vuelo_id,codigo,fila,columna,clase_codigo,clase_nombre,precio_centavos)
    values(p_vuelo,n::text||col,n,col,cls->>'codigo',cls->>'nombre',price);
   end loop;
  end loop;
 end loop;
end $$;

create function public.sistema_operar(p_accion text,p_usuario uuid default null,p_datos jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
 tipo text:=p_datos->>'recurso'; ident uuid:=(p_datos->>'id')::uuid; d jsonb:=p_datos->'datos';
 x jsonb; y jsonb; z jsonb; ids uuid[]; labels text[]; n integer; sub bigint; vat integer; tax integer; cumulative bigint;
 remaining integer; seat record; v public.at_vuelos; p public.at_pedidos; c public.at_cancelaciones;
 rid uuid; aid uuid; bid uuid; start_at timestamptz; end_at timestamptz; cname text; price integer;
begin
 -- Private provider actions are reachable only through this service-role RPC.
 if p_accion not in('listar','cabina','pedidos','pedido','reservas','reserva','cancelacion_obtener') then
  perform pg_advisory_xact_lock(8084008);
 end if;
 if p_usuario is not null and not exists(select 1 from public.usuarios where id=p_usuario) then raise exception 'NO_ENCONTRADO: Usuario'; end if;
 if p_accion in('guardar','borrar') and not exists(select 1 from public.usuarios where id=p_usuario and rol='ADMIN') then
  raise exception 'PROHIBIDO: Se requiere ADMIN';
 end if;
 if p_accion='evento_visto' then return to_jsonb(exists(select 1 from public.at_eventos where id=p_datos->>'event_id'));
 elsif p_accion='vencidos' then
  return coalesce((select jsonb_agg(to_jsonb(t)) from public.at_pedidos t where t.vuelo_id=ident and t.vence_en<now() and t.estado in('preparando_pago','pendiente_pago')),'[]'::jsonb);
 elsif p_accion='listar' then
  if tipo='aeropuertos' then select array_agg(id order by iata) into ids from public.at_aeropuertos where activo;
  elsif tipo='aviones' then select array_agg(id order by matricula) into ids from public.at_aviones where activo;
  elsif tipo='rutas' then select array_agg(id) into ids from public.at_rutas where activo;
  elsif tipo='vuelos' then select array_agg(f.id order by f.salida_en) into ids from public.at_vuelos f join public.at_rutas r on r.id=f.ruta_id
    where f.activo and ((p_datos->>'admin'='true' and exists(select 1 from public.usuarios where id=p_usuario and rol='ADMIN')) or f.salida_en>now())
    and (p_datos->>'origen_id' is null or r.origen_id=(p_datos->>'origen_id')::uuid)
    and (p_datos->>'destino_id' is null or r.destino_id=(p_datos->>'destino_id')::uuid)
    and (p_datos->>'fecha' is null or left(f.datos->>'salida_local',10)=p_datos->>'fecha');
  else raise exception 'INVALIDO: Recurso'; end if;
  select coalesce(jsonb_agg(public.at_catalogo(tipo,i)),'[]'::jsonb) into x from unnest(ids) i;
  return jsonb_build_object(tipo,x);
 elsif p_accion in('guardar','borrar') then
  if tipo not in('aeropuertos','aviones','rutas','vuelos') then raise exception 'INVALIDO: Recurso'; end if;
  if ident is not null then
   x:=public.at_catalogo(tipo,ident);
   if x is null or not (x->>'activo')::boolean then raise exception 'NO_ENCONTRADO: Recurso'; end if;
   if (x->>'version')::integer<>(d->>'version')::integer or d->>'version' is null then raise exception 'CONFLICTO: Versión modificada'; end if;
   if tipo='vuelos' and exists(select 1 from public.at_asientos where vuelo_id=ident and pedido_id is not null) then raise exception 'CONFLICTO: El vuelo tiene asientos retenidos o reservados'; end if;
   if tipo='aviones' and exists(select 1 from public.at_vuelos f join public.at_asientos s on s.vuelo_id=f.id where f.avion_id=ident and s.pedido_id is not null) then raise exception 'CONFLICTO: Avión con cabina ocupada'; end if;
   if tipo='aviones' and p_accion='guardar' and x->'clases' is distinct from d->'clases' and exists(select 1 from public.at_vuelos where avion_id=ident and activo) then
    raise exception 'CONFLICTO: Cambia la cabina antes de programar vuelos'; end if;
   if tipo='aeropuertos' and exists(select 1 from public.at_rutas where activo and (origen_id=ident or destino_id=ident)) then raise exception 'CONFLICTO: Aeropuerto asociado a rutas'; end if;
   if tipo='rutas' and exists(select 1 from public.at_vuelos where ruta_id=ident and activo) then raise exception 'CONFLICTO: Ruta asociada a vuelos'; end if;
   if p_accion='borrar' then
    if tipo='aviones' and exists(select 1 from public.at_vuelos where avion_id=ident and activo) then raise exception 'CONFLICTO: Avión asociado a vuelos'; end if;
    execute format('update public.at_%I set activo=false,version=version+1 where id=$1',tipo) using ident;
    return jsonb_build_object('mensaje','Recurso desactivado.');
   end if;
  else ident:=gen_random_uuid(); end if;
  if tipo='aeropuertos' then
   if not exists(select 1 from pg_timezone_names where name=d->>'zona_horaria') then raise exception 'INVALIDO: Zona horaria'; end if;
   insert into public.at_aeropuertos(id,iata,datos) values(ident,d->>'iata',d-'version')
    on conflict(id) do update set iata=excluded.iata,datos=excluded.datos,version=at_aeropuertos.version+1;
  elsif tipo='aviones' then
   insert into public.at_aviones(id,matricula,datos) values(ident,d->>'matricula',d-'version')
    on conflict(id) do update set matricula=excluded.matricula,datos=excluded.datos,version=at_aviones.version+1;
  elsif tipo='rutas' then
   if (select count(*) from public.at_aeropuertos where activo and id in((d->>'origen_id')::uuid,(d->>'destino_id')::uuid))<>2 then raise exception 'INVALIDO: Aeropuertos activos distintos requeridos'; end if;
   insert into public.at_rutas(id,origen_id,destino_id) values(ident,(d->>'origen_id')::uuid,(d->>'destino_id')::uuid)
    on conflict(id) do update set origen_id=excluded.origen_id,destino_id=excluded.destino_id,version=at_rutas.version+1;
  else
   rid:=(d->>'ruta_id')::uuid; aid:=(d->>'avion_id')::uuid;
   x:=public.at_catalogo('rutas',rid); y:=public.at_catalogo('aviones',aid);
   if x is null or y is null or not (x->>'activo')::boolean or not (y->>'activo')::boolean then raise exception 'INVALIDO: Ruta o avión inactivo'; end if;
   start_at:=(d->>'salida_local')::timestamp at time zone (x->'origen'->>'zona_horaria');
   end_at:=(d->>'llegada_local')::timestamp at time zone (x->'destino'->>'zona_horaria');
   if (d->>'salida_local')::date<=(now() at time zone (x->'origen'->>'zona_horaria'))::date or end_at<=start_at then raise exception 'INVALIDO: Horario pasado o llegada anterior'; end if;
   if jsonb_array_length(d->'tarifas')<>jsonb_array_length(y->'clases') or exists(
    select 1 from jsonb_array_elements(y->'clases') cls where (select count(*) from jsonb_array_elements(d->'tarifas') t where t->>'clase_codigo'=cls->>'codigo' and (t->>'precio_centavos')::integer>=50)<>1) then
    raise exception 'INVALIDO: Define una tarifa por cada clase'; end if;
   insert into public.at_vuelos(id,codigo,ruta_id,avion_id,salida_en,llegada_en,datos)
    values(ident,d->>'codigo',rid,aid,start_at,end_at,d-'version') on conflict(id) do update set codigo=excluded.codigo,ruta_id=excluded.ruta_id,
    avion_id=excluded.avion_id,salida_en=excluded.salida_en,llegada_en=excluded.llegada_en,datos=excluded.datos,version=at_vuelos.version+1;
   perform public.at_generar_asientos(ident,y,d->'tarifas');
  end if;
  return public.at_catalogo(tipo,ident);
 elsif p_accion='cabina' then
  x:=public.at_catalogo('vuelos',ident);
  if x is null or not (x->>'activo')::boolean then raise exception 'NO_ENCONTRADO: Vuelo'; end if;
  select coalesce(jsonb_agg(to_jsonb(s)-'pedido_id' || jsonb_build_object('estado',case when s.pedido_id is null then 'libre'
   when held.estado in('pagado','revision_pago') then 'ocupado' else 'retenido' end,'es_mio',coalesce(held.usuario_id=p_usuario,false)) order by s.fila,s.columna),'[]'::jsonb)
   into y from public.at_asientos s left join public.at_pedidos held on held.id=s.pedido_id where s.vuelo_id=ident;
  return jsonb_build_object('vuelo',x,'asientos',y,'clases',x->'avion'->'clases');
 elsif p_accion='crear_pedido' then
  -- Per-user idempotency is checked before any inventory side effect.
  select * into p from public.at_pedidos where usuario_id=p_usuario and clave_operacion=(p_datos->>'clave_operacion')::uuid for update;
  if found then
   if p.solicitud<>p_datos then raise exception 'CONFLICTO: La clave ya pertenece a otra solicitud'; end if;
   return to_jsonb(p);
  end if;
  select * into v from public.at_vuelos where id=(p_datos->>'vuelo_id')::uuid and activo and salida_en>now() for update;
  if not found then raise exception 'NO_ENCONTRADO: Vuelo disponible'; end if;
  select array_agg(value order by value) into labels from jsonb_array_elements_text(p_datos->'asientos');
  if cardinality(labels)<1 or cardinality(labels)<>(select count(distinct value) from unnest(labels) value) then raise exception 'INVALIDO: Selección de asientos'; end if;
  perform 1 from public.at_asientos where vuelo_id=v.id and codigo=any(labels) order by codigo for update;
  if (select count(*) from public.at_asientos where vuelo_id=v.id and codigo=any(labels) and pedido_id is null)<>cardinality(labels) then raise exception 'CONFLICTO: Algún asiento ya está reservado o retenido'; end if;
  select sum(precio_centavos) into sub from public.at_asientos where vuelo_id=v.id and codigo=any(labels);
  if sub>86956521 then raise exception 'INVALIDO: El pedido supera el máximo técnico de Stripe USD'; end if;
  vat:=round(sub*0.15); remaining:=vat; cumulative:=0; x:='[]'::jsonb; n:=0;
  for seat in select * from public.at_asientos where vuelo_id=v.id and codigo=any(labels) order by fila,columna loop
   n:=n+1; cumulative:=cumulative+seat.precio_centavos; tax:=round(cumulative*0.15)-(vat-remaining); remaining:=remaining-tax;
   x:=x||jsonb_build_array(jsonb_build_object('codigo',seat.codigo,'clase_codigo',seat.clase_codigo,'subtotal_centavos',seat.precio_centavos,'iva_centavos',tax,'total_centavos',seat.precio_centavos+tax));
  end loop;
  insert into public.at_pedidos(usuario_id,vuelo_id,clave_operacion,solicitud,asientos,subtotal_centavos,iva_centavos,total_centavos)
   values(p_usuario,v.id,(p_datos->>'clave_operacion')::uuid,p_datos,x,sub,vat,sub+vat) returning * into p;
  update public.at_asientos set pedido_id=p.id where vuelo_id=v.id and codigo=any(labels);
  return to_jsonb(p);
 elsif p_accion='pedidos' then
  return jsonb_build_object('pedidos',coalesce((select jsonb_agg(public.at_pedido_json(id) order by creado_en desc) from public.at_pedidos where usuario_id=p_usuario),'[]'::jsonb));
 elsif p_accion in('pedido','pedido_interno','vincular','resolver','abandonar','incidencia') then
  select * into p from public.at_pedidos where id=ident and (p_usuario is null or usuario_id=p_usuario) for update;
  if not found then raise exception 'NO_ENCONTRADO: Pedido'; end if;
  if p_accion in('pedido','pedido_interno') then return to_jsonb(p); end if;
  if p_accion='vincular' then
   if p.session_id is not null and p.session_id<>p_datos->>'session_id' then raise exception 'CONFLICTO: Otra sesión de pago'; end if;
   update public.at_pedidos set session_id=p_datos->>'session_id',checkout_url=p_datos->>'checkout_url',
    stripe_vence_en=to_timestamp((p_datos->>'expires_at')::double precision),estado=case when estado='preparando_pago' then 'pendiente_pago' else estado end where id=p.id;
  elsif p_accion='incidencia' then
   update public.at_pedidos set incidencia='Pago en revisión; no se emitió una reserva.',estado='revision_pago' where id=p.id;
  elsif p_accion='abandonar' then
   if p.estado='pagado' then raise exception 'CONFLICTO: El pedido ya está pagado'; end if;
   if p.estado not in('expirado','cancelado') then raise exception 'CONFLICTO: Confirma la expiración en Stripe antes de liberar'; end if;
  elsif p_datos->>'status'='paid' then
   if p.estado='pagado' then return to_jsonb(p); end if;
   if p_datos->>'payment_intent' is null then raise exception 'INVALIDO: Falta referencia de pago'; end if;
   if (select count(*) from public.at_asientos where pedido_id=p.id)<>jsonb_array_length(p.asientos) then
    update public.at_pedidos set estado='revision_pago',payment_intent=p_datos->>'payment_intent',incidencia='Pago tardío; reembolso total pendiente.' where id=p.id;
    -- Durable compensation; never allocate occupied seats to this late order.
    insert into public.at_cancelaciones(pedido_id,usuario_id,clave_operacion,asientos,importe_centavos,motivo)
     values(p.id,p.usuario_id,p.id,'[]',p.total_centavos,'pago_tardio') on conflict(usuario_id,clave_operacion) do nothing;
   else
    insert into public.at_reservas(pedido_id,usuario_id,vuelo_id,vuelo) values(p.id,p.usuario_id,p.vuelo_id,public.at_catalogo('vuelos',p.vuelo_id))
      on conflict(pedido_id) do update set pedido_id=excluded.pedido_id returning id into rid;
    update public.at_pedidos set estado='pagado',payment_intent=p_datos->>'payment_intent',reserva_id=rid,incidencia=null where id=p.id;
   end if;
  elsif p_datos->>'status'='expired' and p.estado not in('pagado','revision_pago') then
   update public.at_asientos set pedido_id=null where pedido_id=p.id;
   update public.at_pedidos set estado='expirado' where id=p.id;
  end if;
  return (select to_jsonb(t) from public.at_pedidos t where t.id=p.id);
 elsif p_accion='reservas' then
  return jsonb_build_object('reservas',coalesce((select jsonb_agg(public.at_reserva_json(id) order by creado_en desc) from public.at_reservas where usuario_id=p_usuario),'[]'::jsonb));
 elsif p_accion='reserva' then
  if not exists(select 1 from public.at_reservas where id=ident and usuario_id=p_usuario) then raise exception 'NO_ENCONTRADO: Reserva'; end if;
  return public.at_reserva_json(ident);
 elsif p_accion='cancelar' then
  select * into c from public.at_cancelaciones where usuario_id=p_usuario and clave_operacion=(p_datos->>'clave_operacion')::uuid for update;
  if found then
   if c.reserva_id<>ident or c.asientos<>p_datos->'asientos' then raise exception 'CONFLICTO: Clave de cancelación reutilizada'; end if;
   return to_jsonb(c)||(select jsonb_build_object('payment_intent',payment_intent) from public.at_pedidos where id=c.pedido_id);
  end if;
  select t.* into p from public.at_pedidos t join public.at_reservas r on r.pedido_id=t.id where r.id=ident and r.usuario_id=p_usuario for update of t;
  if not found then raise exception 'NO_ENCONTRADO: Reserva'; end if;
  if (select salida_en from public.at_vuelos where id=p.vuelo_id)<=now() then raise exception 'CONFLICTO: El vuelo ya salió'; end if;
  select array_agg(value order by value) into labels from jsonb_array_elements_text(p_datos->'asientos');
  if cardinality(labels)<1 or cardinality(labels)<>(select count(distinct value) from unnest(labels) value) then raise exception 'INVALIDO: Selección de cancelación'; end if;
  if (select count(*) from public.at_asientos where pedido_id=p.id and codigo=any(labels))<>cardinality(labels)
   or exists(select 1 from public.at_cancelaciones cc where cc.pedido_id=p.id and cc.asientos ?| labels) then raise exception 'CONFLICTO: Solo puedes cancelar asientos activos sin devolución previa'; end if;
  select sum((s->>'total_centavos')::integer) into sub from jsonb_array_elements(p.asientos) s where s->>'codigo'=any(labels);
  if sub+coalesce((select sum(importe_centavos) from public.at_cancelaciones where pedido_id=p.id),0)>p.total_centavos then raise exception 'CONFLICTO: El reembolso supera el importe cobrado'; end if;
  insert into public.at_cancelaciones(reserva_id,pedido_id,usuario_id,clave_operacion,asientos,importe_centavos)
   values(ident,p.id,p_usuario,(p_datos->>'clave_operacion')::uuid,p_datos->'asientos',sub) returning * into c;
  return to_jsonb(c)||jsonb_build_object('payment_intent',p.payment_intent);
 elsif p_accion in('cancelacion_obtener','reembolso_resultado','reembolso_reintentar','compensacion') then
  if p_accion='compensacion' then select * into c from public.at_cancelaciones where pedido_id=ident and motivo='pago_tardio';
  else select * into c from public.at_cancelaciones where id=ident and (p_usuario is null or usuario_id=p_usuario) for update; end if;
  if not found then
   if p_accion='compensacion' then return null; end if;
   raise exception 'NO_ENCONTRADO: Cancelación';
  end if;
  select * into p from public.at_pedidos where id=c.pedido_id for update;
  if p_accion='reembolso_reintentar' and c.estado='fallido' and c.ultima_clave_retry is distinct from (p_datos->>'clave_operacion')::uuid then
   update public.at_cancelaciones set refund_id=null,intento=intento+1,estado='reembolso_pendiente',ultima_clave_retry=(p_datos->>'clave_operacion')::uuid where id=c.id returning * into c;
  end if;
  if p_accion='reembolso_resultado' then
   if c.refund_id is not null and c.refund_id<>p_datos->>'refund_id' then raise exception 'CONFLICTO: Otra devolución'; end if;
   if c.estado<>'cancelado' then
    update public.at_cancelaciones set refund_id=p_datos->>'refund_id',estado=case when p_datos->>'status'='succeeded' then 'cancelado'
       when p_datos->>'status' in('failed','canceled') then 'fallido' else 'reembolso_pendiente' end where id=c.id returning * into c;
    if c.estado='cancelado' then
     update public.at_asientos set pedido_id=null where pedido_id=p.id and (c.motivo='pago_tardio' or codigo in(select jsonb_array_elements_text(c.asientos)));
     if c.motivo='pago_tardio' then update public.at_pedidos set estado='cancelado',incidencia='Pago tardío reembolsado.' where id=p.id; end if;
    end if;
   end if;
  end if;
  return to_jsonb(c)||jsonb_build_object('payment_intent',p.payment_intent);
 elsif p_accion='evento' then
  insert into public.at_eventos(id,tipo) values(p_datos->>'event_id',p_datos->>'tipo') on conflict do nothing;
  return jsonb_build_object('registrado',true);
 end if;
 raise exception 'INVALIDO: Operación no implementada';
end $$;

-- All application data remains inaccessible to browser/API clients. Only the
-- private SECURITY DEFINER boundary can mutate new inventory/payment tables.
do $$ declare t text; f record; begin
 foreach t in array array['aerotech_migraciones','at_aeropuertos','at_aviones','at_rutas','at_vuelos','at_asientos','at_pedidos','at_reservas','at_cancelaciones','at_eventos'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on table public.%I from public,anon,authenticated,service_role',t);
  execute format('grant select on table public.%I to service_role',t);
 end loop;
 for f in select oid::regprocedure as signature from pg_proc where pronamespace='public'::regnamespace and
   proname in('at_guardar_horario','at_catalogo','at_pedido_json','at_reserva_json','at_generar_asientos','sistema_operar') loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
  execute format('grant execute on function %s to service_role',f.signature);
 end loop;
end $$;
-- Retire all old quantity write paths even for direct service-role callers.
create or replace function public.reservar_vuelo(p_vuelo_id uuid,p_usuario_id uuid,p_cantidad integer)
 returns public.reservas language plpgsql set search_path=public as $$ begin
 raise exception 'FLUJO_RETIRADO: Usa asientos numerados y Stripe TEST'; end $$;
-- Curated airport coordinates (OurAirports public-domain data); no real airline claim.
insert into public.at_aeropuertos(id,iata,datos)
select ('a0000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,iata,
 jsonb_build_object('iata',iata,'nombre',nombre,'ciudad',ciudad,'pais',pais,'codigo_pais',pais_iso,
 'latitud',lat,'longitud',lon,'zona_horaria',zona)
from (values
 (1,'UIO','Aeropuerto Internacional Mariscal Sucre','Quito','Ecuador','EC',-0.1291667,-78.3575,'America/Guayaquil'),
 (2,'GYE','Aeropuerto Internacional José Joaquín de Olmedo','Guayaquil','Ecuador','EC',-2.1574199,-79.8835983,'America/Guayaquil'),
 (3,'CUE','Aeropuerto Mariscal La Mar','Cuenca','Ecuador','EC',-2.88947,-78.984398,'America/Guayaquil'),
 (4,'LOH','Aeropuerto Ciudad de Catamayo','Catamayo','Ecuador','EC',-3.99589,-79.371902,'America/Guayaquil'),
 (5,'MEC','Aeropuerto Internacional Eloy Alfaro','Manta','Ecuador','EC',-0.946078,-80.678802,'America/Guayaquil'),
 (6,'JFK','John F. Kennedy International Airport','New York','Estados Unidos','US',40.639447,-73.779317,'America/New_York'),
 (7,'LIM','Aeropuerto Internacional Jorge Chávez','Lima','Perú','PE',-12.0219,-77.1143,'America/Lima'),
 (8,'BOG','Aeropuerto Internacional El Dorado','Bogotá','Colombia','CO',4.70159,-74.1469,'America/Bogota')
) a(n,iata,nombre,ciudad,pais,pais_iso,lat,lon,zona);
insert into public.at_aviones(id,matricula,datos) values('b0000000-0000-4000-8000-000000000001','AT-DEMO-01',
 '{"matricula":"AT-DEMO-01","modelo":"AeroTech académico — avión ficticio","capacidad_total":36,"clases":[{"codigo":"EJEC","nombre":"Ejecutiva","fila_inicio":1,"filas":2,"columnas":[["A","C"],["D","F"]],"capacidad":8},{"codigo":"ECO","nombre":"Económica","fila_inicio":3,"filas":7,"columnas":[["A","B"],["C","D"]],"capacidad":28}]}');
insert into public.at_rutas(id,origen_id,destino_id) values
 ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000002'),
 ('c0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000003'),
 ('c0000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000001');
do $$ declare n integer; d date:=((now() at time zone 'America/Guayaquil')::date+7); f uuid; start_local timestamp; finish_local timestamp;
begin
 for n in 1..3 loop
  f:=('d0000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
  start_local:=d+make_time(7+n*3,0,0); finish_local:=start_local+interval '1 hour';
  insert into public.at_vuelos(id,codigo,ruta_id,avion_id,salida_en,llegada_en,datos) values
   (f,'AT10'||n,('c0000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'b0000000-0000-4000-8000-000000000001',
   start_local at time zone 'America/Guayaquil',finish_local at time zone 'America/Guayaquil',
   jsonb_build_object('salida_local',to_char(start_local,'YYYY-MM-DD"T"HH24:MI'),'llegada_local',to_char(finish_local,'YYYY-MM-DD"T"HH24:MI'),
     'tarifas','[{"clase_codigo":"EJEC","precio_centavos":12000},{"clase_codigo":"ECO","precio_centavos":5900}]'::jsonb));
  perform public.at_generar_asientos(f,public.at_catalogo('aviones','b0000000-0000-4000-8000-000000000001'),
    '[{"clase_codigo":"EJEC","precio_centavos":12000},{"clase_codigo":"ECO","precio_centavos":5900}]'::jsonb);
 end loop;
end $$;

notify pgrst,'reload schema';
commit;

-- Migration 009: safe administrative user management.
-- Additive user administration. Existing accounts and roles are not changed.
begin;

create or replace function public.administrar_usuario(p_actor uuid, p_accion text, p_datos jsonb)
returns jsonb
language plpgsql security definer set search_path = pg_catalog, public
as $$
declare
  target_id uuid;
  target public.usuarios%rowtype;
  requested_role text;
begin
  -- One common lock serializes every role change, including legacy promotion.
  -- Recheck the actor AFTER waiting: an HTTP authorization check can be stale.
  perform pg_advisory_xact_lock(91420261117);
  if not exists(select 1 from public.usuarios where id = p_actor and rol = 'ADMIN') then
    raise exception 'ADMIN_REQUERIDO';
  end if;
  requested_role := p_datos->>'rol';
  if jsonb_typeof(p_datos) is distinct from 'object'
     or requested_role is null or requested_role not in ('USER', 'ADMIN') then
    raise exception 'DATOS_USUARIO_INVALIDOS';
  end if;
  if p_accion = 'crear' then
    if jsonb_typeof(p_datos->'nombre') is distinct from 'string'
       or length(trim(p_datos->>'nombre')) not between 1 and 120
       or jsonb_typeof(p_datos->'correo') is distinct from 'string'
       or trim(p_datos->>'correo') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
       or jsonb_typeof(p_datos->'password_hash') is distinct from 'string'
       or p_datos->>'password_hash' not like 'scrypt:%' then
      raise exception 'DATOS_USUARIO_INVALIDOS';
    end if;
    insert into public.usuarios(nombre, correo, password_hash, rol)
      values(trim(p_datos->>'nombre'), lower(trim(p_datos->>'correo')), p_datos->>'password_hash', requested_role)
      returning * into target;
  elsif p_accion = 'rol' then
    begin
      target_id := (p_datos->>'id')::uuid;
    exception when invalid_text_representation then
      raise exception 'USUARIO_INEXISTENTE';
    end;
    select * into target from public.usuarios where id = target_id for update;
    if not found then raise exception 'USUARIO_INEXISTENTE'; end if;
    if target_id = p_actor and requested_role = 'USER' then
      raise exception 'AUTO_RETIRO';
    end if;
    if target.rol = 'ADMIN' and requested_role = 'USER'
       and (select count(*) from public.usuarios where rol = 'ADMIN') <= 1 then
      raise exception 'ULTIMO_ADMIN';
    end if;
    update public.usuarios set rol = requested_role where id = target_id returning * into target;
  else
    raise exception 'DATOS_USUARIO_INVALIDOS';
  end if;
  return jsonb_build_object('id', target.id, 'nombre', target.nombre, 'correo', target.correo, 'rol', target.rol);
end;
$$;

revoke all on function public.administrar_usuario(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.administrar_usuario(uuid, text, jsonb) to service_role;
notify pgrst, 'reload schema';
commit;
