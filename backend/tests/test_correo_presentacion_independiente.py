"""Regresiones independientes de contenido y compatibilidad de la plantilla."""
import json
from copy import deepcopy
from html.parser import HTMLParser
from backend.notificaciones import _contenido, _horario_correo
DATA = {'nombre': 'Name <script>x</script> & "quote"', 'correo': 'safe@example.test', 'reserva_id': 'ref<>&"', 'vuelo': {'codigo': 'AT777<>&', 'salida_en': '2026-11-01T05:30:00Z', 'llegada_en': '2026-11-01T06:30:00+00:00', 'ruta': {'origen': {'iata': 'JFK', 'nombre': 'Airport <img src=x>', 'zona_horaria': 'America/New_York'}, 'destino': {'iata': 'MAD', 'nombre': 'Madrid & Barajas', 'zona_horaria': 'Europe/Madrid'}}}, 'asientos': ['7A<script>', {'codigo': '8B<>&', 'clase_codigo': 'ECO<>&'}], 'subtotal_centavos': 1, 'iva_centavos': 2, 'total_centavos': 999, 'moneda': 'USD'}

class Balanced(HTMLParser):

    def __init__(self):
        super().__init__()
        self.stack = []
        self.tags = []

    def handle_starttag(self, tag, attrs):
        self.tags.append(tag)
        assert tag not in ('script', 'img', 'link', 'main', 'iframe')
        assert all((not k.lower().startswith('on') and k.lower() not in ('href', 'src') for k, v in attrs))
        if tag not in ('meta', 'br', 'hr', 'input', 'img', 'link'):
            self.stack.append(tag)

    def handle_endtag(self, tag):
        assert self.stack.pop() == tag, (self.stack, tag)

def test_importes_asientos_escape_y_estructura_independientes():
    before = json.dumps(DATA, sort_keys=True)
    text, html = _contenido(DATA)
    assert json.dumps(DATA, sort_keys=True) == before
    for s in ['USD 0.01', 'USD 0.02', 'USD 9.99', 'Asientos confirmados', 'No es un documento fiscal', 'Gracias por tu compra', 'Gracias por confiar en AeroTech']:
        assert s in html and s in text, s
    for s in ['7A&lt;script&gt;', '8B&lt;&gt;&amp;', 'ECO&lt;&gt;&amp;', 'Airport &lt;img src=x&gt;', 'ref&lt;&gt;&amp;&quot;']:
        assert s in html, s
    assert 'Asiento confirmado' in html
    parser = Balanced()
    parser.feed(html)
    parser.close()
    assert not parser.stack
    assert parser.tags.count('table') >= 4
    for banned in ['http://', 'https://', 'border-radius', 'display:flex', 'display:grid', '<script', '<img']:
        assert banned not in html, banned

def test_horarios_utc_dst_locales_y_rutas_anteriores():
    assert _horario_correo(DATA['vuelo'], 'salida', 'origen') == '01 nov 2026 · 01:30 · America/New_York'
    assert _horario_correo(DATA['vuelo'], 'llegada', 'destino') == '01 nov 2026 · 07:30 · Europe/Madrid'
    d = deepcopy(DATA)
    d['vuelo']['salida_local'] = '2026-11-01T09:45:00'
    assert _horario_correo(d['vuelo'], 'salida', 'origen') == '01 nov 2026 · 09:45 · America/New_York'
    d['vuelo'] = {'codigo': 'OLD', 'origen': 'Old Origin', 'destino': 'Old Destination', 'salida_local': '2026-12-31T23:59:00'}
    text, html = _contenido(d)
    for s in ['Old Origin', 'Old Destination', '31 dic 2026', '23:59', 'Por confirmar']:
        assert s in text and s in html, s
