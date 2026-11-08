import 'dart:convert';

import 'package:aplicacion_flutter/pages/reservas_page.dart';
import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('muestra el IVA y permite consultar el comprobante XML', (
    tester,
  ) async {
    const xml =
        '<?xml version="1.0"?><comprobante><total>57.50</total></comprobante>';
    final cliente = MockClient((solicitud) async {
      if (solicitud.url.path == '/api/reservas') {
        return http.Response(
          jsonEncode([
            {
              'id': 'reserva-2',
              'vuelo_id': 'vuelo-1',
              'cantidad': 1,
              'subtotal': 50.0,
              'iva': 7.5,
              'porcentaje_iva': 15.0,
              'total': 57.5,
              'estado': 'activa',
              'creado_en': '2026-11-09T10:00:00Z',
            },
          ]),
          200,
        );
      }
      if (solicitud.url.path == '/api/reservas/reserva-2/comprobante.xml') {
        expect(solicitud.headers['authorization'], 'Bearer jwt-activo');
        return http.Response.bytes(
          utf8.encode(xml),
          200,
          headers: {'content-type': 'application/xml; charset=utf-8'},
        );
      }
      fail('Ruta inesperada: ${solicitud.url}');
    });
    final servicio = ApiService(
      baseUrl: Uri.parse('http://localhost:5000'),
      client: cliente,
    )..establecerToken('jwt-activo');

    await tester.pumpWidget(
      MaterialApp(home: ReservasPage(apiService: servicio)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('IVA (15%): \$7.50'), findsOneWidget);
    await tester.tap(find.byTooltip('Ver comprobante XML'));
    await tester.pumpAndSettle();

    expect(find.text('Comprobante XML'), findsOneWidget);
    expect(find.textContaining('<total>57.50</total>'), findsOneWidget);
    cliente.close();
  });
}
