-- Arrival slots and generated flight codes. Existing inventory is preserved.
begin;
select pg_advisory_xact_lock(8084008);

do $$ begin
 if to_regprocedure('public.at_catalogo_base_011(text,uuid)') is null then
  alter function public.at_catalogo(text,uuid) rename to at_catalogo_base_011;
 end if;
 if to_regprocedure('public.sistema_operar_base_011(text,uuid,jsonb)') is null then
  alter function public.sistema_operar(text,uuid,jsonb) rename to sistema_operar_base_011;
 end if;
end $$;

create or replace function public.at_catalogo(p_tipo text,p_id uuid) returns jsonb
language plpgsql stable set search_path=public,pg_temp as $$
declare result jsonb;
begin
 result:=public.at_catalogo_base_011(p_tipo,p_id);
 if p_tipo='aeropuertos' and result is not null then
  result:=jsonb_build_object('capacidad_aterrizajes',10,'franja_minutos',60)||result;
 end if;
 return result;
end $$;

create or replace function public.at_disponibilidad_011(p_aeropuerto uuid,p_llegada timestamptz,p_excluir uuid default null)
returns jsonb language plpgsql stable set search_path=public,pg_temp as $$
declare airport jsonb; local_arrival timestamp; starts timestamp; finishes timestamp; capacity integer; minutes integer; used integer;
begin
 airport:=public.at_catalogo('aeropuertos',p_aeropuerto);
 if airport is null or not (airport->>'activo')::boolean then raise exception 'NO_ENCONTRADO: Aeropuerto activo'; end if;
 capacity:=(airport->>'capacidad_aterrizajes')::integer; minutes:=(airport->>'franja_minutos')::integer;
 local_arrival:=p_llegada at time zone (airport->>'zona_horaria');
 starts:=date_bin(make_interval(mins=>minutes),local_arrival,timestamp '2000-01-01');
 finishes:=starts+make_interval(mins=>minutes);
 select count(*) into used from public.at_vuelos v join public.at_rutas r on r.id=v.ruta_id
 where v.activo and r.destino_id=p_aeropuerto and (p_excluir is null or v.id<>p_excluir)
 and (v.llegada_en at time zone (airport->>'zona_horaria'))>=starts
 and (v.llegada_en at time zone (airport->>'zona_horaria'))<finishes;
 return jsonb_build_object('capacidad_aterrizajes',capacity,'franja_minutos',minutes,
  'programados',used,'disponibles',greatest(capacity-used,0),'inicio_local',to_char(starts,'YYYY-MM-DD"T"HH24:MI'),
  'fin_local',to_char(finishes,'YYYY-MM-DD"T"HH24:MI'),'zona_horaria',airport->>'zona_horaria');
end $$;

create or replace function public.at_operacion_vuelo_011() returns trigger
language plpgsql set search_path=public,pg_temp as $$
declare next_number numeric; destination uuid; availability jsonb;
begin
 perform pg_advisory_xact_lock(8084008);
 if tg_op='INSERT' then
  select coalesce(max((substring(codigo from '^AT([0-9]+)(?:-|$)'))::numeric),103)+1 into next_number from public.at_vuelos;
  new.codigo:='AT'||next_number::text;
 else new.codigo:=old.codigo;
 end if;
 new.datos:=jsonb_set(new.datos,'{codigo}',to_jsonb(new.codigo));
 if new.activo then
  select destino_id into destination from public.at_rutas where id=new.ruta_id;
  availability:=public.at_disponibilidad_011(destination,new.llegada_en,new.id);
  if (availability->>'disponibles')::integer<=0 then
   raise exception 'CONFLICTO: El aeropuerto de destino no dispone de cupos de aterrizaje en esa franja';
  end if;
 end if;
 return new;
end $$;
drop trigger if exists at_operacion_011 on public.at_vuelos;
create trigger at_operacion_011 before insert or update on public.at_vuelos
for each row execute function public.at_operacion_vuelo_011();

create or replace function public.at_capacidad_aeropuerto_011() returns trigger
language plpgsql set search_path=public,pg_temp as $$
declare capacity integer; minutes integer;
begin
 perform pg_advisory_xact_lock(8084008);
 new.datos:=jsonb_build_object('capacidad_aterrizajes',10,'franja_minutos',60)||new.datos;
 if jsonb_typeof(new.datos->'capacidad_aterrizajes')<>'number'
  or (new.datos->>'capacidad_aterrizajes')!~'^[0-9]{1,4}$'
  or jsonb_typeof(new.datos->'franja_minutos')<>'number'
  or (new.datos->>'franja_minutos')!~'^[0-9]{1,3}$' then
  raise exception 'INVALIDO: Capacidad y franja deben ser enteros';
 end if;
 capacity:=(new.datos->>'capacidad_aterrizajes')::integer; minutes:=(new.datos->>'franja_minutos')::integer;
 if capacity not between 1 and 1000 or minutes not in(15,30,60,120) then
  raise exception 'INVALIDO: Capacidad de 1 a 1000 y franja de 15, 30, 60 o 120 minutos';
 end if;
 if exists(select 1 from public.at_vuelos v join public.at_rutas r on r.id=v.ruta_id
   where r.destino_id=new.id and v.activo and v.llegada_en>now()
   group by date_bin(make_interval(mins=>minutes),v.llegada_en at time zone(new.datos->>'zona_horaria'),timestamp '2000-01-01')
   having count(*)>capacity) then
  raise exception 'CONFLICTO: La capacidad propuesta es inferior a los aterrizajes ya programados';
 end if;
 return new;
end $$;
drop trigger if exists at_capacidad_011 on public.at_aeropuertos;
create trigger at_capacidad_011 before insert or update on public.at_aeropuertos
for each row execute function public.at_capacidad_aeropuerto_011();

create or replace function public.sistema_operar(p_accion text,p_usuario uuid default null,p_datos jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare result jsonb; existing public.at_aeropuertos; changes jsonb:=p_datos->'datos'; ident uuid:=(p_datos->>'id')::uuid;
 airport jsonb; arrival timestamp;
begin
 if p_accion='disponibilidad_aeropuerto' or (p_accion='guardar' and p_datos->>'recurso'='aeropuertos' and ident is not null) then
  perform pg_advisory_xact_lock(8084008);
  if not exists(select 1 from public.usuarios u where u.id=p_usuario and u.rol='ADMIN'
    and coalesce((to_jsonb(u)->>'activo')::boolean,true)) then raise exception 'PROHIBIDO: Se requiere ADMIN activo'; end if;
  if p_accion='disponibilidad_aeropuerto' then
   airport:=public.at_catalogo('aeropuertos',(p_datos->>'aeropuerto_id')::uuid);
   if airport is null then raise exception 'NO_ENCONTRADO: Aeropuerto'; end if;
   arrival:=(p_datos->>'llegada_local')::timestamp;
   if arrival is null or ((arrival at time zone(airport->>'zona_horaria')) at time zone(airport->>'zona_horaria'))<>arrival then
    raise exception 'INVALIDO: Horario local de llegada inexistente';
   end if;
   return public.at_disponibilidad_011((airport->>'id')::uuid,arrival at time zone(airport->>'zona_horaria'),(p_datos->>'vuelo_id')::uuid);
  end if;
  select * into existing from public.at_aeropuertos where id=ident;
  if found and existing.activo and (changes-'version'-'capacidad_aterrizajes'-'franja_minutos')=
      (existing.datos-'version'-'capacidad_aterrizajes'-'franja_minutos') then
   if changes->>'version' is null or (changes->>'version')::integer<>existing.version then raise exception 'CONFLICTO: Versión modificada'; end if;
   update public.at_aeropuertos set datos=changes-'version',version=version+1 where id=ident;
   return public.at_catalogo('aeropuertos',ident);
  end if;
 end if;
 result:=public.sistema_operar_base_011(p_accion,p_usuario,p_datos);
 if p_accion='listar' and p_datos->>'recurso'='vuelos' and (p_datos ? 'fecha_desde' or p_datos ? 'fecha_hasta') then
  if p_datos->>'fecha_desde' is null or p_datos->>'fecha_hasta' is null
    or (p_datos->>'fecha_desde')::date>(p_datos->>'fecha_hasta')::date then raise exception 'INVALIDO: Rango de fechas'; end if;
  select jsonb_build_object('vuelos',coalesce(jsonb_agg(value order by ordinal),'[]'::jsonb)) into result
  from jsonb_array_elements(result->'vuelos') with ordinality items(value,ordinal)
  where left(value->>'salida_local',10)>=(p_datos->>'fecha_desde')
    and left(value->>'salida_local',10)<=(p_datos->>'fecha_hasta');
 end if;
 return result;
end $$;

revoke all on function public.sistema_operar_base_011(text,uuid,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.at_catalogo_base_011(text,uuid),public.at_disponibilidad_011(uuid,timestamptz,uuid),
 public.at_operacion_vuelo_011(),public.at_capacidad_aeropuerto_011() from public,anon,authenticated,service_role;
revoke all on function public.at_catalogo(text,uuid),public.sistema_operar(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.at_catalogo(text,uuid),public.sistema_operar(text,uuid,jsonb) to service_role;
grant execute on function public.at_catalogo_base_011(text,uuid) to service_role;
insert into public.aerotech_migraciones(version) values(11) on conflict do nothing;
notify pgrst,'reload schema';
commit;
