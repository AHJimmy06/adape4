"""Presentación del comprobante sin cambiar importes, asientos ni transporte."""
from copy import deepcopy
from html.parser import HTMLParser

from backend.notificaciones import _contenido


DATOS = {
    'nombre': 'Ana Torres', 'correo': 'ana@example.test',
    'reserva_id': 'reserva-confirmada-123',
    'vuelo': {
        'codigo': 'AT105', 'salida_local': '2026-12-01T09:45:00',
        'llegada_local': '2026-12-01T10:35:00',
        'ruta': {
            'origen': {'iata': 'UIO', 'nombre': 'Aeropuerto Mariscal Sucre',
                       'ciudad': 'Quito', 'zona_horaria': 'America/Guayaquil'},
            'destino': {'iata': 'GYE', 'nombre': 'Aeropuerto José Joaquín de Olmedo',
                        'ciudad': 'Guayaquil', 'zona_horaria': 'America/Guayaquil'},
        },
    },
    'asientos': [{'codigo': '1A', 'clase_nombre': 'Ejecutiva'},
                 {'codigo': '1C', 'clase_nombre': 'Ejecutiva'}],
    'subtotal_centavos': 24000, 'iva_centavos': 3600,
    'total_centavos': 27600, 'moneda': 'USD',
}


def test_correo_agradece_compra_y_confianza_con_saludo_personal():
    texto, html = _contenido(DATOS)
    for contenido in (texto, html):
        for esperado in ('Gracias por confiar en AeroTech', 'Gracias por tu compra', 'Ana Torres'):
            assert esperado in contenido


def test_comprobante_muestra_referencia_e_importes_persistidos_sin_recalcular():
    datos = deepcopy(DATOS)
    # El correo presenta el snapshot; no vuelve a aplicar porcentajes ni redondeos.
    datos.update(subtotal_centavos=9875, iva_centavos=1481, total_centavos=11356)
    texto, html = _contenido(datos)
    for contenido in (texto, html):
        for esperado in ('Comprobante de compra', 'reserva-confirmada-123', '98.75',
                         '14.81', '113.56', 'No es un documento fiscal'):
            assert esperado in contenido


def test_muestra_todos_los_asientos_confirmados_con_clase_y_ruta():
    texto, html = _contenido(DATOS)
    for contenido in (texto, html):
        for esperado in ('Asientos confirmados', '1A', '1C', 'Ejecutiva', 'AT105',
                         'UIO', 'GYE', 'Mariscal Sucre', 'José Joaquín de Olmedo'):
            assert esperado in contenido


def test_horarios_legibles_y_zonas_de_cada_aeropuerto():
    texto, html = _contenido(DATOS)
    for contenido in (texto, html):
        assert '01 dic 2026' in contenido
        assert '09:45' in contenido and '10:35' in contenido
        assert 'America/Guayaquil' in contenido


def test_html_completo_usa_tablas_sin_recursos_externos_ni_layout_web():
    _, html = _contenido(DATOS)
    assert html.lower().startswith('<!doctype html>')
    assert '<html lang="es"' in html
    assert 'charset="utf-8"' in html
    assert 'role="presentation"' in html
    assert '<table' in html and '</table>' in html
    assert html.rstrip().endswith('</html>')
    for prohibido in ('<script', '<main', '<link', '<img', 'display:flex',
                       'display:grid', 'border-radius', 'http://', 'https://'):
        assert prohibido not in html.lower()
    HTMLParser().feed(html)


def test_contenido_dinamico_se_escapa_sin_modificar_el_snapshot():
    datos = deepcopy(DATOS)
    datos['nombre'] = 'Ana <img src=x onerror=alert(1)>'
    datos['vuelo']['ruta']['destino']['nombre'] = '<script>no</script>'
    datos['asientos'][0]['clase_nombre'] = '<b>Ejecutiva</b>'
    original = deepcopy(datos)
    texto, html = _contenido(datos)
    assert datos == original
    assert '<img' not in html and '<script>' not in html and '<b>Ejecutiva</b>' not in html
    assert '&lt;img' in html and '&lt;script&gt;' in html and '&lt;b&gt;Ejecutiva&lt;/b&gt;' in html
    assert datos['nombre'] in texto
