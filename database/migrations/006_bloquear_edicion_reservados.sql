begin;
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

revoke all on function public.modificar_vuelo(uuid,integer,jsonb) from public, anon, authenticated;
grant execute on function public.modificar_vuelo(uuid,integer,jsonb) to service_role;
commit;
