import 'package:aplicacion_flutter/pages/landing_page.dart';
import 'package:aplicacion_flutter/pages/login_page.dart';
import 'package:aplicacion_flutter/pages/registro_page.dart';
import 'package:aplicacion_flutter/pages/sistema_vuelos_page.dart';
import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:aplicacion_flutter/theme/aerotech_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Widget _globo(BuildContext context) =>
    const SizedBox(key: ValueKey('globo-prueba'), width: 360, height: 360);

void main() {
  testWidgets('explorar abre catálogo público sin pasar por login', (
    tester,
  ) async {
    final consultas = <String>[];
    final api = ApiService(
      client: MockClient((r) async {
        consultas.add(r.url.path);
        return http.Response(
          r.url.path.endsWith('/aeropuertos')
              ? '{"aeropuertos":[]}'
              : '{"vuelos":[]}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LandingPage(apiService: api, globoBuilder: _globo),
      ),
    );
    await tester.tap(find.text('Explorar vuelos'));
    await tester.pumpAndSettle();
    expect(find.byType(SistemaVuelosPage), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    expect(consultas, contains('/api/sistema/vuelos'));
    expect(consultas.any((p) => p.endsWith('/pedidos')), isFalse);
  });
  for (final ancho in [360.0, 768.0, 904.0, 1440.0]) {
    testWidgets('landing mantiene botones y tarjetas uniformes a $ancho', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(ancho, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AerotechTheme.light,
          home: LandingPage(globoBuilder: _globo),
        ),
      );
      final crear = tester.getSize(
        find.byKey(const ValueKey('landing-crear-cuenta')),
      );
      final explorar = tester.getSize(
        find.widgetWithText(OutlinedButton, 'Explorar vuelos'),
      );
      expect(crear.width, explorar.width);
      expect(crear.height, explorar.height);
      expect(crear.height, greaterThanOrEqualTo(52));
      final tarjetas =
          ['Encuentra tu ruta', 'Imagina el recorrido', 'Organiza tu viaje']
              .map(
                (titulo) => tester.getSize(
                  find
                      .ancestor(
                        of: find.text(titulo),
                        matching: find.byType(Container),
                      )
                      .first,
                ),
              )
              .toList();
      expect(tarjetas[0], tarjetas[1]);
      expect(tarjetas[1], tarjetas[2]);
      expect(tester.takeException(), isNull);
    });
  }

  for (final ancho in [360.0, 768.0, 904.0, 1440.0]) {
    testWidgets('landing adaptable sin desbordes a $ancho', (tester) async {
      await tester.binding.setSurfaceSize(Size(ancho, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AerotechTheme.light,
          home: LandingPage(globoBuilder: _globo),
        ),
      );
      expect(find.text('El mundo está\nmás cerca.'), findsOneWidget);
      expect(find.byKey(const ValueKey('globo-prueba')), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('iniciar sesión conserva servicio y permite volver', (
    tester,
  ) async {
    final api = ApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: LandingPage(apiService: api, globoBuilder: _globo),
      ),
    );
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<LoginPage>(find.byType(LoginPage)).apiService,
      same(api),
    );
    expect(find.byKey(const ValueKey('globo-prueba')), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.text('El mundo está\nmás cerca.'), findsOneWidget);
    expect(find.byKey(const ValueKey('globo-prueba')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('crear cuenta abre registro con el mismo servicio', (
    tester,
  ) async {
    final api = ApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: LandingPage(apiService: api, globoBuilder: _globo),
      ),
    );
    final crear = find.byKey(const ValueKey('landing-crear-cuenta'));
    await tester.ensureVisible(crear);
    await tester.tap(crear);
    await tester.pumpAndSettle();
    expect(
      tester.widget<RegistroPage>(find.byType(RegistroPage)).apiService,
      same(api),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('login reemplazado no remonta un visor oculto de la landing', (
    tester,
  ) async {
    final api = ApiService(
      client: MockClient((solicitud) async {
        if (solicitud.url.path == '/api/auth/login') {
          return http.Response(
            '{"token":"prueba","usuario":{"id":"u1","nombre":"Ana",'
            '"correo":"ana@example.test","rol":"USER"}}',
            200,
          );
        }
        return http.Response('[]', 200);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LandingPage(apiService: api, globoBuilder: _globo),
      ),
    );
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), 'ana@example.test');
    await tester.enterText(campos.at(1), 'Contrasena123');
    await tester.ensureVisible(find.text('Iniciar sesión'));
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.byType(SistemaVuelosPage), findsOneWidget);
    expect(find.byType(LandingPage, skipOffstage: false), findsOneWidget);
    expect(
      find.byKey(const ValueKey('globo-prueba'), skipOffstage: false),
      findsNothing,
    );
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('globo-prueba')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'movimiento reducido conserva el modelo sin sustituirlo por icono',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: LandingPage(globoBuilder: _globo),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('globo-prueba')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('landing-globo-estatico')),
        findsNothing,
      );
    },
  );
}
