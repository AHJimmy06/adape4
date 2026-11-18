import 'dart:convert';
import 'dart:async';

import 'package:aplicacion_flutter/pages/landing_page.dart';
import 'package:aplicacion_flutter/pages/sistema_vuelos_page.dart';
import 'package:aplicacion_flutter/pages/login_page.dart';
import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:aplicacion_flutter/widgets/tarjeta_destino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'sistema_vuelos_page_test.dart' show flight;

Widget _globo(BuildContext _) => const SizedBox.square(dimension: 360);
http.Response _json(Object datos, [int estado = 200]) => http.Response(
  jsonEncode(datos),
  estado,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  for (final vista in [const Size(904, 500), const Size(390, 844)]) {
    testWidgets('hero admite pantalla corta o texto ampliado en $vista', (
      t,
    ) async {
      await t.binding.setSurfaceSize(vista);
      addTearDown(() => t.binding.setSurfaceSize(null));
      final api = ApiService(
        client: MockClient((_) async => _json({'vuelos': []})),
      );
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(vista.width < 900 ? 2 : 1),
            ),
            child: child!,
          ),
          home: LandingPage(apiService: api, globoBuilder: _globo),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(
        t.getSize(find.byKey(const ValueKey('landing-hero'))).height,
        greaterThanOrEqualTo(vista.height),
      );
    });
  }
  testWidgets(
    'Reservar entrega el vuelo elegido y conserva servicio sin autenticar',
    (t) async {
      await t.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      var consultasVuelos = 0;
      final consultaCatalogo = Completer<http.Response>();
      final llamadas = <String>[];
      final api = ApiService(
        client: MockClient((r) async {
          llamadas.add(r.url.path);
          expect(r.method, 'GET');
          expect(
            r.headers.keys.map((k) => k.toLowerCase()),
            isNot(contains('authorization')),
          );
          if (r.url.path.endsWith('/vuelos')) {
            consultasVuelos++;
            if (consultasVuelos > 1) return consultaCatalogo.future;
            return _json({
              'vuelos': [flight],
            });
          }
          return _json({'aeropuertos': []});
        }),
      );
      await t.pumpWidget(
        MaterialApp(
          home: LandingPage(apiService: api, globoBuilder: _globo),
        ),
      );
      await t.pumpAndSettle();
      final tarjeta = find.byKey(const ValueKey('landing-vuelo-v'));
      await t.ensureVisible(tarjeta);
      await t.tap(
        find.descendant(
          of: tarjeta,
          matching: find.widgetWithText(FilledButton, 'Reservar'),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      final pagina = t.widget<SistemaVuelosPage>(
        find.byType(SistemaVuelosPage),
      );
      expect(pagina.apiService, same(api));
      expect(pagina.vueloInicial, flight);
      expect(find.byType(LoginPage), findsNothing);
      expect(
        llamadas.any(
          (ruta) => ruta.contains('/auth') || ruta.endsWith('/pedidos'),
        ),
        false,
      );
      await t.pumpWidget(const SizedBox());
      consultaCatalogo.complete(_json({'vuelos': []}));
      await t.pump();
    },
  );
  for (final ancho in [390.0, 1280.0, 1920.0]) {
    testWidgets('hero ocupa viewport y preview una sola fila en $ancho', (
      t,
    ) async {
      await t.binding.setSurfaceSize(Size(ancho, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final vuelos = [
        for (var i = 0; i < 9; i++)
          {...flight, 'id': 'v$i', 'codigo': 'AT${101 + i}'},
      ];
      final api = ApiService(
        client: MockClient((r) async {
          expect(r.method, 'GET');
          expect(
            r.headers.keys.map((k) => k.toLowerCase()),
            isNot(contains('authorization')),
          );
          expect(r.url.path, '/api/sistema/vuelos');
          return _json({'vuelos': vuelos});
        }),
      );
      await t.pumpWidget(
        MaterialApp(
          home: LandingPage(apiService: api, globoBuilder: _globo),
        ),
      );
      await t.pumpAndSettle();
      final hero = t.getSize(find.byKey(const ValueKey('landing-hero')));
      expect(hero.width, ancho);
      expect(hero.height, greaterThanOrEqualTo(1000));
      final tarjetas = find.byType(TarjetaDestino);
      expect(
        tarjetas,
        findsNWidgets(
          ancho == 390
              ? 1
              : ancho == 1280
              ? 3
              : 5,
        ),
      );
      final rectangulos = [
        for (var i = 0; i < tarjetas.evaluate().length; i++)
          t.getRect(tarjetas.at(i)),
      ];
      expect(rectangulos.every((r) => r.top == rectangulos.first.top), true);
      expect(rectangulos.first.left, greaterThanOrEqualTo(0));
      expect(rectangulos.last.right, lessThanOrEqualTo(ancho));
      final experiencia = t.getSize(
        find.byKey(const ValueKey('landing-experiencia')),
      );
      if (ancho > 1600) expect(experiencia.width, greaterThan(1600));
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('error de consulta se recupera sin fabricar vuelos', (t) async {
    var llamadas = 0;
    final api = ApiService(
      client: MockClient((_) async {
        llamadas++;
        return llamadas == 1
            ? _json({
                'error': {'mensaje': 'No disponible'},
              }, 503)
            : _json({'vuelos': []});
      }),
    );
    await t.pumpWidget(
      MaterialApp(
        home: LandingPage(apiService: api, globoBuilder: _globo),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(TarjetaDestino), findsNothing);
    await t.ensureVisible(
      find.byKey(const ValueKey('landing-reintentar-vuelos')),
    );
    await t.tap(find.byKey(const ValueKey('landing-reintentar-vuelos')));
    await t.pumpAndSettle();
    expect(llamadas, 2);
    expect(
      find.text('Pronto habrá nuevos destinos para descubrir.'),
      findsOneWidget,
    );
    expect(find.byType(TarjetaDestino), findsNothing);
  });
  testWidgets(
    'Buscar más abre catálogo con servicio compartido sin pedir login',
    (t) async {
      final llamadas = <String>[];
      final api = ApiService(
        client: MockClient((r) async {
          llamadas.add(r.url.path);
          return _json(
            r.url.path.endsWith('/aeropuertos')
                ? {'aeropuertos': []}
                : {'vuelos': []},
          );
        }),
      );
      await t.pumpWidget(
        MaterialApp(
          home: LandingPage(apiService: api, globoBuilder: _globo),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('landing-buscar-mas')));
      await t.tap(find.byKey(const ValueKey('landing-buscar-mas')));
      await t.pumpAndSettle();
      expect(
        t.widget<SistemaVuelosPage>(find.byType(SistemaVuelosPage)).apiService,
        same(api),
      );
      expect(find.byType(LoginPage), findsNothing);
      expect(
        llamadas.any(
          (ruta) => ruta.contains('/auth') || ruta.endsWith('/pedidos'),
        ),
        false,
      );
    },
  );
}
