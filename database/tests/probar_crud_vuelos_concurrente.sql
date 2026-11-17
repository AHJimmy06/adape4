-- GUIA DE DOS SESIONES. Ejecutar SOLO el bloque indicado en cada paso.
-- UUID exclusivos de esta prueba. No usar vuelos/cuentas reales.
-- PRECONDICION: consultar estos tres UUID; si alguno existe, detenerse, no reutilizarlo.
-- La preparacion COMMIT es necesaria para visibilidad entre sesiones.
-- Ejecutar limpieza al final (solo los tres UUID indicados).

-- 1. PREPARACION (una sola sesion)
begin;
insert into public.usuarios(id,nombre,correo,password_hash) values
('ee7b40de-c188-46a0-86cb-06346b7e18d3','Prueba concurrencia CRUD','crud-ee7b40de@prueba.invalid','no-es-una-credencial');
insert into public.vuelos(id,origen,destino,fecha,hora_salida,hora_llegada,precio,asientos_disponibles) values
('5072f0d6-6a5f-48e7-9ed2-a64a950e55b1','Quito, Ecuador','Cuenca, Ecuador',current_date+7,'10:00','11:00',10,3),
('bf65c3b8-9578-4b59-a720-140da3287e10','Quito, Ecuador','Loja, Ecuador',current_date+7,'10:00','11:00',10,1);
commit;

-- 2A. EDITOR A: iniciar y mientras duerme ejecutar 2B en otra sesion.
begin;
select public.modificar_vuelo('5072f0d6-6a5f-48e7-9ed2-a64a950e55b1',1,
jsonb_build_object('origen','Quito, Ecuador','destino','Cuenca, Ecuador','fecha',current_date+7,
'hora_salida','10:00','hora_llegada','11:00','precio',12,'asientos_disponibles',3));
select pg_sleep(8);
commit;

-- 2B. EDITOR B: espera al bloqueo y debe fallar VUELO_MODIFICADO; precio queda12/version2.
begin;
select public.modificar_vuelo('5072f0d6-6a5f-48e7-9ed2-a64a950e55b1',1,
jsonb_build_object('origen','Quito, Ecuador','destino','Cuenca, Ecuador','fecha',current_date+7,
'hora_salida','10:00','hora_llegada','11:00','precio',99,'asientos_disponibles',3));
rollback;
-- Si el editor deja una transaccion abortada, ejecutar ROLLBACK antes de seguir.

-- 3A. RESERVA: iniciar y mientras duerme ejecutar3B en otra sesion.
begin;
select public.reservar_vuelo('bf65c3b8-9578-4b59-a720-140da3287e10','ee7b40de-c188-46a0-86cb-06346b7e18d3',1);
select pg_sleep(8);
commit;

-- 3B. ELIMINACION: espera al bloqueo; version2 ya corresponde a la reserva.
-- Debe fallar VUELO_CON_RESERVAS, nunca desactivar vuelo con la reserva activa.
begin;
select public.eliminar_vuelo('bf65c3b8-9578-4b59-a720-140da3287e10',2);
rollback;

-- 4. VERIFICACION
select id,precio,asientos_disponibles,version,activo from public.vuelos
where id in ('5072f0d6-6a5f-48e7-9ed2-a64a950e55b1','bf65c3b8-9578-4b59-a720-140da3287e10');
-- Esperado: primer vuelo precio12/version2/activo; segundo stock0/version2/activo.

-- 5. LIMPIEZA EXCLUSIVA DE FIXTURES (una sesion, tras terminar todas las anteriores)
begin;
delete from public.reservas where usuario_id='ee7b40de-c188-46a0-86cb-06346b7e18d3'
 and vuelo_id in ('5072f0d6-6a5f-48e7-9ed2-a64a950e55b1','bf65c3b8-9578-4b59-a720-140da3287e10');
delete from public.vuelos where id in ('5072f0d6-6a5f-48e7-9ed2-a64a950e55b1','bf65c3b8-9578-4b59-a720-140da3287e10');
delete from public.usuarios where id='ee7b40de-c188-46a0-86cb-06346b7e18d3';
commit;
