"""Captura de confirmaciones en Mailtrap Sandbox, separada del pago."""

from html import escape
from datetime import datetime
import re
import threading
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

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


def _horario_correo(vuelo, momento, extremo):
    aeropuerto = (vuelo.get('ruta') or {}).get(extremo) or {}
    zona = aeropuerto.get('zona_horaria', '') if isinstance(aeropuerto, dict) else ''
    local = vuelo.get(f'{momento}_local')
    valor = local or vuelo.get(f'{momento}_en')
    if not valor:
        return 'Por confirmar'
    try:
        fecha = datetime.fromisoformat(str(valor).replace('Z', '+00:00'))
        if not local and fecha.tzinfo is not None and zona:
            fecha = fecha.astimezone(ZoneInfo(zona))
        meses = ('ene', 'feb', 'mar', 'abr', 'may', 'jun',
                 'jul', 'ago', 'sep', 'oct', 'nov', 'dic')
        texto = f'{fecha.day:02d} {meses[fecha.month - 1]} {fecha.year} · {fecha:%H:%M}'
    except (ValueError, ZoneInfoNotFoundError):
        texto = str(valor)
    return ' · '.join(p for p in (texto, zona) if p)


def _contenido(datos):
    vuelo = datos['vuelo']
    asientos = []
    for asiento in datos['asientos']:
        if isinstance(asiento, str):
            asientos.append((asiento, 'Asiento confirmado'))
        else:
            clase = asiento.get('clase_nombre') or asiento.get('clase_codigo') or 'Clase del vuelo'
            asientos.append((str(asiento['codigo']), str(clase)))
    origen, destino = _aeropuerto(vuelo, 'origen'), _aeropuerto(vuelo, 'destino')
    salida = _horario_correo(vuelo, 'salida', 'origen')
    llegada = _horario_correo(vuelo, 'llegada', 'destino')
    codigo = str(vuelo.get('codigo') or 'AeroTech')
    referencia = str(datos['reserva_id'])
    subtotal = _importe(datos, 'subtotal_centavos')
    iva = _importe(datos, 'iva_centavos')
    total = _importe(datos, 'total_centavos')
    detalles = [
        ('Cliente', str(datos['nombre'])), ('Correo', str(datos['correo'])),
        ('Referencia de reserva', referencia), ('Vuelo', codigo),
        ('Aeropuerto de origen', origen), ('Aeropuerto de destino', destino),
        ('Salida', salida), ('Llegada', llegada),
        ('Subtotal', subtotal), ('IVA', iva), ('Total pagado', total),
    ]
    saludo = f"Hola, {datos['nombre']}."
    aviso = 'Tu pago fue confirmado y estos son los detalles de tu reserva.'
    nota = 'Comprobante académico de reserva. No es un documento fiscal.'
    sandbox = 'Demostración en Mailtrap Sandbox: este correo no se entrega a un buzón real.'
    texto = '\n\n'.join([
        'Gracias por confiar en AeroTech', saludo, 'Gracias por tu compra', aviso,
        'Comprobante de compra\n' + '\n'.join(f'{k}: {v}' for k, v in detalles),
        'Asientos confirmados\n' + '\n'.join(f'{a} · {c}' for a, c in asientos),
        nota, sandbox,
    ])
    filas_asientos = ''.join(
        '<tr><td style="padding:12px;border-bottom:1px solid #dce7ef;color:#102d4b;font-weight:bold">'
        f'{escape(a)}</td><td style="padding:12px;border-bottom:1px solid #dce7ef;color:#526784">'
        f'{escape(c)}</td></tr>' for a, c in asientos
    )
    # Tablas e instrucciones inline: no dependemos de imágenes, scripts ni CSS externo.
    html = f'''<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Confirmación de reserva AeroTech</title></head>
<body style="margin:0;padding:0;background-color:#edf4f9;color:#102d4b;font-family:Arial,Helvetica,sans-serif">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#edf4f9">
<tr><td align="center" style="padding:24px 12px">
<!--[if mso]><table role="presentation" width="640" cellpadding="0" cellspacing="0" border="0"><tr><td><![endif]-->
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:640px;background-color:#ffffff;border:1px solid #dce7ef">
<tr><td style="padding:24px;background-color:#102d4b;color:#ffffff">
<p style="margin:0;font-size:24px;font-weight:bold;color:#ffffff">AeroTech</p>
<p style="margin:8px 0 0;font-size:11px;letter-spacing:2px;color:#a8e4eb">TU PRÓXIMA HISTORIA EMPIEZA CON UN VUELO</p>
</td></tr>
<tr><td style="padding:28px 24px 20px">
<p style="margin:0 0 12px;font-size:12px;font-weight:bold;color:#176bac">PAGO CONFIRMADO · RESERVA LISTA</p>
<p style="margin:0 0 16px;font-size:30px;line-height:38px;font-weight:bold;color:#102d4b">Gracias por confiar en AeroTech</p>
<p style="margin:0 0 8px;font-size:16px;line-height:24px">{escape(saludo)}</p>
<p style="margin:0;font-size:15px;line-height:24px"><strong>Gracias por tu compra.</strong> {escape(aviso)}</p>
</td></tr>
<tr><td style="padding:0 24px 24px">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#eef8fa;border-left:4px solid #1689a3">
<tr><td style="padding:16px;font-size:12px;color:#176bac;font-weight:bold">TU ITINERARIO · {escape(codigo)}</td></tr>
<tr><td style="padding:0 16px 16px;font-size:14px;line-height:22px">
<strong>Origen</strong><br>{escape(origen)}<br><span style="color:#526784">{escape(salida)}</span>
</td></tr>
<tr><td style="padding:0 16px 16px;font-size:14px;line-height:22px">
<strong>Destino</strong><br>{escape(destino)}<br><span style="color:#526784">{escape(llegada)}</span>
</td></tr></table>
</td></tr>
<tr><td style="padding:0 24px 24px">
<p style="margin:0 0 12px;font-size:19px;font-weight:bold">Asientos confirmados</p>
<p style="margin:0 0 12px;font-size:13px;color:#526784">{len(asientos)} {'asiento' if len(asientos) == 1 else 'asientos'} en tu reserva</p>
<table width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;font-size:14px">
<tr><th scope="col" align="left" style="padding:10px 12px;background-color:#edf4f9;color:#526784">Asiento</th>
<th scope="col" align="left" style="padding:10px 12px;background-color:#edf4f9;color:#526784">Clase</th></tr>
{filas_asientos}</table>
</td></tr>
<tr><td style="padding:0 24px 24px">
<p style="margin:0 0 14px;font-size:19px;font-weight:bold">Comprobante de compra</p>
<p style="margin:0 0 6px;font-size:12px;color:#526784">Referencia de reserva</p>
<p style="margin:0 0 14px;font-size:13px;color:#102d4b">{escape(referencia)}</p>
<p style="margin:0 0 4px;font-size:14px">{escape(str(datos['nombre']))}</p>
<p style="margin:0 0 16px;font-size:13px;color:#526784">{escape(str(datos['correo']))}</p>
<table width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;font-size:14px">
<tr><td style="padding:10px 0;color:#526784">Subtotal</td><td align="right" style="padding:10px 0">{escape(subtotal)}</td></tr>
<tr><td style="padding:10px 0;color:#526784">IVA</td><td align="right" style="padding:10px 0">{escape(iva)}</td></tr>
<tr><td style="padding:16px 12px;background-color:#102d4b;color:#ffffff;font-weight:bold">Total pagado</td>
<td align="right" style="padding:16px 12px;background-color:#102d4b;color:#ffffff;font-size:22px;font-weight:bold">{escape(total)}</td></tr>
</table>
</td></tr>
<tr><td style="padding:20px 24px;background-color:#f5f8fb;border-top:1px solid #dce7ef">
<p style="margin:0 0 8px;font-size:14px;font-weight:bold;color:#102d4b">Nos alegra acompañarte en tu próximo destino.</p>
<p style="margin:0 0 6px;font-size:12px;line-height:18px;color:#526784">{escape(nota)}</p>
<p style="margin:0;font-size:12px;line-height:18px;color:#526784">{escape(sandbox)}</p>
</td></tr>
</table>
<!--[if mso]></td></tr></table><![endif]-->
</td></tr></table></body></html>'''
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
