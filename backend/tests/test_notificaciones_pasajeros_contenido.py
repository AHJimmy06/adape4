"""La versión personal no revela datos del comprador ni de otros asientos."""
from copy import deepcopy

import pytest

from backend.notificaciones import ErrorCorreo, _contenido
from backend.tests.test_correo_presentacion import DATOS


def propio():
    datos = deepcopy(DATOS)
    datos.pop('reserva_id')
    datos.update(tipo='pasajero', nombre='Luis Pasajero', correo='luis@example.test',
                 asientos=[dict(codigo='2A', clase_nombre='Económica',
                    pasajero=dict(nombre='Luis Pasajero', correo='luis@example.test', categoria='adulto', asignado=True),
                    equipaje=dict(cantidad=1, precio_unitario_centavos=2000, subtotal_centavos=1739, iva_centavos=261, total_centavos=2000),
                    tarifa_subtotal_centavos=10000, tarifa_iva_centavos=1500, tarifa_total_centavos=11500,
                    subtotal_centavos=11739, iva_centavos=1761, total_centavos=13500)],
                 subtotal_centavos=11739, iva_centavos=1761, total_centavos=13500)
    return datos


def test_pasajero_recibe_confirmacion_propia_sin_comprobante_del_comprador():
    datos = propio()
    antes = deepcopy(datos)
    texto, html = _contenido(datos)
    assert datos == antes
    for cuerpo in (texto, html):
        for valor in ('Luis Pasajero', '2A', '135.00', 'Equipaje adicional', '20.00', 'Mariscal Sucre', 'AT105', 'Mailtrap Sandbox'):
            assert valor in cuerpo
        for ajeno in ('Ana Torres', '1A', '1C', '276.00', 'reserva-confirmada-123', 'Gracias por tu compra', 'Comprobante de compra', 'Referencia de reserva'):
            assert ajeno not in cuerpo


def test_version_personal_no_imprime_ids_y_usa_sumas_solo_de_sus_asientos():
    datos = propio()
    datos.update(reserva_id='id-privado-del-comprador', total_centavos=99999999, subtotal_centavos=86956521, iva_centavos=13043478)
    datos['asientos'][0]['pasajero'].update(usuario_id='id-privado-pasajero')
    for cuerpo in _contenido(datos):
        assert '135.00' in cuerpo and '999999.99' not in cuerpo
        assert 'id-privado-del-comprador' not in cuerpo and 'id-privado-pasajero' not in cuerpo


def test_no_admite_asientos_de_otro_destinatario_en_mensaje_personal():
    datos = propio()
    datos['asientos'][0]['pasajero']['correo'] = 'otra-persona@example.test'
    with pytest.raises(ErrorCorreo, match='correo_datos_invalidos'):
        _contenido(datos)


def test_texto_personal_escapa_html_y_conserva_comprador_legacy():
    datos = propio()
    datos['nombre'] = '<script>Pasajero</script>'
    datos['asientos'][0]['pasajero']['nombre'] = datos['nombre']
    texto, html = _contenido(datos)
    assert '<script>Pasajero</script>' in texto
    assert '<script>' not in html and '&lt;script&gt;Pasajero&lt;/script&gt;' in html
    texto_legacy, html_legacy = _contenido(DATOS)
    for cuerpo in (texto_legacy, html_legacy):
        assert 'Gracias por tu compra' in cuerpo and 'Comprobante de compra' in cuerpo
        assert 'reserva-confirmada-123' in cuerpo and '276.00' in cuerpo
