import 'dart:convert';

import 'package:aplicacion_flutter/pages/registro_page.dart';
import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

void main() {
  testWidgets(
    'controles rojos desde abrir y actualizados al escribir sin enviar',
    (tester) async {
      var llamadas = 0;
      final servicio = ApiService(
        baseUrl: Uri.parse('https://example.test'),
        client: MockClient((_) async {
          llamadas++;
          throw StateError('No debe enviar');
        }),
      );
      await tester.pumpWidget(
        MaterialApp(home: RegistroPage(apiService: servicio)),
      );
      await tester.pump();
      expect(find.text('Ingresa tu correo'), findsOneWidget);
      final campos = find.byType(TextFormField);
      expect(find.text('Ingresa tu nombre'), findsOneWidget);
      expect(find.text('Usa entre 10 y 256 caracteres'), findsOneWidget);
      await tester.enterText(campos.at(1), 'correo-invalido');
      await tester.pump();
      expect(find.text('Ingresa un correo electrónico válido'), findsOneWidget);
      await tester.enterText(campos.at(1), 'jimmy@example.test');
      await tester.pump();
      expect(find.text('Ingresa tu correo'), findsNothing);
      expect(find.text('Ingresa un correo electrónico válido'), findsNothing);
      await tester.enterText(campos.at(2), '123456789');
      await tester.pump();
      expect(find.text('Usa entre 10 y 256 caracteres'), findsOneWidget);
      await tester.enterText(campos.at(2), '1234567890');
      await tester.pump();
      expect(find.text('Usa entre 10 y 256 caracteres'), findsNothing);
      expect(llamadas, 0);
    },
  );

  testWidgets(
    'envia normalizacion Unicode equivalente a Python sin alterar contraseña',
    (tester) async {
      Map<String, dynamic>? enviado;
      final servicio = ApiService(
        baseUrl: Uri.parse('https://example.test'),
        client: MockClient((solicitud) async {
          enviado = jsonDecode(solicitud.body) as Map<String, dynamic>;
          return http.Response(
            '{"error":{"codigo":"prueba","mensaje":"Prueba"}}',
            400,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(home: RegistroPage(apiService: servicio)),
      );
      final campos = find.byType(TextFormField);
      await tester.enterText(campos.at(0), '\u0085\ufeffJimmy\u001c');
      await tester.enterText(
        campos.at(1),
        '\u001c\ufeffjimmy@example.test\u0085',
      );
      await tester.enterText(campos.at(2), ' 12345678 ');
      await tester.ensureVisible(find.text('Registrarme'));
      await tester.tap(find.text('Registrarme'));
      await tester.pumpAndSettle();
      expect(enviado?['correo'], '\ufeffjimmy@example.test');
      expect(enviado?['contrasena'], ' 12345678 ');
      expect(enviado?['nombre'], '\ufeffJimmy');
    },
  );

  testWidgets('correo mal formado se valida localmente sin petición', (
    tester,
  ) async {
    var llamadas = 0;
    final servicio = ApiService(
      baseUrl: Uri.parse('https://example.test'),
      client: MockClient((_) async {
        llamadas++;
        throw StateError('No debe enviar');
      }),
    );
    await tester.pumpWidget(
      MaterialApp(home: RegistroPage(apiService: servicio)),
    );
    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), 'Jimmy');
    await tester.enterText(campos.at(1), 'correo-invalido');
    await tester.enterText(campos.at(2), '1234567890');
    await tester.ensureVisible(find.text('Registrarme'));
    await tester.tap(find.text('Registrarme'));
    await tester.pumpAndSettle();
    expect(llamadas, 0);
    expect(find.text('Ingresa un correo electrónico válido'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('registro rechaza nueve caracteres antes de llamar al API', (
    tester,
  ) async {
    var llamadas = 0;
    final servicio = ApiService(
      baseUrl: Uri.parse('https://example.test'),
      client: MockClient((_) async {
        llamadas++;
        return http.Response('{}', 400);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(home: RegistroPage(apiService: servicio)),
    );
    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), 'Jimmy');
    await tester.enterText(campos.at(1), 'jimmy@example.test');
    await tester.enterText(campos.at(2), '123456789');
    await tester.ensureVisible(find.text('Registrarme'));
    await tester.tap(find.text('Registrarme'));
    await tester.pumpAndSettle();
    expect(find.text('Usa entre 10 y 256 caracteres'), findsOneWidget);
    expect(llamadas, 0);
  });

  testWidgets(
    'errores del servidor se muestran en formulario y se limpian al editar',
    (tester) async {
      final servicio = ApiService(
        baseUrl: Uri.parse('https://example.test'),
        client: MockClient(
          (_) async => http.Response(
            '{"error":{"codigo":"credenciales_invalidas","mensaje":"Error de prueba"}}',
            401,
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: RegistroPage(apiService: servicio)),
      );
      final campos = find.byType(TextFormField);
      await tester.enterText(campos.at(0), 'Jimmy');
      await tester.enterText(campos.at(1), 'jimmy@example.test');
      await tester.enterText(campos.at(2), 'contrasena123');
      await tester.ensureVisible(find.text('Registrarme'));
      await tester.tap(find.text('Registrarme'));
      await tester.pumpAndSettle();
      expect(find.text('Error de prueba'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.enterText(campos.at(2), 'nueva123456');
      await tester.pump();
      expect(find.text('Error de prueba'), findsNothing);
    },
  );

  testWidgets('muestra la marca y el formulario de registro', (tester) async {
    final servicio = ApiService(
      baseUrl: Uri.parse('https://example.test'),
      client: MockClient(
        (_) async => throw StateError('No debe llamar al API'),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: RegistroPage(apiService: servicio)),
    );

    expect(find.text('AeroTech'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Card),
        matching: find.text('Crear cuenta'),
      ),
      findsOneWidget,
    );
    expect(find.text('Nombre'), findsOneWidget);
    expect(find.text('Correo'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('Registrarme'), findsOneWidget);
    expect(find.byType(Card), findsOneWidget);
    expect(find.byTooltip('Volver'), findsOneWidget);
  });

  testWidgets('valida los campos vacíos sin llamar al servicio', (
    tester,
  ) async {
    final servicio = ApiService(
      baseUrl: Uri.parse('https://example.test'),
      client: MockClient(
        (_) async => throw StateError('No debe llamar al API'),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: RegistroPage(apiService: servicio)),
    );

    await tester.ensureVisible(find.text('Registrarme'));
    await tester.tap(find.text('Registrarme'));
    await tester.pump();

    expect(find.text('Ingresa tu nombre'), findsOneWidget);
    expect(find.text('Ingresa tu correo'), findsOneWidget);
    expect(find.text('Usa entre 10 y 256 caracteres'), findsOneWidget);
  });
}
