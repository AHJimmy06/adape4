"""Asignación y equipaje mediante la RPC privada con PostgreSQL aislado."""
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from pathlib import Path
import threading
from uuid import uuid4

import psycopg
import pytest
from psycopg.types.json import Jsonb

from backend.tests.test_sistema_integracion import core, create, FLIGHT


MIGRACION = Path('database/migrations/014_pasajeros_equipaje.sql')


@pytest.fixture
def pasajeros(core):
    conn = core[0]
    for nombre in ('010_programacion_vuelos.sql', '011_operaciones_aeropuertos.sql',
                   '012_estado_usuarios.sql', '013_notificaciones_pago.sql'):
        conn.execute(Path('database/migrations/' + nombre).read_text(encoding='utf-8'))
    if MIGRACION.exists():
        conn.execute(MIGRACION.read_text(encoding='utf-8'))
    # Las RPC usan savepoints; la transacción exterior la revierte sql_connection.
    conn.execute('select 1')
    return core


def solicitud(usuarios, **cambios):
    datos = dict(vuelo_id=FLIGHT, clave_operacion=str(uuid4()), asientos=['1A', '1C'],
                 pasajeros=[
                     dict(asiento='1A', correo_usuario=usuarios[2] + '@example.test',
                          categoria='adulto', maletas_adicionales=1),
                     dict(asiento='1C', correo_usuario=None,
                          categoria='nino', maletas_adicionales=2),
                 ])
    datos.update(cambios)
    return datos


def rpc(conn, usuario, datos, accion='crear_pedido'):
    with conn.transaction():
        return conn.execute('select public.sistema_operar(%s,%s,%s)',
                            (accion, usuario, Jsonb(datos))).fetchone()[0]


def test_snapshots_autoritativos_y_20_dolares_finales_por_maleta(pasajeros):
    conn, _, _, _, _, usuarios, _ = pasajeros
    datos = solicitud(usuarios)
    pedido = rpc(conn, usuarios[1], datos)
    primero, segundo = pedido['asientos']
    assert pedido['usuario_id'] == usuarios[1]
    assert primero['pasajero'] == dict(usuario_id=usuarios[2], nombre='USER',
                                      correo=usuarios[2] + '@example.test',
                                      categoria='adulto', asignado=True)
    assert segundo['pasajero'] == dict(categoria='nino', asignado=False)
    for asiento, cantidad in ((primero, 1), (segundo, 2)):
        extra = asiento['equipaje']
        assert extra == dict(cantidad=cantidad, precio_unitario_centavos=2000,
                             subtotal_centavos=1739 * cantidad, iva_centavos=261 * cantidad,
                             total_centavos=2000 * cantidad)
        assert asiento['tarifa_subtotal_centavos'] == 12000
        assert asiento['tarifa_iva_centavos'] == 1800
        assert asiento['tarifa_total_centavos'] == 13800
        assert asiento['total_centavos'] == 13800 + 2000 * cantidad
        assert asiento['subtotal_centavos'] + asiento['iva_centavos'] == asiento['total_centavos']
    assert pedido['total_centavos'] == 33600
    for campo in ('subtotal_centavos', 'iva_centavos', 'total_centavos'):
        assert pedido[campo] == sum(s[campo] for s in pedido['asientos'])
    assert pedido['solicitud'] == datos


def test_legacy_sin_pasajeros_conserva_pedido_y_reintento_exactos(pasajeros):
    conn, _, _, _, _, usuarios, _ = pasajeros
    datos = solicitud(usuarios)
    datos.pop('pasajeros')
    primero = rpc(conn, usuarios[1], datos)
    anterior = conn.execute('select public.sistema_operar_base_014(%s,%s,%s)',
                            ('crear_pedido', usuarios[1], Jsonb(datos))).fetchone()[0]
    assert primero == anterior == rpc(conn, usuarios[1], datos)
    assert primero['solicitud'] == datos
    assert all('pasajero' not in a and 'equipaje' not in a for a in primero['asientos'])
    assert primero['total_centavos'] == 27600


def test_normaliza_idempotencia_y_no_reaplica_extras_al_reintentar(pasajeros):
    conn, _, _, _, _, usuarios, _ = pasajeros
    datos = solicitud(usuarios)
    datos['asientos'].reverse()
    datos['pasajeros'].reverse()
    datos['pasajeros'][1]['correo_usuario'] = '  ' + datos['pasajeros'][1]['correo_usuario'].upper() + '  '
    datos['pasajeros'][1]['categoria'] = 'adulto_mayor'
    primero = rpc(conn, usuarios[1], datos)
    normalizada = solicitud(usuarios, clave_operacion=datos['clave_operacion'])
    segundo = rpc(conn, usuarios[1], normalizada)
    assert primero == segundo
    assert primero['solicitud'] == normalizada
    assert primero['total_centavos'] == 33600
    assert conn.execute('select count(*) from at_pedidos').fetchone()[0] == 1
    # El snapshot comprado no cambia si más tarde se edita/desactiva al asignatario.
    conn.execute("update usuarios set nombre='Cambio posterior',activo=false where id=%s", (usuarios[2],))
    assert rpc(conn, usuarios[1], normalizada) == primero
    cambiado = deepcopy(normalizada)
    cambiado['pasajeros'][0]['maletas_adicionales'] = 2
    with pytest.raises(psycopg.Error, match='CONFLICTO:'):
        rpc(conn, usuarios[1], cambiado)


@pytest.mark.parametrize('cambio', [
    {'pasajeros': None}, {'pasajeros': []},
    {'pasajeros': [{'asiento': '1A', 'categoria': 'adulto', 'maletas_adicionales': 0}]},
    {'pasajeros': [{'asiento': '1A'}, {'asiento': '1A'}]},
    {'pasajeros': [{'asiento': '1A'}, {'asiento': '1D'}]},
])
def test_rechaza_lista_incompleta_duplicada_o_de_otro_asiento_sin_retenciones(pasajeros, cambio):
    conn, _, _, _, _, usuarios, _ = pasajeros
    with pytest.raises(psycopg.Error, match='INVALIDO:'):
        rpc(conn, usuarios[1], solicitud(usuarios, **cambio))
    assert conn.execute('select count(*) from at_pedidos').fetchone()[0] == 0
    assert conn.execute('select count(*) from at_asientos where pedido_id is not null').fetchone()[0] == 0


@pytest.mark.parametrize('cantidad', [-1, True, 1.5, '1', None, 50000, 9999999999999999999999])
def test_cantidad_equipaje_entera_y_acotada_sin_overflow(pasajeros, cantidad):
    conn, _, _, _, _, usuarios, _ = pasajeros
    datos = solicitud(usuarios)
    datos['pasajeros'][0]['maletas_adicionales'] = cantidad
    with pytest.raises(psycopg.Error, match='INVALIDO:'):
        rpc(conn, usuarios[1], datos)
    assert conn.execute('select count(*) from at_pedidos').fetchone()[0] == 0
    assert conn.execute('select count(*) from at_asientos where pedido_id is not null').fetchone()[0] == 0


@pytest.mark.parametrize('correo', ['ausente@example.test', '', 'no-es-correo'])
def test_usuario_asignado_debe_existir_y_ser_activo(pasajeros, correo):
    conn, _, _, _, _, usuarios, _ = pasajeros
    datos = solicitud(usuarios)
    datos['pasajeros'][0]['correo_usuario'] = correo
    with pytest.raises(psycopg.Error, match='INVALIDO:'):
        rpc(conn, usuarios[1], datos)
    assert conn.execute('select count(*) from at_pedidos').fetchone()[0] == 0
    conn.execute('update usuarios set activo=false where id=%s', (usuarios[2],))
    with pytest.raises(psycopg.Error, match='Usuario asignado inexistente o inactivo'):
        rpc(conn, usuarios[1], solicitud(usuarios))
    assert conn.execute('select count(*) from at_asientos where pedido_id is not null').fetchone()[0] == 0


@pytest.mark.parametrize('extra', [{'precio_centavos': 1}, {'total_centavos': 1}, {'usuario_id': 'inventado'}, {'nombre': 'Suplantado'}])
def test_no_acepta_identidad_o_dinero_desde_cliente(pasajeros, extra):
    conn, _, _, _, _, usuarios, _ = pasajeros
    datos = solicitud(usuarios)
    datos['pasajeros'][0].update(extra)
    with pytest.raises(psycopg.Error, match='INVALIDO:'):
        rpc(conn, usuarios[1], datos)
    assert conn.execute('select count(*) from at_pedidos').fetchone()[0] == 0


def test_categorias_descriptivas_no_cambian_tarifas_y_cero_equipaje(pasajeros):
    conn, _, _, _, _, usuarios, _ = pasajeros
    datos = solicitud(usuarios)
    for persona, categoria in zip(datos['pasajeros'], ['adulto_mayor', 'nino']):
        persona.update(correo_usuario=None, categoria=categoria, maletas_adicionales=0)
    pedido = rpc(conn, usuarios[1], datos)
    assert pedido['total_centavos'] == 27600
    assert [s['pasajero']['categoria'] for s in pedido['asientos']] == ['adulto_mayor', 'nino']
    assert all(s['equipaje']['total_centavos'] == 0 for s in pedido['asientos'])
    cambiado = deepcopy(datos)
    cambiado['pasajeros'][0]['categoria'] = 'descuento'
    cambiado['clave_operacion'] = str(uuid4())
    with pytest.raises(psycopg.Error, match='INVALIDO:'):
        rpc(conn, usuarios[1], cambiado)


def test_limite_tecnico_stripe_incluye_equipaje_y_no_deja_pedido(pasajeros):
    conn, _, _, _, _, usuarios, _ = pasajeros
    datos = solicitud(usuarios)
    datos['pasajeros'][0]['maletas_adicionales'] = 49999
    with pytest.raises(psycopg.Error, match='máximo técnico de Stripe'):
        rpc(conn, usuarios[1], datos)
    assert conn.execute('select count(*) from at_pedidos').fetchone()[0] == 0
    assert conn.execute('select count(*) from at_asientos where pedido_id is not null').fetchone()[0] == 0


def test_cantidad_maxima_es_tecnica_no_limite_comercial_si_total_cabe(pasajeros):
    conn, _, _, _, _, usuarios, _ = pasajeros
    conn.execute("update at_asientos set precio_centavos=50 where vuelo_id=%s and codigo='1A'", (FLIGHT,))
    datos = solicitud(usuarios, asientos=['1A'])
    datos['pasajeros'] = [dict(asiento='1A', correo_usuario=None, categoria='adulto', maletas_adicionales=49999)]
    pedido = rpc(conn, usuarios[1], datos)
    assert pedido['total_centavos'] == 99998058
    assert pedido['asientos'][0]['equipaje']['cantidad'] == 49999
    assert pedido['subtotal_centavos'] + pedido['iva_centavos'] == pedido['total_centavos']


def test_comprador_inactivo_no_elude_guardia_previa(pasajeros):
    conn, _, _, _, _, usuarios, _ = pasajeros
    conn.execute('update usuarios set activo=false where id=%s', (usuarios[1],))
    for datos in (solicitud(usuarios), {k: v for k, v in solicitud(usuarios).items() if k != 'pasajeros'}):
        with pytest.raises(psycopg.Error, match='PROHIBIDO:'):
            rpc(conn, usuarios[1], datos)
    assert conn.execute('select count(*) from at_pedidos').fetchone()[0] == 0


def test_cancelacion_parcial_reembolsa_tarifa_y_equipaje_y_no_delega_propiedad(pasajeros):
    conn, _, proveedor, _, cliente, usuarios, cabeceras = pasajeros
    pedido = rpc(conn, usuarios[1], solicitud(usuarios))
    # Checkout y confirmación siguen el flujo HTTP existente del comprador.
    pedido = cliente.get('/api/sistema/pedidos/' + pedido['id'], headers=cabeceras[1]).json['pedido']
    proveedor.pay(pedido['id'])
    pagado = cliente.get('/api/sistema/pedidos/' + pedido['id'], headers=cabeceras[1]).json['pedido']
    assert pagado['estado'] == 'pagado'
    reserva = pagado['reserva_id']
    assert cliente.get('/api/sistema/pedidos/' + pedido['id'], headers=cabeceras[2]).status_code == 404
    assert cliente.get('/api/sistema/reservas/' + reserva + '/comprobante', headers=cabeceras[2]).status_code in (404, 405)
    path = '/api/sistema/reservas/' + reserva + '/cancelaciones'
    assert cliente.post(path, headers=cabeceras[2], json=dict(asientos=['1A'], clave_operacion=str(uuid4()))).status_code == 404
    primero = cliente.post(path, headers=cabeceras[1], json=dict(asientos=['1A'], clave_operacion=str(uuid4())))
    assert primero.status_code == 200, primero.json
    assert primero.json['cancelacion']['importe_centavos'] == 15800
    assert primero.json['cancelacion']['estado'] == 'cancelado'
    assert conn.execute("select pedido_id is null from at_asientos where vuelo_id=%s and codigo='1A'", (FLIGHT,)).fetchone()[0]
    segundo = cliente.post(path, headers=cabeceras[1], json=dict(asientos=['1C'], clave_operacion=str(uuid4())))
    assert segundo.status_code == 200, segundo.json
    assert segundo.json['cancelacion']['importe_centavos'] == 17800
    assert sum(r['amount'] for r in proveedor.refunds.values()) == pagado['total_centavos'] == 33600


def test_migracion_repetida_y_funciones_base_no_publicas(pasajeros):
    conn, _, _, _, _, usuarios, _ = pasajeros
    pedido = rpc(conn, usuarios[1], solicitud(usuarios))
    conn.commit()
    try:
        conn.execute(MIGRACION.read_text(encoding='utf-8'))
        assert rpc(conn, usuarios[1], solicitud(usuarios, clave_operacion=pedido['clave_operacion'])) == pedido
        for rol in ('anon', 'authenticated', 'service_role'):
            assert not conn.execute("select has_function_privilege(%s,'public.sistema_operar_base_014(text,uuid,jsonb)','EXECUTE')", (rol,)).fetchone()[0]
        assert conn.execute("select has_function_privilege('service_role','public.sistema_operar(text,uuid,jsonb)','EXECUTE')").fetchone()[0]
        assert not conn.execute("select has_function_privilege('anon','public.sistema_operar(text,uuid,jsonb)','EXECUTE')").fetchone()[0]
    finally:
        limpiar(conn, pedido['id'])


def limpiar(conn, pedido):
    conn.rollback()
    conn.execute('delete from at_notificaciones where pedido_id=%s', (pedido,))
    conn.execute('update at_pedidos set reserva_id=null where id=%s', (pedido,))
    conn.execute('delete from at_reservas where pedido_id=%s', (pedido,))
    conn.execute('update at_asientos set pedido_id=null where pedido_id=%s', (pedido,))
    conn.execute('delete from at_pedidos where id=%s', (pedido,))
    conn.commit()


def test_competencia_por_asiento_solo_gana_un_comprador(pasajeros, isolated_database):
    conn, _, _, _, _, usuarios, _ = pasajeros
    conn.commit()
    barrera = threading.Barrier(2)

    def comprar(usuario):
        datos = dict(vuelo_id=FLIGHT, clave_operacion=str(uuid4()), asientos=['1A'],
                     pasajeros=[dict(asiento='1A', correo_usuario=None, categoria='adulto', maletas_adicionales=1)])
        with psycopg.connect(isolated_database) as otra:
            barrera.wait(timeout=5)
            try:
                return rpc(otra, usuario, datos)
            except psycopg.Error as error:
                assert 'CONFLICTO:' in str(error)
                return None

    ganadores = []
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            resultados = list(pool.map(comprar, usuarios[1:]))
        ganadores = [r for r in resultados if r]
        assert len(ganadores) == 1
        assert ganadores[0]['total_centavos'] == 15800
        assert conn.execute('select count(*) from at_pedidos').fetchone()[0] == 1
    finally:
        for ganador in ganadores:
            limpiar(conn, ganador['id'])
