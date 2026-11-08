-- Datos ficticios para pruebas locales de la APE 4.
insert into public.vuelos (
    origen, destino, fecha, hora_salida, hora_llegada, precio, asientos_disponibles
)
select 'Quito', 'Guayaquil', date '2026-12-01', time '09:45', time '10:30', 89.00, 20
where not exists (
    select 1 from public.vuelos
    where origen = 'Quito' and destino = 'Guayaquil'
      and fecha = date '2026-12-01' and hora_salida = time '09:45'
);

insert into public.vuelos (
    origen, destino, fecha, hora_salida, hora_llegada, precio, asientos_disponibles
)
select 'Quito', 'Cuenca', date '2026-12-02', time '12:00', time '12:50', 65.00, 12
where not exists (
    select 1 from public.vuelos
    where origen = 'Quito' and destino = 'Cuenca'
      and fecha = date '2026-12-02' and hora_salida = time '12:00'
);
