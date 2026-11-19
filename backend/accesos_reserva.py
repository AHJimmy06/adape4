"""Permisos vigentes por asiento sin transferir la propiedad de la compra."""
import re

from flask import g, jsonify, request

from backend.sistema_validacion import identifier, integer, invalid, object_body, seat_codes


def register_accesos_reserva(app, system, authenticated):
    def private_response(data):
        response = jsonify(data)
        response.headers['Cache-Control'] = 'no-store, private'
        return response

    @app.get('/api/sistema/reservas/<reservation_id>/accesos')
    @authenticated
    def reservation_access(reservation_id):
        return private_response(system.rpc('accesos_reserva', g.usuario['id'], id=identifier(reservation_id)))

    @app.post('/api/sistema/reservas/<reservation_id>/accesos')
    @authenticated
    def assign_reservation_access(reservation_id):
        data = object_body(request.get_json(silent=True))
        if set(data) != {'asiento', 'correo', 'version'}:
            invalid('Indica únicamente el asiento, el correo y la versión del acceso.')
        seat = seat_codes([data['asiento']])[0]
        version = integer(data['version'], minimum=1, maximum=999999999)
        email = data['correo']
        if email is not None:
            if not isinstance(email, str):
                invalid('Ingresa el correo de una cuenta registrada o retira el acceso.')
            email = email.strip().lower()
            if len(email) > 254 or not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', email):
                invalid('Ingresa un correo válido para asignar el acceso.')
        return private_response(system.rpc('asignar_acceso_reserva', g.usuario['id'],
                                           id=identifier(reservation_id), asiento=seat, correo=email, version=version))

    @app.get('/api/sistema/asientos-compartidos')
    @authenticated
    def shared_seats():
        return private_response(system.rpc('asientos_compartidos', g.usuario['id']))
