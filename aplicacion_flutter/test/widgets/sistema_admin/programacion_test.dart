import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aplicacion_flutter/widgets/sistema_admin/formulario_operacion.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    Map<String, dynamic>? registro,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormularioOperacion(
            recurso: 'vuelos',
            registro: registro,
            catalogos: const {},
            guardar: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('nuevo vuelo permite elegir único o diario y exige fecha final', (
    tester,
  ) async {
    await open(tester);
    final frequency = find.byKey(const ValueKey('frecuencia_vuelo'));
    expect(frequency, findsOneWidget);
    final dropdown = tester.widget<DropdownButtonFormField<String>>(frequency);
    expect(dropdown.initialValue, 'unico');
    dropdown.onChanged!('diaria');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('fecha_fin_programacion')),
      findsOneWidget,
    );
    expect(find.textContaining('90 días'), findsOneWidget);
    expect(find.text('Selecciona primero la salida'), findsOneWidget);
  });

  testWidgets(
    'editar conserva una ocurrencia individual sin selector de serie',
    (tester) async {
      await open(tester, registro: {'id': 'flight', 'version': 1});
      expect(find.byKey(const ValueKey('frecuencia_vuelo')), findsNothing);
      expect(
        find.byKey(const ValueKey('fecha_fin_programacion')),
        findsNothing,
      );
      expect(find.text('Editar · vuelos'), findsOneWidget);
    },
  );
}
