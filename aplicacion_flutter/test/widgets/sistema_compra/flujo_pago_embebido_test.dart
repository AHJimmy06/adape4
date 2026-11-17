import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:aplicacion_flutter/services/sistema_api.dart';
import 'package:aplicacion_flutter/widgets/sistema_compra/compra_sistema_dialog.dart';
import 'package:aplicacion_flutter/pages/sistema_reservas_page.dart';

void main() {
  final pedido = <String, dynamic>{
    'id': 'p1',
    'estado': 'pendiente_pago',
    'vuelo_id': 'f1',
    'asientos': [
      {'codigo': '1A', 'clase_codigo': 'ECO'},
    ],
    'total_centavos': 1150,
    'subtotal_centavos': 1000,
    'iva_centavos': 150,
    'vence_en': '2099-12-20T14:30:00Z',
  };
  ApiService api() => ApiService(
    client: MockClient(
      (r) async => http.Response(
        jsonEncode(
          r.url.path.endsWith('/reservas')
              ? {'reservas': []}
              : {
                  'pedidos': [pedido],
                },
        ),
        200,
        headers: {'content-type': 'application/json'},
      ),
    ),
  )..establecerToken('test');
  testWidgets('pedido no muestra actualizacion manual ni abre nueva pestaña', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PedidoSistema(
              api: SistemaApi(api()),
              pedido: pedido,
              launcher: (_) async =>
                  throw StateError('No debe abrir otra pagina'),
              onRefresh: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Actualizar pago'), findsNothing);
    expect(find.textContaining('verifica automáticamente'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('mis reservas muestra pedidos sin pagar recuperables', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: SistemaReservasPage(apiService: api())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pendientes de pago'), findsOneWidget);
    expect(find.text('Continuar pago'), findsOneWidget);
    expect(find.textContaining('1A'), findsOneWidget);
  });
  testWidgets('Stripe se monta dentro del pedido y solo el servidor confirma', (
    tester,
  ) async {
    final paths = <String>[];
    var pagado = false;
    var refreshes = 0;
    final service = ApiService(
      client: MockClient((r) async {
        paths.add('${r.method} ${r.url.path}');
        return http.Response(
          jsonEncode(
            r.url.path.endsWith('/pago-embebido')
                ? {
                    'pedido': pedido,
                    'client_secret': 'cs_test_secret',
                    'publishable_key': 'pk_test_public',
                  }
                : {
                    'pedido': {
                      ...pedido,
                      'estado': pagado ? 'pagado' : 'pendiente_pago',
                    },
                  },
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    )..establecerToken('test');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PedidoSistema(
              api: SistemaApi(service),
              pedido: pedido,
              launcher: (_) async => throw StateError('Nunca abrir pestaña'),
              onRefresh: () => refreshes++,
              stripeBuilder: (secret, key, onComplete) {
                expect(secret, 'cs_test_secret');
                expect(key, 'pk_test_public');
                return TextButton(
                  onPressed: onComplete,
                  child: const Text('Formulario Stripe embebido'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pagar con Stripe TEST'));
    await tester.pumpAndSettle();
    expect(find.text('Formulario Stripe embebido'), findsOneWidget);
    await tester.tap(find.text('Formulario Stripe embebido'));
    await tester.pumpAndSettle();
    expect(find.text('Pendiente de pago'), findsOneWidget);
    expect(refreshes, 0);
    pagado = true;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Pago confirmado · reserva emitida'), findsOneWidget);
    expect(find.text('Formulario Stripe embebido'), findsNothing);
    expect(refreshes, 1);
    expect(paths.first, 'POST /api/sistema/pedidos/p1/pago-embebido');
    await tester.pumpWidget(const SizedBox());
    final count = paths.length;
    await tester.pump(const Duration(seconds: 40));
    expect(paths.length, count);
  });
  testWidgets(
    'abandonar es rojo ancho completo y mantiene la misma clave en reintento',
    (tester) async {
      final keys = <String>[];
      final service = ApiService(
        client: MockClient((r) async {
          keys.add(jsonDecode(r.body)['clave_operacion'] as String);
          if (keys.length == 1) {
            return http.Response(
              jsonEncode({
                'error': {'mensaje': 'Proveedor no disponible'},
              }),
              503,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'pedido': {...pedido, 'estado': 'cancelado'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      )..establecerToken('test');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PedidoSistema(
                api: SistemaApi(service),
                pedido: pedido,
                launcher: (_) async => false,
                onRefresh: () {},
              ),
            ),
          ),
        ),
      );
      final button = find.widgetWithText(FilledButton, 'Abandonar pedido');
      await tester.ensureVisible(button);
      final b = tester.widget<FilledButton>(button);
      final context = tester.element(button);
      expect(
        b.style!.backgroundColor!.resolve({}),
        Theme.of(context).colorScheme.error,
      );
      expect(tester.getSize(button).width, greaterThan(500));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(keys.single, isNotEmpty);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(keys.length, 2);
      expect(keys.first, keys.last);
      expect(find.text('Cancelado'), findsOneWidget);
      expect(find.text('Abandonar pedido'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
