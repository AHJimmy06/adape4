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
