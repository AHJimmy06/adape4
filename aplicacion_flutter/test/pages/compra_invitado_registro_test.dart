import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:aplicacion_flutter/widgets/sistema_compra/autenticacion_compra.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'registro inicial explícito conserva entrada a cuenta existente',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AutenticacionCompra(api: ApiService(), registroInicial: true),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('compra-nombre')), findsOneWidget);
      expect(find.text('Crear cuenta y continuar'), findsOneWidget);
      await t.tap(find.text('Ya tengo cuenta'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('compra-nombre')), findsNothing);
      expect(find.text('Iniciar sesión y continuar'), findsOneWidget);
    },
  );
  testWidgets('autenticación global mantiene login por defecto', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AutenticacionCompra(api: ApiService())),
      ),
    );
    expect(find.byKey(const ValueKey('compra-nombre')), findsNothing);
    expect(find.text('Iniciar sesión y continuar'), findsOneWidget);
  });
}
