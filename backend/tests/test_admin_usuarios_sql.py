"""Real PostgreSQL proof, including stale actors waiting on a concurrent change."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Event
from time import monotonic, sleep
from uuid import uuid4

import pytest


def seed(conn, role='ADMIN'):
    user_id = uuid4()
    conn.execute('insert into public.usuarios(id,nombre,correo,password_hash,rol) values(%s,%s,%s,%s,%s)',
                 (user_id, 'SQL User', f'{user_id}@example.test', 'scrypt:test', role))
    return user_id


def invoke(conn, actor, action, data):
    from psycopg.types.json import Jsonb
    return conn.execute('select public.administrar_usuario(%s,%s,%s)', (actor, action, Jsonb(data))).fetchone()[0]


def test_sql_current_authorization_self_guard_validation_and_privileges(sql_connection):
    conn = sql_connection
    actor, other, user = seed(conn), seed(conn), seed(conn, 'USER')
    assert invoke(conn, actor, 'rol', {'id': str(other), 'rol': 'USER'})['rol'] == 'USER'
    assert conn.execute("select count(*) from public.usuarios where rol='ADMIN'").fetchone()[0] >= 1
    for who, data, error in [(actor, {'id': str(actor), 'rol': 'USER'}, 'AUTO_RETIRO'),
                             (other, {'id': str(user), 'rol': 'ADMIN'}, 'ADMIN_REQUERIDO'),
                             (actor, {'id': 'bad', 'rol': 'USER'}, 'USUARIO_INEXISTENTE'),
                             (actor, {'id': str(user), 'rol': 'bad'}, 'DATOS_USUARIO_INVALIDOS')]:
        with conn.transaction():
            with pytest.raises(Exception, match=error):
                with conn.transaction():
                    invoke(conn, who, 'rol', data)
    created = invoke(conn, actor, 'crear', {'nombre': ' New ', 'correo': f'{uuid4()}@EXAMPLE.test',
                                         'password_hash': 'scrypt:test', 'rol': 'ADMIN'})
    assert created['rol'] == 'ADMIN' and 'password_hash' not in created
    for role in ('anon', 'authenticated'):
        if conn.execute('select 1 from pg_roles where rolname=%s', (role,)).fetchone():
            assert not conn.execute("select has_function_privilege(%s,'public.administrar_usuario(uuid,text,jsonb)','EXECUTE')", (role,)).fetchone()[0]
    assert conn.execute("select proacl::text from pg_proc where oid='public.administrar_usuario(uuid,text,jsonb)'::regprocedure").fetchone()[0] is not None


def test_migration_is_idempotent_preserves_users_and_roles(sql_connection):
    conn = sql_connection
    seed(conn)
    before = conn.execute('select id,rol,password_hash from public.usuarios order by id').fetchall()
    # Strip transaction wrappers to keep this test inside the rollback fixture.
    migration = Path('database/migrations/009_administracion_usuarios.sql').read_text(encoding='utf-8')
    migration = migration.replace('begin;', '').replace('commit;', '')
    conn.execute(migration)
    conn.execute(migration)
    assert conn.execute('select id,rol,password_hash from public.usuarios order by id').fetchall() == before


def test_waiting_admin_is_rechecked_after_lock_before_mutation(isolated_database):
    import psycopg
    with psycopg.connect(isolated_database) as conn:
        first, second, target = seed(conn), seed(conn), seed(conn, 'USER')
    started = Event()

    def waiting_change():
        with psycopg.connect(isolated_database, application_name='usuarios_waiting_test') as waiting:
            started.set()
            with pytest.raises(Exception, match='ADMIN_REQUERIDO'):
                invoke(waiting, second, 'rol', {'id': str(first), 'rol': 'USER'})
            waiting.rollback()
            return waiting.execute('select rol from public.usuarios where id=%s', (target,)).fetchone()[0]

    with ThreadPoolExecutor(max_workers=1) as pool:
        with psycopg.connect(isolated_database) as winning:
            # Acquire the same transaction lock before the other request starts.
            winning.execute('select pg_advisory_xact_lock(91420261117)')
            future = pool.submit(waiting_change)
            assert started.wait(5)
            with psycopg.connect(isolated_database, autocommit=True) as observer:
                deadline = monotonic() + 5
                while monotonic() < deadline:
                    blocked = observer.execute("select count(*) from pg_stat_activity where application_name='usuarios_waiting_test' and wait_event_type='Lock' and wait_event='advisory'").fetchone()[0]
                    if blocked:
                        break
                    sleep(0.02)
                assert blocked == 1, 'The second real connection must be blocked on the shared role lock.'
            assert invoke(winning, first, 'rol', {'id': str(second), 'rol': 'USER'})['rol'] == 'USER'
            winning.commit()
        assert future.result(timeout=10) == 'USER'
    with psycopg.connect(isolated_database) as conn:
        assert conn.execute('select rol from public.usuarios where id=%s', (first,)).fetchone()[0] == 'ADMIN'
        assert conn.execute('select rol from public.usuarios where id=%s', (second,)).fetchone()[0] == 'USER'
