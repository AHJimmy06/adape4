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
