-- Additive account state; existing accounts remain active and data is preserved.
begin;
select pg_advisory_xact_lock(91420261117);
alter table public.usuarios add column if not exists activo boolean not null default true;
alter table public.usuarios add column if not exists version_acceso integer not null default 0;

create or replace function public.administrar_usuario(p_actor uuid, p_accion text, p_datos jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  target_id uuid;
  target public.usuarios%rowtype;
  requested_role text;
  requested_active boolean;
begin
  -- Role and state changes share one lock and recheck the current actor.
  perform pg_advisory_xact_lock(91420261117);
  if not exists(select 1 from public.usuarios where id=p_actor and rol='ADMIN' and activo) then
    raise exception 'ADMIN_REQUERIDO';
  end if;
  if jsonb_typeof(p_datos) is distinct from 'object' then
    raise exception 'DATOS_USUARIO_INVALIDOS';
  end if;
  if p_accion in ('crear','rol') then
    requested_role:=p_datos->>'rol';
    if requested_role is null or requested_role not in ('USER','ADMIN') then
      raise exception 'DATOS_USUARIO_INVALIDOS';
    end if;
  end if;
  if p_accion='crear' then
    if jsonb_typeof(p_datos->'nombre') is distinct from 'string'
       or length(trim(p_datos->>'nombre')) not between 1 and 120
       or jsonb_typeof(p_datos->'correo') is distinct from 'string'
       or trim(p_datos->>'correo') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
       or jsonb_typeof(p_datos->'password_hash') is distinct from 'string'
       or p_datos->>'password_hash' not like 'scrypt:%' then
      raise exception 'DATOS_USUARIO_INVALIDOS';
    end if;
    insert into public.usuarios(nombre,correo,password_hash,rol)
      values(trim(p_datos->>'nombre'),lower(trim(p_datos->>'correo')),p_datos->>'password_hash',requested_role)
      returning * into target;
  elsif p_accion in ('rol','estado') then
    begin
      target_id:=(p_datos->>'id')::uuid;
    exception when invalid_text_representation then
      raise exception 'USUARIO_INEXISTENTE';
    end;
    select * into target from public.usuarios where id=target_id for update;
    if not found then raise exception 'USUARIO_INEXISTENTE'; end if;
    if p_accion='rol' then
      if target_id=p_actor and requested_role='USER' then raise exception 'AUTO_RETIRO'; end if;
      if target.rol='ADMIN' and target.activo and requested_role='USER'
         and (select count(*) from public.usuarios where rol='ADMIN' and activo)<=1 then
        raise exception 'ULTIMO_ADMIN';
      end if;
      -- Changing a role never reactivates a disabled account.
      update public.usuarios set rol=requested_role where id=target_id returning * into target;
    else
      if jsonb_typeof(p_datos->'activo') is distinct from 'boolean' then
        raise exception 'DATOS_USUARIO_INVALIDOS';
      end if;
      requested_active:=(p_datos->>'activo')::boolean;
      if target_id=p_actor and not requested_active then raise exception 'AUTO_DESACTIVACION'; end if;
      if target.rol='ADMIN' and target.activo and not requested_active
         and (select count(*) from public.usuarios where rol='ADMIN' and activo)<=1 then
        raise exception 'ULTIMO_ADMIN';
      end if;
      -- An access generation revokes all previous JWTs without deleting history.
      update public.usuarios set activo=requested_active,
        version_acceso=version_acceso+case when activo and not requested_active then 1 else 0 end
        where id=target_id returning * into target;
    end if;
  else
    raise exception 'DATOS_USUARIO_INVALIDOS';
  end if;
  return jsonb_build_object('id',target.id,'nombre',target.nombre,'correo',target.correo,
                           'rol',target.rol,'activo',target.activo);
end;
$$;
revoke all on function public.administrar_usuario(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.administrar_usuario(uuid,text,jsonb) to service_role;

-- Normal operations can run concurrently, but account deactivation waits for
-- their shared access boundary. Provider settlement is not a user login.
do $$ begin
 if to_regprocedure('public.sistema_operar_base_012(text,uuid,jsonb)') is null then
  alter function public.sistema_operar(text,uuid,jsonb) rename to sistema_operar_base_012;
 end if;
end $$;
revoke all on function public.sistema_operar_base_012(text,uuid,jsonb) from public,anon,authenticated,service_role;
create or replace function public.sistema_operar(p_accion text,p_usuario uuid default null,p_datos jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 perform pg_advisory_xact_lock_shared(91420261117);
 if p_usuario is not null and p_accion not in (
   'pedido','pedido_interno','cancelacion_obtener','vincular','resolver',
   'incidencia','compensacion','reembolso_resultado','evento','evento_visto'
 ) and not exists(select 1 from public.usuarios where id=p_usuario and activo) then
  raise exception 'PROHIBIDO: La cuenta está desactivada';
 end if;
 return public.sistema_operar_base_012(p_accion,p_usuario,p_datos);
end;
$$;
revoke all on function public.sistema_operar(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.sistema_operar(text,uuid,jsonb) to service_role;
insert into public.aerotech_migraciones(version) values(12) on conflict do nothing;
notify pgrst,'reload schema';
commit;
