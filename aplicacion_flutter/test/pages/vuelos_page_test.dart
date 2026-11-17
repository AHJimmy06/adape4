import 'dart:convert';

import 'package:aplicacion_flutter/pages/vuelos_page.dart';
import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'Reservar opens selected route without a POST and final confirmation refreshes flights',
    (tester) async {
      var reservations = 0;
      var searches = 0;
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          reservations++;
          expect(jsonDecode(request.body), {
            'vuelo_id': 'route-2',
            'cantidad': 2,
          });
          return http.Response('{"mensaje":"Confirmada"}', 201);
        }
        searches++;
        return http.Response(
          jsonEncode([
            {
              'id': 'route-2',
              'origen': 'Cuenca',
              'destino': 'Quito',
              'fecha': '2026-11-20',
              'hora_salida': '08:00',
              'precio': 90,
              'asientos_disponibles': 10,
            },
          ]),
          200,
        );
      });
      final api = ApiService(client: client)..establecerToken('test');
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: child!,
          ),
          home: VuelosPage(apiService: api),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reservar'));
      await tester.pumpAndSettle();
      expect(reservations, 0);
      expect(find.text('Cuenca → Quito'), findsNWidgets(2));
      await tester.ensureVisible(find.text('Cancelar'));
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(reservations, 0);
      expect(searches, 1);
      await tester.tap(find.text('Reservar'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continuar a la cabina'));
      await tester.tap(find.text('Continuar a la cabina'));
      await tester.pumpAndSettle();
      for (final asiento in ['1A', '1B']) {
        await tester.tap(find.byKey(ValueKey('seat-$asiento')));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.byKey(ValueKey('seat-$asiento')));
        await tester.pump(const Duration(milliseconds: 350));
      }
      await tester.ensureVisible(find.text('Confirmar reserva'));
      await tester.tap(find.text('Confirmar reserva'));
      await tester.pumpAndSettle();
      expect(reservations, 1);
      expect(searches, 2);
      client.close();
    },
  );
  for (final restantes in [0, 1]) {
    testWidgets(
      'conflicto muestra modal y actualiza stock $restantes al aceptar',
      (tester) async {
        var busquedas = 0;
        var reservas = 0;
        final cliente = MockClient((solicitud) async {
          if (solicitud.method == 'POST') {
            reservas++;
            expect(jsonDecode(solicitud.body)['cantidad'], 2);
            return http.Response(
              jsonEncode({
                'error': {
                  'codigo': 'asientos_insuficientes',
                  'mensaje': 'No hay suficientes asientos disponibles.',
                },
              }),
              409,
            );
          }
          busquedas++;
          if (busquedas > 1) {
            expect(solicitud.url.queryParameters, {
              'origen': 'Cuenca',
              'destino': 'Quito',
            });
          }
          return http.Response(
            jsonEncode([
              {
                'id': 'vuelo-conflicto',
                'origen': 'Cuenca',
                'destino': 'Quito',
                'fecha': '2026-11-20',
                'hora_salida': '08:00',
                'precio': 90,
                'asientos_disponibles': busquedas > 2 ? restantes : 4,
              },
            ]),
            200,
          );
        });
        final api = ApiService(client: cliente)..establecerToken('prueba');
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: child!,
            ),
            home: VuelosPage(apiService: api),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(0), 'Cuenca');
        await tester.enterText(find.byType(TextField).at(1), 'Quito');
        await tester.tap(find.text('Buscar'));
        await tester.pumpAndSettle();
        expect(busquedas, 2);
        await tester.tap(find.text('Reservar'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Continuar a la cabina'));
        await tester.tap(find.text('Continuar a la cabina'));
        await tester.pumpAndSettle();
        for (final asiento in ['1A', '1B']) {
          await tester.tap(find.byKey(ValueKey('seat-$asiento')));
          await tester.pump(const Duration(milliseconds: 100));
          await tester.tap(find.byKey(ValueKey('seat-$asiento')));
          await tester.pump(const Duration(milliseconds: 350));
        }
        await tester.ensureVisible(find.text('Confirmar reserva'));
        await tester.tap(find.text('Confirmar reserva'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.textContaining('Ya no hay suficientes asientos'),
          findsOneWidget,
        );
        expect(busquedas, 2);
        expect(reservas, 1);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('confirm-booking')),
              )
              .onPressed,
          isNull,
        );
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('Aceptar'));
        await tester.pumpAndSettle();
        expect(busquedas, 3);
        expect(reservas, 1);
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          find.textContaining('$restantes asientos disponibles'),
          findsOneWidget,
        );
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
        cliente.close();
      },
    );
  }
  testWidgets(
    'mantiene el buscador y resultados responsivos con la paleta AeroTech',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final cliente = MockClient((solicitud) async {
        expect(solicitud.url.path, '/api/vuelos');
        return http.Response(
          jsonEncode([
            {
              'id': 'vuelo-1',
              'origen': 'Quito',
              'destino': 'Lima',
              'fecha': '2026-11-20',
              'hora_salida': '08:00',
              'hora_llegada': '10:00',
              'precio': 125.0,
              'asientos_disponibles': 12,
            },
          ]),
          200,
        );
      });
      final servicio = ApiService(
        baseUrl: Uri.parse('http://localhost:5000'),
        client: cliente,
      )..establecerToken('jwt-activo');

      await tester.pumpWidget(
        MaterialApp(home: VuelosPage(apiService: servicio)),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        const Color(0xFFF2F6FA),
      );
      expect(find.text('Origen'), findsOneWidget);
      expect(find.text('Destino'), findsOneWidget);
      expect(find.text('Buscar'), findsOneWidget);
      expect(find.text('Quito → Lima'), findsOneWidget);
      expect(
        tester
            .widget<Card>(
              find.ancestor(
                of: find.text('Quito → Lima'),
                matching: find.byType(Card),
              ),
            )
            .shape,
        isA<RoundedRectangleBorder>().having(
          (shape) => shape.borderRadius,
          'borderRadius',
          BorderRadius.circular(20),
        ),
      );
      expect(tester.takeException(), isNull);
      cliente.close();
    },
  );
  testWidgets('actualizar permisos permite descubrir el panel tras promocion', (
    tester,
  ) async {
    var perfiles = 0;
    final cliente = MockClient((solicitud) async {
      if (solicitud.url.path == '/api/auth/perfil') {
        perfiles++;
        return http.Response(
          '{"usuario":{"id":"admin-test","nombre":"Cuenta de prueba","correo":"prueba@example.invalid","rol":"ADMIN"}}',
          200,
        );
      }
      if (solicitud.url.path == '/api/admin/usuarios') {
        return http.Response('[]', 200);
      }
      expect(solicitud.url.path, '/api/vuelos');
      return http.Response('[]', 200);
    });
    final api = ApiService(client: cliente)..establecerToken('token-de-prueba');
    await tester.pumpWidget(MaterialApp(home: VuelosPage(apiService: api)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Administración'), findsNothing);
    await tester.tap(find.byTooltip('Actualizar permisos'));
    await tester.pumpAndSettle();
    expect(perfiles, 1);
    expect(find.byTooltip('Administración'), findsOneWidget);
    await tester.tap(find.byTooltip('Administración'));
    await tester.pumpAndSettle();
    expect(find.text('Administración'), findsWidgets);
    expect(tester.takeException(), isNull);
    cliente.close();
  });
}
