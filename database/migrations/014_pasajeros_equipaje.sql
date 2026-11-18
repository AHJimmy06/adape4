-- Extensión aditiva de pedidos: pasajeros descriptivos y USD20 finales por maleta.
-- Los pedidos sin pasajeros conservan exactamente el contrato anterior.
begin;
select pg_advisory_xact_lock(8084015);

do $$ begin
  if to_regprocedure('public.sistema_operar_base_014(text,uuid,jsonb)') is null then
    alter function public.sistema_operar(text,uuid,jsonb) rename to sistema_operar_base_014;
  end if;
end $$;
revoke all on function public.sistema_operar_base_014(text,uuid,jsonb)
  from public,anon,authenticated,service_role;

create or replace function public.sistema_operar(p_accion text,p_usuario uuid default null,p_datos jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare
  persona jsonb; normalizados jsonb:='[]'::jsonb; seleccion text[];
  asiento jsonb; ampliados jsonb:='[]'::jsonb; pasajero jsonb;
  solicitud jsonb; pedido jsonb; previo boolean;
  correo text; categoria text; cantidad integer;
  asignatario public.usuarios%rowtype;
  extra_total bigint; extra_base bigint; extra_iva bigint;
  subtotal bigint:=0; iva bigint:=0; total bigint:=0;
begin
  if p_accion is distinct from 'crear_pedido' or not (p_datos ? 'pasajeros') then
    return public.sistema_operar_base_014(p_accion,p_usuario,p_datos);
  end if;
  if jsonb_typeof(p_datos) is distinct from 'object'
     or jsonb_typeof(p_datos->'pasajeros') is distinct from 'array'
     or jsonb_typeof(p_datos->'asientos') is distinct from 'array' then
    raise exception 'INVALIDO: Datos de pasajeros inválidos';
  end if;
  if exists(select 1 from jsonb_object_keys(p_datos) as k(clave)
            where clave not in ('vuelo_id','clave_operacion','asientos','checkout_ui','pasajeros')) then
    raise exception 'INVALIDO: Datos de pasajeros inválidos';
  end if;
  if exists(select 1 from jsonb_array_elements(p_datos->'asientos') s
            where jsonb_typeof(s) is distinct from 'string') then
    raise exception 'INVALIDO: Pasajeros y asientos no coinciden';
  end if;
  select array_agg(value order by value) into seleccion from jsonb_array_elements_text(p_datos->'asientos');
  if coalesce(cardinality(seleccion),0)=0
     or cardinality(seleccion)<>(select count(distinct s) from unnest(seleccion) s)
     or cardinality(seleccion)<>jsonb_array_length(p_datos->'pasajeros') then
    raise exception 'INVALIDO: Pasajeros y asientos no coinciden';
  end if;
  for persona in select value from jsonb_array_elements(p_datos->'pasajeros')
                 order by value->>'asiento' loop
    if jsonb_typeof(persona) is distinct from 'object' then
      raise exception 'INVALIDO: Datos de pasajeros inválidos';
    end if;
    if exists(select 1 from jsonb_object_keys(persona) as k(clave)
              where clave not in ('asiento','correo_usuario','categoria','maletas_adicionales'))
       or jsonb_typeof(persona->'asiento') is distinct from 'string'
       or not (persona->>'asiento'=any(seleccion))
       or exists(select 1 from jsonb_array_elements(normalizados) n where n->>'asiento'=persona->>'asiento') then
      raise exception 'INVALIDO: Pasajeros y asientos no coinciden';
    end if;
    categoria:=persona->>'categoria';
    if categoria is null or categoria not in ('adulto','adulto_mayor','nino') then
      raise exception 'INVALIDO: Datos de pasajeros inválidos';
    end if;
    if jsonb_typeof(persona->'maletas_adicionales') is distinct from 'number'
       or persona->>'maletas_adicionales' !~ '^[0-9]+$' then
      raise exception 'INVALIDO: Cantidad de maletas adicionales inválida';
    end if;
    if (persona->>'maletas_adicionales')::numeric>49999 then
      raise exception 'INVALIDO: Cantidad de maletas adicionales inválida';
    end if;
    cantidad:=(persona->>'maletas_adicionales')::integer;
    correo:=null;
    if persona ? 'correo_usuario' and persona->'correo_usuario'<>'null'::jsonb then
      if jsonb_typeof(persona->'correo_usuario') is distinct from 'string' then
        raise exception 'INVALIDO: Usuario asignado inexistente o inactivo';
      end if;
      correo:=lower(btrim(persona->>'correo_usuario'));
      if correo='' or correo !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
        raise exception 'INVALIDO: Usuario asignado inexistente o inactivo';
      end if;
      categoria:='adulto';
    end if;
    normalizados:=normalizados||jsonb_build_array(jsonb_build_object(
      'asiento',persona->>'asiento','correo_usuario',correo,
      'categoria',categoria,'maletas_adicionales',cantidad));
  end loop;
  solicitud:=p_datos||jsonb_build_object('asientos',to_jsonb(seleccion),'pasajeros',normalizados);

  -- Mismo orden de locks que la cadena vigente: acceso compartido antes del dominio.
  -- Protege compradores/asignatarios contra cambios administrativos concurrentes.
  perform pg_advisory_xact_lock_shared(91420261117);
  perform pg_advisory_xact_lock(8084008);
  select exists(select 1 from public.at_pedidos
    where usuario_id=p_usuario and clave_operacion=(p_datos->>'clave_operacion')::uuid) into previo;
  -- La implementación anterior mantiene permisos, idempotencia e inventario canónicos.
  pedido:=public.sistema_operar_base_014(p_accion,p_usuario,solicitud);
  if previo then return pedido; end if;

  for asiento in select value from jsonb_array_elements(pedido->'asientos') loop
    select value into persona from jsonb_array_elements(normalizados)
      where value->>'asiento'=asiento->>'codigo';
    correo:=persona->>'correo_usuario';
    pasajero:=jsonb_build_object('categoria',persona->>'categoria','asignado',correo is not null);
    if correo is not null then
      select u.* into asignatario from public.usuarios u
        where u.correo=(persona->>'correo_usuario') and u.activo for share of u;
      if not found then
        raise exception 'INVALIDO: Usuario asignado inexistente o inactivo';
      end if;
      pasajero:=pasajero||jsonb_build_object('usuario_id',asignatario.id,
        'nombre',asignatario.nombre,'correo',asignatario.correo);
    end if;
    cantidad:=(persona->>'maletas_adicionales')::integer;
    extra_total:=cantidad::bigint*2000;
    extra_base:=round(extra_total::numeric/1.15)::bigint;
    extra_iva:=extra_total-extra_base;
    subtotal:=subtotal+(asiento->>'subtotal_centavos')::bigint+extra_base;
    iva:=iva+(asiento->>'iva_centavos')::bigint+extra_iva;
    total:=total+(asiento->>'total_centavos')::bigint+extra_total;
    if total>99999999 then
      raise exception 'INVALIDO: El pedido supera el máximo técnico de Stripe USD';
    end if;
    ampliados:=ampliados||jsonb_build_array(asiento||jsonb_build_object(
      'pasajero',pasajero,
      'equipaje',jsonb_build_object('cantidad',cantidad,'precio_unitario_centavos',2000,
        'subtotal_centavos',extra_base,'iva_centavos',extra_iva,'total_centavos',extra_total),
      'tarifa_subtotal_centavos',asiento->'subtotal_centavos',
      'tarifa_iva_centavos',asiento->'iva_centavos',
      'tarifa_total_centavos',asiento->'total_centavos',
      'subtotal_centavos',(asiento->>'subtotal_centavos')::bigint+extra_base,
      'iva_centavos',(asiento->>'iva_centavos')::bigint+extra_iva,
      'total_centavos',(asiento->>'total_centavos')::bigint+extra_total));
  end loop;
  update public.at_pedidos set asientos=ampliados,subtotal_centavos=subtotal::integer,
    iva_centavos=iva::integer,total_centavos=total::integer
    where id=(pedido->>'id')::uuid returning to_jsonb(at_pedidos.*) into pedido;
  return pedido;
end;
$$;
revoke all on function public.sistema_operar(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.sistema_operar(text,uuid,jsonb) to service_role;
insert into public.aerotech_migraciones(version) values(14) on conflict do nothing;
notify pgrst,'reload schema';
commit;
