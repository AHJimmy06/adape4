"""Regresiones independientes con SQL y transporte HTTP aislados."""
import os, json, threading
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit
from uuid import uuid4
import pytest, psycopg, requests
from psycopg.types.json import Jsonb
from psycopg.conninfo import make_conninfo
from backend.tests.conftest import isolated_database as base_isolated_database, sql_connection

@pytest.fixture
def isolated_database():
    yield from base_isolated_database.__wrapped__()
from backend.tests.test_sistema_integracion import core, create, paid, FLIGHT
from backend.notificaciones import ClienteMailtrap, DespachadorCorreos, ErrorCorreo
MIG = Path('database/migrations/013_notificaciones_pago.sql')

def rpc(conn, action, **data):
    return conn.execute('select public.notificaciones_operar(%s,%s)', (action, Jsonb(data))).fetchone()[0]

@pytest.fixture
def complete(core):
    for n in ('010_programacion_vuelos.sql', '011_operaciones_aeropuertos.sql', '012_estado_usuarios.sql', '013_notificaciones_pago.sql'):
        core[0].execute(Path('database/migrations/' + n).read_text(encoding='utf8'))
    return core

@pytest.fixture
def httpmail():
    state = {'status': 500, 'calls': [], 'url': [], 'body': 'DO_NOT_LEAK_SECRET'}

    class Handler(BaseHTTPRequestHandler):

        def do_POST(self):
            state['calls'].append((self.path, dict(self.headers), json.loads(self.rfile.read(int(self.headers['Content-Length'])))))
            self.send_response(state['status'])
            self.send_header('Location', 'http://127.0.0.1:' + str(server.server_port) + '/unexpected')
            self.end_headers()
            self.wfile.write(json.dumps(state['body']).encode())

        def do_GET(self):
            state['calls'].append(('unexpected GET', {}, {}))
            self.send_response(500)
            self.end_headers()

        def log_message(self, *args):
            pass
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    class Adapter(requests.adapters.HTTPAdapter):

        def send(self, request, **kwargs):
            state['url'].append((request.url, kwargs['timeout']))
            assert request.url == 'https://sandbox.api.mailtrap.io/api/send/42'
            request.url = 'http://127.0.0.1:' + str(server.server_port) + urlsplit(request.url).path
            return super().send(request, **kwargs)
    session = requests.Session()
    session.mount('https://sandbox.api.mailtrap.io/', Adapter())
    client = ClienteMailtrap('FAKE_NOT_A_REAL_TOKEN', '42', session=session)
    yield (state, client)
    session.close()
    server.shutdown()
    server.server_close()
    thread.join(2)

def test_own_no_history_spoof_or_prepaid_notification_and_snapshot_authority(core):
    conn, repo, stripe, app, client, users, h = core
    historic = paid(core, ['1A'])
    conn.execute(MIG.read_text(encoding='utf8'))
    assert conn.execute('select count(*) from at_notificaciones').fetchone()[0] == 0
    data = {'vuelo_id': FLIGHT, 'asientos': ['1C'], 'clave_operacion': str(uuid4()), 'correo': 'attacker@example.test', 'total_centavos': 1, 'estado': 'pagado'}
    r = client.post('/api/sistema/pedidos', headers=h[1], json=data)
    assert r.status_code == 201, r.json
    order = r.json['pedido']
    event = {'id': 'evt_own_before_paid', 'livemode': False, 'type': 'checkout.session.completed', 'data': {'object': stripe.sessions[order['id']]}}
    headers = {'Stripe-Signature': 'verified-test-signature'}
    assert client.post('/api/stripe/webhook', json=event, headers=headers).status_code == 200
    assert conn.execute('select count(*) from at_notificaciones').fetchone()[0] == 0
    assert conn.execute('select count(*) from at_reservas where pedido_id=%s', (order['id'],)).fetchone()[0] == 0
    stripe.pay(order['id'])
    event['id'] = 'evt_own_after_paid'
    event['data']['object'] = stripe.sessions[order['id']]
    assert client.post('/api/stripe/webhook', json=event, headers={'Stripe-Signature': 'bad'}).status_code == 400
    assert conn.execute('select count(*) from at_notificaciones').fetchone()[0] == 0
    for _ in range(2):
        assert client.post('/api/stripe/webhook', json=event, headers=headers).status_code == 200
    row = conn.execute('select datos from at_notificaciones where pedido_id=%s', (order['id'],)).fetchone()[0]
    reservation = conn.execute('select id::text,vuelo from at_reservas where pedido_id=%s', (order['id'],)).fetchone()
    assert row['correo'] == users[1] + '@example.test' and row['reserva_id'] == reservation[0] and (row['vuelo'] == reservation[1])
    assert row['total_centavos'] == order['total_centavos'] and row['total_centavos'] > 1
    assert [s['codigo'] for s in row['asientos']] == ['1C']
    assert not {'password_hash', 'session_id', 'payment_intent', 'usuario_id'} & row.keys()
    conn.execute('update usuarios set nombre=%s,correo=%s where id=%s', ('Changed', 'changed@example.test', users[1]))
    conn.execute(MIG.read_text(encoding='utf8'))
    assert conn.execute('select datos from at_notificaciones where pedido_id=%s', (order['id'],)).fetchone()[0] == row
    assert conn.execute('select count(*) from at_notificaciones').fetchone()[0] == 1
    assert conn.execute('select estado from at_pedidos where id=%s', (historic['id'],)).fetchone()[0] == 'pagado'

def test_own_sql_to_real_http_fail_redirect_retry_preserves_payment(complete, httpmail):
    conn, repo, stripe, app, client, users, h = complete
    state, mail = httpmail
    order = paid(complete, ['1A'])
    before = conn.execute('select row_to_json(p) from at_pedidos p where id=%s', (order['id'],)).fetchone()[0]
    reservation = conn.execute('select row_to_json(r) from at_reservas r where pedido_id=%s', (order['id'],)).fetchone()[0]

    class ServiceQueue:

        def notificaciones_operar(self, action, data):
            with conn.transaction():
                conn.execute('set local role service_role')
                try:
                    return rpc(conn, action, **data)
                finally:
                    conn.execute('reset role')
    worker = DespachadorCorreos(ServiceQueue(), mail)
    for status in (500, 302, 200):
        state['status'] = status
        state['body'] = {'success': True, 'message_ids': ['own_http_message']} if status == 200 else 'DO_NOT_LEAK_SECRET'
        result = worker.procesar_uno()
        assert result == (status == 200)
        row = conn.execute('select estado,intentos,error_codigo,proveedor_id from at_notificaciones where pedido_id=%s', (order['id'],)).fetchone()
        assert row[0] == ('enviado' if status == 200 else 'pendiente'), row
        assert conn.execute('select row_to_json(p) from at_pedidos p where id=%s', (order['id'],)).fetchone()[0] == before
        assert conn.execute('select row_to_json(r) from at_reservas r where pedido_id=%s', (order['id'],)).fetchone()[0] == reservation
        if status != 200:
            assert row[2] == 'mailtrap_http_' + str(status)
            assert worker.procesar_uno() is False
            conn.execute("update at_notificaciones set proximo_intento=clock_timestamp()-interval '1 second'")
            conn.execute("update at_notificaciones_control set permite_en='-infinity'")
    assert len(state['calls']) == 3, state['calls']
    assert row == ('enviado', 3, None, 'own_http_message'), row
    assert all((url == 'https://sandbox.api.mailtrap.io/api/send/42' and timeout == (3, 10) for url, timeout in state['url']))
    for path, headers, body in state['calls']:
        assert path == '/api/send/42' and headers['Authorization'] == 'Bearer FAKE_NOT_A_REAL_TOKEN'
        assert body['to'][0]['email'] == users[1] + '@example.test'
        assert 'FAKE_NOT_A_REAL_TOKEN' not in json.dumps(body)
        assert str(order['total_centavos'] // 100) in body['text']
    assert mail._session.trust_env is False

def test_own_permissions_claim_race_lease_rotation_and_global_throttle(complete):
    conn, repo, stripe, app, client, users, h = complete
    first = paid(complete, ['1A'])
    second = paid(complete, ['1C'])
    for role in ('anon', 'authenticated'):
        for statement in ("select notificaciones_operar('tomar','{}'::jsonb)", 'select * from at_notificaciones', 'select * from at_notificaciones_control'):
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                with conn.transaction():
                    conn.execute('set local role ' + role)
                    conn.execute(statement)
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        with conn.transaction():
            conn.execute('set local role service_role')
            conn.execute('select * from at_notificaciones')
    conn.commit()
    dsn = make_conninfo(os.environ['AEROTECH_TEST_DSN'], dbname=conn.info.dbname)
    barrier = threading.Barrier(4)

    def claim(_):
        with psycopg.connect(dsn) as other:
            barrier.wait(5)
            other.execute('set local role service_role')
            return rpc(other, 'tomar')
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(claim, range(4)))
    claims = [r for r in results if r is not None]
    assert len(claims) == 1, results
    old = claims[0]
    before = conn.execute('select row_to_json(n) from at_notificaciones n where id=%s', (old['id'],)).fetchone()[0]
    assert rpc(conn, 'terminar', id=old['id'], token=str(uuid4()), ok=True) is False
    assert conn.execute('select row_to_json(n) from at_notificaciones n where id=%s', (old['id'],)).fetchone()[0] == before
    conn.execute("update at_notificaciones set lease_hasta=clock_timestamp()-interval '1 second' where id=%s", (old['id'],))
    assert rpc(conn, 'terminar', id=old['id'], token=old['token'], ok=True) is False
    conn.execute("update at_notificaciones_control set permite_en='-infinity'")
    new = rpc(conn, 'tomar')
    assert new['id'] == old['id'] and new['token'] != old['token']
    assert rpc(conn, 'terminar', id=old['id'], token=old['token'], ok=True) is False
    assert rpc(conn, 'terminar', id=new['id'], token=new['token'], ok=True, proveedor_id='message') is True
    assert rpc(conn, 'tomar') is None
    assert conn.execute('select count(*) from at_reservas where pedido_id=any(%s::uuid[])', ([first['id'], second['id']],)).fetchone()[0] == 2

@pytest.fixture(autouse=True)
def correo_prueba_desactivado(monkeypatch):
    monkeypatch.setenv('MAILTRAP_ENABLED', 'false')
