"""Passenger input is normalized before the transaction, never priced by clients."""
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest

from backend.app import create_app
from backend.models import ErrorAPI
from backend.repository import RepositorioSupabase
from backend.tests.test_api import FakeRepository, auth, login, registrar

FLIGHT = 'd0000000-0000-4000-8000-000000000001'
KEY = 'f0000000-0000-4000-8000-000000000001'
ORDER = 'e0000000-0000-4000-8000-000000000001'
BODY = dict(vuelo_id=FLIGHT, asientos=['2A', '1C'], clave_operacion=KEY)
PASSENGERS = [dict(asiento='2A', correo_usuario='  ANA@EXAMPLE.COM ', categoria='nino', maletas_adicionales=2),
              dict(asiento='1C', categoria='adulto_mayor', maletas_adicionales=0)]
NORMALIZED = [dict(asiento='1C', correo_usuario=None, categoria='adulto_mayor', maletas_adicionales=0),
              dict(asiento='2A', correo_usuario='ana@example.com', categoria='adulto', maletas_adicionales=2)]


class OrderRepository(FakeRepository):
    def __init__(self):
        super().__init__()
        self.calls = []
        self.previous = None

    def sistema_operar(self, action, user, data):
        self.calls.append((action, user, deepcopy(data)))
        if action == 'crear_pedido':
            if self.previous:
                raise ErrorAPI('conflicto', 'La operación ya existe.', 409)
            # The transaction supplies final prices; HTTP must not recalculate.
            return dict(id=ORDER, usuario_id=user, estado='pendiente_pago', session_id='cs_test_existing',
                        subtotal_centavos=25001, iva_centavos=3749, total_centavos=28750,
                        asientos=[dict(codigo='2A', total_centavos=28750)],
                        vence_en=(datetime.now(timezone.utc) + timedelta(minutes=30)).isoformat())
        if action == 'pedidos':
            return {'pedidos': [self.previous]}
        if action == 'pedido':
            return self.previous
        raise AssertionError(action)


@pytest.fixture
def api():
    repo = OrderRepository()
    provider = SimpleNamespace(ready=lambda: None)
    client = create_app(repo, 'x' * 40, stripe_provider=provider).test_client()
    registrar(client)
    return client, repo, auth(login(client).json['token'])


def post(api, body):
    client, _, headers = api
    return client.post('/api/sistema/pedidos', json=body, headers=headers)


def test_passenger_order_normalization_and_database_pricing(api):
    result = post(api, {**BODY, 'pasajeros': PASSENGERS})
    assert result.status_code == 201, result.json
    assert api[1].calls[0][2]['pasajeros'] == NORMALIZED
    assert api[1].calls[0][2]['asientos'] == ['1C', '2A']
    assert result.json['pedido']['total_centavos'] == 28750
    assert result.json['pedido']['subtotal_centavos'] == 25001
    assert result.json['pedido']['iva_centavos'] == 3749


def test_legacy_omission_keeps_original_rpc_identity(api):
    assert post(api, BODY).status_code == 201
    assert api[1].calls[0][2] == {**BODY, 'asientos': ['1C', '2A'], 'checkout_ui': 'embedded_card_v2'}


@pytest.mark.parametrize('passengers', [None, {}, [], PASSENGERS[:1], PASSENGERS + PASSENGERS[:1],
    [PASSENGERS[0], PASSENGERS[0]],
    [{**PASSENGERS[0], 'asiento': '3A'}, PASSENGERS[1]],
    [{**PASSENGERS[0], 'nombre': 'untrusted'}, PASSENGERS[1]],
    [{**PASSENGERS[0], 'total_centavos': 1}, PASSENGERS[1]],
    [{**PASSENGERS[0], 'categoria': 'otro'}, PASSENGERS[1]],
    [{**PASSENGERS[0], 'correo_usuario': 'bad'}, PASSENGERS[1]],
    [{**PASSENGERS[0], 'correo_usuario': 12}, PASSENGERS[1]]])
def test_invalid_passenger_shapes_create_no_hold(api, passengers):
    response = post(api, {**BODY, 'pasajeros': passengers})
    assert response.status_code == 400, response.json
    assert api[1].calls == []


@pytest.mark.parametrize('bags', [-1, True, False, 1.5, '2', None, 50000])
def test_invalid_baggage_creates_no_hold(api, bags):
    response = post(api, {**BODY, 'pasajeros': [{**PASSENGERS[0], 'maletas_adicionales': bags}, PASSENGERS[1]]})
    assert response.status_code == 400, response.json
    assert api[1].calls == []


@pytest.mark.parametrize('amount', ['total_centavos', 'precio', 'subtotal_centavos', 'iva_centavos', 'tarifas'])
def test_untrusted_amounts_are_rejected(api, amount):
    response = post(api, {**BODY, 'pasajeros': PASSENGERS, amount: 1})
    assert response.status_code == 400
    assert api[1].calls == []


def test_optional_values_and_technical_limit(api):
    response = post(api, {**BODY, 'pasajeros': [dict(asiento='2A', correo_usuario=' ', maletas_adicionales=49999),
                                              dict(asiento='1C', categoria='nino')]})
    assert response.status_code == 201, response.json
    assert api[1].calls[0][2]['pasajeros'] == [
        dict(asiento='1C', correo_usuario=None, categoria='nino', maletas_adicionales=0),
        dict(asiento='2A', correo_usuario=None, categoria='adulto', maletas_adicionales=49999)]


@pytest.mark.parametrize(('changes', 'status'), [({}, 201), ({'maletas_adicionales': 3}, 409),
                                               ({'correo_usuario': 'otro@example.com'}, 409)])
def test_retry_matches_complete_normalized_passenger_selection(api, changes, status):
    repo = api[1]
    selection = {**BODY, 'asientos': ['1C', '2A'], 'pasajeros': deepcopy(NORMALIZED)}
    repo.previous = dict(id=ORDER, clave_operacion=KEY, solicitud=selection, estado='pendiente_pago',
                         session_id='cs_test_existing', total_centavos=28750,
                         vence_en=(datetime.now(timezone.utc) + timedelta(minutes=30)).isoformat())
    response = post(api, {**BODY, 'pasajeros': [{**PASSENGERS[0], **changes}, PASSENGERS[1]]})
    assert response.status_code == status, response.json
    assert all(call[0] in ('crear_pedido', 'pedidos', 'pedido') for call in repo.calls)


def test_passengers_still_require_authentication(api):
    response = api[0].post('/api/sistema/pedidos', json={**BODY, 'pasajeros': PASSENGERS})
    assert response.status_code == 401
    assert api[1].calls == []


def test_assigned_user_error_is_safe_and_usable():
    def execute():
        raise RuntimeError('INVALIDO: Usuario asignado inexistente o inactivo SECRET_SQL email@example.test')
    repository = RepositorioSupabase(SimpleNamespace(rpc=lambda *_: SimpleNamespace(execute=execute)))
    with pytest.raises(ErrorAPI) as caught:
        repository.sistema_operar('crear_pedido', 'owner', {})
    assert caught.value.codigo == 'usuario_asignado_no_disponible'
    assert caught.value.estado_http == 400
    assert 'usuario activo' in caught.value.mensaje
    assert 'SECRET_SQL' not in caught.value.mensaje and 'email@' not in caught.value.mensaje
