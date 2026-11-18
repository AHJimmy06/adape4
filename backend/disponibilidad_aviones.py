"""Read-only schedule suggestions; the existing SQL trigger owns final exclusion."""
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from flask import g, jsonify, request

from backend.models import ErrorAPI
from backend.sistema_validacion import identifier, invalid


def _local(value):
    try:
        parsed = datetime.fromisoformat(value)
        if parsed.tzinfo is not None or parsed.second or parsed.microsecond:
            raise ValueError
        return parsed
    except (TypeError, ValueError):
        invalid('Usa fecha y hora local AAAA-MM-DDTHH:MM sin offset.')


def _instant(local, zone):
    # Never silently choose one side of an ambiguous clock change.
    try:
        candidates = {local.replace(tzinfo=zone, fold=fold).astimezone(timezone.utc)
                      for fold in (0, 1)
                      if local.replace(tzinfo=zone, fold=fold).astimezone(timezone.utc)
                      .astimezone(zone).replace(tzinfo=None) == local}
    except (OverflowError, ValueError):
        invalid('La fecha está fuera del rango de horarios admitido.')
    if len(candidates) != 1:
        invalid('El horario local no existe o es ambiguo por cambio de zona horaria.')
    return candidates.pop()


def _stored_instant(value):
    try:
        parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
        if parsed.tzinfo is None:
            raise ValueError
        return parsed.astimezone(timezone.utc)
    except (ValueError, TypeError, AttributeError):
        raise ErrorAPI('disponibilidad_no_verificada',
                       'No se pudo verificar el horario del avión. Actualiza los datos.', 503) from None


def _civil(instant, zone):
    return instant.astimezone(zone).replace(tzinfo=None).isoformat(timespec='minutes')


def availability(params, catalogs):
    plane_id, route_id = identifier(params.get('avion_id')), identifier(params.get('ruta_id'))
    excluded = identifier(params['vuelo_id']) if params.get('vuelo_id') else None
    try:
        day = date.fromisoformat(params.get('fecha', ''))
        last = date.fromisoformat(params.get('fecha_hasta') or day.isoformat())
        horizon = day + timedelta(days=2)
    except (ValueError, TypeError, OverflowError):
        invalid('Selecciona una fecha válida para consultar horarios.')
    if not 1 <= (last - day).days + 1 <= 90:
        invalid('La programación diaria debe abarcar entre 1 y 90 días.')
    plane = next((p for p in catalogs['aviones'] if p['id'] == plane_id and p.get('activo', True)), None)
    route = next((r for r in catalogs['rutas'] if r['id'] == route_id and r.get('activo', True)), None)
    if plane is None or route is None:
        invalid('No se encontró el avión o la ruta activa.', 'no_encontrado', 404)
    try:
        origin = ZoneInfo(route['origen']['zona_horaria'])
        destination = ZoneInfo(route['destino']['zona_horaria'])
    except (KeyError, TypeError, ValueError, ZoneInfoNotFoundError):
        invalid('No se pudo verificar la zona horaria de la ruta.', 'disponibilidad_no_verificada', 503)
    start = _instant(datetime.combine(day, time.min), origin)
    end = _instant(datetime.combine(horizon, time.min), origin)
    intervals = []
    for flight in catalogs['vuelos']:
        if not flight.get('activo', True) or flight.get('avion_id') != plane_id or flight['id'] == excluded:
            continue
        departure, arrival = _stored_instant(flight['salida_en']), _stored_instant(flight['llegada_en'])
        if arrival <= departure:
            invalid('No se pudo verificar el horario del avión.', 'disponibilidad_no_verificada', 503)
        intervals.append((departure, arrival, flight))
    intervals.sort(key=lambda item: item[0])
    occupied, windows, cursor = [], [], start

    def window(a, b):
        return dict(inicio_en=a.isoformat(), fin_en=b.isoformat(), inicio_local=_civil(a, origin),
                    fin_local=_civil(b, origin), inicio_destino_local=_civil(a, destination),
                    fin_destino_local=_civil(b, destination))

    for departure, arrival, flight in intervals:
        if departure >= end or arrival <= start:
            continue
        occupied.append(dict(id=flight['id'], codigo=flight.get('codigo', ''),
                             inicio_en=departure.isoformat(), fin_en=arrival.isoformat(),
                             inicio_local=_civil(departure, origin), fin_local=_civil(arrival, origin)))
        if departure > cursor:
            windows.append(window(cursor, min(departure, end)))
        cursor = max(cursor, min(arrival, end))
    if cursor < end:
        windows.append(window(cursor, end))

    conflicts, available = [], None
    if params.get('salida_local') or params.get('llegada_local'):
        departure_local, arrival_local = _local(params.get('salida_local')), _local(params.get('llegada_local'))
        if departure_local.date() != day:
            invalid('La salida debe pertenecer a la fecha consultada.')
        for offset in range((last - day).days + 1):
            try:
                departure = _instant(departure_local + timedelta(days=offset), origin)
                arrival = _instant(arrival_local + timedelta(days=offset), destination)
            except OverflowError:
                invalid('La fecha está fuera del rango de horarios admitido.')
            if arrival <= departure:
                invalid('La llegada debe ser posterior a la salida.')
            for busy_start, busy_end, flight in intervals:
                if departure < busy_end and arrival > busy_start:
                    conflicts.append(dict(fecha=(day + timedelta(days=offset)).isoformat(),
                                          codigo=flight.get('codigo', ''),
                                          inicio_local=_civil(busy_start, origin), fin_local=_civil(busy_end, origin)))
        available = not conflicts
    return dict(fecha=day.isoformat(), zona_origen=str(origin), zona_destino=str(destination),
                ventanas=windows, ocupados=occupied, conflictos=conflicts, disponible=available)


def register_aircraft_availability(app, system, administrator):
    @app.get('/api/sistema/disponibilidad-avion')
    @administrator
    def aircraft_availability():
        # Each list is fetched with the same authenticated ADMIN actor. This is
        # a suggestion, not a reservation; SQL rechecks under its existing lock.
        catalogs = {resource: system.rpc('listar', g.usuario['id'], recurso=resource, admin=True)[resource]
                    for resource in ('aviones', 'rutas', 'vuelos')}
        response = jsonify(availability(request.args, catalogs))
        response.headers['Cache-Control'] = 'no-store'
        return response
