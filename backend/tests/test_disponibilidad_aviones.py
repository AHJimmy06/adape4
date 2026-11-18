"""Read-only aircraft availability through the authenticated HTTP boundary."""
from copy import deepcopy

import pytest

from backend.app import create_app
from backend.tests.test_api import FakeRepository, auth, login, registrar

PLANE = 'b0000000-0000-4000-8000-000000000001'
ROUTE = 'c0000000-0000-4000-8000-000000000001'
FLIGHT = 'd0000000-0000-4000-8000-000000000001'


class AvailabilityRepository(FakeRepository):
    def __init__(self):
        super().__init__()
        self.calls = []
        self.catalogs = {
            'aviones': [{'id': PLANE, 'activo': True}],
            'rutas': [{'id': ROUTE, 'activo': True,
                       'origen': {'zona_horaria': 'America/Guayaquil'},
                       'destino': {'zona_horaria': 'Europe/Madrid'}}],
            'vuelos': [{'id': FLIGHT, 'codigo': 'AT104', 'activo': True,
                        'avion_id': PLANE, 'salida_en': '2026-12-01T04:00:00Z',
                        'llegada_en': '2026-12-01T07:00:00Z'}],
        }

    def sistema_operar(self, action, user, data):
        self.calls.append((action, user, data))
        assert action == 'listar' and data['admin'] is True
        return {data['recurso']: deepcopy(self.catalogs[data['recurso']])}


@pytest.fixture
def availability():
    repo = AvailabilityRepository()
    client = create_app(repo, 'x' * 40).test_client()
    registrar(client)
    token = login(client).json['token']
    user_headers = auth(token)
    repo.users['ana@example.com']['rol'] = 'ADMIN'
    return client, repo, user_headers


def get(client, headers, **data):
    return client.get('/api/sistema/disponibilidad-avion', headers=headers,
                      query_string={'avion_id': PLANE, 'ruta_id': ROUTE,
                                    'fecha': '2026-12-01', **data})


def test_endpoint_is_admin_and_does_not_mutate(availability):
    client, repo, headers = availability
    assert get(client, {}).status_code == 401
    repo.users['ana@example.com']['rol'] = 'USER'
    assert get(client, headers).status_code == 403
    assert repo.calls == []
    repo.users['ana@example.com']['rol'] = 'ADMIN'
    before = deepcopy(repo.catalogs)
    response = get(client, headers)
    assert response.status_code == 200
    assert response.headers['Cache-Control'] == 'no-store'
    assert repo.catalogs == before
    assert len(repo.calls) == 3


def test_overnight_previous_day_and_destination_timezones(availability):
    client, _, headers = availability
    result = get(client, headers)
    assert result.status_code == 200, result.json
    data = result.json
    assert data['zona_origen'] == 'America/Guayaquil'
    assert data['zona_destino'] == 'Europe/Madrid'
    assert data['disponible'] is None
    assert data['ocupados'][0]['inicio_local'] == '2026-11-30T23:00'
    assert data['ventanas'][0]['inicio_local'] == '2026-12-01T02:00'
    assert data['ventanas'][0]['inicio_destino_local'] == '2026-12-01T08:00'
    assert data['ventanas'][-1]['fin_local'] == '2026-12-03T00:00'


def test_edit_excludes_own_flight_and_inactive_other_planes(availability):
    client, repo, headers = availability
    repo.catalogs['vuelos'].extend([
        {**repo.catalogs['vuelos'][0], 'id': 'other', 'avion_id': 'other'},
        {**repo.catalogs['vuelos'][0], 'id': 'inactive', 'activo': False},
    ])
    data = get(client, headers, vuelo_id=FLIGHT).json
    assert data['ocupados'] == []
    assert data['ventanas'][0]['inicio_local'] == '2026-12-01T00:00'


@pytest.mark.parametrize(('departure', 'arrival', 'free'), [
    ('2026-12-01T01:59', '2026-12-01T09:00', False),
    ('2026-12-01T02:00', '2026-12-01T09:00', True),
])
def test_complete_interval_and_half_open_boundaries(availability, departure, arrival, free):
    client, _, headers = availability
    response = get(client, headers, salida_local=departure, llegada_local=arrival)
    assert response.status_code == 200, response.json
    assert response.json['disponible'] is free
    assert bool(response.json['conflictos']) is not free


def test_daily_series_checks_every_occurrence_and_keeps_dates(availability):
    client, repo, headers = availability
    repo.catalogs['vuelos'] = [{**repo.catalogs['vuelos'][0],
        'salida_en': '2026-12-02T15:00:00Z', 'llegada_en': '2026-12-02T16:00:00Z'}]
    response = get(client, headers, salida_local='2026-12-01T10:00',
                   llegada_local='2026-12-01T17:00', fecha_hasta='2026-12-03')
    assert response.status_code == 200, response.json
    assert response.json['disponible'] is False
    assert [c['fecha'] for c in response.json['conflictos']] == ['2026-12-02']


@pytest.mark.parametrize('params', [
    {'fecha': 'invalid'}, {'fecha': '9999-12-31'}, {'avion_id': 'bad'}, {'ruta_id': 'bad'},
    {'salida_local': '2026-12-01T02:00'},
    {'salida_local': '2026-12-01T02:00+00:00', 'llegada_local': '2026-12-01T09:00'},
    {'salida_local': '2026-12-02T02:00', 'llegada_local': '2026-12-02T09:00'},
    {'salida_local': '2026-12-01T02:00', 'llegada_local': '2026-12-01T01:00'},
    {'fecha_hasta': '2027-04-01'}, {'fecha_hasta': '2026-11-30'},
])
def test_invalid_requests_are_not_available(availability, params):
    client, _, headers = availability
    response = get(client, headers, **params)
    assert response.status_code == 400, response.json
    assert 'ventanas' not in response.json


def test_bad_persisted_utc_never_looks_free(availability):
    client, repo, headers = availability
    repo.catalogs['vuelos'][0]['salida_en'] = '2026-12-01T04:00:00'
    response = get(client, headers)
    assert response.status_code == 503
    assert 'ventanas' not in response.json


@pytest.mark.parametrize('local', ['2027-03-14T02:30', '2026-11-01T01:30'])
def test_nonexistent_and_ambiguous_dst_are_rejected(availability, local):
    client, repo, headers = availability
    repo.catalogs['rutas'][0]['origen']['zona_horaria'] = 'America/New_York'
    response = get(client, headers, fecha=local[:10], salida_local=local,
                   llegada_local=local[:10] + 'T16:00')
    assert response.status_code == 400, response.json


def test_merged_occupied_intervals_produce_only_free_complement(availability):
    client, repo, headers = availability
    repo.catalogs['vuelos'].append({**repo.catalogs['vuelos'][0], 'id': 'second',
        'salida_en': '2026-12-01T06:00:00Z', 'llegada_en': '2026-12-01T08:00:00Z'})
    data = get(client, headers).json
    assert len(data['ocupados']) == 2
    assert data['ventanas'][0]['inicio_local'] == '2026-12-01T03:00'
