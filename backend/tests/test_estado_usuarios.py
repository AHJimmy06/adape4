"""Account deactivation is reversible, but previous sessions stay revoked."""
from pathlib import Path
from uuid import uuid4

import pytest

from backend.tests.test_api import api, auth, login, token_para
from backend.tests.test_roles import admin_token
from backend.tests.test_sistema_integracion import core, create


def test_deactivation_rejects_login_and_existing_session_until_new_login(api):
    client, repo = api
    admin = admin_token(client, repo)
    old = token_para(client, 'beto@example.com')
    path = '/api/admin/usuarios/usuario-2/estado'
    assert client.put(path, json={'activo': False}, headers=auth(admin)).status_code == 200
    assert login(client, correo='beto@example.com').status_code == 401
    assert client.get('/api/auth/perfil', headers=auth(old)).status_code == 401
    assert client.put(path, json={'activo': True}, headers=auth(admin)).status_code == 200
    assert client.get('/api/auth/perfil', headers=auth(old)).status_code == 401
    fresh = login(client, correo='beto@example.com')
    assert fresh.status_code == 200
    assert client.get('/api/auth/perfil', headers=auth(fresh.json['token'])).status_code == 200


def test_state_requires_admin_boolean_and_no_self_deactivation(api):
    client, repo = api
    admin = admin_token(client, repo)
    user = token_para(client, 'beto@example.com')
    path = '/api/admin/usuarios/usuario-2/estado'
    assert client.put(path, json={'activo': False}).status_code == 401
    assert client.put(path, json={'activo': False}, headers=auth(user)).status_code == 403
    for value in ('false', 0, None):
        assert client.put(path, json={'activo': value}, headers=auth(admin)).status_code == 400
    assert client.put('/api/admin/usuarios/usuario-1/estado', json={'activo': False}, headers=auth(admin)).status_code == 400
    assert repo.users['ana@example.com'].get('activo', True)


def test_public_signup_cannot_force_account_state_or_access_generation(api):
    client, repo = api
    response = client.post('/api/usuarios/registro', json={
        'nombre': 'Nueva', 'correo': 'nueva@example.test', 'contrasena': 'ClaveSegura123',
        'rol': 'ADMIN', 'activo': False, 'version_acceso': 99,
    })
    assert response.status_code == 201
    assert response.json['usuario']['activo'] is True
    assert response.json['usuario']['rol'] == 'USER'
    assert 'version_acceso' not in response.json['usuario']


@pytest.fixture
def state_db(sql_connection):
    conn = sql_connection
    migration = Path('database/migrations/012_estado_usuarios.sql').read_text(encoding='utf8')
    conn.execute(migration.replace('begin;', '').replace('commit;', ''))
    users = []
    for role in ('ADMIN', 'ADMIN', 'USER'):
        uid = str(uuid4())
        conn.execute('insert into usuarios(id,nombre,correo,password_hash,rol) values(%s,%s,%s,%s,%s)',
                     (uid, role, uid+'@example.test', 'scrypt:test', role))
        users.append(uid)
    return conn, users


def invoke(conn, actor, action, data):
    from psycopg.types.json import Jsonb
    return conn.execute('select administrar_usuario(%s,%s,%s)', (actor, action, Jsonb(data))).fetchone()[0]


def test_sql_state_preserves_data_and_serializes_admin_guards(state_db):
    conn, (admin, other, user) = state_db
    before = conn.execute('select id,rol,password_hash from usuarios order by id').fetchall()
    result = invoke(conn, admin, 'estado', {'id': other, 'activo': False})
    assert result['activo'] is False
    assert conn.execute('select version_acceso from usuarios where id=%s', (other,)).fetchone()[0] == 1
    for actor, action, data, error in [
        (other, 'estado', {'id': user, 'activo': False}, 'ADMIN_REQUERIDO'),
        (admin, 'estado', {'id': admin, 'activo': False}, 'AUTO_DESACTIVACION'),
        (admin, 'rol', {'id': admin, 'rol': 'USER'}, 'AUTO_RETIRO'),
    ]:
        with pytest.raises(Exception, match=error):
            with conn.transaction():
                invoke(conn, actor, action, data)
    assert invoke(conn, admin, 'estado', {'id': other, 'activo': True})['activo'] is True
    assert conn.execute('select id,rol,password_hash from usuarios order by id').fetchall() == before
    for role in ('anon', 'authenticated'):
        assert not conn.execute("select has_function_privilege(%s,'public.administrar_usuario(uuid,text,jsonb)','execute')", (role,)).fetchone()[0]


def test_sql_state_repeat_is_noop_and_public_signup_defaults_active(state_db):
    conn, (admin, _, user) = state_db
    assert conn.execute('select activo from usuarios where id=%s', (user,)).fetchone()[0] is True
    invoke(conn, admin, 'estado', {'id': user, 'activo': False})
    invoke(conn, admin, 'estado', {'id': user, 'activo': False})
    assert conn.execute('select version_acceso from usuarios where id=%s', (user,)).fetchone()[0] == 1
    migration = Path('database/migrations/012_estado_usuarios.sql').read_text(encoding='utf8')
    conn.execute(migration.replace('begin;', '').replace('commit;', ''))
    assert conn.execute('select activo,version_acceso from usuarios where id=%s', (user,)).fetchone() == (False, 1)


def test_disabled_customer_cannot_use_api_but_verified_webhook_settles_paid_order(core):
    conn, repo, provider, _, client, users, headers = core
    migration = Path('database/migrations/012_estado_usuarios.sql').read_text(encoding='utf8')
    conn.execute(migration.replace('begin;', '').replace('commit;', ''))
    original_lookup = repo.buscar_usuario_por_id
    def lookup(uid):
        result = original_lookup(uid)
        if result:
            active, version = conn.execute('select activo,version_acceso from usuarios where id=%s', (uid,)).fetchone()
            result.update(activo=active, version_acceso=version)
        return result
    repo.buscar_usuario_por_id = lookup
    repo.administrar_usuario = lambda actor, action, data: invoke(conn, actor, action, data)
    order = create(client, headers[1], ['1A']).json['pedido']
    disabled = client.put('/api/admin/usuarios/'+users[1]+'/estado', json={'activo': False}, headers=headers[0])
    assert disabled.status_code == 200, disabled.json
    assert client.get('/api/auth/perfil', headers=headers[1]).status_code == 401
    assert client.get('/api/sistema/pedidos', headers=headers[1]).status_code == 401
    provider.pay(order['id'])
    session = provider.sessions[order['id']]
    event = dict(id='evt_state_paid', type='checkout.session.completed', livemode=False,
                 data={'object': session})
    response = client.post('/api/stripe/webhook', json=event,
                           headers={'Stripe-Signature': 'verified-test-signature'})
    assert response.status_code == 200, response.json
    assert conn.execute('select count(*) from at_reservas where pedido_id=%s', (order['id'],)).fetchone()[0] == 1
    assert conn.execute('select estado from at_pedidos where id=%s', (order['id'],)).fetchone()[0] == 'pagado'


def test_sql_disabled_actor_cannot_mutate_catalogs(state_db):
    conn, (admin, other, _) = state_db
    invoke(conn, admin, 'estado', {'id': other, 'activo': False})
    from psycopg.types.json import Jsonb
    with pytest.raises(Exception, match='PROHIBIDO'):
        with conn.transaction():
            conn.execute('select sistema_operar(%s,%s,%s)', ('guardar', other, Jsonb({'recurso': 'aviones', 'datos': {}})))


def test_concurrent_admin_deactivations_recheck_actor_after_wait(isolated_database):
    import psycopg
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier
    ids = [str(uuid4()), str(uuid4())]
    with psycopg.connect(isolated_database) as conn:
        migration = Path('database/migrations/012_estado_usuarios.sql').read_text(encoding='utf8')
        conn.execute(migration)
        for uid in ids:
            conn.execute('insert into usuarios(id,nombre,correo,password_hash,rol) values(%s,%s,%s,%s,%s)',
                         (uid, 'Admin', uid+'@example.test', 'scrypt:test', 'ADMIN'))
    barrier = Barrier(2)
    def disable(index):
        with psycopg.connect(isolated_database) as conn:
            barrier.wait(5)
            try:
                invoke(conn, ids[index], 'estado', {'id': ids[1-index], 'activo': False})
                conn.commit()
                return 'ok'
            except psycopg.Error as error:
                assert 'ADMIN_REQUERIDO' in str(error)
                conn.rollback()
                return 'denegado'
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(disable, (0, 1)))
    assert sorted(results) == ['denegado', 'ok']
    with psycopg.connect(isolated_database) as conn:
        assert conn.execute('select count(*) from usuarios where id=any(%s::uuid[]) and activo', (ids,)).fetchone()[0] == 1
