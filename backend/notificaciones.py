"""Captura de confirmaciones en Mailtrap Sandbox, separada del pago."""

from html import escape
import re
import threading

import requests


class ErrorCorreo(Exception):
    """Solo códigos seguros: nunca incluir respuestas, destinatarios ni claves."""

    def __init__(self, codigo, reintentar_segundos=60):
        self.codigo = codigo
        self.reintentar_segundos = max(30, min(int(reintentar_segundos), 86400))
        super().__init__(codigo)


def _correo_valido(valor):
    return isinstance(valor, str) and re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', valor) is not None


def _aeropuerto(vuelo, extremo):
    ruta = vuelo.get('ruta') or {}
    aeropuerto = ruta.get(extremo) or vuelo.get(extremo) or {}
    if isinstance(aeropuerto, str):
        return aeropuerto
    return ' · '.join(str(aeropuerto[k]) for k in ('nombre', 'iata', 'ciudad', 'pais') if aeropuerto.get(k)) or 'Por confirmar'


def _importe(datos, campo):
    valor = datos[campo]
    if not isinstance(valor, int) or isinstance(valor, bool) or valor < 0:
        raise ErrorCorreo('correo_datos_invalidos')
    return f'USD {valor // 100}.{valor % 100:02d}'


def _contenido(datos):
    vuelo = datos['vuelo']
    asientos = []
    for asiento in datos['asientos']:
        if isinstance(asiento, str):
            asientos.append(asiento)
        else:
            clase = asiento.get('clase_nombre') or asiento.get('clase_codigo') or ''
            asientos.append(' · '.join(str(v) for v in (asiento['codigo'], clase) if v))
    origen = (vuelo.get('ruta') or {}).get('origen') or {}
    zona = origen.get('zona_horaria', '') if isinstance(origen, dict) else ''
    detalles = [
        ('Reserva', str(datos['reserva_id'])),
        ('Vuelo', str(vuelo.get('codigo') or 'AeroTech')),
        ('Aeropuerto de origen', _aeropuerto(vuelo, 'origen')),
        ('Aeropuerto de destino', _aeropuerto(vuelo, 'destino')),
        ('Salida', ' · '.join(str(v) for v in (vuelo.get('salida_local') or vuelo.get('salida_en'), zona) if v)),
        ('Asientos', ', '.join(asientos)),
        ('Subtotal', _importe(datos, 'subtotal_centavos')),
        ('IVA', _importe(datos, 'iva_centavos')),
        ('Total pagado', _importe(datos, 'total_centavos')),
    ]
    saludo = f"Hola, {datos['nombre']}."
    aviso = 'Tu pago fue confirmado y tu reserva está lista.'
    nota = 'Correo de demostración de AeroTech. Capturado en Mailtrap Sandbox; no se entrega a un buzón real.'
    texto = '\n\n'.join([saludo, aviso, '\n'.join(f'{k}: {v}' for k, v in detalles), nota])
    filas = ''.join(f'<tr><th scope="row" style="padding:10px;text-align:left;color:#526784">{escape(k)}</th>'
                    f'<td style="padding:10px;color:#102d4b">{escape(v)}</td></tr>' for k, v in detalles)
    html = ('<!doctype html><html lang="es"><head><meta charset="utf-8"></head>'
            '<body style="margin:0;background:#f1f6fa;font-family:Arial,sans-serif;padding:24px">'
            '<main style="max-width:640px;margin:auto;background:white;border-radius:20px;padding:28px">'
            '<p style="color:#176bac;font-weight:bold">AEROTECH · CONFIRMACIÓN DE RESERVA</p>'
            '<h1 style="color:#102d4b">Tu próximo viaje está confirmado</h1>'
            f'<p>{escape(saludo)}</p><p>{escape(aviso)}</p>'
            f'<table style="width:100%;border-collapse:collapse">{filas}</table>'
            f'<p style="font-size:12px;color:#526784">{escape(nota)}</p></main></body></html>')
    return texto, html


class ClienteMailtrap:
    """El host es fijo para impedir entregas reales o destinos arbitrarios."""

    def __init__(self, api_token, inbox_id, remitente='reservas@aerotech.example', *, session=None):
        if (not isinstance(api_token, str) or not api_token or any(c.isspace() for c in api_token)
                or not re.fullmatch(r'[1-9][0-9]*', str(inbox_id)) or not _correo_valido(remitente)):
            raise ValueError('Configuración de Mailtrap Sandbox inválida.')
        self._token = api_token
        self._url = f'https://sandbox.api.mailtrap.io/api/send/{inbox_id}'
        self._remitente = remitente
        self._session = session or requests.Session()
        self._session.trust_env = False

    @classmethod
    def desde_entorno(cls, config):
        habilitado = str(config.get('MAILTRAP_ENABLED', '')).lower().strip()
        if habilitado in ('', 'false', '0', 'no'):
            return None
        if habilitado not in ('true', '1', 'yes'):
            raise ValueError('MAILTRAP_ENABLED debe indicar verdadero o falso.')
        return cls(config.get('MAILTRAP_API_TOKEN'), config.get('MAILTRAP_INBOX_ID'),
                   config.get('MAILTRAP_FROM_EMAIL', 'reservas@aerotech.example'))

    def enviar(self, datos):
        try:
            if not _correo_valido(datos['correo']):
                raise ErrorCorreo('correo_datos_invalidos')
            texto, html = _contenido(datos)
            mensaje = {
                'from': {'email': self._remitente, 'name': 'AeroTech'},
                'to': [{'email': datos['correo'], 'name': datos['nombre']}],
                'subject': f"AeroTech · Reserva confirmada · {datos['vuelo'].get('codigo') or 'Tu viaje'}",
                'text': texto, 'html': html, 'category': 'Confirmación de pago · Demostración',
            }
        except (KeyError, TypeError, ValueError, AttributeError):
            raise ErrorCorreo('correo_datos_invalidos') from None
        try:
            respuesta = self._session.post(self._url, json=mensaje,
                                          headers={'Authorization': f'Bearer {self._token}'},
                                          timeout=(3, 10), allow_redirects=False)
        except requests.RequestException:
            raise ErrorCorreo('mailtrap_no_disponible') from None
        try:
            if respuesta.status_code != 200:
                demora = 60
                if respuesta.status_code == 429:
                    valor = respuesta.headers.get('Retry-After', '')
                    demora = int(valor) if valor.isascii() and valor.isdigit() else 900
                raise ErrorCorreo(f'mailtrap_http_{respuesta.status_code}', demora)
            try:
                contenido = respuesta.json()
            except ValueError:
                raise ErrorCorreo('mailtrap_respuesta_invalida') from None
            ids = contenido.get('message_ids') if isinstance(contenido, dict) else None
            if (not isinstance(contenido, dict) or contenido.get('success') is not True
                    or not isinstance(ids, list) or not ids or not all(isinstance(i, str) and i for i in ids)):
                raise ErrorCorreo('mailtrap_respuesta_invalida')
            return ids[0]
        finally:
            respuesta.close()


class DespachadorCorreos:
    """Un envío por ciclo; la exclusión entre procesos la impone la cola SQL."""

    def __init__(self, repositorio, cliente):
        self._repositorio = repositorio
        self._cliente = cliente
        self._detener = threading.Event()
        self._inicio = threading.Lock()
        self._hilo = None

    def procesar_uno(self):
        try:
            fila = self._repositorio.notificaciones_operar('tomar', {})
            if fila is None:
                return False
            fin = {'id': fila['id'], 'token': fila['token']}
            try:
                referencia = self._cliente.enviar(fila['datos'])
            except ErrorCorreo as error:
                self._repositorio.notificaciones_operar('terminar', {
                    **fin, 'ok': False, 'error_codigo': error.codigo,
                    'reintentar_segundos': error.reintentar_segundos,
                })
                return False
            except Exception:
                self._repositorio.notificaciones_operar('terminar', {
                    **fin, 'ok': False, 'error_codigo': 'correo_no_disponible', 'reintentar_segundos': 60,
                })
                return False
            resultado = self._repositorio.notificaciones_operar('terminar', {
                **fin, 'ok': True, 'proveedor_id': referencia,
            })
            return resultado is not False and resultado is not None
        except Exception:
            # La cola conserva el lease para recuperarlo; ningún fallo altera el pago.
            return False

    def _ejecutar(self):
        while not self._detener.is_set():
            self.procesar_uno()
            self._detener.wait(15)

    def iniciar(self):
        with self._inicio:
            if self._hilo is None:
                self._hilo = threading.Thread(target=self._ejecutar, name='aerotech-correos', daemon=True)
                self._hilo.start()
        return self

    def detener(self, timeout=15):
        self._detener.set()
        if self._hilo is not None and self._hilo is not threading.current_thread():
            self._hilo.join(timeout=timeout)
