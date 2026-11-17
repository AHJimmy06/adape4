-- Additive user administration. Existing accounts and roles are not changed.
begin;

create or replace function public.administrar_usuario(p_actor uuid, p_accion text, p_datos jsonb)
returns jsonb
language plpgsql security definer set search_path = pg_catalog, public
as $$
declare
  target_id uuid;
  target public.usuarios%rowtype;
  requested_role text;
begin
  -- One common lock serializes every role change, including legacy promotion.
  -- Recheck the actor AFTER waiting: an HTTP authorization check can be stale.
  perform pg_advisory_xact_lock(91420261117);
  if not exists(select 1 from public.usuarios where id = p_actor and rol = 'ADMIN') then
    raise exception 'ADMIN_REQUERIDO';
  end if;
  requested_role := p_datos->>'rol';
  if jsonb_typeof(p_datos) is distinct from 'object'
     or requested_role is null or requested_role not in ('USER', 'ADMIN') then
    raise exception 'DATOS_USUARIO_INVALIDOS';
  end if;
  if p_accion = 'crear' then
    if jsonb_typeof(p_datos->'nombre') is distinct from 'string'
       or length(trim(p_datos->>'nombre')) not between 1 and 120
       or jsonb_typeof(p_datos->'correo') is distinct from 'string'
       or trim(p_datos->>'correo') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
       or jsonb_typeof(p_datos->'password_hash') is distinct from 'string'
       or p_datos->>'password_hash' not like 'scrypt:%' then
      raise exception 'DATOS_USUARIO_INVALIDOS';
    end if;
    insert into public.usuarios(nombre, correo, password_hash, rol)
      values(trim(p_datos->>'nombre'), lower(trim(p_datos->>'correo')), p_datos->>'password_hash', requested_role)
      returning * into target;
  elsif p_accion = 'rol' then
    begin
      target_id := (p_datos->>'id')::uuid;
    exception when invalid_text_representation then
      raise exception 'USUARIO_INEXISTENTE';
    end;
    select * into target from public.usuarios where id = target_id for update;
    if not found then raise exception 'USUARIO_INEXISTENTE'; end if;
    if target_id = p_actor and requested_role = 'USER' then
      raise exception 'AUTO_RETIRO';
    end if;
    if target.rol = 'ADMIN' and requested_role = 'USER'
       and (select count(*) from public.usuarios where rol = 'ADMIN') <= 1 then
      raise exception 'ULTIMO_ADMIN';
    end if;
    update public.usuarios set rol = requested_role where id = target_id returning * into target;
  else
    raise exception 'DATOS_USUARIO_INVALIDOS';
  end if;
  return jsonb_build_object('id', target.id, 'nombre', target.nombre, 'correo', target.correo, 'rol', target.rol);
end;
$$;

revoke all on function public.administrar_usuario(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.administrar_usuario(uuid, text, jsonb) to service_role;
notify pgrst, 'reload schema';
commit;
