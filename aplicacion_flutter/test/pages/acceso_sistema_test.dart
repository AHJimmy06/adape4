import 'dart:convert';

import 'package:aplicacion_flutter/pages/login_page.dart';
import 'package:aplicacion_flutter/pages/sistema_vuelos_page.dart';
import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('login abre el sistema integral con la misma sesión', (
    tester,
  ) async {
    final api = ApiService(
      client: MockClient((r) async {
        if (r.url.path == '/api/auth/login') {
          return http.Response(
            jsonEncode({
              'token': 'prueba',
              'usuario': {
                'id': 'u1',
                'nombre': 'Ana',
                'correo': 'ana@example.test',
                'rol': 'ADMIN',
              },
            }),
            200,
          );
        }
        expect(r.headers['authorization'], 'Bearer prueba');
        final nombre = r.url.path.split('/').last;
        return http.Response(jsonEncode({nombre: <Object>[]}), 200);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(apiService: api, globoBuilder: (_) => const SizedBox()),
      ),
    );
    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), 'ana@example.test');
    await tester.enterText(campos.at(1), 'Contrasena123');
    await tester.ensureVisible(find.text('Iniciar sesión'));
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.byType(SistemaVuelosPage), findsOneWidget);
    expect(
      tester
          .widget<SistemaVuelosPage>(find.byType(SistemaVuelosPage))
          .apiService,
      same(api),
    );
    expect(tester.takeException(), isNull);
  });
}
