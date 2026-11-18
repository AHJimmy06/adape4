import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest
import requests
from requests.adapters import HTTPAdapter

from backend.notificaciones import ClienteMailtrap, DespachadorCorreos, ErrorCorreo


TOKEN = 'token_falso_de_prueba'
DATOS = {
    'nombre': 'Ana <script>alert(1)</script>', 'correo': 'ana@example.test',
    'reserva_id': 'reserva-123',
    'vuelo': {'codigo': 'AT105', 'salida_local': '2026-12-20T10:00:00',
              'ruta': {'origen': {'iata': 'UIO', 'nombre': 'Mariscal Sucre', 'ciudad': 'Quito', 'zona_horaria': 'America/Guayaquil'},
                       'destino': {'iata': 'GYE', 'nombre': 'José Joaquín de Olmedo', 'ciudad': 'Guayaquil'}}},
    'asientos': [{'codigo': '1A', 'clase_nombre': 'Ejecutiva'}],
    'subtotal_centavos': 12000, 'iva_centavos': 1800, 'total_centavos': 13800, 'moneda': 'USD',
}


@pytest.fixture
def servidor():
    estado = {'status': 200, 'body': {'success': True, 'message_ids': ['correo-123']},
              'headers': {}, 'delay': 0, 'calls': [], 'requested': []}

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            estado['calls'].append({'path': self.path, 'headers': dict(self.headers),
                                    'body': json.loads(self.rfile.read(int(self.headers['Content-Length'])))})
            time.sleep(estado['delay'])
            self.send_response(estado['status'])
            for key, value in estado['headers'].items():
                self.send_header(key, value)
            self.end_headers()
            body = estado['body']
            try:
                self.wfile.write((body if isinstance(body, str) else json.dumps(body)).encode())
            except (BrokenPipeError, ConnectionResetError):
                pass

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    class AdaptadorLocal(HTTPAdapter):
        def send(self, request, **kwargs):
            estado['requested'].append((request.url, kwargs['timeout']))
            request.url = request.url.replace('https://sandbox.api.mailtrap.io',
                                              f'http://127.0.0.1:{server.server_port}')
            if estado['delay']:
                kwargs['timeout'] = (.05, .05)
            return super().send(request, **kwargs)

    session = requests.Session()
    session.trust_env = False
    session.mount('https://sandbox.api.mailtrap.io/', AdaptadorLocal())
    yield estado, session
    session.close()
    server.shutdown()
    server.server_close()
    thread.join(timeout=2)


def cliente(servidor):
    return ClienteMailtrap(TOKEN, '42', 'reservas@aerotech.example', session=servidor[1])


def test_configuracion_deshabilitada_no_requiere_secretos():
    assert ClienteMailtrap.desde_entorno({}) is None
    assert ClienteMailtrap.desde_entorno({'MAILTRAP_ENABLED': 'false'}) is None


def test_configuracion_habilitada_usa_solo_sandbox():
    correo = ClienteMailtrap.desde_entorno({'MAILTRAP_ENABLED': 'true', 'MAILTRAP_API_TOKEN': TOKEN,
                                          'MAILTRAP_INBOX_ID': '42'})
    assert correo._url == 'https://sandbox.api.mailtrap.io/api/send/42'
    assert correo._remitente == 'reservas@aerotech.example'
    assert correo._session.trust_env is False
    assert TOKEN not in repr(correo)
    correo._session.close()


@pytest.mark.parametrize('cambio', [
    {'MAILTRAP_API_TOKEN': ''}, {'MAILTRAP_API_TOKEN': 'token\nsecreto'},
    {'MAILTRAP_INBOX_ID': 'https://evil.test'}, {'MAILTRAP_INBOX_ID': '0'},
    {'MAILTRAP_FROM_EMAIL': 'sin-correo'}, {'MAILTRAP_FROM_EMAIL': 'x@example.test\nBcc:y@example.test'},
])
def test_configuracion_invalida_es_segura(cambio):
    config = {'MAILTRAP_ENABLED': 'true', 'MAILTRAP_API_TOKEN': TOKEN,
              'MAILTRAP_INBOX_ID': '42', 'MAILTRAP_FROM_EMAIL': 'reservas@aerotech.example', **cambio}
    with pytest.raises(ValueError) as exc:
        ClienteMailtrap.desde_entorno(config)
    assert TOKEN not in str(exc.value)
    assert 'secreto' not in str(exc.value)


def test_http_real_sandbox_payload_escapado_y_timeout(servidor):
    assert cliente(servidor).enviar(DATOS) == 'correo-123'
    estado = servidor[0]
    assert estado['requested'] == [('https://sandbox.api.mailtrap.io/api/send/42', (3, 10))]
    llamada = estado['calls'][0]
    assert llamada['path'] == '/api/send/42'
    assert llamada['headers']['Authorization'] == 'Bearer ' + TOKEN
    body = llamada['body']
    assert body['to'] == [{'email': DATOS['correo'], 'name': DATOS['nombre']}]
    assert body['from']['email'] == 'reservas@aerotech.example'
    assert '<script>' not in body['html']
    assert '&lt;script&gt;' in body['html']
    for texto in ['AT105', 'Mariscal Sucre', 'José Joaquín de Olmedo', '1A', 'Ejecutiva', '138.00', '18.00', 'America/Guayaquil', 'reserva-123']:
        assert texto in body['text']
        assert texto in body['html']
    assert TOKEN not in json.dumps(body)


@pytest.mark.parametrize('status', [400, 401, 429, 500, 302])
def test_fallo_http_no_expone_respuesta_ni_sigue_redirect(servidor, status):
    estado = servidor[0]
    estado.update(status=status, body=TOKEN)
    estado['headers'] = {'Retry-After': '120', 'Location': 'http://127.0.0.1:1/robar'}
    with pytest.raises(ErrorCorreo) as exc:
        cliente(servidor).enviar(DATOS)
    assert exc.value.codigo == f'mailtrap_http_{status}'
    assert exc.value.reintentar_segundos >= 30
    if status == 429:
        assert exc.value.reintentar_segundos >= 120
    assert TOKEN not in str(exc.value)
    assert len(estado['calls']) == 1


@pytest.mark.parametrize('body', ['no-json', {'success': False}, {'success': True, 'message_ids': []},
                                  {'success': True, 'message_ids': 'incorrecto'}])
def test_respuesta_invalida_no_confirma_envio(servidor, body):
    servidor[0]['body'] = body
    with pytest.raises(ErrorCorreo) as exc:
        cliente(servidor).enviar(DATOS)
    assert exc.value.codigo == 'mailtrap_respuesta_invalida'


def test_timeout_real_tiene_resultado_desconocido_y_secreto_oculto(servidor):
    servidor[0]['delay'] = .15
    with pytest.raises(ErrorCorreo) as exc:
        cliente(servidor).enviar(DATOS)
    assert exc.value.codigo == 'mailtrap_no_disponible'
    assert TOKEN not in str(exc.value)


class Repositorio:
    def __init__(self, fila=True, fallo=None):
        self.fila, self.fallo, self.calls = fila, fallo, []

    def notificaciones_operar(self, accion, datos):
        self.calls.append((accion, datos))
        if accion == self.fallo:
            raise RuntimeError(TOKEN)
        if accion == 'tomar':
            return {'id': 'n1', 'token': 'lease-actual', 'datos': DATOS} if self.fila else None
        return {'actualizada': True}


def test_worker_confirma_solo_tras_http_valido(servidor):
    repo = Repositorio()
    assert DespachadorCorreos(repo, cliente(servidor)).procesar_uno() is True
    assert repo.calls[1] == ('terminar', {'id': 'n1', 'token': 'lease-actual', 'ok': True, 'proveedor_id': 'correo-123'})


def test_worker_fallo_agenda_sin_propagacion_y_no_incluye_body(servidor):
    repo = Repositorio()
    servidor[0].update(status=500, body=TOKEN)
    assert DespachadorCorreos(repo, cliente(servidor)).procesar_uno() is False
    fin = repo.calls[1][1]
    assert fin['ok'] is False and fin['reintentar_segundos'] >= 30
    assert fin['error_codigo'] == 'mailtrap_http_500'
    assert TOKEN not in json.dumps(repo.calls)


@pytest.mark.parametrize('fallo', ['tomar', 'terminar'])
def test_worker_error_rpc_no_propaga(servidor, fallo):
    repo = Repositorio(fallo=fallo)
    assert DespachadorCorreos(repo, cliente(servidor)).procesar_uno() is False


def test_worker_sin_fila_no_hace_http(servidor):
    repo = Repositorio(fila=False)
    assert DespachadorCorreos(repo, cliente(servidor)).procesar_uno() is False
    assert servidor[0]['calls'] == []
    assert len(repo.calls) == 1


@pytest.mark.parametrize('resultado', [False, None])
def test_worker_no_anuncia_exito_sin_ack_del_lease(servidor, resultado):
    class RepositorioLease(Repositorio):
        def notificaciones_operar(self, accion, datos):
            valor = super().notificaciones_operar(accion, datos)
            return resultado if accion == 'terminar' else valor

    assert DespachadorCorreos(RepositorioLease(), cliente(servidor)).procesar_uno() is False


def test_worker_inicio_repetido_crea_un_hilo_y_se_detiene(servidor):
    worker = DespachadorCorreos(Repositorio(fila=False), cliente(servidor))
    assert worker.iniciar() is worker
    hilo = worker._hilo
    assert hilo.daemon and hilo.is_alive()
    assert worker.iniciar()._hilo is hilo
    worker.detener()
    assert not hilo.is_alive()
