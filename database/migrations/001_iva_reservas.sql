-- Ejecutar una vez sobre instalaciones existentes antes de desplegar la API actualizada.
alter table public.reservas
    add column if not exists subtotal numeric(10, 2),
    add column if not exists iva numeric(10, 2),
    add column if not exists porcentaje_iva numeric(5, 2);

-- Conserva los importes históricos: el total previo pasa a subtotal con IVA cero.
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
    if p_cantidad is null or p_cantidad < 1 or p_cantidad > 9 then
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

revoke all on function public.reservar_vuelo(uuid, uuid, integer) from public, anon, authenticated;
grant execute on function public.reservar_vuelo(uuid, uuid, integer) to service_role;
