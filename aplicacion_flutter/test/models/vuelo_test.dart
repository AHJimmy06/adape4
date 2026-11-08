import 'package:aplicacion_flutter/models/vuelo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Vuelo.fromJson convierte campos numéricos y fechas del API', () {
    final vuelo = Vuelo.fromJson({
      'id': 'vuelo-7',
      'origen': 'Quito',
      'destino': 'Guayaquil',
      'fecha': '2026-11-20',
      'hora_salida': '09:45',
      'hora_llegada': '10:30',
      'precio': 89,
      'asientos_disponibles': 4,
    });

    expect(vuelo.id, 'vuelo-7');
    expect(vuelo.origen, 'Quito');
    expect(vuelo.destino, 'Guayaquil');
    expect(vuelo.precio, 89.0);
    expect(vuelo.asientosDisponibles, 4);
  });

  test('Vuelo.fromJson acepta identificadores UUID de PostgreSQL', () {
    final vuelo = Vuelo.fromJson({
      'id': 'c9ef93c7-7e3d-4ec4-8d50-3323a66374fa',
      'origen': 'Quito',
      'destino': 'Guayaquil',
      'fecha': '2026-11-20',
      'hora_salida': '09:45',
      'hora_llegada': '10:30',
      'precio': 89,
      'asientos_disponibles': 4,
    });

    expect(vuelo.id, 'c9ef93c7-7e3d-4ec4-8d50-3323a66374fa');
  });
}
