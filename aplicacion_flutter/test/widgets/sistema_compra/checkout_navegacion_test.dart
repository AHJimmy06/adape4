import 'dart:convert';

import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:aplicacion_flutter/services/sistema_api.dart';
import 'package:aplicacion_flutter/pages/sistema_vuelos_page.dart';
import 'package:aplicacion_flutter/widgets/sistema_compra/compra_sistema_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../pages/sistema_vuelos_page_test.dart'
    show airport, flight, cabin, seat, order;

void main() {
  testWidgets('abandonar desde compra cierra el diálogo y conserva catálogo', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final api = ApiService(
      client: MockClient(
        (r) async => http.Response(
          jsonEncode(
            r.url.path.endsWith('/asientos')
                ? {
                    'clases': [cabin],
                    'asientos': [seat('1A', 'libre')],
                  }
                : {
                    'pedido': order(
                      r.url.path.endsWith('/abandonar')
                          ? 'cancelado'
                          : 'pendiente_pago',
                    ),
                  },
          ),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    )..establecerToken('token');
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                const Text('Catálogo principal'),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => CompraSistemaDialog(
                      api: SistemaApi(api),
                      vuelo: flight,
                      launcher: (_) async => false,
                      onRefresh: () {},
                    ),
                  ),
                  child: const Text('Elegir vuelo'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Elegir vuelo'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('asiento-1A')));
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(find.byKey(const ValueKey('asiento-1A')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Continuar con 1 asiento(s)'));
    await t.tap(find.text('Continuar con 1 asiento(s)'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Abandonar pedido'));
    await t.tap(find.text('Abandonar pedido'));
    await t.pumpAndSettle();
    expect(find.byType(CompraSistemaDialog), findsNothing);
    expect(find.text('Catálogo principal'), findsOneWidget);
    expect(api.tieneSesion, true);
  });

  testWidgets(
    'abandonar pendiente desde reservas vuelve a catálogo sin cerrar sesión',
    (t) async {
      await t.binding.setSurfaceSize(const Size(1100, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      var abandoned = false;
      final api = ApiService(
        client: MockClient((r) async {
          Object data;
          if (r.url.path.endsWith('/abandonar')) {
            abandoned = true;
            data = {'pedido': order('cancelado')};
          } else if (r.url.path.endsWith('/reservas')) {
            data = {'reservas': []};
          } else if (r.url.path.endsWith('/vuelos')) {
            data = {
              'vuelos': [flight],
            };
          } else if (r.url.path.endsWith('/aeropuertos')) {
            data = {
              'aeropuertos': [airport],
            };
          } else {
            data = {
              'pedidos': abandoned ? [] : [order('pendiente_pago')],
            };
          }
          return http.Response(
            jsonEncode(data),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      )..establecerToken('token');
      await t.pumpWidget(MaterialApp(home: SistemaVuelosPage(apiService: api)));
      await t.pumpAndSettle();
      await t.tap(find.text('Mis reservas'));
      await t.pumpAndSettle();
      await t.tap(find.text('Continuar pago'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Abandonar pedido'));
      await t.tap(find.text('Abandonar pedido'));
      await t.pumpAndSettle();
      expect(find.text('AeroTech · Vuelos'), findsOneWidget);
      expect(find.text('Tu pedido pendiente'), findsNothing);
      expect(api.tieneSesion, true);
    },
  );
  for (final status in ['cancelado', 'expirado', 'pagado', 'error']) {
    testWidgets('abandonar navega solo con confirmación $status', (t) async {
      var abandoned = 0;
      final api = ApiService(
        client: MockClient(
          (r) async => http.Response(
            jsonEncode(
              status == 'error'
                  ? {
                      'error': {'mensaje': 'Proveedor no disponible'},
                    }
                  : {
                      'pedido': {
                        'id': 'p',
                        'estado': status,
                        'asientos': [],
                        'total_centavos': 1150,
                      },
                    },
            ),
            status == 'error' ? 503 : 200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      )..establecerToken('token');
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PedidoSistema(
                api: SistemaApi(api),
                pedido: const {
                  'id': 'p',
                  'estado': 'pendiente_pago',
                  'asientos': [],
                  'total_centavos': 1150,
                  'vence_en': '2099-12-20T10:00:00Z',
                },
                launcher: (_) async => false,
                onRefresh: () {},
                onAbandonado: () => abandoned++,
              ),
            ),
          ),
        ),
      );
      await t.ensureVisible(find.text('Abandonar pedido'));
      await t.tap(find.text('Abandonar pedido'));
      await t.pumpAndSettle();
      expect(abandoned, ['cancelado', 'expirado'].contains(status) ? 1 : 0);
      if (status == 'error') {
        expect(
          find.textContaining('No se pudo verificar el pago'),
          findsOneWidget,
        );
      }
      await t.pumpWidget(const SizedBox());
    });
  }
}
