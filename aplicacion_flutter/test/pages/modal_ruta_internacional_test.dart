import 'package:aplicacion_flutter/pages/sistema_vuelos_page.dart';
import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'sistema_vuelos_page_test.dart' as fixtures;

void main() {
  for (final size in [
    const Size(1280, 900),
    const Size(813, 495),
    const Size(390, 700),
  ]) {
    testWidgets('international route uses available space at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final destination = {
        ...fixtures.airport,
        'id': 'lim',
        'iata': 'LIM',
        'ciudad': 'Lima',
        'pais': 'Perú',
        'codigo_pais': 'PE',
        'latitud': -12.02,
        'longitud': -77.11,
      };
      final flight = {
        ...fixtures.flight,
        'ruta': {'origen': fixtures.airport, 'destino': destination},
      };
      final api = ApiService(
        client: MockClient(
          (r) async => fixtures.json(
            r.url.path.endsWith('/vuelos')
                ? {
                    'vuelos': [flight],
                  }
                : {
                    'aeropuertos': [fixtures.airport, destination],
                  },
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SistemaVuelosPage(
            apiService: api,
            routeBuilder: (_, ruta) =>
                const SizedBox(key: ValueKey('route-area'), height: 280),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Reservar'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Reservar'));
      await tester.pumpAndSettle();
      await tester.binding.setSurfaceSize(size);
      await tester.pumpAndSettle();
      final route = tester.getRect(find.byKey(const ValueKey('route-area')));
      expect(route.height, greaterThan(280));
      if (size.width > 1100) expect(route.width, greaterThan(900));
      expect(route.left, greaterThanOrEqualTo(0));
      expect(route.right, lessThanOrEqualTo(size.width));
      expect(route.bottom, lessThan(size.height));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Volver'));
      await tester.pumpAndSettle();
      expect(find.text('Tu ruta AeroTech'), findsNothing);
    });
  }
  testWidgets('national route keeps the compact presentation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = ApiService(
      client: MockClient(
        (r) async => fixtures.json(
          r.url.path.endsWith('/vuelos')
              ? {
                  'vuelos': [fixtures.flight],
                }
              : {
                  'aeropuertos': [fixtures.airport],
                },
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SistemaVuelosPage(
          apiService: api,
          routeBuilder: (_, ruta) =>
              const SizedBox(key: ValueKey('national-area'), height: 280),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reservar'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('national-area'))),
      const Size(650, 280),
    );
    expect(tester.takeException(), isNull);
  });
}
