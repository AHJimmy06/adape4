"""Destinatarios por pago y privacidad con PostgreSQL y Stripe simulado."""
from copy import deepcopy
import json
from pathlib import Path
from uuid import uuid4

import psycopg
from psycopg.types.json import Jsonb
import pytest

from backend.tests.test_sistema_integracion import core, FLIGHT
from backend.tests.test_pasajeros_equipaje_sql import limpiar


MIGRACION = Path('database/migrations/015_notificaciones_pasajeros.sql')


@pytest.fixture
def correos(core):
    conn = core[0]
    for nombre in ('010_programacion_vuelos.sql', '011_operaciones_aeropuertos.sql',
                   '012_estado_usuarios.sql', '013_notificaciones_pago.sql',
                   '014_pasajeros_equipaje.sql'):
        conn.execute(Path('database/migrations/' + nombre).read_text(encoding='utf-8'))
    if MIGRACION.exists():
        conn.execute(MIGRACION.read_text(encoding='utf-8'))
    conn.execute('select 1')
    return core


def crear(contexto, destinatarios=None):
    conn, _, _, app, _, usuarios, _ = contexto
    destinatarios = destinatarios or [usuarios[2], None]
    seleccion = dict(vuelo_id=FLIGHT, clave_operacion=str(uuid4()), asientos=['1A', '1C'],
        pasajeros=[dict(asiento=codigo, correo_usuario=usuario + '@example.test' if usuario else None,
                        categoria='adulto' if usuario else 'nino', maletas_adicionales=cantidad)
                   for codigo, usuario, cantidad in zip(['1A', '1C'], destinatarios, [1, 2])])
    pedido = conn.execute('select public.sistema_operar(%s,%s,%s)',
                          ('crear_pedido', usuarios[1], Jsonb(seleccion))).fetchone()[0]
    return app.extensions['sistema'].checkout(pedido)


def pagar(contexto, pedido):
    _, _, proveedor, app, _, _, cabeceras = contexto
    proveedor.pay(pedido['id'])
    otro_cliente = app.test_client()
    resultado = otro_cliente.get('/api/sistema/pedidos/' + pedido['id'], headers=cabeceras[1])
    assert resultado.status_code == 200, resultado.json
    assert resultado.json['pedido']['estado'] == 'pagado'
    return resultado.json['pedido']


def mensajes(conn, pedido):
    return [fila[0] for fila in conn.execute(
        'select datos from at_notificaciones where pedido_id=%s order by datos->>\'correo\'',
        (pedido['id'],)).fetchall()]


def test_otro_cliente_confirma_y_encola_comprador_y_pasajero_propio(correos):
    conn, _, _, app, _, usuarios, cabeceras = correos
    pedido = crear(correos)
    assert mensajes(conn, pedido) == []
    assert app.test_client().get('/api/sistema/pedidos/' + pedido['id'], headers=cabeceras[1]).status_code == 200
    assert mensajes(conn, pedido) == []
    pagado = pagar(correos, pedido)
    todos = mensajes(conn, pedido)
    assert len(todos) == 2
    comprador = next(m for m in todos if m['correo'] == usuarios[1] + '@example.test')
    pasajero = next(m for m in todos if m['correo'] == usuarios[2] + '@example.test')
    assert len(comprador['asientos']) == 2 and comprador['total_centavos'] == 33600
    assert comprador['reserva_id'] == pagado['reserva_id']
    assert pasajero['tipo'] == 'pasajero'
    assert [a['codigo'] for a in pasajero['asientos']] == ['1A']
    assert pasajero['total_centavos'] == 15800
    assert pasajero['subtotal_centavos'] + pasajero['iva_centavos'] == 15800
    assert pasajero['asientos'][0]['equipaje']['total_centavos'] == 2000
    assert 'reserva_id' not in pasajero
    assert not any(k in json.dumps(pasajero) for k in ('usuario_id', 'payment_intent', 'session_id', pagado['reserva_id']))
    assert pasajero['vuelo']['ruta']['origen']['nombre']
    assert pasajero['vuelo']['codigo'] == comprador['vuelo']['codigo']


@pytest.mark.parametrize('mismo_comprador', [False, True])
def test_deduplica_varios_asientos_y_comprador_tambien_asignado(correos, mismo_comprador):
    conn, _, _, _, _, usuarios, _ = correos
    receptor = usuarios[1] if mismo_comprador else usuarios[2]
    pedido = crear(correos, [receptor, receptor])
    pagar(correos, pedido)
    todos = mensajes(conn, pedido)
    assert len(todos) == (1 if mismo_comprador else 2)
    if not mismo_comprador:
        propio = next(m for m in todos if m['tipo'] == 'pasajero')
        assert [a['codigo'] for a in propio['asientos']] == ['1A', '1C']
        assert propio['total_centavos'] == 33600


def test_beneficiarios_distintos_no_comparten_nombres_importes_ni_asientos(correos):
    conn, _, _, _, _, usuarios, _ = correos
    conn.execute("update usuarios set nombre='Pasajero Uno' where id=%s", (usuarios[0],))
    conn.execute("update usuarios set nombre='Pasajero Dos' where id=%s", (usuarios[2],))
    pedido = crear(correos, [usuarios[0], usuarios[2]])
    pagar(correos, pedido)
    todos = mensajes(conn, pedido)
    assert len(todos) == 3
    propios = [m for m in todos if m.get('tipo') == 'pasajero']
    for mensaje in propios:
        propio = mensaje['nombre'] == 'Pasajero Uno'
        assert [a['codigo'] for a in mensaje['asientos']] == (['1A'] if propio else ['1C'])
        assert mensaje['total_centavos'] == (15800 if propio else 17800)
        assert ('Pasajero Dos' if propio else 'Pasajero Uno') not in json.dumps(mensaje)
        assert all(a['pasajero']['correo'] == mensaje['correo'] for a in mensaje['asientos'])


def test_deduplica_correo_actual_del_beneficiario_igual_al_comprador_sin_importar_mayusculas(correos):
    conn, _, _, _, _, usuarios, _ = correos
    pedido = crear(correos)
    conn.execute('update usuarios set correo=%s where id=%s',
                 ((usuarios[1] + '@example.test').upper(), usuarios[2]))
    pagar(correos, pedido)
    todos = mensajes(conn, pedido)
    assert len(todos) == 1 and todos[0]['correo'] == usuarios[1] + '@example.test'


def test_destinatario_usa_id_y_perfil_vigente_no_correo_manipulado(correos):
    conn, _, _, _, _, usuarios, _ = correos
    pedido = crear(correos)
    snapshot = deepcopy(pedido['asientos'])
    snapshot[0]['pasajero'].update(correo='externo@example.test', nombre='Nombre manipulado')
    conn.execute('update at_pedidos set asientos=%s where id=%s', (Jsonb(snapshot), pedido['id']))
    conn.execute("update usuarios set correo='nuevo@example.test',nombre='Pasajero vigente' where id=%s", (usuarios[2],))
    pagar(correos, pedido)
    pasajero = next(m for m in mensajes(conn, pedido) if m.get('tipo') == 'pasajero')
    assert pasajero['correo'] == 'nuevo@example.test' and pasajero['nombre'] == 'Pasajero vigente'
    assert pasajero['asientos'][0]['pasajero']['correo'] == 'nuevo@example.test'
    assert pasajero['asientos'][0]['pasajero']['nombre'] == 'Pasajero vigente'
    assert 'externo@example.test' not in json.dumps(pasajero)
    assert 'Nombre manipulado' not in json.dumps(pasajero)
    assert conn.execute('select asientos from at_pedidos where id=%s', (pedido['id'],)).fetchone()[0] == snapshot


@pytest.mark.parametrize('eliminado', [False, True])
def test_asignatario_desactivado_o_eliminado_no_recibe_ni_bloquea_pago(correos, eliminado):
    conn, _, _, _, _, usuarios, _ = correos
    pedido = crear(correos)
    conn.execute('delete from usuarios where id=%s' if eliminado else 'update usuarios set activo=false where id=%s', (usuarios[2],))
    pagar(correos, pedido)
    todos = mensajes(conn, pedido)
    assert len(todos) == 1 and todos[0]['correo'] == usuarios[1] + '@example.test'


def test_id_no_registrado_no_recurre_al_correo_del_snapshot(correos):
    conn = correos[0]
    pedido = crear(correos)
    snapshot = deepcopy(pedido['asientos'])
    snapshot[0]['pasajero']['usuario_id'] = 'identificador-no-valido'
    conn.execute('update at_pedidos set asientos=%s where id=%s', (Jsonb(snapshot), pedido['id']))
    pagar(correos, pedido)
    assert len(mensajes(conn, pedido)) == 1


def test_replay_y_eventos_fuera_orden_no_reenvian(correos):
    conn, _, proveedor, _, cliente, _, cabeceras = correos
    pedido = crear(correos)
    sesion = proveedor.sessions[pedido['id']]
    evento = dict(id='evt_sin_pago', livemode=False, type='checkout.session.completed',
                  data={'object': {'id': sesion['id'], 'metadata': sesion['metadata']}})
    firma = {'Stripe-Signature': 'verified-test-signature', 'Content-Type': 'application/json'}
    assert cliente.post('/api/stripe/webhook', data=json.dumps(evento), headers=firma).status_code == 200
    assert mensajes(conn, pedido) == []
    proveedor.pay(pedido['id'])
    evento['id'] = 'evt_pago_confirmado'
    for _ in range(2):
        assert cliente.post('/api/stripe/webhook', data=json.dumps(evento), headers=firma).status_code == 200
    evento.update(id='evt_expiracion_tardia', type='checkout.session.expired')
    assert cliente.post('/api/stripe/webhook', data=json.dumps(evento), headers=firma).status_code == 200
    assert cliente.get('/api/sistema/pedidos/' + pedido['id'], headers=cabeceras[1]).json['pedido']['estado'] == 'pagado'
    assert len(mensajes(conn, pedido)) == 2


def test_migracion_repetida_no_backfill_y_preserva_trabajo_legacy(correos):
    conn = correos[0]
    pedido = crear(correos)
    conn.execute('alter table at_pedidos disable trigger at_notificar_pago')
    pagado = pagar(correos, pedido)
    conn.execute('alter table at_pedidos enable trigger at_notificar_pago')
    original = dict(nombre='Comprador anterior', correo='anterior@example.test', reserva_id=pagado['reserva_id'],
                    vuelo={}, asientos=[], subtotal_centavos=0, iva_centavos=0, total_centavos=0, moneda='USD')
    fila = conn.execute("insert into at_notificaciones(pedido_id,datos,estado,proveedor_id) values(%s,%s,'enviado','legacy-id') returning to_jsonb(at_notificaciones.*)",
                        (pedido['id'], Jsonb(original))).fetchone()[0]
    conn.commit()
    try:
        for _ in range(2):
            conn.execute(MIGRACION.read_text(encoding='utf-8'))
        assert conn.execute('select to_jsonb(n.*) from at_notificaciones n where pedido_id=%s', (pedido['id'],)).fetchall() == [(fila,)]
        conn.execute("update at_pedidos set estado='revision_pago' where id=%s", (pedido['id'],))
        conn.execute("update at_pedidos set estado='pagado' where id=%s", (pedido['id'],))
        assert conn.execute('select to_jsonb(n.*) from at_notificaciones n where pedido_id=%s', (pedido['id'],)).fetchall() == [(fila,)]
    finally:
        limpiar(conn, pedido['id'])


def test_cola_privada_conserva_lease_y_throttle_para_dos_destinatarios(correos):
    conn = correos[0]
    pedido = crear(correos)
    pagar(correos, pedido)

    def operar(accion, **datos):
        return conn.execute('select notificaciones_operar(%s,%s)', (accion, Jsonb(datos))).fetchone()[0]

    primero = operar('tomar')
    assert primero and operar('tomar') is None
    assert operar('terminar', id=primero['id'], token=primero['token'], ok=True, proveedor_id='captura-1') is True
    assert operar('tomar') is None
    conn.execute("update at_notificaciones_control set permite_en=clock_timestamp()-interval '1 second'")
    segundo = operar('tomar')
    assert segundo and segundo['datos']['correo'] != primero['datos']['correo']
    assert operar('terminar', id=segundo['id'], token=primero['token'], ok=True) is False
    for rol in ('anon', 'authenticated'):
        assert not conn.execute("select has_function_privilege(%s,'notificaciones_operar(text,jsonb)','EXECUTE')", (rol,)).fetchone()[0]
        assert not conn.execute("select has_function_privilege(%s,'at_encolar_confirmacion_pago()','EXECUTE')", (rol,)).fetchone()[0]
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            with conn.transaction():
                conn.execute('set local role ' + rol)
                conn.execute('select * from at_notificaciones')
