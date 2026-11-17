import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aplicacion_flutter/pages/sistema_vuelos_page.dart';
import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:aplicacion_flutter/widgets/sistema_compra/cabina_sistema.dart';
import 'package:aplicacion_flutter/utils/checkout_launcher.dart';

final airport = {
  'id': 'uio',
  'iata': 'UIO',
  'nombre': 'Mariscal Sucre',
  'ciudad': 'Quito',
  'pais': 'Ecuador',
  'codigo_pais': 'EC',
  'zona_horaria': 'America/Guayaquil',
  'latitud': -0.129,
  'longitud': -78.357,
};
final cabin = {
  'codigo': 'ECO',
  'nombre': 'Económica',
  'fila_inicio': 1,
  'filas': 1,
  'columnas': [
    ['A', 'B'],
    ['C', 'D'],
  ],
  'capacidad': 4,
};
final flight = {
  'id': 'v',
  'codigo': 'AT101',
  'ruta': {
    'origen': airport,
    'destino': {
      ...airport,
      'id': 'gye',
      'iata': 'GYE',
      'ciudad': 'Guayaquil',
      'latitud': -2.15,
      'longitud': -79.88,
    },
  },
  'avion': {
    'modelo': 'A320',
    'matricula': 'HC-ABC',
    'clases': [cabin],
  },
  'salida_en': '2099-12-20T14:00:00Z',
  'salida_local': '2099-12-20T09:00',
  'llegada_local': '2099-12-20T10:00',
  'asientos_disponibles': 3,
  'precio_desde_centavos': 1000,
  'tarifas': [
    {'clase_codigo': 'ECO', 'precio_centavos': 1000, 'disponibles': 3},
  ],
};
Map<String, dynamic> seat(String c, String state) => {
  'id': c,
  'codigo': c,
  'fila': 1,
  'columna': c.substring(1),
  'clase_codigo': 'ECO',
  'clase_nombre': 'Económica',
  'precio_centavos': 1000,
  'estado': state,
  'es_mio': false,
};
Map<String, dynamic> order(String state) => {
  'id': 'p',
  'vuelo_id': 'v',
  'estado': state,
  'asientos': [
    {'codigo': '1B', 'clase_codigo': 'ECO', 'total_centavos': 1150},
  ],
  'subtotal_centavos': 1000,
  'iva_centavos': 150,
  'total_centavos': 1150,
  'vence_en': '2099-12-20T14:30:00Z',
  'checkout_url': 'https://checkout.stripe.com/c/pay/test_123',
};
http.Response json(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json'},
);
void main() {
  test('checkout allows only HTTPS Stripe hosted origin', () {
    expect(
      esCheckoutSeguro(Uri.parse('https://checkout.stripe.com/c/pay/test')),
      true,
    );
    for (final value in [
      'http://checkout.stripe.com/x',
      'https://checkout.stripe.com.evil.org/x',
      'https://evil@checkout.stripe.com/x',
      'https://checkout.stripe.com:444/x',
    ]) {
      expect(esCheckoutSeguro(Uri.parse(value)), false);
    }
  });
  testWidgets(
    'occupied seat remains rendered, exact labels sent, retry stable and pending not confirmed',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final bodies = <Map<String, dynamic>>[];
      var orderGets = 0;
      var launched = 0;
      final api = ApiService(
        client: MockClient((r) async {
          expect(r.headers['Authorization'], 'Bearer token');
          if (r.url.path.endsWith('/aeropuertos')) {
            return json({
              'aeropuertos': [airport],
            });
          }
          if (r.url.path.endsWith('/asientos')) {
            return json({
              'vuelo': flight,
              'clases': [cabin],
              'asientos': [
                seat('1A', 'ocupado'),
                seat('1B', 'libre'),
                seat('1C', 'retenido'),
                seat('1D', 'libre'),
              ],
            });
          }
          if (r.url.path.endsWith('/vuelos')) {
            return json({
              'vuelos': [flight],
            });
          }
          if (r.url.path.endsWith('/pedidos') && r.method == 'GET') {
            return json({'pedidos': []});
          }
          if (r.url.path.endsWith('/pedidos') && r.method == 'POST') {
            bodies.add(Map<String, dynamic>.from(jsonDecode(r.body) as Map));
            if (bodies.length == 1) throw http.ClientException('offline');
            return json({'pedido': order('pendiente_pago')}, 201);
          }
          if (r.url.path.endsWith('/pedidos/p')) {
            orderGets++;
            return json({'pedido': order('pagado')});
          }
          throw StateError(r.url.toString());
        }),
      )..establecerToken('token');
      await tester.pumpWidget(
        MaterialApp(
          home: SistemaVuelosPage(
            apiService: api,
            routeBuilder: (_, r) => Text('airport ${r.puntoOrigen}'),
            checkoutLauncher: (_) async {
              launched++;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reservar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('airport (-0.129'), findsOneWidget);
      await tester.tap(find.text('Elegir asientos'));
      await tester.pumpAndSettle();
      var cabinWidget = tester.widget<CabinaSistema>(
        find.byType(CabinaSistema),
      );
      expect(cabinWidget.asientos.length, 4);
      await tester.tap(find.byKey(const ValueKey('asiento-1A')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const ValueKey('asiento-1A')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CabinaSistema>(find.byType(CabinaSistema)).seleccionados,
        isEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('asiento-1B')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const ValueKey('asiento-1B')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar con 1 asiento(s)'));
      await tester.pumpAndSettle();
      expect(bodies, hasLength(1));
      await tester.tap(find.text('Continuar con 1 asiento(s)'));
      await tester.pumpAndSettle();
      expect(bodies, hasLength(2));
      expect(bodies[0], bodies[1]);
      expect(bodies[1]['asientos'], ['1B']);
      expect(bodies[1].containsKey('precio_centavos'), false);
      expect(find.textContaining('Pago confirmado'), findsNothing);
      expect(launched, 0);
      await tester.tap(find.text('Pagar con Stripe TEST'));
      await tester.pumpAndSettle();
      expect(launched, 1);
      expect(find.textContaining('Pago confirmado'), findsNothing);
      await tester.tap(find.text('Actualizar pago'));
      await tester.pumpAndSettle();
      expect(orderGets, 1);
      expect(find.text('Pago confirmado · reserva emitida'), findsOneWidget);
    },
  );
  testWidgets('seat conflict accepts refresh and discards stale selection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var maps = 0, flights = 0;
    final api = ApiService(
      client: MockClient((r) async {
        if (r.url.path.endsWith('/aeropuertos')) {
          return json({
            'aeropuertos': [airport],
          });
        }
        if (r.url.path.endsWith('/vuelos')) {
          flights++;
          return json({
            'vuelos': [flight],
          });
        }
        if (r.url.path.endsWith('/pedidos') && r.method == 'GET') {
          return json({'pedidos': []});
        }
        if (r.url.path.endsWith('/asientos')) {
          maps++;
          return json({
            'vuelo': flight,
            'clases': [cabin],
            'asientos': [
              seat('1A', 'ocupado'),
              seat('1B', maps == 1 ? 'libre' : 'ocupado'),
              seat('1C', 'libre'),
              seat('1D', 'libre'),
            ],
          });
        }
        if (r.url.path.endsWith('/pedidos')) {
          return json({
            'error': {
              'codigo': 'asiento_no_disponible',
              'mensaje': 'Asiento ocupado',
            },
          }, 409);
        }
        throw StateError(r.url.toString());
      }),
    )..establecerToken('token');
    await tester.pumpWidget(
      MaterialApp(
        home: SistemaVuelosPage(
          apiService: api,
          routeBuilder: (_, _) => const Text('route'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reservar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elegir asientos'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asiento-1B')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const ValueKey('asiento-1B')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar con 1 asiento(s)'));
    await tester.pumpAndSettle();
    expect(find.text('La disponibilidad cambió'), findsOneWidget);
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
    expect(maps, 2);
    expect(flights, greaterThan(1));
    final cabina = tester.widget<CabinaSistema>(find.byType(CabinaSistema));
    expect(cabina.seleccionados, isEmpty);
    expect(
      cabina.asientos.singleWhere((s) => s['codigo'] == '1B')['estado'],
      'ocupado',
    );
  });
}
