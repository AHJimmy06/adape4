"""Arrival windows, generated flight numbers and anonymous catalog boundaries."""
from datetime import date, timedelta
from pathlib import Path
from uuid import uuid4

import pytest
from psycopg.types.json import Jsonb

from backend.models import ErrorAPI
from backend.sistema_validacion import validate_catalog
from backend.tests.test_sistema_integracion import core, FLIGHT, PLANE

AIRPORT = 'a0000000-0000-4000-8000-000000000002'
ROUTE = 'c0000000-0000-4000-8000-000000000001'


def flight(day=None, hour='09:00', arrival='10:00', plane=PLANE):
    day = day or date.today() + timedelta(days=100)
    return dict(ruta_id=ROUTE, avion_id=plane, salida_local=f'{day}T{hour}',
                llegada_local=f'{day}T{arrival}', tarifas=[
                    {'clase_codigo': 'EJEC', 'precio_centavos': 12000},
                    {'clase_codigo': 'ECO', 'precio_centavos': 5900}])


@pytest.fixture
def operations(core):
    conn = core[0]
    for name in ('010_programacion_vuelos.sql', '011_operaciones_aeropuertos.sql'):
        conn.execute(Path('database/migrations/' + name).read_text(encoding='utf-8'))
    yield core


def test_airport_window_validation():
    base = dict(iata='UIO', nombre='Airport', ciudad='Quito', pais='Ecuador',
                codigo_pais='EC', latitud=0, longitud=0, zona_horaria='America/Guayaquil')
    result = validate_catalog('aeropuertos', base)
    assert result['capacidad_aterrizajes'] == 10
    assert result['franja_minutos'] == 60
    for invalid in ({'capacidad_aterrizajes': 0}, {'capacidad_aterrizajes': True}, {'franja_minutos': 17}):
        with pytest.raises(ErrorAPI):
            validate_catalog('aeropuertos', {**base, **invalid})


def test_generated_flight_code_and_immutable_edit(operations):
    conn, _, _, _, client, _, headers = operations
    first = client.post('/api/sistema/vuelos', json=flight(), headers=headers[0])
    assert first.status_code == 201, first.json
    assert first.json['vuelo']['codigo'] == 'AT104'
    created = first.json['vuelo']
    edit = client.put('/api/sistema/vuelos/' + created['id'], headers=headers[0],
                      json={**flight(), 'codigo': 'MANUAL', 'version': created['version']})
    assert edit.status_code == 200, edit.json
    assert edit.json['vuelo']['codigo'] == created['codigo']


def test_capacity_same_window_and_next_boundary(operations):
    conn, _, _, _, client, users, headers = operations
    airport = conn.execute('select public.at_catalogo(%s,%s)', ('aeropuertos', AIRPORT)).fetchone()[0]
    data = {**airport, 'capacidad_aterrizajes': 1, 'franja_minutos': 60}
    assert client.put('/api/sistema/aeropuertos/' + AIRPORT, json=data, headers=headers[0]).status_code == 200
    plane = str(uuid4())
    conn.execute("insert into at_aviones(id,matricula,datos) select %s,'AT-SECOND',datos from at_aviones where id=%s", (plane, PLANE))
    assert client.post('/api/sistema/vuelos', json=flight(), headers=headers[0]).status_code == 201
    rejected = client.post('/api/sistema/vuelos', json=flight(hour='09:30', arrival='10:30', plane=plane), headers=headers[0])
    assert rejected.status_code == 409, rejected.json
    assert client.post('/api/sistema/vuelos', json=flight(hour='10:00', arrival='11:00', plane=plane), headers=headers[0]).status_code == 201
    available = client.get('/api/sistema/disponibilidad-aeropuerto', headers=headers[0], query_string={
        'aeropuerto_id': AIRPORT, 'llegada_local': flight()['llegada_local']})
    assert available.status_code == 200, available.json
    assert available.json['programados'] == 1 and available.json['disponibles'] == 0
    assert available.json['inicio_local'].endswith('10:00')


def test_public_cabin_does_not_touch_provider_or_leak_owner(operations):
    _, _, provider, _, client, _, headers = operations
    response = client.get(f'/api/sistema/vuelos/{FLIGHT}/asientos')
    assert response.status_code == 200, response.json
    assert len(response.json['asientos']) == 36
    assert all(s['es_mio'] is False and not {'id', 'pedido_id', 'usuario_id'} & s.keys() for s in response.json['asientos'])
    assert provider.sessions == {}
    assert client.post('/api/sistema/pedidos', json={}).status_code == 401
    assert client.get(f'/api/sistema/vuelos/{FLIGHT}/asientos', headers={'Authorization': 'Bearer invalid'}).status_code == 401


def test_range_is_inclusive_and_rejects_reversed(operations):
    _, _, _, _, client, _, headers = operations
    day = date.today() + timedelta(days=100)
    assert client.post('/api/sistema/vuelos', json=flight(day), headers=headers[0]).status_code == 201
    found = client.get('/api/sistema/vuelos', query_string={'fecha_desde': str(day), 'fecha_hasta': str(day)})
    assert found.status_code == 200 and len(found.json['vuelos']) == 1
    assert client.get('/api/sistema/vuelos', query_string={'fecha_desde': str(day), 'fecha_hasta': str(day-timedelta(days=1))}).status_code == 400


def test_daily_occurrences_get_sequential_numbers(operations):
    _, _, _, _, client, _, headers = operations
    data = flight()
    response = client.post('/api/sistema/programaciones', headers=headers[0], json={**data,
        'frecuencia': 'diaria', 'fecha_fin': str(date.fromisoformat(data['salida_local'][:10])+timedelta(days=2)),
        'clave_operacion': str(uuid4())})
    assert response.status_code == 201, response.json
    assert [v['codigo'] for v in response.json['vuelos']] == ['AT104', 'AT105', 'AT106']


def test_capacity_cannot_be_reduced_below_future_arrivals(operations):
    conn, _, _, _, client, _, headers = operations
    plane = str(uuid4())
    conn.execute("insert into at_aviones(id,matricula,datos) select %s,'AT-THIRD',datos from at_aviones where id=%s", (plane, PLANE))
    for data in (flight(), flight(hour='09:30', arrival='10:30', plane=plane)):
        assert client.post('/api/sistema/vuelos', json=data, headers=headers[0]).status_code == 201
    airport = conn.execute('select public.at_catalogo(%s,%s)', ('aeropuertos', AIRPORT)).fetchone()[0]
    response = client.put('/api/sistema/aeropuertos/' + AIRPORT, headers=headers[0],
                          json={**airport, 'capacidad_aterrizajes': 1})
    assert response.status_code == 409, response.json
    after = conn.execute('select public.at_catalogo(%s,%s)', ('aeropuertos', AIRPORT)).fetchone()[0]
    assert after == airport


def test_daily_collision_rolls_back_series_and_repeated_migration_preserves_data(operations):
    conn, _, _, _, client, _, headers = operations
    airport = conn.execute('select public.at_catalogo(%s,%s)', ('aeropuertos', AIRPORT)).fetchone()[0]
    assert client.put('/api/sistema/aeropuertos/' + AIRPORT, headers=headers[0],
                      json={**airport, 'capacidad_aterrizajes': 1}).status_code == 200
    plane = str(uuid4())
    conn.execute("insert into at_aviones(id,matricula,datos) select %s,'AT-FOURTH',datos from at_aviones where id=%s", (plane, PLANE))
    day = date.today() + timedelta(days=102)
    assert client.post('/api/sistema/vuelos', json=flight(day, plane=plane), headers=headers[0]).status_code == 201
    before = conn.execute('select count(*) from at_vuelos').fetchone()[0]
    data = {**flight(), 'frecuencia': 'diaria', 'fecha_fin': str(day), 'clave_operacion': str(uuid4())}
    response = client.post('/api/sistema/programaciones', json=data, headers=headers[0])
    assert response.status_code == 409, response.json
    assert conn.execute('select count(*) from at_vuelos').fetchone()[0] == before
    conn.execute(Path('database/migrations/011_operaciones_aeropuertos.sql').read_text(encoding='utf-8'))
    assert conn.execute('select count(*) from at_vuelos').fetchone()[0] == before
    assert conn.execute("select has_function_privilege('anon','public.sistema_operar(text,uuid,jsonb)','execute')").fetchone()[0] is False
    with conn.transaction():
        conn.execute('set local role service_role')
        assert conn.execute('select public.at_catalogo(%s,%s)', ('aeropuertos', AIRPORT)).fetchone()[0]['capacidad_aterrizajes'] == 1


def test_concurrent_capacity_and_number_generation(operations):
    from concurrent.futures import ThreadPoolExecutor
    import os
    import psycopg
    from psycopg.conninfo import make_conninfo
    conn, _, _, _, client, users, headers = operations
    airport = conn.execute('select public.at_catalogo(%s,%s)', ('aeropuertos', AIRPORT)).fetchone()[0]
    assert client.put('/api/sistema/aeropuertos/' + AIRPORT, headers=headers[0],
                      json={**airport, 'capacidad_aterrizajes': 1}).status_code == 200
    plane = str(uuid4())
    conn.execute("insert into at_aviones(id,matricula,datos) select %s,%s,datos from at_aviones where id=%s", (plane,'AT-CONCURRENT-'+plane[:8], PLANE))
    conn.commit()
    day = date.today()+timedelta(days=110)
    dsn = make_conninfo(os.environ['AEROTECH_TEST_DSN'], dbname=conn.info.dbname)
    def create(data):
        with psycopg.connect(dsn, autocommit=True) as other:
            try:
                result=other.execute('select public.sistema_operar(%s,%s,%s)',
                    ('guardar',users[0],Jsonb({'recurso':'vuelos','datos':validate_catalog('vuelos',data)}))).fetchone()[0]
                return result['codigo']
            except Exception as error:
                assert 'CONFLICTO:' in str(error)
                return 'conflicto'
    with ThreadPoolExecutor(max_workers=2) as executor:
        result=list(executor.map(create,[flight(day),flight(day,plane=plane)]))
    assert result.count('conflicto')==1
    with ThreadPoolExecutor(max_workers=2) as executor:
        result=list(executor.map(create,[flight(day+timedelta(days=1)),flight(day+timedelta(days=2),plane=plane)]))
    assert len(set(result))==2 and 'conflicto' not in result
