import 'package:aplicacion_flutter/models/ruta_vuelo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Quito a Ambato del ejemplo tiene ambos puntos nacionales conocidos',
    () {
      final ruta = RutaVuelo('Quito, Ecuador', 'Ambato, Ecuador');
      expect(ruta.esNacional, isTrue);
      expect(ruta.puntoOrigen, isNotNull);
      expect(ruta.puntoDestino, isNotNull);
    },
  );
  test('country classification is trimmed and exact, never aliased', () {
    expect(RutaVuelo('Quito, Ecuador ', 'Cuenca, Ecuador').esNacional, isTrue);
    expect(RutaVuelo('Quito, Ecuador', 'Lima, ecuador').esNacional, isFalse);
    expect(
      RutaVuelo('Quito, USA', 'Miami, Estados Unidos').esNacional,
      isFalse,
    );
    expect(RutaVuelo('Quito, Ecuador', 'Miami, USA').esInternacional, isTrue);
  });
  test('legacy known cities infer countries, unknown ones remain unknown', () {
    expect(RutaVuelo('Quito', 'Cuenca').esNacional, isTrue);
    expect(RutaVuelo('Quito', 'Lima').esInternacional, isTrue);
    expect(RutaVuelo('Unknown', 'Other').paisOrigen, isNull);
    expect(RutaVuelo('Unknown', 'Other').esNacional, isFalse);
    expect(RutaVuelo('Quito, ', 'Cuenca, ').paisOrigen, isNull);
  });
}
