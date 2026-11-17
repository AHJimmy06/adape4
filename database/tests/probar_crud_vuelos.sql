-- Prueba aislada del contrato SQL real. No conserva filas ni cambia vuelos reales.
begin;
do $$
declare
    usuario_prueba uuid := gen_random_uuid();
    vuelo_prueba public.vuelos;
    reserva_prueba public.reservas;
    datos jsonb;
begin
    insert into public.usuarios(id, nombre, correo, password_hash)
    values (usuario_prueba, 'Prueba CRUD aislada', usuario_prueba::text || '@crud-prueba.invalid', 'no-es-una-credencial');
    insert into public.vuelos(origen, destino, fecha, hora_salida, hora_llegada, precio, asientos_disponibles)
    values ('Quito, Ecuador', 'Cuenca, Ecuador', current_date + 7, '10:00', '11:00', 10, 3)
    returning * into vuelo_prueba;
    if vuelo_prueba.version <> 1 or not vuelo_prueba.activo then
        raise exception 'ESTADO_INICIAL_INCORRECTO';
    end if;
    datos := jsonb_build_object('origen', vuelo_prueba.origen, 'destino', vuelo_prueba.destino,
        'fecha', vuelo_prueba.fecha, 'hora_salida', '10:00', 'hora_llegada', '11:00',
        'precio', 20, 'asientos_disponibles', 2);

    select * into reserva_prueba from public.reservar_vuelo(vuelo_prueba.id, usuario_prueba, 1);
    select * into vuelo_prueba from public.vuelos where id = vuelo_prueba.id;
    if vuelo_prueba.version <> 2 or vuelo_prueba.asientos_disponibles <> 2 or reserva_prueba.total <> 11.50 then
        raise exception 'RESERVA_O_VERSION_INCORRECTA';
    end if;
    begin
        perform public.modificar_vuelo(vuelo_prueba.id, 1, datos);
        raise exception 'EDICION_OBSOLETA_PERMITIDA';
    exception when others then
        if sqlerrm <> 'VUELO_MODIFICADO' then raise; end if;
    end;
    begin
        perform public.eliminar_vuelo(vuelo_prueba.id, 1);
        raise exception 'ELIMINACION_OBSOLETA_PERMITIDA';
    exception when others then
        if sqlerrm <> 'VUELO_MODIFICADO' then raise; end if;
    end;
    begin
        perform public.eliminar_vuelo(vuelo_prueba.id, 2);
        raise exception 'ELIMINACION_CON_RESERVA_PERMITIDA';
    exception when others then
        if sqlerrm <> 'VUELO_CON_RESERVAS' then raise; end if;
    end;
    select * into vuelo_prueba from public.modificar_vuelo(vuelo_prueba.id, 2, datos);
    if vuelo_prueba.version <> 3 or vuelo_prueba.precio <> 20 then
        raise exception 'EDICION_NO_APLICADA';
    end if;
    if (select total from public.reservas where id = reserva_prueba.id) <> 11.50 then
        raise exception 'IMPORTE_HISTORICO_MODIFICADO';
    end if;
    perform public.cancelar_reserva(reserva_prueba.id, usuario_prueba);
    select * into vuelo_prueba from public.vuelos where id = vuelo_prueba.id;
    if vuelo_prueba.version <> 4 or vuelo_prueba.asientos_disponibles <> 3 then
        raise exception 'CANCELACION_O_VERSION_INCORRECTA';
    end if;
    datos := jsonb_set(datos, '{asientos_disponibles}', '0'::jsonb);
    select * into vuelo_prueba from public.modificar_vuelo(vuelo_prueba.id, 4, datos);
    if vuelo_prueba.version <> 5 or vuelo_prueba.asientos_disponibles <> 0 then
        raise exception 'EDICION_AGOTADO_NO_PERMITIDA';
    end if;
    select * into vuelo_prueba from public.eliminar_vuelo(vuelo_prueba.id, 5);
    if vuelo_prueba.activo or vuelo_prueba.version <> 6 then
        raise exception 'ELIMINACION_LOGICA_INCORRECTA';
    end if;
    begin
        perform public.reservar_vuelo(vuelo_prueba.id, usuario_prueba, 1);
        raise exception 'RESERVA_INACTIVO_PERMITIDA';
    exception when others then
        if sqlerrm <> 'VUELO_INEXISTENTE' then raise; end if;
    end;
    if not exists (select 1 from public.reservas where id = reserva_prueba.id and estado = 'cancelada') then
        raise exception 'HISTORIAL_ELIMINADO';
    end if;
end;
$$;
rollback;
select 'CRUD_SQL_AISLADO_OK' as resultado;
