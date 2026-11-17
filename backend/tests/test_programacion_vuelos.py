"""Daily flights use real inventory and one atomic, replayable operation."""
from datetime import date, timedelta
from pathlib import Path
from uuid import uuid4

import pytest
from psycopg.types.json import Jsonb

from backend.models import ErrorAPI
from backend.vuelos_programacion import validate_programacion
from backend.app import create_app
from backend.tests.test_sistema_integracion import SQLRepository, FakeStripe


def payload(days=3):
    start = date.today() + timedelta(days=100)
    return dict(codigo='AT-DIARIO', ruta_id='c0000000-0000-4000-8000-000000000001',
                avion_id='b0000000-0000-4000-8000-000000000001',
                salida_local=f'{start}T09:00', llegada_local=f'{start}T10:00',
                tarifas=[dict(clase_codigo='EJEC', precio_centavos=10000),
                         dict(clase_codigo='ECO', precio_centavos=5000)],
                frecuencia='diaria', fecha_fin=str(start + timedelta(days=days-1)),
                clave_operacion=str(uuid4()))


@pytest.mark.parametrize('days', [0, 91])
def test_daily_range_is_explicit_and_bounded(days):
    with pytest.raises(ErrorAPI):
        validate_programacion(payload(days))


def test_daily_requires_frequency_and_operation():
    for changes in ({'frecuencia': 'semanal'}, {'clave_operacion': 'invalid'}):
        with pytest.raises(ErrorAPI):
            validate_programacion({**payload(), **changes})


def test_daily_reuses_catalog_validation():
    assert validate_programacion(payload())['frecuencia'] == 'diaria'
    with pytest.raises(ErrorAPI):
        validate_programacion({**payload(), 'tarifas': [{'clase_codigo': 'ECO', 'precio_centavos': 1}]})


@pytest.fixture
def scheduled(sql_connection):
    conn = sql_connection
    conn.execute(Path('database/migrations/010_programacion_vuelos.sql').read_text(encoding='utf-8'))
    admin, user = str(uuid4()), str(uuid4())
    for uid, role in ((admin, 'ADMIN'), (user, 'USER')):
        conn.execute('insert into public.usuarios(id,nombre,correo,password_hash,rol) values(%s,%s,%s,%s,%s)',
                     (uid, role, uid+'@example.test', 'test-only', role))
    return conn, admin, user


def rpc(conn, actor, data):
    return conn.execute('select public.sistema_operar(%s,%s,%s)',
                        ('programar', actor, Jsonb(data))).fetchone()[0]


def test_daily_occurrences_have_independent_inventory_and_replay(scheduled):
    conn, admin, _ = scheduled
    data = validate_programacion(payload())
    first = rpc(conn, admin, data)
    assert len(first['vuelos']) == 3
    assert len({v['id'] for v in first['vuelos']}) == 3
    assert all(v['asientos_disponibles'] == 36 and v['frecuencia'] == 'diaria' for v in first['vuelos'])
    assert [v['hora_salida'] for v in first['vuelos']] == ['09:00'] * 3
    assert rpc(conn, admin, data) == first
    count = conn.execute('select count(*) from public.at_vuelos').fetchone()[0]
    with pytest.raises(Exception, match='CONFLICTO'):
        with conn.transaction():
            rpc(conn, admin, {**data, 'codigo': 'CAMBIO'})
    assert conn.execute('select count(*) from public.at_vuelos').fetchone()[0] == count


def test_daily_collision_rolls_back_all_occurrences(scheduled):
    conn, admin, _ = scheduled
    data = validate_programacion(payload())
    last = {k: v for k, v in data.items() if k not in ('frecuencia', 'fecha_fin', 'clave_operacion')}
    last.update(codigo='AT-CHOQUE', salida_local=f"{data['fecha_fin']}T09:15", llegada_local=f"{data['fecha_fin']}T10:15")
    conn.execute('select public.sistema_operar(%s,%s,%s)', ('guardar', admin, Jsonb({'recurso': 'vuelos', 'datos': last})))
    before = conn.execute('select count(*) from public.at_vuelos').fetchone()[0]
    with pytest.raises(Exception, match='CONFLICTO'):
        with conn.transaction():
            rpc(conn, admin, data)
    assert conn.execute('select count(*) from public.at_vuelos').fetchone()[0] == before
    assert conn.execute('select count(*) from public.at_programaciones').fetchone()[0] == 0


def test_daily_sql_requires_admin_and_service_role(scheduled):
    conn, _, user = scheduled
    with pytest.raises(Exception, match='PROHIBIDO'):
        with conn.transaction():
            rpc(conn, user, validate_programacion(payload()))
    assert conn.execute("select has_function_privilege('anon','public.sistema_operar(text,uuid,jsonb)','execute')").fetchone()[0] is False
    assert conn.execute("select has_function_privilege('authenticated','public.sistema_operar(text,uuid,jsonb)','execute')").fetchone()[0] is False


def test_programacion_public_endpoint_roles_and_inventory(scheduled):
    conn, admin, user = scheduled
    from werkzeug.security import generate_password_hash
    conn.execute('update public.usuarios set password_hash=%s where id in (%s,%s)',
                 (generate_password_hash('password123'), admin, user))
    app = create_app(SQLRepository(conn), 'x' * 40, stripe_provider=FakeStripe())
    client = app.test_client()
    assert client.post('/api/sistema/programaciones', json=payload()).status_code == 401
    headers = []
    for uid in (admin, user):
        token = client.post('/api/auth/login', json={'correo': uid+'@example.test', 'contrasena': 'password123'}).json['token']
        headers.append({'Authorization': 'Bearer '+token})
    assert client.post('/api/sistema/programaciones', json=payload(), headers=headers[1]).status_code == 403
    response = client.post('/api/sistema/programaciones', json=payload(), headers=headers[0])
    assert response.status_code == 201, response.json
    assert response.json['programacion']['cantidad'] == 3
    flight = response.json['vuelos'][0]
    seats = client.get('/api/sistema/vuelos/'+flight['id']+'/asientos', headers=headers[1])
    assert seats.status_code == 200
    assert len(seats.json['asientos']) == 36


def test_migration_can_repeat_without_changing_existing_flights(scheduled):
    conn, admin, _ = scheduled
    result = rpc(conn, admin, validate_programacion(payload()))
    conn.execute(Path('database/migrations/010_programacion_vuelos.sql').read_text(encoding='utf-8'))
    assert conn.execute('select resultado from public.at_programaciones where id=%s', (result['programacion']['id'],)).fetchone()[0] == result
