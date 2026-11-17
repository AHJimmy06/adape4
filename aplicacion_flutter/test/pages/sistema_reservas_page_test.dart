import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:aplicacion_flutter/pages/sistema_reservas_page.dart';
import 'package:aplicacion_flutter/services/api_service.dart';

import 'sistema_vuelos_page_test.dart' show flight, json;

Map<String, dynamic> reserva() => {
  'id': 'r',
  'vuelo_id': 'v',
  'vuelo': flight,
  'estado': 'activa',
  'legada': false,
  'cantidad': 2,
  'cantidad_activa': 2,
  'cantidad_cancelada': 0,
  'subtotal_centavos': 2001,
  'iva_centavos': 300,
  'total_centavos': 2301,
  'reembolsado_centavos': 0,
  'asientos': [
    {
      'codigo': '1A',
      'clase_codigo': 'ECO',
      'estado': 'activo',
      'total_centavos': 1150,
    },
    {
      'codigo': '1B',
      'clase_codigo': 'ECO',
      'estado': 'activo',
      'total_centavos': 1151,
    },
  ],
  'cancelaciones': [],
};
void main() {
  testWidgets(
    'partial cancel chooses actual labels, min one max active, preserves cents, XML vertical',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final bodies = <Map<String, dynamic>>[];
      var listGets = 0;
      final api = ApiService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/comprobante.xml')) {
            return http.Response(
              '<reserva><asientos><asiento>1A</asiento></asientos><total>23.01</total></reserva>',
              200,
              headers: {'content-type': 'application/xml'},
            );
          }
          if (request.url.path.endsWith('/cancelaciones')) {
            bodies.add(
              Map<String, dynamic>.from(jsonDecode(request.body) as Map),
            );
            if (bodies.length == 1) throw http.ClientException('offline');
            return json({
              'cancelacion': {
                'id': 'c',
                'estado': 'pendiente',
                'importe_centavos': 1151,
              },
              'reserva': reserva(),
            });
          }
          if (request.url.path.endsWith('/reservas')) {
            listGets++;
            return json({
              'reservas': [reserva()],
            });
          }
          throw StateError(request.url.toString());
        }),
      )..establecerToken('token');
      await tester.pumpWidget(
        MaterialApp(home: SistemaReservasPage(apiService: api)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Total original: USD 23.01'), findsOneWidget);
      await tester.tap(find.text('Ver comprobante XML'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '<reserva>\n  <asientos>\n    <asiento>1A</asiento>\n  </asientos>\n  <total>23.01</total>\n</reserva>',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar asientos'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirmar cancelación'),
            )
            .onPressed,
        isNull,
      );
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      await tester.tap(find.widgetWithText(CheckboxListTile, '1B · ECO'));
      await tester.pumpAndSettle();
      expect(find.text('Reembolso estimado: USD 11.51'), findsOneWidget);
      await tester.tap(find.text('Confirmar cancelación'));
      await tester.pumpAndSettle();
      expect(bodies, hasLength(1));
      await tester.tap(find.text('Reintentar misma cancelación'));
      await tester.pumpAndSettle();
      expect(bodies, hasLength(2));
      expect(bodies[0], bodies[1]);
      expect(bodies[1]['asientos'], ['1B']);
      expect(
        find.textContaining('Solicitud de reembolso: Reembolso pendiente'),
        findsOneWidget,
      );
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect(listGets, 2);
    },
  );
  testWidgets(
    'expired flight and non-owner response never offer cancellation',
    (tester) async {
      final api = ApiService(
        client: MockClient(
          (request) async => json({
            'error': {'codigo': 'no_autorizado', 'mensaje': 'No autorizado'},
          }, 401),
        ),
      )..establecerToken('invalid');
      await tester.pumpWidget(
        MaterialApp(home: SistemaReservasPage(apiService: api)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cancelar asientos'), findsNothing);
      expect(find.textContaining('No autorizado'), findsOneWidget);
    },
  );
}
