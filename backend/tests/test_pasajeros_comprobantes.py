"""Passenger snapshots remain readable and escaped in both receipt formats."""
from copy import deepcopy
from xml.etree import ElementTree as ET

from backend.notificaciones import _contenido
from backend.tests.test_correo_presentacion import DATOS
from backend.tests.test_pasajeros_http import ORDER, api  # noqa: F401


def snapshot():
    seat = dict(codigo='1A', clase_nombre='Ejecutiva', estado='ocupado',
                pasajero=dict(usuario_id='private-user-id', nombre='Ana <Torres>', correo='ana@example.test',
                              categoria='adulto', asignado=True),
                equipaje=dict(cantidad=2, precio_unitario_centavos=2000, subtotal_centavos=3478,
                              iva_centavos=522, total_centavos=4000),
                tarifa_subtotal_centavos=10000, tarifa_iva_centavos=1500, tarifa_total_centavos=11500,
                subtotal_centavos=13478, iva_centavos=2022, total_centavos=15500)
    data = deepcopy(DATOS)
    data.update(asientos=[seat], subtotal_centavos=13478, iva_centavos=2022, total_centavos=15500)
    return data


def test_mail_shows_passenger_category_baggage_and_persisted_breakdown_without_repricing():
    data = snapshot()
    before = deepcopy(data)
    text, html = _contenido(data)
    for body in (text, html):
        for expected in ('Pasajero', 'Adulto', 'Equipaje adicional', '2', '40.00', '20.00', '115.00', '155.00'):
            assert expected in body
        assert 'private-user-id' not in body
    assert 'Ana <Torres>' in text
    assert 'Ana &lt;Torres&gt;' in html and 'Ana <Torres>' not in html
    assert data == before


def test_mail_categories_and_legacy_seats_keep_existing_confirmation():
    data = snapshot()
    data['asientos'][0]['pasajero'] = dict(categoria='adulto_mayor', asignado=False)
    assert 'Adulto mayor' in _contenido(data)[0]
    data['asientos'][0]['pasajero'] = dict(categoria='nino', asignado=False)
    assert 'Niño' in _contenido(data)[0]
    text, html = _contenido(DATOS)
    assert 'Gracias por confiar en AeroTech' in text and '1A' in html
    data['asientos'] = ['1A']
    assert 'Asiento confirmado' in _contenido(data)[1]


def test_xml_contains_structured_passenger_and_baggage_not_dictionary_representations(api):
    client, repo, headers = api
    data = snapshot()
    reservation = dict(data, id=ORDER, creado_en='2026-12-01T10:00:00Z', estado='confirmada',
                       cantidad=1, cantidad_activa=1, reembolsado_centavos=0)
    original = repo.sistema_operar
    repo.sistema_operar = lambda action, user, payload: reservation if action == 'reserva' else original(action, user, payload)
    response = client.get(f'/api/sistema/reservas/{ORDER}/comprobante.xml', headers=headers)
    assert response.status_code == 200
    root = ET.fromstring(response.data)
    passenger = root.find('./asientos/asiento/pasajero')
    assert passenger is not None and passenger.findtext('nombre') == 'Ana <Torres>'
    assert passenger.findtext('categoria') == 'adulto'
    assert passenger.findtext('asignado') == 'true'
    assert passenger.find('usuario_id') is None
    assert root.findtext('./asientos/asiento/equipaje/cantidad') == '2'
    assert root.findtext('./asientos/asiento/equipaje/total_centavos') == '4000'
    assert b"{'" not in response.data and b'private-user-id' not in response.data
    assert root.findtext('total_centavos') == '15500'


def test_receipt_still_requires_owner_authentication(api):
    assert api[0].get(f'/api/sistema/reservas/{ORDER}/comprobante.xml').status_code == 401
    assert api[1].calls == []
