"""Bounded daily schedules; SQL creates every flight atomically."""
from datetime import date

from flask import g, jsonify, request

from backend.sistema_validacion import identifier, invalid, object_body, validate_catalog


def validate_programacion(data):
    data = object_body(data)
    flight = validate_catalog('vuelos', data)
    if data.get('frecuencia') != 'diaria':
        invalid('La programación debe tener frecuencia diaria.')
    try:
        end = date.fromisoformat(data.get('fecha_fin', ''))
        start = date.fromisoformat(flight['salida_local'][:10])
    except (TypeError, ValueError):
        invalid('Selecciona una fecha final válida.')
    if not 1 <= (end - start).days + 1 <= 90:
        invalid('La programación diaria debe abarcar entre 1 y 90 días.')
    if len(flight['codigo']) > 21:
        invalid('El código base de vuelos diarios admite hasta 21 caracteres.')
    return dict(flight, frecuencia='diaria', fecha_fin=end.isoformat(),
                clave_operacion=identifier(data.get('clave_operacion')))


def register_programaciones(app, repository, administrator):
    @app.post('/api/sistema/programaciones')
    @administrator
    def programaciones():
        data = validate_programacion(request.get_json(silent=True))
        return jsonify(repository.sistema_operar('programar', g.usuario['id'], data)), 201
