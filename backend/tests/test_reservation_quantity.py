from pathlib import Path
import re
import pytest
from test_api import api, auth, token_para


@pytest.mark.parametrize('quantity', [1, 2, 9, 10, 24, 30])
def test_reserva_cantidad_disponible_y_cancelacion(api, quantity):
    client, repo = api
    repo.flights[0]['asientos_disponibles'] = 30
    headers = auth(token_para(client))
    response = client.post('/api/reservas', json={'vuelo_id': 'vuelo-1', 'cantidad': quantity}, headers=headers)
    assert response.status_code == 201
    data = response.get_json()
    assert data['subtotal'] == 50 * quantity
    assert data['iva'] == 7.5 * quantity
    assert data['total'] == 57.5 * quantity
    assert repo.reservations[data['reserva_id']]['cantidad'] == quantity
    assert repo.flights[0]['asientos_disponibles'] == 30 - quantity
    response = client.delete(f"/api/reservas/{data['reserva_id']}", headers=headers)
    assert response.status_code == 200
    assert repo.flights[0]['asientos_disponibles'] == 30
    assert repo.reservations[data['reserva_id']]['estado'] == 'cancelada'


@pytest.mark.parametrize('quantity', [0, -1, True, False, 1.5, '10', 2147483648])
def test_rechaza_cantidad_invalida_sin_mutar(api, quantity):
    client, repo = api
    headers = auth(token_para(client))
    response = client.post('/api/reservas', json={'vuelo_id': 'vuelo-1', 'cantidad': quantity}, headers=headers)
    assert response.status_code == 400
    assert response.get_json()['error']['codigo'] == 'cantidad_invalida'
    assert repo.flights[0]['asientos_disponibles'] == 2
    assert repo.reservations == {}


@pytest.mark.parametrize('quantity', [31, 2147483647])
def test_stock_es_limite_sin_mutar(api, quantity):
    client, repo = api
    repo.flights[0]['asientos_disponibles'] = 30
    headers = auth(token_para(client))
    response = client.post('/api/reservas', json={'vuelo_id': 'vuelo-1', 'cantidad': quantity}, headers=headers)
    assert response.status_code == 409
    assert response.get_json()['error']['codigo'] == 'asientos_insuficientes'
    assert repo.flights[0]['asientos_disponibles'] == 30
    assert repo.reservations == {}


def test_migracion_solo_reemplaza_limite_y_rpc():
    root = Path(__file__).resolve().parents[2]
    migration = (root / 'database/migrations/004_reservas_disponibilidad.sql').read_text(encoding='utf-8').lower()
    schema = (root / 'database/schema.sql').read_text(encoding='utf-8').lower()
    assert migration.strip().startswith('begin;')
    assert migration.strip().endswith('commit;')
    assert 'drop constraint if exists reservas_cantidad_check' in migration
    assert 'add constraint reservas_cantidad_check check (cantidad >= 1)' in migration
    function = migration.split('create or replace function public.reservar_vuelo', 1)[1].split('$$;', 1)[0]
    assert 'p_cantidad > 9' not in function
    assert 'p_cantidad is null or p_cantidad < 1 then' in function
    assert 'and asientos_disponibles >= p_cantidad' in function
    assert 'subtotal_reserva + iva_reserva' in function
    assert 'round(subtotal_reserva * porcentaje_reserva / 100, 2)' in function
    outside = re.sub(r'as \$\$.*?\$\$;', '', migration, flags=re.S)
    assert not re.search(r'\b(update|delete|insert)\b', outside)
    assert 'from public, anon, authenticated' in migration
    assert 'to service_role' in migration
    assert 'cantidad integer not null check (cantidad >= 1)' in schema
    assert 'p_cantidad > 9' not in schema

