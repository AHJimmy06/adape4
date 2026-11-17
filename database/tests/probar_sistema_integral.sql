-- Isolated functional probe. Own UUID fixtures only; every row rolls back.
begin;
do $$
declare u uuid:=gen_random_uuid(); a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid();
 plane uuid; route uuid; flight uuid; order_id uuid; booking uuid; cancel_id uuid; x jsonb; y jsonb; key uuid:=gen_random_uuid();
 departure text:=to_char(current_date+30,'YYYY-MM-DD')||'T10:00'; arrival text:=to_char(current_date+30,'YYYY-MM-DD')||'T11:00';
begin
 insert into public.usuarios(id,nombre,correo,password_hash,rol) values(u,'Prueba aislada',u::text||'@example.test','no-login','ADMIN');
 -- Unique random IATA fixture labels selected from unassigned combinations.
 for x in select jsonb_build_object('iata',i,'nombre','Prueba','ciudad','Prueba','pais','Ecuador','codigo_pais','EC','latitud',0,'longitud',0,'zona_horaria','America/Guayaquil')
   from (values('XZA'),('XZB')) q(i) loop
  if exists(select 1 from public.at_aeropuertos where iata=x->>'iata') then raise exception 'Fixture IATA ocupado: ejecutar en DB aislada'; end if;
  y:=public.sistema_operar('guardar',u,jsonb_build_object('recurso','aeropuertos','datos',x));
  if x->>'iata'='XZA' then a:=(y->>'id')::uuid; else b:=(y->>'id')::uuid; end if;
 end loop;
 x:=public.sistema_operar('guardar',u,jsonb_build_object('recurso','aviones','datos',jsonb_build_object('matricula',u::text,'modelo','Prueba aislada','capacidad_total',2,
  'clases','[{"codigo":"ECO","nombre":"Económica","fila_inicio":1,"filas":1,"columnas":[["A","B"]],"capacidad":2}]'::jsonb)));
 plane:=(x->>'id')::uuid;
 x:=public.sistema_operar('guardar',u,jsonb_build_object('recurso','rutas','datos',jsonb_build_object('origen_id',a,'destino_id',b))); route:=(x->>'id')::uuid;
 x:=public.sistema_operar('guardar',u,jsonb_build_object('recurso','vuelos','datos',jsonb_build_object('codigo',u::text,'ruta_id',route,'avion_id',plane,
 'salida_local',departure,'llegada_local',arrival,'tarifas','[{"clase_codigo":"ECO","precio_centavos":51}]'::jsonb))); flight:=(x->>'id')::uuid;
 x:=public.sistema_operar('crear_pedido',u,jsonb_build_object('vuelo_id',flight,'asientos','["1A","1B"]'::jsonb,'clave_operacion',key)); order_id:=(x->>'id')::uuid;
 if (x->>'subtotal_centavos')::integer<>102 or (x->>'iva_centavos')::integer<>15 or (x->>'total_centavos')::integer<>117 then raise exception 'IVA agregado incorrecto'; end if;
 y:=public.sistema_operar('crear_pedido',u,jsonb_build_object('vuelo_id',flight,'asientos','["1A","1B"]'::jsonb,'clave_operacion',key));
 if y->>'id'<>x->>'id' then raise exception 'Idempotencia incorrecta'; end if;
 begin
  perform public.sistema_operar('crear_pedido',u,jsonb_build_object('vuelo_id',flight,'asientos','["1A"]'::jsonb,'clave_operacion',gen_random_uuid()));
  raise exception 'ASIENTO_DUPLICADO_ACEPTADO';
 exception when others then if sqlerrm not like 'CONFLICTO:%' then raise; end if; end;
 x:=public.sistema_operar('resolver',u,jsonb_build_object('id',order_id,'status','paid','payment_intent','pi_sql_'||u)); booking:=(x->>'reserva_id')::uuid;
 x:=public.sistema_operar('cancelar',u,jsonb_build_object('id',booking,'asientos','["1A"]'::jsonb,'clave_operacion',gen_random_uuid())); cancel_id:=(x->>'id')::uuid;
 if (select count(*) from public.at_asientos where pedido_id=order_id)<>2 then raise exception 'Asiento liberado antes del reembolso'; end if;
 perform public.sistema_operar('reembolso_resultado',u,jsonb_build_object('id',cancel_id,'refund_id','re_sql_'||u,'status','succeeded'));
 perform public.sistema_operar('reembolso_resultado',u,jsonb_build_object('id',cancel_id,'refund_id','re_sql_'||u,'status','succeeded'));
 if (select count(*) from public.at_asientos where pedido_id=order_id)<>1 then raise exception 'Stock duplicado en reembolso'; end if;
 if (public.at_reserva_json(booking)->>'total_centavos')::integer<>117 then raise exception 'Importe original mutado'; end if;
 if has_function_privilege('anon','public.sistema_operar(text,uuid,jsonb)','execute') then raise exception 'RPC público'; end if;
 if has_table_privilege('service_role','public.at_asientos','UPDATE') then raise exception 'Stock editable fuera del RPC'; end if;
 raise notice 'PASS: IVA, cabina, idempotencia, exclusión, devolución, historial, permisos';
end $$;
rollback;
