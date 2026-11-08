import 'package:aplicacion_flutter/models/reserva.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Reserva.fromJson analiza su vuelo anidado', () {
    final reserva = Reserva.fromJson({
      'id': 'reserva-13',
      'vuelo_id': 'vuelo-7',
      'cantidad': 2,
      'subtotal': 179.5,
      'iva': 26.93,
      'porcentaje_iva': 15.0,
      'total': 206.43,
      'estado': 'confirmada',
      'fecha_reserva': '2026-11-08',
      'vuelo': {
        'id': 'vuelo-7',
        'origen': 'Quito',
        'destino': 'Guayaquil',
        'fecha': '2026-11-20',
        'hora_salida': '09:45',
        'hora_llegada': '10:30',
        'precio': 89.75,
        'asientos_disponibles': 4,
      },
    });

    expect(reserva.id, 'reserva-13');
    expect(reserva.vueloId, 'vuelo-7');
    expect(reserva.cantidad, 2);
    expect(reserva.subtotal, 179.5);
    expect(reserva.iva, 26.93);
    expect(reserva.porcentajeIva, 15.0);
    expect(reserva.total, 206.43);
    expect(reserva.vuelo?.destino, 'Guayaquil');
  });
}
