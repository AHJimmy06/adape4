begin;
alter table public.vuelos add column if not exists tiene_reservas boolean not null default false;
create or replace function public.actualizar_indicador_reservas_vuelo()
returns trigger language plpgsql set search_path = public as $$
declare
    id_anterior uuid;
    id_actual uuid;
begin
    if TG_OP <> 'INSERT' then id_anterior := old.vuelo_id; end if;
    if TG_OP <> 'DELETE' then id_actual := new.vuelo_id; end if;
    perform 1 from public.vuelos where id in (id_anterior, id_actual) order by id for update;
    update public.vuelos v
       set tiene_reservas = exists (select 1 from public.reservas r where r.vuelo_id=v.id and r.estado='activa')
     where v.id in (id_anterior, id_actual)
       and v.tiene_reservas is distinct from exists (select 1 from public.reservas r where r.vuelo_id=v.id and r.estado='activa');
    return null;
end;
$$;
drop trigger if exists reservas_actualizar_indicador_vuelo on public.reservas;
create trigger reservas_actualizar_indicador_vuelo after insert or update or delete on public.reservas
for each row execute function public.actualizar_indicador_reservas_vuelo();
update public.vuelos v set tiene_reservas=exists(select 1 from public.reservas r where r.vuelo_id=v.id and r.estado='activa')
where v.tiene_reservas is distinct from exists(select 1 from public.reservas r where r.vuelo_id=v.id and r.estado='activa');
revoke all on function public.actualizar_indicador_reservas_vuelo() from public, anon, authenticated;
grant execute on function public.actualizar_indicador_reservas_vuelo() to service_role;
notify pgrst, 'reload schema';
commit;
