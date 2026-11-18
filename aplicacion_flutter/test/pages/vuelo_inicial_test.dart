import 'dart:convert';

import 'package:aplicacion_flutter/pages/sistema_vuelos_page.dart';
import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'sistema_vuelos_page_test.dart' show airport, flight;

void main() {
  for (final exists in [true, false]) {
    testWidgets(
      'vuelo inicial usa catálogo fresco sin pedir ingreso: $exists',
      (t) async {
        final paths = <String>[];
        final api = ApiService(
          client: MockClient((r) async {
            paths.add(r.url.path);
            expect(r.headers['Authorization'], isNull);
            return http.Response(
              jsonEncode(
                r.url.path.endsWith('/aeropuertos')
                    ? {
                        'aeropuertos': [airport],
                      }
                    : {
                        'vuelos': exists ? [flight] : [],
                      },
              ),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        await t.pumpWidget(
          MaterialApp(
            home: SistemaVuelosPage(
              apiService: api,
              vueloInicial: {'id': flight['id'], 'ruta': null},
              routeBuilder: (_, _) => const Text('Ruta fresca'),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(
          find.text('Ruta fresca'),
          exists ? findsOneWidget : findsNothing,
        );
        if (!exists) {
          expect(
            find.textContaining('El vuelo seleccionado ya no está disponible'),
            findsOneWidget,
          );
        }
        expect(
          paths.any((p) => p.contains('auth') || p.endsWith('/pedidos')),
          false,
        );
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
