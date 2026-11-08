import 'package:aplicacion_flutter/pages/login_page.dart';
import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

void main() {
  testWidgets('el formulario de inicio de sesión valida campos vacíos', (
    tester,
  ) async {
    final servicio = ApiService(
      baseUrl: Uri.parse('http://localhost:5000'),
      client: MockClient(
        (_) async => throw StateError('No debe llamar al API'),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: LoginPage(apiService: servicio)));

    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump();

    expect(find.text('Ingresa tu correo'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña'), findsOneWidget);
    expect(find.text('Crear cuenta'), findsOneWidget);
  });
}
