"""Owner-scoped embedded checkout without real provider charges."""
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest

from backend.app import create_app
from backend.models import ErrorAPI
from backend.stripe_test import StripeTest
from backend.tests.test_api import FakeRepository
from backend.tests.test_sistema_integracion import core, create, FLIGHT


@pytest.fixture
def embedded_client(monkeypatch):
    monkeypatch.setenv('STRIPE_PUBLISHABLE_KEY', 'pk_test_simulated')
    repo = FakeRepository()
    provider = type('Provider', (), {'ready': lambda self: None})()
    app = create_app(repo, 'x' * 40, stripe_provider=provider)
    client = app.test_client()
    client.post('/api/usuarios/registro', json={'nombre': 'Cliente', 'correo': 'cliente@example.test', 'contrasena': 'password123'})
    login = client.post('/api/auth/login', json={'correo': 'cliente@example.test', 'contrasena': 'password123'})
    headers = {'Authorization': 'Bearer ' + login.json['token']}
    now = datetime.now(timezone.utc)
    order = dict(id=str(uuid4()), usuario_id='usuario-1', estado='pendiente_pago', session_id='cs_test_owned',
                 total_centavos=1000, creado_en=now.isoformat(), vence_en=(now + timedelta(minutes=30)).isoformat(),
                 asientos=[{'codigo': '1A'}])
    session = dict(id='cs_test_owned', livemode=False, mode='payment', currency='usd', amount_total=1000,
                   client_reference_id=order['id'], metadata=dict(app='aerotech', pedido_id=order['id'], usuario_id='usuario-1'),
                   status='open', payment_status='unpaid', ui_mode='embedded', client_secret='cs_test_owned_secret_example')
    def rpc(action, user, data):
        if action == 'pedido':
            if data['id'] != order['id'] or user != order['usuario_id']:
                raise ErrorAPI('no_encontrado', 'Pedido no encontrado.', 404)
            return deepcopy(order)
        raise AssertionError(action)
    repo.sistema_operar = rpc
    provider.retrieve = lambda ident: deepcopy(session)
    return client, headers, order, session


def test_embedded_checkout_owner_only_and_not_cacheable(embedded_client):
    client, headers, order, session = embedded_client
    path = '/api/sistema/pedidos/' + order['id'] + '/pago-embebido'
    assert client.post(path).status_code == 401
    assert client.post('/api/sistema/pedidos/' + str(uuid4()) + '/pago-embebido', headers=headers).status_code == 404
    response = client.post(path, headers=headers)
    assert response.status_code == 200, response.json
    assert response.json['client_secret'] == session['client_secret']
    assert response.json['publishable_key'] == 'pk_test_simulated'
    assert 'no-store' in response.headers['Cache-Control']
    assert not {'usuario_id', 'session_id', 'client_secret', 'payment_intent'} & response.json['pedido'].keys()


def test_embedded_checkout_never_exposes_secret_for_hosted_or_terminal(embedded_client):
    client, headers, order, session = embedded_client
    path = '/api/sistema/pedidos/' + order['id'] + '/pago-embebido'
    session['ui_mode'] = 'hosted'
    response = client.post(path, headers=headers)
    assert response.status_code == 409
    assert session['client_secret'] not in response.get_data(as_text=True)
    order['estado'] = 'pagado'
    assert client.post(path, headers=headers).status_code == 409


def test_embedded_checkout_requires_test_publishable_key(embedded_client, monkeypatch):
    client, headers, order, _ = embedded_client
    monkeypatch.setenv('STRIPE_PUBLISHABLE_KEY', 'pk_live_refused')
    assert client.post('/api/sistema/pedidos/' + order['id'] + '/pago-embebido', headers=headers).status_code == 503


def test_embedded_checkout_rejects_unbound_provider_secret(embedded_client):
    client, headers, order, session = embedded_client
    session['metadata']['usuario_id'] = 'foreign-user'
    # A mismatched provider response is never returned to the client.
    client.application.extensions['sistema'].rpc = lambda action, user=None, **data: deepcopy(order)
    response = client.post('/api/sistema/pedidos/' + order['id'] + '/pago-embebido', headers=headers)
    assert response.status_code == 409
    assert session['client_secret'] not in response.get_data(as_text=True)


def test_pre_rollout_idempotency_recovers_original_but_rejects_changed_seats(embedded_client):
    client, headers, order, _ = embedded_client
    selection = dict(vuelo_id=str(uuid4()), asientos=['1A'], clave_operacion=str(uuid4()))
    order['solicitud'] = selection.copy()
    system = client.application.extensions['sistema']
    def rpc(action, user=None, **data):
        if action == 'crear_pedido':
            raise ErrorAPI('conflicto', 'La clave ya pertenece a otra solicitud.', 409)
        if action == 'pedidos':
            return {'pedidos': [{'id': order['id'], 'clave_operacion': selection['clave_operacion']}]}
        if action == 'pedido':
            return deepcopy(order)
        raise AssertionError(action)
    system.rpc = rpc
    result = client.post('/api/sistema/pedidos', headers=headers, json=selection)
    assert result.status_code == 201, result.json
    assert result.json['pedido']['id'] == order['id']
    changed = {**selection, 'asientos': ['1C']}
    assert client.post('/api/sistema/pedidos', headers=headers, json=changed).status_code == 409


def test_sql_pending_is_held_not_reserved_until_provider_confirms(core, monkeypatch):
    conn, _, provider, _, client, _, headers = core
    monkeypatch.setenv('STRIPE_PUBLISHABLE_KEY', 'pk_test_simulated')
    order = create(client, headers[1], ['1A']).json['pedido']
    session = provider.sessions[order['id']]
    session.update(ui_mode='embedded', client_secret=session['id'] + '_secret_simulated')
    path = '/api/sistema/pedidos/' + order['id'] + '/pago-embebido'
    assert client.post(path, headers=headers[2]).status_code == 404
    assert client.post(path, headers=headers[1]).status_code == 200
    assert conn.execute('select count(*) from public.at_reservas').fetchone()[0] == 0
    seats = client.get(f'/api/sistema/vuelos/{FLIGHT}/asientos', headers=headers[1]).json['asientos']
    assert next(s for s in seats if s['codigo'] == '1A')['estado'] == 'retenido'
    assert create(client, headers[2], ['1A']).status_code == 409
    provider.pay(order['id'])
    assert client.post(path, headers=headers[1]).status_code == 409
    assert conn.execute('select count(*) from public.at_reservas').fetchone()[0] == 1
    seats = client.get(f'/api/sistema/vuelos/{FLIGHT}/asientos', headers=headers[1]).json['asientos']
    assert next(s for s in seats if s['codigo'] == '1A')['estado'] == 'ocupado'


def test_new_checkout_embeds_without_redirect_and_legacy_params_stay_stable(monkeypatch):
    monkeypatch.setenv('STRIPE_SECRET_KEY', 'sk_test_simulated')
    monkeypatch.setenv('STRIPE_WEBHOOK_SECRET', 'whsec_simulated')
    monkeypatch.setenv('PUBLIC_API_URL', 'https://example.invalid')
    captured = []
    sessions = type('Sessions', (), {'create': lambda self, params, **kw: captured.append((params, kw)) or {'id': 'cs_test_sim'}})()
    client = type('Client', (), {'v1': type('V1', (), {'checkout': type('Checkout', (), {'sessions': sessions})()})()})()
    provider = StripeTest(client)
    order = dict(id=str(uuid4()), usuario_id=str(uuid4()), total_centavos=1000,
                 creado_en=datetime.now(timezone.utc).isoformat(), asientos=[{'codigo': '1A'}])
    provider.checkout(order)
    legacy = deepcopy(captured[-1])
    provider.checkout(order)
    assert captured[-1] == legacy
    order['solicitud'] = {'checkout_ui': 'embedded'}
    provider.checkout(order)
    params, options = captured[-1]
    assert params['ui_mode'] == 'embedded'
    assert params['redirect_on_completion'] == 'never'
    assert not {'success_url', 'cancel_url', 'return_url'} & params.keys()
    assert params['payment_method_types'] == ['card']
