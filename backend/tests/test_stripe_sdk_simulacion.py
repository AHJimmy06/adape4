"""Exercise the installed Stripe SDK against a bounded local HTTP simulator."""
import hashlib
import hmac
import json
import socket
import threading
import time
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
    state = dict(sessions={}, refunds={}, keys={}, disconnect_checkout=False, disconnect_refund=False, requests=[])
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
            if key in state['keys']:
                return self.reply(state['keys'][key])
            if self.path == '/v1/checkout/sessions':
                ident='cs_test_'+uuid4().hex
                result=dict(id=ident,object='checkout.session',livemode=False,mode='payment',currency='usd',
                   amount_total=int(get('line_items[0][price_data][unit_amount]')),status='open',payment_status='unpaid',
                   payment_intent=None,client_reference_id=get('client_reference_id'),expires_at=int(get('expires_at')),
                   metadata={k:get('metadata['+k+']') for k in ('app','pedido_id','usuario_id')},url='https://checkout.stripe.com/c/pay/'+ident)
                state['sessions'][ident]=result
                flag='disconnect_checkout'
            elif self.path == '/v1/refunds':
                ident='re_'+uuid4().hex
                result=dict(id=ident,object='refund',livemode=False,currency='usd',status='succeeded',amount=int(get('amount')),
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
    client=stripe.StripeClient('sk_test_local_simulation_only',base_addresses={'api':f'http://127.0.0.1:{server.server_port}'},
                                max_network_retries=0,http_client=stripe.RequestsClient(timeout=2))
    yield StripeTest(client), state
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
