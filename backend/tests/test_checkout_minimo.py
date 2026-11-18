"""Versioned card-only Checkout options never alter legacy recovery payloads."""
from copy import deepcopy
from datetime import datetime, timezone
from types import SimpleNamespace
import pytest

from backend.stripe_test import StripeTest, STRIPE_API_VERSION
from backend.tests.test_pago_embebido import embedded_client  # noqa: F401
from backend.tests.test_stripe_sdk_simulacion import sdk_provider  # noqa: F401


def order(marker=None):
    result = dict(id='order', usuario_id='owner', total_centavos=2300,
                  creado_en=datetime.now(timezone.utc).isoformat(), asientos=[{'codigo': '1A'}])
    if marker:
        result['solicitud'] = dict(checkout_ui=marker)
    return result


def test_new_card_form_disables_link_and_optional_collection(monkeypatch):
    for key, value in dict(STRIPE_SECRET_KEY='sk_test_fake', STRIPE_WEBHOOK_SECRET='whsec_fake',
                           PUBLIC_API_URL='https://example.invalid').items():
        monkeypatch.setenv(key, value)
    captured = []
    sessions = SimpleNamespace(create=lambda params, **kwargs: captured.append((deepcopy(params), kwargs)) or {'id': 'cs_test_new'})
    provider = StripeTest(SimpleNamespace(v1=SimpleNamespace(checkout=SimpleNamespace(sessions=sessions))))
    provider.checkout(order('embedded_card_v2'))
    params, options = captured[-1]
    assert params['ui_mode'] == 'embedded_page'
    assert params['payment_method_types'] == ['card']
    assert params['wallet_options'] == {'link': {'display': 'never'}}
    assert params['billing_address_collection'] == 'auto'
    assert params['name_collection'] == {'individual': {'enabled': False}, 'business': {'enabled': False}}
    assert params['phone_number_collection'] == {'enabled': False}
    assert params['saved_payment_method_options'] == {'payment_method_save': 'disabled'}
    assert 'customer_email' not in params
    assert params['redirect_on_completion'] == 'never'
    assert not {'success_url', 'cancel_url', 'return_url', 'shipping_address_collection'} & params.keys()
    assert options['options']['idempotency_key'] == 'aerotech-checkout-order'


def test_sdk_encodes_new_options_but_keeps_legacy_payloads(sdk_provider):
    provider, state = sdk_provider
    old = order('embedded')
    provider.checkout(old)
    before = deepcopy(state['bodies'][-1])
    provider.checkout(old)
    assert state['bodies'][-1] == before
    assert 'wallet_options[link][display]' not in before
    assert 'customer_email' not in before
    assert before['ui_mode'] == ['embedded_page']
    new = order('embedded_card_v2')
    new['id'] = 'new-order'
    provider.checkout(new)
    body = state['bodies'][-1]
    assert body['wallet_options[link][display]'] == ['never']
    assert body['saved_payment_method_options[payment_method_save]'] == ['disabled']
    assert body['name_collection[individual][enabled]'] == ['false']
    assert body['phone_number_collection[enabled]'] == ['false']
    assert 'customer_email' not in body
    provider.checkout(new)
    assert state['bodies'][-1] == body
    assert state['requests'][-1][1] == state['requests'][-2][1]
    assert set(state['versions']) == {STRIPE_API_VERSION}


def test_existing_embedded_order_recovers_without_changing_its_request(embedded_client):
    client, headers, original, _ = embedded_client
    selection = dict(vuelo_id='d0000000-0000-4000-8000-000000000001', asientos=['1A'],
                     clave_operacion='e0000000-0000-4000-8000-000000000001')
    original['solicitud'] = {**selection, 'checkout_ui': 'embedded'}
    from backend.models import ErrorAPI
    system = client.application.extensions['sistema']

    def rpc(action, user=None, **data):
        if action == 'crear_pedido':
            raise ErrorAPI('conflicto', 'La clave ya pertenece a otra solicitud.', 409)
        if action == 'pedidos':
            return {'pedidos': [{'id': original['id'], 'clave_operacion': selection['clave_operacion']}]}
        if action == 'pedido':
            return deepcopy(original)
        raise AssertionError(action)

    system.rpc = rpc
    response = client.post('/api/sistema/pedidos', headers=headers, json=selection)
    assert response.status_code == 201, response.json
    assert response.json['pedido']['id'] == original['id']
    assert client.post('/api/sistema/pedidos', headers=headers,
                       json={**selection, 'asientos': ['1C']}).status_code == 409


@pytest.mark.parametrize(('change', 'status'), [('none', 201), ('bags', 409), ('category', 409),
                                              ('unknown', 409), ('unknown_passenger', 409)])
def test_legacy_sql_lexical_order_recovers_only_identical_complete_passengers(embedded_client, change, status):
    client, headers, original, _ = embedded_client
    selection = dict(vuelo_id='d0000000-0000-4000-8000-000000000001', asientos=['2A', '10A'],
                     clave_operacion='e0000000-0000-4000-8000-000000000001', pasajeros=[
                         dict(asiento='2A', correo_usuario=None, categoria='adulto_mayor', maletas_adicionales=2),
                         dict(asiento='10A', correo_usuario=None, categoria='nino', maletas_adicionales=1)])
    original['solicitud'] = {**deepcopy(selection), 'asientos': ['10A', '2A'],
                             'pasajeros': list(reversed(deepcopy(selection['pasajeros']))), 'checkout_ui': 'embedded'}
    if change == 'bags':
        selection['pasajeros'][0]['maletas_adicionales'] += 1
    elif change == 'category':
        selection['pasajeros'][0]['categoria'] = 'adulto'
    elif change == 'unknown':
        original['solicitud']['unknown_snapshot_field'] = 'must-not-disappear'
    elif change == 'unknown_passenger':
        original['solicitud']['pasajeros'][0]['unknown_snapshot_field'] = 'must-not-disappear'
    from backend.models import ErrorAPI
    system = client.application.extensions['sistema']

    def rpc(action, user=None, **data):
        if action == 'crear_pedido':
            raise ErrorAPI('conflicto', 'La clave ya pertenece a otra solicitud.', 409)
        if action == 'pedidos':
            return {'pedidos': [{'id': original['id'], 'clave_operacion': selection['clave_operacion']}]}
        if action == 'pedido':
            return deepcopy(original)
        raise AssertionError(action)

    system.rpc = rpc
    frozen = deepcopy(original)
    response = client.post('/api/sistema/pedidos', headers=headers, json=selection)
    assert response.status_code == status, response.json
    assert original == frozen
    if status == 201:
        assert response.json['pedido']['id'] == original['id']
