import 'package:flutter_test/flutter_test.dart';
import 'package:aplicacion_flutter/widgets/sistema_admin/validacion_operaciones.dart';

void main() {
  test('USD exacto', () {
    expect(ValidacionOperaciones.centavos('89.50'), 8950);
    expect(ValidacionOperaciones.centavos('0.50'), 50);
    expect(ValidacionOperaciones.centavos('0.49'), isNull);
    expect(ValidacionOperaciones.centavos('1.005'), isNull);
  });
  test('Cabina capacidad y filas únicas', () {
    final clases = <Map<String, dynamic>>[
      {
        'codigo': 'J',
        'nombre': 'Ejecutiva',
        'fila_inicio': 1,
        'filas': 3,
        'columnas': [
          ['A', 'C'],
          ['D', 'F'],
        ],
      },
      {
        'codigo': 'ECO',
        'nombre': 'Económica',
        'fila_inicio': 4,
        'filas': 20,
        'columnas': [
          ['A', 'B', 'C'],
          ['D', 'E', 'F'],
        ],
      },
    ];
    expect(ValidacionOperaciones.errorCabina(clases), isNull);
    expect(ValidacionOperaciones.capacidad(clases.first), 12);
    expect(ValidacionOperaciones.capacidad(clases.last), 120);
    clases.last['fila_inicio'] = 3;
    expect(ValidacionOperaciones.errorCabina(clases), isNotNull);
    clases.last['fila_inicio'] = 4;
    clases.last['columnas'] = [
      ['A', 'A'],
    ];
    expect(ValidacionOperaciones.errorCabina(clases), isNotNull);
  });
  test('Coordenadas negativas y límites', () {
    expect(ValidacionOperaciones.coordenada('-90', 90), isNull);
    expect(ValidacionOperaciones.coordenada('-180', 180), isNull);
    expect(ValidacionOperaciones.coordenada('90.1', 90), isNotNull);
    expect(ValidacionOperaciones.coordenada('NaN', 90), isNotNull);
  });
}
