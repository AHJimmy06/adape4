import 'package:aplicacion_flutter/widgets/sistema_compra/pasajeros_asientos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('por defecto adulto sin asignación ni equipaje y USD20 finales', () {
    final p = PasajeroAsiento();
    expect(p.datos('1A'), {
      'asiento': '1A',
      'correo_usuario': null,
      'categoria': 'adulto',
      'maletas_adicionales': 0,
    });
    p.maletas = '2';
    expect(p.equipajeCentavos, 4000);
    expect(p.error, isNull);
    p.asignado = true;
    p.correo = ' ANA@EXAMPLE.TEST ';
    p.categoria = 'nino';
    expect(p.datos('1A')['correo_usuario'], 'ana@example.test');
    expect(p.datos('1A')['categoria'], 'adulto');
  });
  test('rechaza correo y cantidades inválidos antes de comprar', () {
    final p = PasajeroAsiento()..asignado = true;
    expect(p.error, isNotNull);
    p.correo = 'ana@example.test';
    for (final valor in ['-1', '1.5', '50000', 'abc', '']) {
      p.maletas = valor;
      expect(p.error, isNotNull, reason: valor);
    }
    p.maletas = '49999';
    expect(p.error, isNull);
  });
  testWidgets('configura categoría y maletas por asiento sin mezclar datos', (
    t,
  ) async {
    final configuraciones = {'1A': PasajeroAsiento(), '1B': PasajeroAsiento()};
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (_, actualizar) => PasajerosAsientos(
                configuraciones: configuraciones,
                tarifasCentavos: const {'1A': 1150, '1B': 1150},
                bloqueado: false,
                onChanged: () => actualizar(() {}),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.byKey(const ValueKey('pasajero-1A')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('maletas-1A')), '2');
    await t.pumpAndSettle();
    expect(configuraciones['1A']!.maletas, '2');
    expect(configuraciones['1B']!.maletas, '0');
    expect(find.text('USD 63.00'), findsOneWidget);
    final categoria = t.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('categoria-1A')),
    );
    categoria.onChanged!('adulto_mayor');
    await t.pumpAndSettle();
    expect(configuraciones['1A']!.categoria, 'adulto_mayor');
  });
}
