"""Real PostgreSQL RPC plus public HTTP; Stripe is the only simulated dependency."""
import hashlib
import hmac
import json
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
from psycopg.types.json import Jsonb
from werkzeug.security import generate_password_hash

from backend.app import create_app
from backend.models import ErrorAPI
from backend.repository import RepositorioSupabase
from backend.sistema_validacion import allocate_vat, cabin

FLIGHT = 'd0000000-0000-4000-8000-000000000001'
PLANE = 'b0000000-0000-4000-8000-000000000001'


class SQLRepository:
    def __init__(self, connection):
        self.conn = connection
        self.tokens = {}

    def sistema_operar(self, action, user, data):
        try:
            with self.conn.transaction():
                return self.conn.execute('select public.sistema_operar(%s,%s,%s)', (action, user, Jsonb(data))).fetchone()[0]
        except Exception as exc:
            message = str(exc)
            for marker, code, status in [('CONFLICTO:', 'conflicto', 409), ('PROHIBIDO:', 'acceso_denegado', 403),
                                         ('NO_ENCONTRADO:', 'no_encontrado', 404), ('INVALIDO:', 'datos_invalidos', 400)]:
                if marker in message:
                    raise ErrorAPI(code, message.split('\n')[0], status) from exc
            raise

    def buscar_usuario_por_id(self, user):
        row = self.conn.execute('select id,nombre,correo,rol from public.usuarios where id=%s', (user,)).fetchone()
        return dict(zip(('id', 'nombre', 'correo', 'rol'), map(str, row))) if row else None

    def buscar_usuario_por_correo(self, email):
        row = self.conn.execute('select id,nombre,correo,rol,password_hash from public.usuarios where correo=%s', (email,)).fetchone()
        return dict(zip(('id', 'nombre', 'correo', 'rol', 'password_hash'), map(str, row))) if row else None

    def crear_token(self, user, token, expiry):
        self.tokens[token] = user

    def token_esta_activo(self, user, token):
        return self.tokens.get(token) == user

    def listar_reservas(self, user):
        return []

    def listar_vuelos(self, **kwargs):
        return []


class FakeStripe:
    def __init__(self):
        self.sessions = {}
        self.refunds = {}
        self.refund_calls = 0
        self.down = False
        self.refund_timeout = False
        self.status = 'succeeded'
        self.signature_events = {}

    def ready(self):
        return 'https://example.invalid'

    def checkout(self, order):
        session = self.sessions.setdefault(order['id'], dict(id='cs_test_' + order['id'], mode='payment', livemode=False,
          metadata=dict(app='aerotech', pedido_id=order['id'], usuario_id=order['usuario_id']), currency='usd',
          amount_total=order['total_centavos'], client_reference_id=order['id'], status='open', payment_status='unpaid',
          payment_intent=None, url='https://checkout.stripe.com/c/pay/' + order['id'], expires_at=int(time.time()+2100)))
        return session.copy()

    def retrieve(self, session):
        if self.down:
            raise ErrorAPI('proveedor_no_disponible', 'Provider down', 503)
        return next(s.copy() for s in self.sessions.values() if s['id'] == session)

    def expire(self, session):
        self.retrieve(session)
        item = next(s for s in self.sessions.values() if s['id'] == session)
        if item['payment_status'] != 'paid':
            item['status'] = 'expired'
        return item.copy()

    def pay(self, order):
        self.sessions[order]['status'] = 'complete'
        self.sessions[order]['payment_status'] = 'paid'
        self.sessions[order]['payment_intent'] = 'pi_' + order

    def refund(self, cancellation):
        self.refund_calls += 1
        attempt = cancellation['id'] + '-' + str(cancellation.get('intento', 1))
        item = self.refunds.setdefault(attempt, dict(id='re_' + attempt, livemode=False,
          payment_intent=cancellation['payment_intent'], amount=cancellation['importe_centavos'], currency='usd', status=self.status,
          metadata=dict(app='aerotech', cancelacion_id=cancellation['id'], pedido_id=cancellation['pedido_id'])))
        if self.refund_timeout:
            raise ErrorAPI('proveedor_no_disponible', 'Unknown outcome after write', 503)
        return item.copy()

    def retrieve_refund(self, refund):
        return next(s.copy() for s in self.refunds.values() if s['id'] == refund)

    def event(self, payload, signature):
        if signature != 'verified-test-signature':
            raise ErrorAPI('firma_invalida', 'Invalid signature', 400)
        return json.loads(payload)


@pytest.fixture
def core(sql_connection):
    conn = sql_connection
    users = []
    for role in ('ADMIN', 'USER', 'USER'):
        user = str(uuid4())
        conn.execute('insert into public.usuarios(id,nombre,correo,password_hash,rol) values(%s,%s,%s,%s,%s)',
                     (user, role, user+'@example.test', generate_password_hash('password123'), role))
        users.append(user)
    repo = SQLRepository(conn)
    provider = FakeStripe()
    app = create_app(repo, 'x'*40, stripe_provider=provider)
    client = app.test_client()
    headers = []
    for user in users:
        response = client.post('/api/auth/login', json={'correo': user+'@example.test', 'contrasena': 'password123'})
        assert response.status_code == 200, response.json
        headers.append({'Authorization': 'Bearer ' + response.json['token']})
    return conn, repo, provider, app, client, users, headers


def create(client, header, seats=None, key=None):
    return client.post('/api/sistema/pedidos', headers=header, json=dict(vuelo_id=FLIGHT,
                      asientos=seats or ['1A', '1C'], clave_operacion=key or str(uuid4())))


def paid(core, seats=None):
    conn, repo, provider, app, client, users, headers = core
    response = create(client, headers[1], seats)
    assert response.status_code == 201, response.json
    order_id = response.json['pedido']['id']
    provider.pay(order_id)
    result = client.get('/api/sistema/pedidos/' + order_id, headers=headers[1])
    assert result.status_code == 200, result.json
    assert result.json['pedido']['estado'] == 'pagado'
    return result.json['pedido']


def test_catalog_cabin_snapshot_and_public_role(core):
    _, _, _, _, client, _, headers = core
    response = client.get('/api/sistema/vuelos')
    assert response.status_code == 200
    assert len(response.json['vuelos']) == 3
    assert response.json['vuelos'][0]['asientos_disponibles'] == 36
    assert client.get('/api/sistema/aviones').status_code == 401
    assert client.get('/api/sistema/aviones', headers=headers[1]).status_code == 403
    assert client.get('/api/sistema/aviones', headers=headers[0]).status_code == 200
    seats = client.get(f'/api/sistema/vuelos/{FLIGHT}/asientos', headers=headers[1]).json['asientos']
    assert len(seats) == 36 and len({s['codigo'] for s in seats}) == 36
    assert seats[0]['codigo'] == '1A' and seats[0]['clase_codigo'] == 'EJEC'
    assert all(s['estado'] == 'libre' for s in seats)


def test_same_seat_exclusive_idempotent_payload_and_owner(core):
    _, _, _, _, client, _, h = core
    key = str(uuid4())
    first = create(client, h[1], key=key)
    second = create(client, h[1], key=key)
    assert first.status_code == second.status_code == 201
    assert first.json['pedido']['id'] == second.json['pedido']['id']
    assert create(client, h[2], ['1A']).status_code == 409
    assert create(client, h[1], ['2A'], key=key).status_code == 409
    order = first.json['pedido']
    assert order['total_centavos'] == 27600
    assert 'usuario_id' not in order and 'session_id' not in order
    assert client.get('/api/sistema/pedidos/' + order['id'], headers=h[2]).status_code == 404
    seats = client.get(f'/api/sistema/vuelos/{FLIGHT}/asientos', headers=h[2]).json['asientos']
    assert len(seats) == 36 and seats[0]['estado'] == 'retenido' and not seats[0]['es_mio']


def test_partial_refund_preserves_original_amounts_and_releases_exact_seat(core):
    _, _, provider, _, client, _, h = core
    order = paid(core)
    reservation = order['reserva_id']
    key = str(uuid4())
    body = dict(asientos=['1A'], clave_operacion=key)
    response = client.post(f'/api/sistema/reservas/{reservation}/cancelaciones', headers=h[1], json=body)
    assert response.status_code == 200, response.json
    data = response.json
    assert data['cancelacion']['importe_centavos'] == 13800
    assert data['reserva']['cantidad_activa'] == 1
    assert data['reserva']['cantidad_cancelada'] == 1
    assert data['reserva']['total_centavos'] == 27600
    assert data['reserva']['reembolsado_centavos'] == 13800
    assert client.post(f'/api/sistema/reservas/{reservation}/cancelaciones', headers=h[1], json=body).status_code == 200
    assert provider.refund_calls == 1
    assert create(client, h[2], ['1A']).status_code == 201
    assert create(client, h[2], ['1C']).status_code == 409
    assert client.post(f'/api/sistema/reservas/{reservation}/cancelaciones', headers=h[1], json=dict(asientos=['1A'], clave_operacion=str(uuid4()))).status_code == 409
    xml = client.get(f'/api/sistema/reservas/{reservation}/comprobante.xml', headers=h[1])
    assert xml.status_code == 200 and b'<codigo>1A</codigo>' in xml.data
    assert client.get(f'/api/sistema/reservas/{reservation}', headers=h[2]).status_code == 404


def test_unknown_refund_write_retry_is_single_money_and_stock(core):
    _, repo, provider, _, client, users, h = core
    order = paid(core)
    provider.refund_timeout = True
    key = str(uuid4())
    body = dict(asientos=['1A'], clave_operacion=key)
    response = client.post(f"/api/sistema/reservas/{order['reserva_id']}/cancelaciones", headers=h[1], json=body)
    assert response.status_code == 503
    assert create(client, h[2], ['1A']).status_code == 409
    reservation = repo.sistema_operar('reserva', users[1], {'id': order['reserva_id']})
    cancellation = reservation['cancelaciones'][0]
    assert reservation['asientos'][0]['estado'] == 'reembolso_pendiente'
    provider.refund_timeout = False
    retry = client.post(f"/api/sistema/reservas/{order['reserva_id']}/cancelaciones/{cancellation['id']}/reintentar",
                        headers=h[1], json={'clave_operacion':str(uuid4())})
    assert retry.status_code == 200, retry.json
    assert len(provider.refunds) == 1
    assert retry.json['reserva']['reembolsado_centavos'] == 13800


def test_provider_down_local_expiry_never_releases_paid_seat(core):
    conn, _, provider, _, client, _, h = core
    order = create(client, h[1], ['1A']).json['pedido']
    provider.pay(order['id'])
    conn.execute("update public.at_pedidos set vence_en=now()-interval '1 hour' where id=%s", (order['id'],))
    provider.down = True
    assert client.get('/api/sistema/pedidos/'+order['id'], headers=h[1]).status_code == 503
    assert create(client, h[2], ['1A']).status_code == 409
    seats = client.get(f'/api/sistema/vuelos/{FLIGHT}/asientos', headers=h[2]).json['asientos']
    assert seats[0]['estado'] == 'retenido'
    provider.down = False
    assert client.get('/api/sistema/pedidos/'+order['id'], headers=h[1]).json['pedido']['estado'] == 'pagado'


def test_verified_expiration_abandon_and_duplicate_no_stock_inflation(core):
    _, _, _, _, client, _, h = core
    order = create(client, h[1], ['1A']).json['pedido']
    for _ in range(2):
        result = client.post('/api/sistema/pedidos/'+order['id']+'/abandonar', headers=h[1], json={'clave_operacion':str(uuid4())})
        assert result.status_code == 200, result.json
        assert result.json['pedido']['estado'] == 'expirado'
    seats = client.get(f'/api/sistema/vuelos/{FLIGHT}/asientos', headers=h[2]).json['asientos']
    assert len([s for s in seats if s['estado'] == 'libre']) == 36


def test_payment_amount_metadata_mode_mismatch_rejected(core):
    _, _, provider, _, client, _, h = core
    order = create(client, h[1], ['1A']).json['pedido']
    provider.pay(order['id'])
    provider.sessions[order['id']]['amount_total'] += 1
    result = client.get('/api/sistema/pedidos/'+order['id'], headers=h[1])
    assert result.status_code == 409
    assert client.get('/api/sistema/reservas', headers=h[1]).json == {'reservas': []}
    provider.sessions[order['id']]['amount_total'] -= 1
    provider.sessions[order['id']]['livemode'] = True
    assert client.get('/api/sistema/pedidos/'+order['id'], headers=h[1]).status_code == 409


def test_webhook_signature_replay_and_foreign_project(core):
    conn, _, provider, _, client, _, h = core
    order = create(client, h[1], ['1A']).json['pedido']
    provider.pay(order['id'])
    event = dict(id='evt_test_'+str(uuid4()), type='checkout.session.completed',livemode=False,
                 data={'object': provider.sessions[order['id']]})
    assert client.post('/api/stripe/webhook', json=event).status_code == 400
    headers = {'Stripe-Signature':'verified-test-signature'}
    assert client.post('/api/stripe/webhook', headers=headers,json=event).status_code == 200
    repeated = client.post('/api/stripe/webhook', headers=headers,json=event)
    assert repeated.json['repetido']
    assert conn.execute('select count(*) from public.at_reservas').fetchone()[0] == 1
    foreign = dict(id='evt_foreign',type='checkout.session.completed',livemode=False,data={'object': {'metadata': {'app':'other'}}})
    assert client.post('/api/stripe/webhook', headers=headers,json=foreign).json['ignorado']
    foreign['livemode'] = True
    assert client.post('/api/stripe/webhook', headers=headers,json=foreign).status_code == 400


def test_hold_blocks_flight_edits_and_aircraft_layout(core):
    _, _, _, _, client, _, h = core
    create(client, h[1], ['1A'])
    flight = client.get('/api/sistema/vuelos').json['vuelos'][0]
    for method in ('put', 'delete'):
        data = {**flight, 'version':flight['version']}
        result = getattr(client,method)('/api/sistema/vuelos/'+FLIGHT, headers=h[0], json=data)
        assert result.status_code == 409, result.json
    plane = client.get('/api/sistema/aviones',headers=h[0]).json['aviones'][0]
    plane['clases'][0]['nombre'] = 'Ejecutiva modificada'
    assert client.put('/api/sistema/aviones/'+PLANE, headers=h[0],json=plane).status_code == 409
    assert client.post('/api/reservas', headers=h[1], json={'vuelo_id':FLIGHT,'cantidad':1}).status_code == 410


def test_schedule_fk_version_and_counter_not_client_controlled(core):
    _, _, _, _, client, _, h = core
    flight = client.get('/api/sistema/vuelos').json['vuelos'][0]
    data = {key:flight[key] for key in ('ruta_id','avion_id','salida_local','llegada_local','tarifas')}
    data['codigo']='OVERLAP'
    assert client.post('/api/sistema/vuelos',headers=h[0],json=data).status_code == 409
    data['codigo'] = 'NEW-TEST'
    departure = datetime.fromisoformat(data['salida_local'])+timedelta(days=1)
    data.update(salida_local=departure.isoformat(timespec='minutes'), llegada_local=(departure+timedelta(hours=1)).isoformat(timespec='minutes'),asientos_disponibles=999999)
    response = client.post('/api/sistema/vuelos',headers=h[0],json=data)
    assert response.status_code == 201, response.json
    assert response.json['vuelo']['asientos_disponibles'] == 36
    item = response.json['vuelo']
    assert client.delete('/api/sistema/vuelos/'+item['id'],headers=h[0],json={'version':0}).status_code == 400
    assert client.delete('/api/sistema/vuelos/'+item['id'],headers=h[0],json={'version':999}).status_code == 409
    assert client.delete('/api/sistema/vuelos/'+item['id'],headers=h[0],json={'version':1}).status_code == 200
    data['ruta_id'] = str(uuid4())
    data['codigo'] = 'MISSING'
    assert client.post('/api/sistema/vuelos',headers=h[0],json=data).status_code == 400


def test_live_role_reload_prevents_stale_admin(core):
    conn, _, _, _, client, users, h = core
    conn.execute("update public.usuarios set rol='USER' where id=%s",(users[0],))
    assert client.get('/api/sistema/aviones',headers=h[0]).status_code == 403
    assert client.get('/api/auth/perfil',headers=h[1]).status_code == 200
    assert client.get('/api/reservas',headers=h[1]).status_code == 200


def test_vat_aggregate_allocation_cannot_over_refund():
    seats = allocate_vat([{'codigo': str(i)+'A','subtotal_centavos':51} for i in range(1,4)])
    assert sum(s['iva_centavos'] for s in seats) == 23
    assert sum(s['total_centavos'] for s in seats) == 176
    assert all(s['total_centavos'] >= s['subtotal_centavos'] for s in seats)
    with pytest.raises(ErrorAPI):
        cabin([dict(codigo='ECO',nombre='ECO',fila_inicio=1,filas=1,columnas=[['A','A']])])


def test_two_real_connections_same_seat_one_winner(isolated_database):
    import psycopg
    user_ids = [str(uuid4()),str(uuid4())]
    with psycopg.connect(isolated_database,autocommit=True) as setup:
        for user in user_ids:
            setup.execute("insert into public.usuarios(id,nombre,correo,password_hash) values(%s,'Race',%s,'hash')",(user,user+'@race.test'))
    barrier = threading.Barrier(2)
    def attempt(user):
        with psycopg.connect(isolated_database,autocommit=True) as conn:
            barrier.wait()
            try:
                conn.execute('select sistema_operar(%s,%s,%s)',('crear_pedido',user,Jsonb(dict(vuelo_id=FLIGHT,asientos=['9D'],clave_operacion=str(uuid4())))))
                return 'held'
            except Exception as exc:
                assert 'CONFLICTO:' in str(exc)
                return 'conflict'
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(attempt,user_ids))
    assert sorted(results) == ['conflict','held']


def test_late_paid_order_refunded_without_stealing_rebooked_seat(core):
    conn, _, provider, _, client, _, h = core
    original = create(client,h[1],['1A']).json['pedido']
    expired = client.post('/api/sistema/pedidos/'+original['id']+'/abandonar',headers=h[1],json={'clave_operacion':str(uuid4())})
    assert expired.status_code==200
    replacement = create(client,h[2],['1A']).json['pedido']
    provider.pay(original['id'])
    event=dict(id='evt_late_'+str(uuid4()),type='checkout.session.completed',livemode=False,
               data={'object':provider.sessions[original['id']]})
    response=client.post('/api/stripe/webhook',headers={'Stripe-Signature':'verified-test-signature'},json=event)
    assert response.status_code==200,response.json
    assert conn.execute('select pedido_id::text from public.at_asientos where vuelo_id=%s and codigo=%s',(FLIGHT,'1A')).fetchone()[0]==replacement['id']
    assert conn.execute('select count(*) from public.at_reservas where pedido_id=%s',(original['id'],)).fetchone()[0]==0
    assert next(iter(provider.refunds.values()))['amount']==original['total_centavos']
    assert client.get('/api/sistema/pedidos/'+original['id'],headers=h[1]).json['pedido']['estado']=='cancelado'


def test_pending_and_failed_refunds_keep_seats_then_retry_confirmed_failure(core):
    conn, _, provider, _, client, _, h=core
    order=paid(core,['1A'])
    provider.status='pending'
    body=dict(asientos=['1A'],clave_operacion=str(uuid4()))
    response=client.post(f"/api/sistema/reservas/{order['reserva_id']}/cancelaciones",headers=h[1],json=body)
    assert response.status_code==200
    cancellation=response.json['cancelacion']
    assert cancellation['estado']=='reembolso_pendiente'
    assert create(client,h[2],['1A']).status_code==409
    next(iter(provider.refunds.values()))['status']='failed'
    checked=client.post(f"/api/sistema/reservas/{order['reserva_id']}/cancelaciones/{cancellation['id']}/reintentar",headers=h[1],json={'clave_operacion':str(uuid4())})
    assert checked.json['cancelacion']['estado']=='fallido'
    assert create(client,h[2],['1A']).status_code==409
    provider.status='succeeded'
    retried=client.post(f"/api/sistema/reservas/{order['reserva_id']}/cancelaciones/{cancellation['id']}/reintentar",headers=h[1],json={'clave_operacion':str(uuid4())})
    assert retried.status_code==200,retried.json
    assert retried.json['cancelacion']['estado']=='cancelado'
    assert retried.json['cancelacion']['intento']==2
    assert len(provider.refunds)==2
    assert retried.json['reserva']['reembolsado_centavos']==order['total_centavos']
    assert create(client,h[2],['1A']).status_code==201


def test_cancellation_empty_duplicate_foreign_and_departed_rejected(core):
    conn, _, _, _, client, _, h=core
    order=paid(core)
    path=f"/api/sistema/reservas/{order['reserva_id']}/cancelaciones"
    for selection in ([],['1A','1A']):
        assert client.post(path,headers=h[1],json=dict(asientos=selection,clave_operacion=str(uuid4()))).status_code==400
    assert client.post(path,headers=h[2],json=dict(asientos=['1A'],clave_operacion=str(uuid4()))).status_code==404
    assert client.post(path,headers=h[1],json=dict(asientos=['9D'],clave_operacion=str(uuid4()))).status_code==409
    conn.execute("update public.at_vuelos set salida_en=now()-interval '2 hours',llegada_en=now()-interval '1 hour' where id=%s",(FLIGHT,))
    assert client.post(path,headers=h[1],json=dict(asientos=['1A'],clave_operacion=str(uuid4()))).status_code==409
    assert conn.execute('select count(*) from public.at_cancelaciones').fetchone()[0]==0


def test_airport_catalog_crud_and_reference_guard(core):
    _, _, _, _, client, _, h=core
    data=dict(iata='ZZQ',nombre='Isolated',ciudad='City',pais='Ecuador',codigo_pais='EC',latitud=0,longitud=0,zona_horaria='America/Guayaquil')
    response=client.post('/api/sistema/aeropuertos',headers=h[0],json=data)
    assert response.status_code==201,response.json
    airport=response.json['aeropuerto']
    assert airport['version']==1
    assert client.post('/api/sistema/aeropuertos',headers=h[1],json=data).status_code==403
    data.update(nombre='Changed',version=1)
    updated=client.put('/api/sistema/aeropuertos/'+airport['id'],headers=h[0],json=data)
    assert updated.status_code==200 and updated.json['aeropuerto']['version']==2
    assert client.delete('/api/sistema/aeropuertos/'+airport['id'],headers=h[0],json={'version':1}).status_code==409
    assert client.delete('/api/sistema/aeropuertos/'+airport['id'],headers=h[0],json={'version':2}).status_code==200
    assert airport['id'] not in [a['id'] for a in client.get('/api/sistema/aeropuertos').json['aeropuertos']]
    uio=next(a for a in client.get('/api/sistema/aeropuertos').json['aeropuertos'] if a['iata']=='UIO')
    assert client.delete('/api/sistema/aeropuertos/'+uio['id'],headers=h[0],json={'version':uio['version']}).status_code==409


def test_utc_cross_zone_overnight_and_same_day_rule(core):
    _, _, _, _, client, _, h=core
    flight=client.get('/api/sistema/vuelos').json['vuelos'][0]
    airport=client.post('/api/sistema/aeropuertos',headers=h[0],json=dict(iata='XZT',nombre='Timezone fixture',ciudad='Fixture',pais='Japan',codigo_pais='JP',latitud=0,longitud=0,zona_horaria='Asia/Tokyo')).json['aeropuerto']
    route=client.post('/api/sistema/rutas',headers=h[0],json=dict(origen_id=flight['ruta']['origen_id'],destino_id=airport['id'])).json['ruta']
    departure=datetime.fromisoformat(flight['salida_local'])+timedelta(days=2)
    departure=departure.replace(hour=22)
    arrival=(departure+timedelta(days=1)).replace(hour=18)
    data=dict(codigo='UTC-CROSS',ruta_id=route['id'],avion_id=PLANE,tarifas=flight['tarifas'],salida_local=departure.isoformat(timespec='minutes'),llegada_local=arrival.isoformat(timespec='minutes'))
    response=client.post('/api/sistema/vuelos',headers=h[0],json=data)
    assert response.status_code==201,response.json
    actual=response.json['vuelo']
    assert datetime.fromisoformat(actual['llegada_en'])-datetime.fromisoformat(actual['salida_en'])==timedelta(hours=6)
    today=datetime.now(timezone(timedelta(hours=-5))).date().isoformat()
    data.update(codigo='TODAY-DENIED',salida_local=today+'T22:00',llegada_local=(datetime.now()+timedelta(days=1)).date().isoformat()+'T18:00')
    assert client.post('/api/sistema/vuelos',headers=h[0],json=data).status_code==400


def test_migration008_rerun_refuses_before_deleting_any_data(isolated_database):
    import psycopg
    from pathlib import Path
    with psycopg.connect(isolated_database,autocommit=True) as conn:
        before=conn.execute('select count(*) from public.at_asientos').fetchone()[0]
        canary=str(uuid4())
        conn.execute("insert into public.vuelos(id,origen,destino,fecha,hora_salida,precio,asientos_disponibles) values(%s,'Canary A','Canary B',current_date+30,'10:00',1,1)",(canary,))
        with pytest.raises(Exception,match='MIGRACION_008_YA_APLICADA'):
            conn.execute(Path('database/migrations/008_sistema_integral.sql').read_text(encoding='utf-8'))
        conn.rollback()
        assert conn.execute('select count(*) from public.vuelos where id=%s',(canary,)).fetchone()[0]==1
        assert conn.execute('select count(*) from public.at_asientos').fetchone()[0]==before
