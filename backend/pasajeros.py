"""Normalize per-seat passenger choices without trusting client pricing."""
from backend.services import CORREO_RE
from backend.sistema_validacion import integer, invalid, object_body, seat_codes


def validar_pasajeros(data, seats):
    monetary = {'subtotal', 'subtotal_centavos', 'iva', 'iva_centavos', 'total', 'total_centavos',
                'precio', 'precio_centavos', 'importe', 'importe_centavos', 'monto', 'tarifas'}
    if monetary.intersection(data):
        invalid('Los importes se calculan en el servidor; no envíes precios ni totales.')
    # Omission preserves the exact legacy operation identity, including retries.
    if 'pasajeros' not in data:
        return None
    passengers = data['pasajeros']
    if not isinstance(passengers, list) or len(passengers) != len(seats):
        invalid('Completa los datos de un pasajero por cada asiento seleccionado.')
    normalized = {}
    allowed = {'asiento', 'correo_usuario', 'categoria', 'maletas_adicionales'}
    for passenger in passengers:
        passenger = object_body(passenger)
        if set(passenger) - allowed:
            invalid('Los datos del pasajero contienen campos no permitidos.')
        code = seat_codes([passenger.get('asiento')])[0]
        if code not in seats or code in normalized:
            invalid('Los pasajeros deben coincidir, sin repetir, con los asientos seleccionados.')
        email = passenger.get('correo_usuario')
        if email is not None:
            if not isinstance(email, str):
                invalid('Ingresa un correo válido para asignar el asiento.')
            email = email.strip().lower() or None
            if email is not None and (len(email) > 320 or not CORREO_RE.fullmatch(email)):
                invalid('Ingresa un correo válido para asignar el asiento.')
        category = passenger.get('categoria', 'adulto')
        if category not in ('adulto', 'adulto_mayor', 'nino'):
            invalid('Selecciona la categoría Adulto, Adulto mayor o Niño.')
        normalized[code] = dict(asiento=code, correo_usuario=email,
                                categoria='adulto' if email else category,
                                maletas_adicionales=integer(passenger.get('maletas_adicionales', 0), 0, 49999))
    return [normalized[code] for code in seats]
