import 'package:flutter_test/flutter_test.dart';
import 'package:aplicacion_flutter/models/ruta_vuelo.dart';
import 'package:aplicacion_flutter/utils/checkout_operacion.dart';

void main() {
  test('airport coordinates override city and country centers', () {
    final r = RutaVuelo.desdeAeropuertos(
      {
        'ciudad': 'Quito',
        'pais': 'Ecuador',
        'codigo_pais': 'EC',
        'latitud': -0.129,
        'longitud': -78.357,
      },
      {
        'ciudad': 'Miami',
        'pais': 'USA',
        'codigo_pais': 'US',
        'latitud': 25.795,
        'longitud': -80.287,
      },
    );
    expect(r.puntoOrigen, (-0.129, -78.357));
    expect(r.centroDestino, (25.795, -80.287));
    expect(r.esInternacional, true);
  });
  test('operation keeps key for identical retry and uses integer money', () {
    final op = CheckoutOperacion();
    final a = op.preparar('v', ['1A', '1B']);
    expect(op.preparar('v', ['1B', '1A']), a);
    expect(op.preparar('v', ['1C']), isNot(a));
    expect(dinero(101), 'USD 1.01');
  });
}
