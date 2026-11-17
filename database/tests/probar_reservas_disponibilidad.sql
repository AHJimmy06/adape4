-- Prueba aislada: todas las filas de ejemplo se revierten, incluso si falla un paso.
-- Ejecutar despues de 004_reservas_disponibilidad.sql. Nunca cambiar ROLLBACK por COMMIT.
begin;

do $$
declare
    usuario_prueba uuid := gen_random_uuid();
    vuelo_prueba uuid := gen_random_uuid();
    reserva_prueba public.reservas;
    asientos integer;
begin
    insert into public.usuarios (id, nombre, correo, password_hash)
    values (usuario_prueba, 'Prueba transaccional de cantidad',
            'prueba-capacidad-' || usuario_prueba::text || '@example.invalid',
            'valor-de-prueba-no-es-una-credencial');
    insert into public.vuelos (id, origen, destino, fecha, hora_salida, hora_llegada, precio, asientos_disponibles)
    values (vuelo_prueba, 'Origen de prueba, Ecuador', 'Destino de prueba, Ecuador',
            '2099-01-01', '08:00', '09:00', 10.00, 30);

    reserva_prueba := public.reservar_vuelo(vuelo_prueba, usuario_prueba, 10);
    select asientos_disponibles into asientos from public.vuelos where id = vuelo_prueba;
    if reserva_prueba.cantidad <> 10 or asientos <> 20 or reserva_prueba.total <> 115.00 then
        raise exception 'PRUEBA_FALLIDA: reserva de diez, inventario o IVA';
    end if;

    begin
        perform public.reservar_vuelo(vuelo_prueba, usuario_prueba, 21);
        raise exception 'PRUEBA_FALLIDA: se permitio sobreventa';
    exception when sqlstate 'P0001' then
        if sqlerrm <> 'ASIENTOS_INSUFICIENTES' then
            raise;
        end if;
    end;
    select asientos_disponibles into asientos from public.vuelos where id = vuelo_prueba;
    if asientos <> 20 or (select count(*) from public.reservas where vuelo_id = vuelo_prueba) <> 1 then
        raise exception 'PRUEBA_FALLIDA: el rechazo cambio datos';
    end if;

    perform public.cancelar_reserva(reserva_prueba.id, usuario_prueba);
    select asientos_disponibles into asientos from public.vuelos where id = vuelo_prueba;
    if asientos <> 30 then
        raise exception 'PRUEBA_FALLIDA: cancelacion no restauro inventario';
    end if;
    reserva_prueba := public.reservar_vuelo(vuelo_prueba, usuario_prueba, 30);
    select asientos_disponibles into asientos from public.vuelos where id = vuelo_prueba;
    if reserva_prueba.cantidad <> 30 or asientos <> 0 or reserva_prueba.total <> 345.00 then
        raise exception 'PRUEBA_FALLIDA: reserva de treinta, inventario o IVA';
    end if;
end;
$$;

rollback;
select 'Pruebas de diez y treinta, IVA, cancelacion y rechazo de sobreventa completadas; filas de prueba revertidas' as resultado;
