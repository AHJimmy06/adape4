"""Exercise the installed Stripe SDK against a bounded local HTTP simulator."""
import hashlib
import hmac
import json
import socket
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs
from uuid import uuid4

import pytest
import stripe

from backend.models import ErrorAPI
from backend.stripe_test import StripeTest
from backend.tests.test_sistema_integracion import core, create, FLIGHT


@pytest.fixture
def sdk_provider(monkeypatch):
    monkeypatch.setenv('STRIPE_SECRET_KEY','sk_test_local_simulation_only')
    monkeypatch.setenv('STRIPE_WEBHOOK_SECRET','whsec_local_simulation_only')
    monkeypatch.setenv('PUBLIC_API_URL','https://example.invalid')
    monkeypatch.setenv('STRIPE_PUBLISHABLE_KEY','pk_test_local_simulation_only')
    state = dict(sessions={}, refunds={}, keys={}, disconnect_checkout=False, disconnect_refund=False, requests=[], versions=[], bodies=[])
    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args):
            pass
        def reply(self, data):
            payload = json.dumps(data).encode()
            self.send_response(200)
            self.send_header('Content-Type','application/json')
            self.send_header('Content-Length',str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        def do_POST(self):
            body = parse_qs(self.rfile.read(int(self.headers['Content-Length'])).decode())
            get = lambda key: body[key][0]
            key = self.headers.get('Idempotency-Key')
            state['requests'].append((self.path,key))
            state['versions'].append(self.headers.get('Stripe-Version'))
            state['bodies'].append(body)
            if key in state['keys']:
                return self.reply(state['keys'][key])
            if self.path == '/v1/checkout/sessions':
                ident='cs_test_'+uuid4().hex
                result=dict(id=ident,object='checkout.session',livemode=False,mode='payment',currency='usd',
                   amount_total=int(get('line_items[0][price_data][unit_amount]')),status='open',payment_status='unpaid',
                   payment_intent=None,client_reference_id=get('client_reference_id'),expires_at=int(get('expires_at')),
                   metadata={k:get('metadata['+k+']') for k in ('app','pedido_id','usuario_id')},url='https://checkout.stripe.com/c/pay/'+ident)
                if body.get('ui_mode') == ['embedded']:
                    result.update(ui_mode='embedded', client_secret=ident+'_secret_simulated', url=None)
                state['sessions'][ident]=result
                flag='disconnect_checkout'
            elif self.path == '/v1/refunds':
                ident='re_'+uuid4().hex
                result=dict(id=ident,object='refund',currency='usd',status='succeeded',amount=int(get('amount')),
                    payment_intent=get('payment_intent'),metadata={k:get('metadata['+k+']') for k in ('app','cancelacion_id','pedido_id')})
                state['refunds'][ident]=result
                flag='disconnect_refund'
            else:
                self.send_error(404)
                return
            state['keys'][key]=result
            if state[flag]:
                state[flag]=False
                self.connection.shutdown(socket.SHUT_RDWR)
                self.connection.close()
                return
            self.reply(result)
        def do_GET(self):
            ident=self.path.split('/')[-1]
            result=state['sessions'].get(ident) or state['refunds'].get(ident)
            if result:
                self.reply(result)
            else:
                self.send_error(404)
    server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
    thread=threading.Thread(target=server.serve_forever,daemon=True)
    thread.start()
    original_client = stripe.StripeClient
    def local_client(api_key, **options):
        # Exercise the production constructor; substitute transport only, never
        # its API version or Checkout parameters.
        options.update(max_network_retries=0, http_client=stripe.RequestsClient(timeout=2))
        return original_client(api_key, base_addresses={'api': f'http://127.0.0.1:{server.server_port}'}, **options)
    monkeypatch.setattr(stripe, 'StripeClient', local_client)
    provider = StripeTest()
    provider.ready()
    yield provider, state
    server.shutdown()
    server.server_close()
    thread.join(timeout=3)


def test_sdk_checkout_unknown_after_write_recovers_same_session(core,sdk_provider):
    conn,repo,_,app,client,users,h=core
    provider,state=sdk_provider
    app.extensions['sistema'].provider=provider
    state['disconnect_checkout']=True
    key=str(uuid4())
    first=create(client,h[1],['1A'],key)
    assert first.status_code == 503,first.json
    row=conn.execute('select id,estado,session_id from public.at_pedidos').fetchone()
    assert row[1:] == ('preparando_pago',None)
    assert conn.execute('select count(*) from public.at_asientos where pedido_id=%s',(row[0],)).fetchone()[0] == 1
    second=create(client,h[1],['1A'],key)
    assert second.status_code == 201,second.json
    assert len(state['sessions']) == 1
    assert state['requests'][0][1] == state['requests'][1][1] == 'aerotech-checkout-'+str(row[0])
    assert second.json['pedido']['estado'] == 'pendiente_pago'


def test_sdk_refund_unknown_after_write_recovers_exact_amount(core,sdk_provider):
    conn,repo,_,app,client,users,h=core
    provider,state=sdk_provider
    app.extensions['sistema'].provider=provider
    order=create(client,h[1],['1A']).json['pedido']
    session=next(iter(state['sessions'].values()))
    session.update(status='complete',payment_status='paid',payment_intent='pi_simulated_verified')
    paid=client.get('/api/sistema/pedidos/'+order['id'],headers=h[1])
    assert paid.status_code == 200,paid.json
    rid=paid.json['pedido']['reserva_id']
    state['disconnect_refund']=True
    key=str(uuid4())
    first=client.post(f'/api/sistema/reservas/{rid}/cancelaciones',headers=h[1],json=dict(asientos=['1A'],clave_operacion=key))
    assert first.status_code == 503,first.json
    assert conn.execute('select count(*) from public.at_asientos where pedido_id=%s',(order['id'],)).fetchone()[0] == 1
    second=client.post(f'/api/sistema/reservas/{rid}/cancelaciones',headers=h[1],json=dict(asientos=['1A'],clave_operacion=key))
    assert second.status_code == 200,second.json
    assert len(state['refunds']) == 1
    assert second.json['reserva']['reembolsado_centavos'] == order['total_centavos']
    assert conn.execute('select count(*) from public.at_asientos where pedido_id=%s',(order['id'],)).fetchone()[0] == 0


def test_sdk_webhook_requires_real_signature_and_test_config(sdk_provider):
    provider,_=sdk_provider
    payload=json.dumps(dict(id='evt_signed',livemode=False,type='checkout.session.completed',data={'object':{}})).encode()
    with pytest.raises(ErrorAPI) as error:
        provider.event(payload,None)
    assert error.value.estado_http == 400
    timestamp=str(int(time.time()))
    digest=hmac.new(b'whsec_local_simulation_only',timestamp.encode()+b'.'+payload,hashlib.sha256).hexdigest()
    event=provider.event(payload,'t='+timestamp+',v1='+digest)
    assert event['id']=='evt_signed'
    with pytest.raises(ErrorAPI):
        provider.event(payload+b' ','t='+timestamp+',v1='+digest)


def test_missing_or_live_credentials_are_unavailable(monkeypatch):
    monkeypatch.setenv('STRIPE_SECRET_KEY','sk_live_do_not_use')
    monkeypatch.setenv('STRIPE_WEBHOOK_SECRET','whsec_simulated')
    monkeypatch.setenv('PUBLIC_API_URL','https://example.invalid')
    with pytest.raises(ErrorAPI) as error:
        StripeTest().ready()
    assert error.value.codigo == 'pagos_no_configurados' and error.value.estado_http==503


def test_production_client_pins_webhook_compatible_api_and_card_only(sdk_provider):
    provider, state = sdk_provider
    order = dict(id=str(uuid4()), usuario_id=str(uuid4()), total_centavos=13800,
                 creado_en=datetime.now(timezone.utc).isoformat(), asientos=[{'codigo': '1A'}])
    first = provider.checkout(order)
    repeated = provider.checkout(order)
    assert state['versions'] == ['2026-05-27.dahlia', '2026-05-27.dahlia']
    assert all(body['payment_method_types[0]'] == ['card'] for body in state['bodies'])
    assert state['bodies'][0] == state['bodies'][1]
    assert state['requests'][0][1] == state['requests'][1][1] == 'aerotech-checkout-' + order['id']
    assert first['id'] == repeated['id'] and len(state['sessions']) == 1


def test_sdk_embedded_checkout_has_no_redirect_and_preserves_idempotency(sdk_provider):
    provider, state = sdk_provider
    order = dict(id=str(uuid4()), usuario_id=str(uuid4()), total_centavos=13800,
                 creado_en=datetime.now(timezone.utc).isoformat(), asientos=[{'codigo': '1A'}],
                 solicitud={'checkout_ui': 'embedded'})
    first = provider.checkout(order)
    again = provider.checkout(order)
    assert first['id'] == again['id'] and len(state['sessions']) == 1
    assert first['client_secret'].startswith(first['id'] + '_secret_')
    for body in state['bodies']:
        assert body['ui_mode'] == ['embedded']
        assert body['redirect_on_completion'] == ['never']
        assert not {'success_url', 'cancel_url', 'return_url'} & body.keys()


def test_sdk_actual_refund_shape_without_livemode_and_partial_replay(core, sdk_provider):
    conn, repo, _, app, client, users, headers = core
    provider, state = sdk_provider
    app.extensions['sistema'].provider = provider
    order = create(client, headers[1], ['1A', '3A']).json['pedido']
    assert order['total_centavos'] == 20585
    session = next(iter(state['sessions'].values()))
    session.update(status='complete', payment_status='paid', payment_intent='pi_partial_verified')
    paid = client.get('/api/sistema/pedidos/' + order['id'], headers=headers[1]).json['pedido']
    path = f"/api/sistema/reservas/{paid['reserva_id']}/cancelaciones"
    body = dict(asientos=['3A'], clave_operacion=str(uuid4()))
    # Reproduce the live incident's durable boundary: Stripe already succeeded
    # but the application rejected its shape before saving refund_id.
    cancellation = repo.sistema_operar('cancelar', users[1], dict(id=paid['reserva_id'], **body))
    external = provider.refund(cancellation)
    assert external['status'] == 'succeeded' and 'livemode' not in external
    assert conn.execute('select refund_id, intento from public.at_cancelaciones where id=%s', (cancellation['id'],)).fetchone() == (None, 1)
    response = client.post(path, headers=headers[1], json=body)
    assert response.status_code == 200, response.json
    refund = next(iter(state['refunds'].values()))
    assert 'livemode' not in refund and refund['object'] == 'refund'
    assert refund['amount'] == 6785 and refund['status'] == 'succeeded'
    repeated = client.post(path, headers=headers[1], json=body)
    assert repeated.status_code == 200
    assert repeated.json['reserva']['reembolsado_centavos'] == 6785
    assert repeated.json['reserva']['cantidad_activa'] == 1
    assert repeated.json['reserva']['total_centavos'] == 20585
    assert len(state['refunds']) == 1
    refund_calls = [entry for entry in state['requests'] if entry[0] == '/v1/refunds']
    assert len(refund_calls) == 2 and refund_calls[0][1] == refund_calls[1][1]
    assert response.json['cancelacion']['refund_id'] == external['id']
    assert response.json['cancelacion']['intento'] == 1
    assert conn.execute('select codigo from public.at_asientos where pedido_id=%s', (order['id'],)).fetchall() == [('1A',)]


@pytest.mark.parametrize('change', [{'livemode': True}, {'payment_status': 'unpaid'}, {'payment_intent': 'pi_other'}])
def test_refund_requires_current_verified_test_paid_checkout_before_money(core, sdk_provider, change):
    conn, _, _, app, client, _, headers = core
    provider, state = sdk_provider
    app.extensions['sistema'].provider = provider
    order = create(client, headers[1], ['1A']).json['pedido']
    session = next(iter(state['sessions'].values()))
    session.update(status='complete', payment_status='paid', payment_intent='pi_original_verified')
    paid = client.get('/api/sistema/pedidos/' + order['id'], headers=headers[1]).json['pedido']
    session.update(change)
    response = client.post(f"/api/sistema/reservas/{paid['reserva_id']}/cancelaciones", headers=headers[1],
                           json=dict(asientos=['1A'], clave_operacion=str(uuid4())))
    assert response.status_code == 409, response.json
    assert state['refunds'] == {}
    assert conn.execute('select count(*) from public.at_asientos where pedido_id=%s', (order['id'],)).fetchone()[0] == 1
