-- Run only after 002_roles.sql. Explicit single-account bootstrap, not a seed.
begin;
-- Operator: insert SET LOCAL ape4.admin_inicial_id = '<authorized-account-uuid>';
-- immediately above the lock when executing, without committing the private value.
lock table public.usuarios in exclusive mode;
do $$
declare
    target_id uuid;
begin
    -- Missing, empty or malformed account settings must never select an account.
    begin
        target_id := nullif(current_setting('ape4.admin_inicial_id', true), '')::uuid;
    exception when invalid_text_representation then
        raise exception 'ADMIN_BOOTSTRAP_ABORTED: authorized account setting must be a UUID';
    end;
    if target_id is null then
        raise exception 'ADMIN_BOOTSTRAP_ABORTED: set ape4.admin_inicial_id in this transaction';
    end if;
    if (select count(*) from public.usuarios) <> 1
       or not exists (
           select 1 from public.usuarios where id = target_id
       ) then
        raise exception 'ADMIN_BOOTSTRAP_ABORTED: expected exactly the authorized account';
    end if;
    update public.usuarios set rol = 'ADMIN' where id = target_id;
end;
$$;
commit;
