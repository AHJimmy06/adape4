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
  test(
    'extras canonicalizados preservan reintentos y cambian la operación',
    () {
      final op = CheckoutOperacion();
      final pasajeros = [
        {'asiento': '1B', 'categoria': 'nino', 'maletas_adicionales': 1},
        {
          'asiento': '1A',
          'categoria': 'adulto',
          'correo_usuario': ' ANA@EXAMPLE.TEST ',
          'maletas_adicionales': 0,
        },
      ];
      final primera = op.preparar('v', ['1A', '1B'], pasajeros: pasajeros);
      expect(
        op.preparar(
          'v',
          ['1B', '1A'],
          pasajeros: [
            {
              'asiento': '1A',
              'correo_usuario': 'ana@example.test',
              'maletas_adicionales': 0,
              'categoria': 'adulto',
            },
            {
              'asiento': '1B',
              'correo_usuario': null,
              'categoria': 'nino',
              'maletas_adicionales': 1,
            },
          ],
        ),
        primera,
      );
      expect(
        op.preparar(
          'v',
          ['1A', '1B'],
          pasajeros: [
            {...pasajeros[0], 'maletas_adicionales': 2},
            pasajeros[1],
          ],
        ),
        isNot(primera),
      );
    },
  );
}
