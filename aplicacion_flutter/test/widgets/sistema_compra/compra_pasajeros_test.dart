import 'dart:convert';

import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:aplicacion_flutter/pages/sistema_reservas_page.dart';
import 'package:aplicacion_flutter/services/sistema_api.dart';
import 'package:aplicacion_flutter/widgets/sistema_compra/compra_sistema_dialog.dart';
import 'package:aplicacion_flutter/widgets/sistema_compra/detalle_pasajero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../pages/sistema_vuelos_page_test.dart'
    show cabin, flight, seat, order;

void main() {
  testWidgets(
    'cancelación usa el total persistido incluido equipaje del asiento',
    (t) async {
      await t.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final api = ApiService(
        client: MockClient(
          (_) async => throw StateError(
            'No debe emitir cancelación durante la vista previa',
          ),
        ),
      );
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CancelacionSistemaDialog(
              api: SistemaApi(api),
              reserva: {
                'id': 'r1',
                'legada': false,
                'cantidad_activa': 1,
                'asientos': [
                  {
                    'codigo': '1A',
                    'clase_codigo': 'ECO',
                    'estado': 'activo',
                    'total_centavos': 3150,
                    'pasajero': {'asignado': false, 'categoria': 'nino'},
                    'equipaje': {'cantidad': 1, 'total_centavos': 2000},
                  },
                ],
              },
            ),
          ),
        ),
      );
      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      expect(find.text('Reembolso estimado: USD 31.50'), findsOneWidget);
      expect(
        find.textContaining('incluye su equipaje adicional'),
        findsOneWidget,
      );
      expect(find.text('Asiento 1A · Niño'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('quitar un asiento descarta su equipaje y no lo aplica a otro', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(1100, 1700));
    addTearDown(() => t.binding.setSurfaceSize(null));
    Map<String, dynamic>? enviado;
    final api = ApiService(
      client: MockClient((r) async {
        if (r.url.path.endsWith('/asientos')) {
          return http.Response(
            jsonEncode({
              'clases': [cabin],
              'asientos': [seat('1A', 'libre'), seat('1B', 'libre')],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        enviado = Map<String, dynamic>.from(jsonDecode(r.body));
        return http.Response(
          jsonEncode({'pedido': order('pagado')}),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    )..establecerToken('test');
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompraSistemaDialog(
            api: SistemaApi(api),
            vuelo: flight,
            launcher: (_) async => false,
            onRefresh: () {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    Future<void> elegir(String codigo) async {
      final boton = find.byKey(ValueKey('asiento-$codigo'));
      await t.ensureVisible(boton);
      await t.tap(boton);
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(boton);
      await t.pumpAndSettle();
    }

    await elegir('1A');
    await t.tap(find.byKey(const ValueKey('pasajero-1A')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('maletas-1A')), '3');
    await t.pumpAndSettle();
    await elegir('1A');
    await elegir('1B');
    await elegir('1A');
    await t.tap(find.text('Continuar con 2 asiento(s)'));
    await t.pumpAndSettle();
    final pasajeros = enviado!['pasajeros'] as List;
    expect(pasajeros.map((p) => p['asiento']), ['1A', '1B']);
    expect(pasajeros.map((p) => p['maletas_adicionales']), [0, 0]);
    await t.pumpWidget(const SizedBox());
  });
  for (final estadoError in [400, 503]) {
    testWidgets(
      'envía pasajeros y equipaje; reintento conserva configuración tras $estadoError',
      (t) async {
        await t.binding.setSurfaceSize(const Size(1100, 1700));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final cuerpos = <Map<String, dynamic>>[];
        final api = ApiService(
          client: MockClient((r) async {
            if (r.url.path.endsWith('/asientos')) {
              return http.Response(
                jsonEncode({
                  'clases': [cabin],
                  'asientos': [seat('1A', 'libre'), seat('1B', 'libre')],
                }),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }
            expect(r.url.path.endsWith('/pedidos'), true);
            cuerpos.add(Map<String, dynamic>.from(jsonDecode(r.body)));
            if (cuerpos.length == 1) {
              return http.Response(
                jsonEncode({
                  'error': {
                    'mensaje': 'Reintenta',
                    'codigo': estadoError == 400
                        ? 'usuario_asignado_no_disponible'
                        : 'proveedor_no_disponible',
                  },
                }),
                estadoError,
              );
            }
            return http.Response(
              jsonEncode({'pedido': order('pagado')}),
              201,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        )..establecerToken('test');
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CompraSistemaDialog(
                api: SistemaApi(api),
                vuelo: flight,
                launcher: (_) async => false,
                onRefresh: () {},
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        for (final codigo in ['1A', '1B']) {
          await t.tap(find.byKey(ValueKey('asiento-$codigo')));
          await t.pump(const Duration(milliseconds: 50));
          await t.tap(find.byKey(ValueKey('asiento-$codigo')));
          await t.pumpAndSettle();
        }
        await t.tap(find.byKey(const ValueKey('pasajero-1A')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('asignar-1A')));
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const ValueKey('correo-pasajero-1A')),
          ' ANA@EXAMPLE.TEST ',
        );
        await t.enterText(find.byKey(const ValueKey('maletas-1A')), '2');
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(const ValueKey('pasajero-1B')));
        await t.tap(find.byKey(const ValueKey('pasajero-1B')));
        await t.pumpAndSettle();
        t
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const ValueKey('categoria-1B')),
            )
            .onChanged!('nino');
        await t.pumpAndSettle();
        await t.tap(find.text('Continuar con 2 asiento(s)'));
        await t.pumpAndSettle();
        expect(cuerpos.single['pasajeros'], [
          {
            'asiento': '1A',
            'correo_usuario': 'ana@example.test',
            'categoria': 'adulto',
            'maletas_adicionales': 2,
          },
          {
            'asiento': '1B',
            'correo_usuario': null,
            'categoria': 'nino',
            'maletas_adicionales': 0,
          },
        ]);
        await t.tap(find.text('Continuar con 2 asiento(s)'));
        await t.pumpAndSettle();
        expect(cuerpos[0], cuerpos[1]);
        expect(find.text('Pedido · Stripe TEST'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'snapshot muestra identidad, categoría y coste de equipaje sin recalcular',
    (t) async {
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                DetallePasajero(
                  asiento: {
                    'codigo': '1A',
                    'pasajero': {
                      'asignado': true,
                      'nombre': 'Ana',
                      'correo': 'ana@example.test',
                      'categoria': 'adulto',
                    },
                    'equipaje': {'cantidad': 2, 'total_centavos': 4000},
                  },
                ),
                DetallePasajero(
                  asiento: {
                    'codigo': '1B',
                    'pasajero': {
                      'asignado': false,
                      'categoria': 'adulto_mayor',
                    },
                    'equipaje': {'cantidad': 0, 'total_centavos': 0},
                  },
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Asiento 1A · Ana'), findsOneWidget);
      expect(find.text('ana@example.test'), findsOneWidget);
      expect(find.text('Asiento 1B · Adulto mayor'), findsOneWidget);
      expect(find.textContaining('USD 40.00'), findsOneWidget);
    },
  );
}
