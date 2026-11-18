"""Regression probes across airport capacity, guest browsing and account state."""
from pathlib import Path
from datetime import date, timedelta
from uuid import uuid4
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
import os
import pytest
import psycopg
from psycopg.conninfo import make_conninfo
from psycopg.types.json import Jsonb
from backend.tests.conftest import isolated_database, sql_connection
from backend.tests.test_sistema_integracion import core, create, FLIGHT, PLANE
from backend.tests.test_operaciones_capacidad import flight, AIRPORT
from backend.sistema_validacion import validate_catalog

@pytest.fixture
def complete(core):
    conn = core[0]
    for name in ('010_programacion_vuelos.sql', '011_operaciones_aeropuertos.sql', '012_estado_usuarios.sql'):
        conn.execute(Path('database/migrations/' + name).read_text(encoding='utf8'))
    return core

def test_integracion_120_minute_civil_boundary_and_atomic_failed_update(complete):
    conn, repo, provider, app, client, users, h = complete
    airport = conn.execute('select at_catalogo(%s,%s)', ('aeropuertos', AIRPORT)).fetchone()[0]
    r = client.put('/api/sistema/aeropuertos/' + AIRPORT, headers=h[0], json={**airport, 'capacidad_aterrizajes': 1, 'franja_minutos': 120})
    assert r.status_code == 200, r.json
    plane = str(uuid4())
    conn.execute('insert into at_aviones(id,matricula,datos) select %s,%s,datos from at_aviones where id=%s', (plane, 'OWN-' + plane[:8], PLANE))
    day = date.today() + timedelta(days=130)
    a = client.post('/api/sistema/vuelos', headers=h[0], json=flight(day, hour='08:00', arrival='09:59'))
    assert a.status_code == 201, a.json
    b = client.post('/api/sistema/vuelos', headers=h[0], json=flight(day, hour='09:00', arrival='10:00', plane=plane))
    assert b.status_code == 201, b.json
    aid = a.json['vuelo']['id']
    before = conn.execute('select row_to_json(v) from at_vuelos v where id=%s', (aid,)).fetchone()[0]
    update = {**flight(day, hour='08:00', arrival='10:01'), 'version': a.json['vuelo']['version']}
    r = client.put('/api/sistema/vuelos/' + aid, headers=h[0], json=update)
    assert r.status_code == 409, r.json
    assert conn.execute('select row_to_json(v) from at_vuelos v where id=%s', (aid,)).fetchone()[0] == before
    preview = client.get('/api/sistema/disponibilidad-aeropuerto', headers=h[0], query_string={'aeropuerto_id': AIRPORT, 'llegada_local': str(day) + 'T10:00'})
    assert preview.status_code == 200, preview.json
    assert preview.json['inicio_local'] == str(day) + 'T10:00' and preview.json['fin_local'] == str(day) + 'T12:00' and (preview.json['disponibles'] == 0)

def test_integracion_guest_occupied_map_does_not_reconcile_or_disclose(complete):
    conn, repo, provider, app, client, users, h = complete
    order = create(client, h[1], ['1A']).json['pedido']
    before = conn.execute('select row_to_json(p) from at_pedidos p order by id').fetchall()
    provider.down = True
    seats = client.get('/api/sistema/vuelos/' + FLIGHT + '/asientos')
    assert seats.status_code == 200, seats.json
    assert next((s for s in seats.json['asientos'] if s['codigo'] == '1A'))['estado'] != 'libre'

    def keys(obj):
        if isinstance(obj, dict):
            for k, v in obj.items():
                yield k
                yield from keys(v)
        elif isinstance(obj, list):
            for v in obj:
                yield from keys(v)
    assert not {'pedido_id', 'usuario_id', 'session_id', 'payment_intent', 'client_secret'} & set(keys(seats.json))
    for path in ['/api/sistema/pedidos', '/api/sistema/pedidos/' + order['id'], '/api/sistema/reservas']:
        assert client.get(path).status_code == 401, path
    assert client.post('/api/sistema/pedidos', json={'vuelo_id': FLIGHT, 'asientos': ['1C'], 'clave_operacion': str(uuid4())}).status_code == 401
    assert conn.execute('select row_to_json(p) from at_pedidos p order by id').fetchall() == before
    assert len(provider.sessions) == 1

def test_integracion_filter_exact_range_and_route_intersection(complete):
    conn, repo, provider, app, client, users, h = complete
    day = date.today() + timedelta(days=140)
    for offset in range(3):
        r = client.post('/api/sistema/vuelos', headers=h[0], json=flight(day + timedelta(days=offset)))
        assert r.status_code == 201, r.json
    for offset in range(3):
        r = client.get('/api/sistema/vuelos', query_string={'fecha_desde': str(day), 'fecha_hasta': str(day + timedelta(days=2)), 'fecha': str(day + timedelta(days=offset)), 'destino_id': AIRPORT, 'origen_id': 'a0000000-0000-4000-8000-000000000001'})
        assert r.status_code == 200, r.json
        assert len(r.json['vuelos']) == 1, r.json
    for q in [{'fecha_desde': str(day)}, {'fecha_hasta': str(day)}, {'fecha': '2026-99-01'}, {'fecha_desde': str(day + timedelta(days=1)), 'fecha_hasta': str(day)}]:
        assert client.get('/api/sistema/vuelos', query_string=q).status_code == 400, q

def test_integracion_mixed_capacity_reduction_vs_arrival_serializes(complete):
    conn, repo, provider, app, client, users, h = complete
    day = date.today() + timedelta(days=150)
    a = client.post('/api/sistema/vuelos', headers=h[0], json=flight(day))
    assert a.status_code == 201, a.json
    plane = str(uuid4())
    conn.execute('insert into at_aviones(id,matricula,datos) select %s,%s,datos from at_aviones where id=%s', (plane, 'RACE-' + plane[:8], PLANE))
    airport = conn.execute('select at_catalogo(%s,%s)', ('aeropuertos', AIRPORT)).fetchone()[0]
    conn.commit()
    dsn = make_conninfo(os.environ['AEROTECH_TEST_DSN'], dbname=conn.info.dbname)
    gate = Barrier(2)

    def task(i):
        with psycopg.connect(dsn) as other:
            gate.wait(5)
            payload = {'recurso': 'aeropuertos', 'id': AIRPORT, 'datos': validate_catalog('aeropuertos', {**airport, 'capacidad_aterrizajes': 1}, update=True)} if i == 0 else {'recurso': 'vuelos', 'datos': validate_catalog('vuelos', flight(day, hour='09:15', arrival='10:15', plane=plane))}
            try:
                other.execute('select sistema_operar(%s,%s,%s)', ('guardar', users[0], Jsonb(payload)))
                other.commit()
                return 'ok'
            except psycopg.Error as e:
                assert 'CONFLICTO:' in str(e), str(e)
                other.rollback()
                return 'conflict'
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(task, [0, 1]))
    assert sorted(results) == ['conflict', 'ok'], results
    cap = conn.execute('select at_catalogo(%s,%s)', ('aeropuertos', AIRPORT)).fetchone()[0]['capacidad_aterrizajes']
    count = conn.execute('select count(*) from at_vuelos where llegada_en::date=%s', (day,)).fetchone()[0]
    assert count <= cap

def test_integracion_disabled_reactivated_old_jwt_and_signed_settlement_with_all_migrations(complete):
    conn, repo, provider, app, client, users, h = complete
    for attribute in ['buscar_usuario_por_id', 'buscar_usuario_por_correo']:
        original = getattr(repo, attribute)

        def lookup(value, original=original):
            result = original(value)
            if result:
                active, generation = conn.execute('select activo,version_acceso from usuarios where id=%s', (result['id'],)).fetchone()
                result.update(activo=active, version_acceso=generation)
            return result
        setattr(repo, attribute, lookup)
    repo.administrar_usuario = lambda actor, action, data: conn.execute('select administrar_usuario(%s,%s,%s)', (actor, action, Jsonb(data))).fetchone()[0]
    order = create(client, h[1], ['1A']).json['pedido']
    assert client.put('/api/admin/usuarios/' + users[1] + '/estado', headers=h[0], json={'activo': False}).status_code == 200
    assert client.post('/api/auth/login', json={'correo': users[1] + '@example.test', 'contrasena': 'password123'}).status_code == 401
    assert client.get('/api/auth/perfil', headers=h[1]).status_code == 401
    provider.pay(order['id'])
    event = {'id': 'evt_own_combined', 'type': 'checkout.session.completed', 'livemode': False, 'data': {'object': provider.sessions[order['id']]}}
    assert client.post('/api/stripe/webhook', json=event, headers={'Stripe-Signature': 'wrong'}).status_code == 400
    assert conn.execute('select estado from at_pedidos where id=%s', (order['id'],)).fetchone()[0] != 'pagado'
    r = client.post('/api/stripe/webhook', json=event, headers={'Stripe-Signature': 'verified-test-signature'})
    assert r.status_code == 200, r.json
    assert conn.execute('select estado from at_pedidos where id=%s', (order['id'],)).fetchone()[0] == 'pagado'
    assert conn.execute('select count(*) from at_reservas where pedido_id=%s', (order['id'],)).fetchone()[0] == 1
    assert client.put('/api/admin/usuarios/' + users[1] + '/estado', headers=h[0], json={'activo': True}).status_code == 200
    assert client.get('/api/auth/perfil', headers=h[1]).status_code == 401
    fresh = client.post('/api/auth/login', json={'correo': users[1] + '@example.test', 'contrasena': 'password123'})
    assert fresh.status_code == 200, fresh.json
    assert client.get('/api/auth/perfil', headers={'Authorization': 'Bearer ' + fresh.json['token']}).status_code == 200

def test_integracion_all_migrations_daily_numbers_and_concurrent_last_admin(complete):
    conn, repo, provider, app, client, users, h = complete
    import re
    numbers = [int(match.group(1))
               for (code,) in conn.execute('select codigo from at_vuelos').fetchall()
               if (match := re.match(r'^AT([0-9]+)(?:-|$)', code))]
    next_number = max(numbers, default=103) + 1
    d = date.today() + timedelta(days=170)
    data = {**flight(d), 'frecuencia': 'diaria', 'fecha_fin': str(d + timedelta(days=1)), 'clave_operacion': str(uuid4())}
    r = client.post('/api/sistema/programaciones', json=data, headers=h[0])
    assert r.status_code == 201, r.json
    codes = [v['codigo'] for v in r.json['vuelos']]
    assert codes == [f'AT{next_number}', f'AT{next_number + 1}'], codes
    second = str(uuid4())
    conn.execute('insert into usuarios(id,nombre,correo,password_hash,rol) values(%s,%s,%s,%s,%s)', (second, 'Other', second + '@example.test', 'scrypt:test', 'ADMIN'))
    conn.commit()
    dsn = make_conninfo(os.environ['AEROTECH_TEST_DSN'], dbname=conn.info.dbname)
    gate = Barrier(2)
    ids = [users[0], second]

    def race(i):
        with psycopg.connect(dsn) as other:
            gate.wait(5)
            try:
                other.execute('select administrar_usuario(%s,%s,%s)', (ids[i], 'estado', Jsonb({'id': ids[1 - i], 'activo': False})))
                other.commit()
                return 'ok'
            except psycopg.Error as error:
                assert 'ADMIN_REQUERIDO' in str(error)
                other.rollback()
                return 'denied'
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(race, [0, 1]))
    assert sorted(results) == ['denied', 'ok'], results
    assert conn.execute("select count(*) from usuarios where activo and rol='ADMIN' and id=any(%s::uuid[])", (ids,)).fetchone()[0] == 1
