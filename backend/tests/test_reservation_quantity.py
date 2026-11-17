"""The legacy quantity write boundary is intentionally retired by migration008."""
from pathlib import Path
import re
import pytest
from test_api import api, auth, token_para


@pytest.mark.parametrize('quantity', [1,2,9,10,24,30,0,-1,True,False,1.5,'10',2147483648,31,2147483647])
def test_quantity_endpoint_retired_without_inventory_or_payment_side_effect(api, quantity):
    client, repo = api
    headers = auth(token_para(client))
    before = repo.flights[0]['asientos_disponibles']
    response = client.post('/api/reservas', json={'vuelo_id':'vuelo-1','cantidad':quantity}, headers=headers)
    assert response.status_code == 410
    assert response.json['error']['codigo'] == 'flujo_retirado'
    assert repo.flights[0]['asientos_disponibles'] == before
    assert not repo.reservations


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

