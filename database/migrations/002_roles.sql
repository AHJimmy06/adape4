-- Add roles without changing existing identities, passwords, tokens or reservations.
begin;

alter table public.usuarios
    add column if not exists rol text not null default 'USER';

-- Reapplication preserves assigned roles and validates any pre-existing column.
alter table public.usuarios alter column rol set default 'USER';
alter table public.usuarios alter column rol set not null;
do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conrelid = 'public.usuarios'::regclass and conname = 'usuarios_rol_check'
    ) then
        alter table public.usuarios add constraint usuarios_rol_check
            check (rol in ('ADMIN', 'USER'));
    end if;
end;
$$;

-- No client policies: only the backend service key may access these rows.
alter table public.usuarios enable row level security;
revoke all on table public.usuarios from public, anon, authenticated;
grant all on table public.usuarios to service_role;
commit;
