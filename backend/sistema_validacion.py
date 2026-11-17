"""Validation and orchestration for the AeroTech service boundary."""
from datetime import datetime, timezone
from decimal import Decimal, ROUND_HALF_UP
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from uuid import UUID
import re

from backend.models import ErrorAPI


def invalid(message, code='datos_invalidos', status=400):
    raise ErrorAPI(code, message, status)


def object_body(data):
    if not isinstance(data, dict):
        invalid('Se requiere un objeto JSON.')
    return data


def identifier(value):
    try:
        return str(UUID(str(value)))
    except (ValueError, TypeError, AttributeError):
        invalid('Identificador UUID inválido.')


def integer(value, minimum=1, maximum=100000000):
    if isinstance(value, bool) or not isinstance(value, int) or not minimum <= value <= maximum:
        invalid(f'Se requiere un entero entre {minimum} y {maximum}.')
    return value


def text(data, key, maximum=120):
    value = data.get(key)
    if not isinstance(value, str) or not 1 <= len(value.strip()) <= maximum:
        invalid(f'El campo {key} es obligatorio y admite hasta {maximum} caracteres.')
    return value.strip()


def seat_codes(value):
    if not isinstance(value, list) or not 1 <= len(value) <= 1000:
        invalid('Selecciona entre 1 y 1000 asientos.')
    if any(not isinstance(s, str) or not re.fullmatch(r'[1-9][0-9]{0,3}[A-Z]', s) for s in value):
        invalid('Los asientos deben usar etiquetas como 1A.')
    if len(set(value)) != len(value):
        invalid('No repitas asientos.')
    return sorted(value, key=lambda s: (int(s[:-1]), s[-1]))


def cabin(classes):
    if not isinstance(classes, list) or not 1 <= len(classes) <= 10:
        invalid('Define al menos una clase de cabina.')
    result, seats, codes = [], set(), set()
    for item in classes:
        object_body(item)
        code = text(item, 'codigo', 12).upper()
        if not re.fullmatch(r'[A-Z][A-Z0-9_]{0,11}', code) or code in codes:
            invalid('Los códigos de clase deben ser únicos.')
        codes.add(code)
        start = integer(item.get('fila_inicio'), 1, 999)
        rows = integer(item.get('filas'), 1, 200)
        columns = item.get('columnas')
        if not isinstance(columns, list) or not 1 <= len(columns) <= 5:
            invalid('Define bloques de columnas para cada clase.')
        flattened = []
        for block in columns:
            if not isinstance(block, list) or not block:
                invalid('Cada bloque debe contener columnas.')
            for column in block:
                if not isinstance(column, str) or not re.fullmatch('[A-Z]', column) or column in flattened:
                    invalid('Las columnas deben ser letras A..Z únicas dentro de la clase.')
                flattened.append(column)
        for row in range(start, start + rows):
            for column in flattened:
                label = f'{row}{column}'
                if label in seats:
                    invalid('Las clases no pueden compartir etiquetas de asiento.')
                seats.add(label)
        result.append(dict(codigo=code, nombre=text(item, 'nombre'), fila_inicio=start,
                           filas=rows, columnas=columns, capacidad=rows * len(flattened)))
    if len(seats) > 1000:
        invalid('La capacidad técnica máxima es 1000 asientos.')
    return result


def validate_catalog(resource, data, update=False):
    data = object_body(data)
    result = {}
    if update:
        result['version'] = integer(data.get('version'))
    if resource == 'aeropuertos':
        for key in ('iata', 'nombre', 'ciudad', 'pais', 'codigo_pais', 'zona_horaria'):
            result[key] = text(data, key)
        result['iata'] = result['iata'].upper()
        result['codigo_pais'] = result['codigo_pais'].upper()
        if not re.fullmatch('[A-Z]{3}', result['iata']) or not re.fullmatch('[A-Z]{2}', result['codigo_pais']):
            invalid('IATA requiere 3 letras y país requiere ISO de 2 letras.')
        for key, bound in (('latitud', 90), ('longitud', 180)):
            value = data.get(key)
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not -bound <= value <= bound:
                invalid(f'{key} fuera de rango.')
            result[key] = value
        try:
            ZoneInfo(result['zona_horaria'])
        except (ZoneInfoNotFoundError, ValueError):
            invalid('Zona horaria IANA desconocida.')
    elif resource == 'aviones':
        result.update(matricula=text(data, 'matricula', 30).upper(), modelo=text(data, 'modelo'),
                      clases=cabin(data.get('clases')))
        result['capacidad_total'] = sum(c['capacidad'] for c in result['clases'])
    elif resource == 'rutas':
        result.update(origen_id=identifier(data.get('origen_id')), destino_id=identifier(data.get('destino_id')))
        if result['origen_id'] == result['destino_id']:
            invalid('Origen y destino deben ser distintos.')
    elif resource == 'vuelos':
        result.update(codigo=text(data, 'codigo', 30).upper(), ruta_id=identifier(data.get('ruta_id')),
                      avion_id=identifier(data.get('avion_id')))
        for key in ('salida_local', 'llegada_local'):
            value = text(data, key, 30)
            try:
                parsed = datetime.fromisoformat(value)
                if parsed.tzinfo is not None or parsed.second or parsed.microsecond:
                    raise ValueError
            except ValueError:
                invalid('Usa fecha y hora local AAAA-MM-DDTHH:MM sin offset.')
            result[key] = parsed.isoformat(timespec='minutes')
        tariffs = data.get('tarifas')
        if not isinstance(tariffs, list) or not tariffs:
            invalid('Define tarifas por clase.')
        seen = set()
        result['tarifas'] = []
        for tariff in tariffs:
            object_body(tariff)
            code = text(tariff, 'clase_codigo', 12)
            if code in seen:
                invalid('No repitas tarifas por clase.')
            seen.add(code)
            result['tarifas'].append(dict(clase_codigo=code, precio_centavos=integer(tariff.get('precio_centavos'), 50, 10000000)))
    return result


def allocate_vat(seats):
    """Round aggregate tax once; assign remainder deterministically per seat."""
    subtotal = sum(s['subtotal_centavos'] for s in seats)
    vat = int((Decimal(subtotal) * Decimal('.15')).quantize(Decimal('1'), rounding=ROUND_HALF_UP))
    allocated, cumulative = 0, 0
    result = []
    for seat in seats:
        cumulative += seat['subtotal_centavos']
        target = int((Decimal(cumulative) * Decimal('.15')).quantize(Decimal('1'), rounding=ROUND_HALF_UP))
        tax = target - allocated
        allocated = target
        result.append({**seat, 'iva_centavos': tax, 'total_centavos': seat['subtotal_centavos'] + tax})
    return result
