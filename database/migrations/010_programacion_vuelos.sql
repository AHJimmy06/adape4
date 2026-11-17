-- Additive schedules. Existing flights, orders and user accounts are preserved.
begin;
select pg_advisory_xact_lock(8084008);
create table if not exists public.at_programaciones (
 id uuid primary key default gen_random_uuid(), usuario_id uuid not null references public.usuarios(id),
 clave_operacion uuid not null, solicitud jsonb not null, resultado jsonb not null,
 creado_en timestamptz not null default now(), unique(usuario_id,clave_operacion)
);
alter table public.at_programaciones enable row level security;
revoke all on table public.at_programaciones from public,anon,authenticated,service_role;
grant select on table public.at_programaciones to service_role;

-- Preserve the proven inventory/payment implementation behind one dispatch seam.
do $$ begin
 if to_regprocedure('public.sistema_operar_base_010(text,uuid,jsonb)') is null then
  alter function public.sistema_operar(text,uuid,jsonb) rename to sistema_operar_base_010;
 end if;
end $$;
revoke all on function public.sistema_operar_base_010(text,uuid,jsonb) from public,anon,authenticated,service_role;

create or replace function public.sistema_operar(p_accion text,p_usuario uuid default null,p_datos jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
 existing public.at_programaciones; series_id uuid:=gen_random_uuid(); operation_id uuid;
 first_day date; last_day date; day_index integer; total integer; departure timestamp; arrival timestamp;
 occurrence jsonb; flight jsonb; flights jsonb:='[]'::jsonb; result jsonb; zone_a text; zone_b text;
begin
 if p_accion<>'programar' then
  return public.sistema_operar_base_010(p_accion,p_usuario,p_datos);
 end if;
 perform pg_advisory_xact_lock(8084008);
 if not exists(select 1 from public.usuarios where id=p_usuario and rol='ADMIN') then
  raise exception 'PROHIBIDO: Se requiere ADMIN';
 end if;
 operation_id:=(p_datos->>'clave_operacion')::uuid;
 if operation_id is null then raise exception 'INVALIDO: Clave de operación requerida'; end if;
 select * into existing from public.at_programaciones where usuario_id=p_usuario and clave_operacion=operation_id;
 if found then
  if existing.solicitud<>p_datos then raise exception 'CONFLICTO: La operación ya tiene otros datos'; end if;
  return existing.resultado;
 end if;
 departure:=(p_datos->>'salida_local')::timestamp;
 arrival:=(p_datos->>'llegada_local')::timestamp;
 first_day:=departure::date; last_day:=(p_datos->>'fecha_fin')::date;
 total:=last_day-first_day+1;
 if p_datos->>'frecuencia' is distinct from 'diaria' or total is null or total<1 or total>90
  or length(coalesce(p_datos->>'codigo','')) not between 1 and 21 or departure is null or arrival is null then
  raise exception 'INVALIDO: Programación diaria de 1 a 90 días y código base de hasta 21 caracteres';
 end if;
 select a.datos->>'zona_horaria',b.datos->>'zona_horaria' into zone_a,zone_b
 from public.at_rutas r join public.at_aeropuertos a on a.id=r.origen_id
 join public.at_aeropuertos b on b.id=r.destino_id where r.id=(p_datos->>'ruta_id')::uuid;
 for day_index in 0..total-1 loop
  -- Round trips through the airport zone reject nonexistent DST civil times.
  if ((departure+make_interval(days=>day_index)) at time zone zone_a) at time zone zone_a
       <>departure+make_interval(days=>day_index)
   or ((arrival+make_interval(days=>day_index)) at time zone zone_b) at time zone zone_b
       <>arrival+make_interval(days=>day_index) then
   raise exception 'INVALIDO: Horario local inexistente por cambio de zona horaria';
  end if;
  occurrence:=(p_datos-'fecha_fin'-'clave_operacion') || jsonb_build_object(
   'codigo',(p_datos->>'codigo')||'-'||to_char(first_day+day_index,'YYYYMMDD'),
   'salida_local',to_char(departure+make_interval(days=>day_index),'YYYY-MM-DD"T"HH24:MI'),
   'llegada_local',to_char(arrival+make_interval(days=>day_index),'YYYY-MM-DD"T"HH24:MI'),
   'programacion_id',series_id,'codigo_base',p_datos->>'codigo');
  flight:=public.sistema_operar_base_010('guardar',p_usuario,jsonb_build_object('recurso','vuelos','datos',occurrence));
  flights:=flights||jsonb_build_array(flight);
 end loop;
 result:=jsonb_build_object('vuelos',flights,'programacion',jsonb_build_object(
  'id',series_id,'frecuencia','diaria','fecha_inicio',first_day,'fecha_fin',last_day,'cantidad',total));
 insert into public.at_programaciones(id,usuario_id,clave_operacion,solicitud,resultado)
 values(series_id,p_usuario,operation_id,p_datos,result);
 return result;
end $$;
revoke all on function public.sistema_operar(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.sistema_operar(text,uuid,jsonb) to service_role;
insert into public.aerotech_migraciones(version) values(10) on conflict do nothing;
notify pgrst,'reload schema';
commit;
