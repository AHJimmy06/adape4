import 'package:flutter/material.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:aplicacion_flutter/widgets/presentacion/dialogo_aerotech.dart';
import 'package:aplicacion_flutter/theme/aerotech_theme.dart';
import 'package:aplicacion_flutter/widgets/sistema_compra/compra_sistema_dialog.dart';
import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:aplicacion_flutter/services/sistema_api.dart';

import '../../pages/sistema_vuelos_page_test.dart'
    show order, cabin, flight, seat, json;

void main() {
  testWidgets('pedido legible con fecha UTC y acciones accesibles en móvil', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AerotechTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PedidoSistema(
              api: SistemaApi(ApiService()),
              pedido: order('pendiente_pago'),
              launcher: (_) async => true,
              onRefresh: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Pendiente de pago'), findsOneWidget);
    expect(find.text('20 dic 2099 · 09:30 Ecuador (UTC−5)'), findsOneWidget);
    expect(find.textContaining('2099-12-20T'), findsNothing);
    expect(find.text('USD 11.50'), findsOneWidget);
    expect(find.textContaining('pendiente_pago'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'cambiar de cabina desplazada a pedido reinicia solo el paso visual',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final bodies = <Map<String, dynamic>>[];
      final api = SistemaApi(
        ApiService(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/asientos')) {
              return json({
                'clases': [
                  {...cabin, 'filas': 8},
                ],
                'asientos': [
                  for (var row = 1; row <= 8; row++) seat('${row}B', 'libre'),
                ],
              });
            }
            bodies.add(
              Map<String, dynamic>.from(jsonDecode(request.body) as Map),
            );
            return json({'pedido': order('pendiente_pago')}, 201);
          }),
        )..establecerToken('token'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AerotechTheme.light,
          home: Scaffold(
            body: CompraSistemaDialog(
              api: api,
              vuelo: flight,
              launcher: (_) async => true,
              onRefresh: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('asiento-7B')));
      await tester.tap(find.byKey(const ValueKey('asiento-7B')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const ValueKey('asiento-7B')));
      await tester.pumpAndSettle();
      final before = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(DialogoAerotech),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      before.position.jumpTo(before.position.maxScrollExtent);
      await tester.pump();
      expect(before.position.pixels, greaterThan(0));
      await tester.tap(find.text('Continuar con 1 asiento(s)'));
      await tester.pumpAndSettle();
      final after = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(DialogoAerotech),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(after.position.pixels, 0);
      expect(find.text('Pedido · Stripe TEST').hitTestable(), findsOneWidget);
      expect(bodies.single['asientos'], ['7B']);
      expect(bodies.single['vuelo_id'], flight['id']);
      expect(bodies.single['clave_operacion'], isNotEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('pedido desktop muestra pago sin desplazar el resumen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AerotechTheme.light,
        home: Scaffold(
          body: DialogoAerotech(
            title: 'Pedido · Stripe TEST',
            subtitle: 'Revisa tu pedido y continúa al pago seguro.',
            eyebrow: 'RESUMEN DE COMPRA',
            icon: Icons.receipt_long_outlined,
            actions: [
              TextButton(onPressed: () {}, child: const Text('Cerrar')),
            ],
            child: PedidoSistema(
              api: SistemaApi(ApiService()),
              pedido: order('pendiente_pago'),
              launcher: (_) async => true,
              onRefresh: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pay = find.widgetWithText(FilledButton, 'Pagar con Stripe TEST');

    final viewport = tester.getRect(find.byType(SingleChildScrollView).first);
    expect(tester.getBottomRight(pay).dy, lessThanOrEqualTo(viewport.bottom));
    expect(pay.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
