"""Cola transaccional de correos; PostgreSQL local y pago HTTP verificado."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import json
import threading

import psycopg
from psycopg.types.json import Jsonb
import pytest

from backend.tests.test_sistema_integracion import core, create, paid


MIGRACION = Path('database/migrations/013_notificaciones_pago.sql')


@pytest.fixture
def correos(core):
    conn = core[0]
    for nombre in ('010_programacion_vuelos.sql', '011_operaciones_aeropuertos.sql',
                   '012_estado_usuarios.sql'):
        conn.execute(Path('database/migrations/' + nombre).read_text(encoding='utf-8'))
    if MIGRACION.exists():
        conn.execute(MIGRACION.read_text(encoding='utf-8'))
    return core


def operar(conn, accion, **datos):
    return conn.execute('select public.notificaciones_operar(%s,%s)',
                        (accion, Jsonb(datos))).fetchone()[0]


def test_pago_no_confirmado_no_encola_y_pagado_encola_una_vez(correos):
    conn, _, proveedor, _, cliente, usuarios, cabeceras = correos
    pedido = create(cliente, cabeceras[1]).json['pedido']
    assert conn.execute('select count(*) from at_notificaciones').fetchone()[0] == 0
    proveedor.pay(pedido['id'])
    url = '/api/sistema/pedidos/' + pedido['id']
    for _ in range(3):
        respuesta = cliente.get(url, headers=cabeceras[1])
        assert respuesta.status_code == 200
        assert respuesta.json['pedido']['estado'] == 'pagado'
    assert conn.execute('select count(*) from at_notificaciones where pedido_id=%s',
                        (pedido['id'],)).fetchone()[0] == 1
    fila = conn.execute('select datos from at_notificaciones where pedido_id=%s',
                        (pedido['id'],)).fetchone()[0]
    assert fila['correo'] == usuarios[1] + '@example.test'
    assert fila['nombre'] == 'USER'
    assert fila['reserva_id'] == respuesta.json['pedido']['reserva_id']
    assert fila['total_centavos'] == respuesta.json['pedido']['total_centavos']
    assert fila['vuelo']['ruta']['origen']['nombre']
    assert fila['vuelo']['ruta']['destino']['nombre']
    assert [a['codigo'] for a in fila['asientos']] == ['1A', '1C']
    assert not {'password_hash', 'session_id', 'payment_intent', 'usuario_id'} & fila.keys()
    # Otro UPDATE de un pedido ya pagado no altera el snapshot ni duplica.
    conn.execute("update usuarios set correo='cambiado@example.test' where id=%s", (usuarios[1],))
    conn.execute('update at_pedidos set incidencia=null where id=%s', (pedido['id'],))
    assert conn.execute('select datos from at_notificaciones where pedido_id=%s',
                        (pedido['id'],)).fetchone()[0] == fila


def test_migracion_repetida_no_reenvia_pago_historico(core):
    conn = core[0]
    texto = MIGRACION.read_text(encoding='utf-8')
    conn.execute(texto)
    # Representa un pago anterior a la instalación del trigger, solo en esta BD aislada.
    conn.execute('alter table at_pedidos disable trigger at_notificar_pago')
    anterior = paid(core)
    conn.execute('alter table at_pedidos enable trigger at_notificar_pago')
    conn.commit()
    try:
        conn.execute(texto)
        conn.execute(texto)
        assert conn.execute('select count(*) from at_notificaciones').fetchone()[0] == 0
        assert conn.execute('select estado,reserva_id::text from at_pedidos where id=%s',
                            (anterior['id'],)).fetchone() == ('pagado', anterior['reserva_id'])
    finally:
        limpiar_pedido(conn, anterior['id'])


def test_webhook_confirmado_y_replay_no_duplican_notificacion(correos):
    conn, _, proveedor, _, cliente, _, cabeceras = correos
    pedido = create(cliente, cabeceras[1]).json['pedido']
    sesion = proveedor.sessions[pedido['id']]
    evento = dict(id='evt_correo_confirmado', livemode=False, type='checkout.session.completed',
                  data={'object': {'id': sesion['id'], 'metadata': sesion['metadata']}})
    firma = {'Stripe-Signature': 'verified-test-signature', 'Content-Type': 'application/json'}
    assert cliente.post('/api/stripe/webhook', data=json.dumps(evento), headers={**firma, 'Stripe-Signature': 'invalida'}).status_code == 400
    assert conn.execute('select count(*) from at_notificaciones').fetchone()[0] == 0
    proveedor.pay(pedido['id'])
    for _ in range(2):
        assert cliente.post('/api/stripe/webhook', data=json.dumps(evento), headers=firma).status_code == 200
    assert conn.execute('select count(*) from at_notificaciones where pedido_id=%s', (pedido['id'],)).fetchone()[0] == 1
    assert cliente.get('/api/sistema/pedidos/' + pedido['id'], headers=cabeceras[1]).json['pedido']['estado'] == 'pagado'
    assert conn.execute('select count(*) from at_notificaciones where pedido_id=%s', (pedido['id'],)).fetchone()[0] == 1


def test_reclamar_confirmar_y_rechazar_token_anterior(correos):
    conn = correos[0]
    pedido = paid(correos)
    trabajo = operar(conn, 'tomar')
    assert trabajo['datos']['reserva_id'] == pedido['reserva_id']
    assert trabajo['token'] and trabajo['id']
    assert operar(conn, 'tomar') is None
    assert operar(conn, 'terminar', id=trabajo['id'], token='00000000-0000-4000-8000-000000000000', ok=True) is False
    assert operar(conn, 'terminar', id=trabajo['id'], token=trabajo['token'], ok=True, proveedor_id='mensaje-prueba') is True
    assert operar(conn, 'terminar', id=trabajo['id'], token=trabajo['token'], ok=True) is False
    assert conn.execute('select estado,proveedor_id from at_notificaciones where id=%s',
                        (trabajo['id'],)).fetchone() == ('enviado', 'mensaje-prueba')
    assert operar(conn, 'tomar') is None


def test_fallo_difiere_sin_revertir_pago_y_respeta_reintento(correos):
    conn = correos[0]
    pedido = paid(correos)
    trabajo = operar(conn, 'tomar')
    assert operar(conn, 'terminar', id=trabajo['id'], token=trabajo['token'], ok=False,
                  error_codigo='mailtrap_http_429', reintentar_segundos=180) is True
    fila = conn.execute("select estado,intentos,error_codigo,proximo_intento>clock_timestamp()+interval '170 seconds' from at_notificaciones where id=%s",
                        (trabajo['id'],)).fetchone()
    assert fila == ('pendiente', 1, 'mailtrap_http_429', True)
    assert operar(conn, 'tomar') is None
    assert conn.execute('select estado,reserva_id::text from at_pedidos where id=%s',
                        (pedido['id'],)).fetchone() == ('pagado', pedido['reserva_id'])
    assert conn.execute('select count(*) from at_reservas where pedido_id=%s',
                        (pedido['id'],)).fetchone()[0] == 1


def test_recupera_lease_expirado_no_admite_finish_viejo(correos):
    conn = correos[0]
    paid(correos)
    viejo = operar(conn, 'tomar')
    conn.execute("update at_notificaciones set lease_hasta=clock_timestamp()-interval '1 second' where id=%s", (viejo['id'],))
    conn.execute("update at_notificaciones_control set permite_en=clock_timestamp()-interval '1 second'")
    nuevo = operar(conn, 'tomar')
    assert nuevo['id'] == viejo['id'] and nuevo['token'] != viejo['token']
    assert operar(conn, 'terminar', id=viejo['id'], token=viejo['token'], ok=True) is False
    assert operar(conn, 'terminar', id=nuevo['id'], token=nuevo['token'], ok=True) is True


def test_finish_rechaza_lease_vencido_aunque_no_haya_reclamacion(correos):
    conn = correos[0]
    paid(correos)
    trabajo = operar(conn, 'tomar')
    conn.execute("update at_notificaciones set lease_hasta=clock_timestamp()-interval '1 second' where id=%s", (trabajo['id'],))
    assert operar(conn, 'terminar', id=trabajo['id'], token=trabajo['token'], ok=True) is False


def test_throttle_global_persiste_despues_de_finalizar(correos):
    conn = correos[0]
    paid(correos, ['1A'])
    paid(correos, ['1C'])
    primero = operar(conn, 'tomar')
    assert operar(conn, 'terminar', id=primero['id'], token=primero['token'], ok=True) is True
    assert operar(conn, 'tomar') is None
    conn.execute("update at_notificaciones_control set permite_en=clock_timestamp()-interval '1 second'")
    segundo = operar(conn, 'tomar')
    assert segundo['id'] != primero['id']


@pytest.mark.parametrize('rol', ['anon', 'authenticated'])
def test_roles_publicos_no_leen_cola_ni_ejecutan_rpc(correos, rol):
    conn = correos[0]
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        with conn.transaction():
            conn.execute('set local role ' + rol)
            operar(conn, 'tomar')
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        with conn.transaction():
            conn.execute('set local role ' + rol)
            conn.execute('select * from public.at_notificaciones').fetchall()
    with conn.transaction():
        conn.execute('set local role service_role')
        assert operar(conn, 'tomar') is None


def limpiar_pedido(conn, pedido):
    conn.rollback()
    conn.execute('delete from at_notificaciones where pedido_id=%s', (pedido,))
    conn.execute('update at_pedidos set reserva_id=null where id=%s', (pedido,))
    conn.execute('delete from at_reservas where pedido_id=%s', (pedido,))
    conn.execute('update at_asientos set pedido_id=null where pedido_id=%s', (pedido,))
    conn.execute('delete from at_pedidos where id=%s', (pedido,))
    conn.execute("update at_notificaciones_control set permite_en='-infinity'")
    conn.commit()


def test_claims_concurrentes_reclaman_un_solo_trabajo(correos, isolated_database):
    conn = correos[0]
    pedido = paid(correos)
    conn.commit()
    barrera = threading.Barrier(2)

    def reclamar():
        with psycopg.connect(isolated_database) as otra:
            barrera.wait(timeout=5)
            return operar(otra, 'tomar')

    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            resultados = list(pool.map(lambda _: reclamar(), range(2)))
        assert sum(r is not None for r in resultados) == 1
        assert conn.execute('select intentos from at_notificaciones where pedido_id=%s',
                            (pedido['id'],)).fetchone()[0] == 1
    finally:
        limpiar_pedido(conn, pedido['id'])
