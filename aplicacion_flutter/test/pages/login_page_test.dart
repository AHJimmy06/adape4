import 'dart:convert';

import 'package:aplicacion_flutter/pages/login_page.dart';
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
        MaterialApp(
          home: LoginPage(apiService: servicio, globoBuilder: _globoDePrueba),
        ),
      );
      await tester.pump();
      expect(find.text('Ingresa tu correo'), findsOneWidget);
      final campos = find.byType(TextFormField);
      expect(find.text('Ingresa tu contraseña'), findsOneWidget);
      await tester.enterText(campos.at(0), 'correo-invalido');
      await tester.pump();
      expect(find.text('Ingresa un correo electrónico válido'), findsOneWidget);
      await tester.enterText(campos.at(0), 'jimmy@example.test');
      await tester.pump();
      expect(find.text('Ingresa tu correo'), findsNothing);
      expect(find.text('Ingresa un correo electrónico válido'), findsNothing);
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
        MaterialApp(
          home: LoginPage(apiService: servicio, globoBuilder: _globoDePrueba),
        ),
      );
      final campos = find.byType(TextFormField);
      await tester.enterText(
        campos.at(0),
        '\u001c\ufeffjimmy@example.test\u0085',
      );
      await tester.enterText(campos.at(1), ' 12345678 ');
      await tester.ensureVisible(find.text('Iniciar sesión'));
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();
      expect(enviado?['correo'], '\ufeffjimmy@example.test');
      expect(enviado?['contrasena'], ' 12345678 ');
    },
  );

  testWidgets(
    'login delega contraseña corta al backend sin regla de registro',
    (tester) async {
      var llamadas = 0;
      final servicio = ApiService(
        baseUrl: Uri.parse('https://example.test'),
        client: MockClient((_) async {
          llamadas++;
          return http.Response(
            '{"error":{"codigo":"credenciales_invalidas","mensaje":"Correo o contrasena incorrectos."}}',
            401,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(apiService: servicio, globoBuilder: _globoDePrueba),
        ),
      );
      final campos = find.byType(TextFormField);
      await tester.enterText(campos.at(0), 'jimmy@example.test');
      await tester.enterText(campos.at(1), '123456789');
      await tester.ensureVisible(find.text('Iniciar sesión'));
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();
      expect(llamadas, 1);
      expect(find.text('Correo o contrasena incorrectos.'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
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
      MaterialApp(
        home: LoginPage(apiService: servicio, globoBuilder: _globoDePrueba),
      ),
    );
    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), 'correo-invalido');
    await tester.enterText(campos.at(1), '1234567890');
    await tester.ensureVisible(find.text('Iniciar sesión'));
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(llamadas, 0);
    expect(find.text('Ingresa un correo electrónico válido'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
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
        MaterialApp(
          home: LoginPage(apiService: servicio, globoBuilder: _globoDePrueba),
        ),
      );
      final campos = find.byType(TextFormField);
      await tester.enterText(campos.at(0), 'jimmy@example.test');
      await tester.enterText(campos.at(1), 'contrasena123');
      await tester.ensureVisible(find.text('Iniciar sesión'));
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();
      expect(find.text('Error de prueba'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.enterText(campos.at(1), 'nueva123456');
      await tester.pump();
      expect(find.text('Error de prueba'), findsNothing);
    },
  );

  testWidgets('el formulario de inicio de sesión valida campos vacíos', (
    tester,
  ) async {
    final servicio = ApiService(
      baseUrl: Uri.parse('http://localhost:5000'),
      client: MockClient(
        (_) async => throw StateError('No debe llamar al API'),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(apiService: servicio, globoBuilder: _globoDePrueba),
      ),
    );

    await tester.ensureVisible(find.text('Iniciar sesión'));
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump();

    expect(find.text('Ingresa tu correo'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña'), findsOneWidget);
    expect(find.text('Crear cuenta'), findsOneWidget);
  });

  testWidgets('presenta una marca accesible y permite mostrar contraseña', (
    tester,
  ) async {
    final servicio = ApiService(
      baseUrl: Uri.parse('https://example.test'),
      client: MockClient(
        (_) async => throw StateError('No debe llamar al API'),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(apiService: servicio, globoBuilder: _globoDePrueba),
      ),
    );

    expect(find.text('AeroTech'), findsOneWidget);
    expect(
      tester.getCenter(find.text('Tu próximo destino empieza aquí.')).dy,
      lessThan(tester.getCenter(find.text('Reserva tu próximo vuelo')).dy),
    );
    expect(
      find.bySemanticsLabel('Globo 3D de AeroTech con aviones en rutas'),
      findsOneWidget,
    );
    expect(find.byTooltip('Mostrar contraseña'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Mostrar contraseña'));
    await tester.tap(find.byTooltip('Mostrar contraseña'));
    await tester.pump();

    expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
  });

  testWidgets('la vista amplia conserva el diseño sin desbordamientos', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final servicio = ApiService(
      baseUrl: Uri.parse('https://example.test'),
      client: MockClient(
        (_) async => throw StateError('No debe llamar al API'),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(apiService: servicio, globoBuilder: _globoDePrueba),
      ),
    );

    expect(find.text('AeroTech'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _globoDePrueba(BuildContext context) {
  return Semantics(
    label: 'Globo 3D de AeroTech con aviones en rutas',
    image: true,
    child: const SizedBox.expand(),
  );
}
