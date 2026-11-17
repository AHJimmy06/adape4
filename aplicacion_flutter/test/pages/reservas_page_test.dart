import 'dart:async';
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
      if (solicitud.url.path == '/api/vuelos') {
        return http.Response(
          jsonEncode([
            {
              'id': 'vuelo-1',
              'origen': 'Quito',
              'destino': 'Guayaquil',
              'fecha': '2026-11-20',
              'precio': 50,
              'asientos_disponibles': 10,
            },
          ]),
          200,
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

    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      const Color(0xFFF2F6FA),
    );
    expect(
      tester.widget<Card>(find.byType(Card)).shape,
      isA<RoundedRectangleBorder>().having(
        (shape) => shape.borderRadius,
        'borderRadius',
        BorderRadius.circular(20),
      ),
    );
    expect(find.textContaining('IVA (15%): \$7.50'), findsOneWidget);
    expect(find.text('Quito → Guayaquil'), findsOneWidget);
    await tester.tap(find.byTooltip('Ver comprobante XML'));
    await tester.pumpAndSettle();

    expect(find.text('Comprobante XML'), findsOneWidget);
    expect(find.textContaining('<total>57.50</total>'), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      '<?xml version="1.0"?>\n<comprobante>\n  <total>57.50</total>\n</comprobante>',
    );
    cliente.close();
  });

  testWidgets(
    'el catálogo fallido no oculta reservas ni bloquea cancelar o XML',
    (tester) async {
      var cancelada = false;
      final servicio = _servicio((solicitud) async {
        if (solicitud.url.path == '/api/vuelos') {
          return http.Response('{"mensaje":"No disponible"}', 503);
        }
        if (solicitud.method == 'DELETE') {
          expect(solicitud.url.path, '/api/reservas/reserva-2');
          cancelada = true;
          return http.Response('{}', 200);
        }
        if (solicitud.url.path.endsWith('comprobante.xml')) {
          return http.Response(
            '<r><total>57.50</total></r>',
            200,
            headers: {'content-type': 'application/xml'},
          );
        }
        return http.Response(
          jsonEncode([_reserva(estado: cancelada ? 'cancelada' : 'activa')]),
          200,
        );
      });
      await tester.pumpWidget(
        MaterialApp(home: ReservasPage(apiService: servicio)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Vuelo no disponible'), findsOneWidget);
      expect(find.textContaining('Vuelo #'), findsNothing);
      expect(
        find.textContaining('Reserva #reserva-2 · activa'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Ver comprobante XML'));
      await tester.pumpAndSettle();
      expect(find.textContaining('<total>57.50</total>'), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cancelar reserva'));
      await tester.pumpAndSettle();
      expect(find.text('¿Quieres cancelar esta reserva?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Cancelar reserva'));
      await tester.pumpAndSettle();
      expect(cancelada, isTrue);
      expect(
        find.textContaining('Reserva #reserva-2 · cancelada'),
        findsOneWidget,
      );
      expect(find.text('Reserva cancelada.'), findsOneWidget);
    },
  );

  testWidgets('prioriza el vuelo incluido sin solicitar catálogo', (
    tester,
  ) async {
    final servicio = _servicio((solicitud) async {
      expect(solicitud.url.path, '/api/reservas');
      return http.Response(
        jsonEncode([
          {..._reserva(), 'vuelo': _vuelo()},
        ]),
        200,
      );
    });
    await tester.pumpWidget(
      MaterialApp(home: ReservasPage(apiService: servicio)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Quito → Guayaquil'), findsOneWidget);
    expect(find.textContaining('Reserva #reserva-2'), findsOneWidget);
  });

  testWidgets('un catálogo pendiente no bloquea las reservas y su XML', (
    tester,
  ) async {
    final catalogo = Completer<http.Response>();
    final servicio = _servicio((solicitud) async {
      if (solicitud.url.path == '/api/vuelos') return catalogo.future;
      if (solicitud.url.path.endsWith('comprobante.xml')) {
        return http.Response(
          '<r><total>57.50</total></r>',
          200,
          headers: {'content-type': 'application/xml'},
        );
      }
      return http.Response(jsonEncode([_reserva()]), 200);
    });
    await tester.pumpWidget(
      MaterialApp(home: ReservasPage(apiService: servicio)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Vuelo no disponible'), findsOneWidget);
    await tester.tap(find.byTooltip('Ver comprobante XML'));
    await tester.pumpAndSettle();
    expect(find.textContaining('<total>57.50</total>'), findsOneWidget);
    catalogo.complete(http.Response('[]', 200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('Vuelo no disponible'), findsOneWidget);
  });

  for (final size in [
    const Size(320, 640),
    const Size(320, 900),
    const Size(1440, 900),
  ]) {
    testWidgets('XML largo tiene desplazamiento sin desbordarse en $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final xml =
          '<comprobante>${List.generate(60, (i) => '<detalle>Valor $i &amp; texto</detalle>').join()}</comprobante>';
      final servicio = _servicio((solicitud) async {
        if (solicitud.url.path.endsWith('comprobante.xml')) {
          return http.Response(
            xml,
            200,
            headers: {'content-type': 'application/xml'},
          );
        }
        return http.Response(
          jsonEncode([
            {..._reserva(), 'vuelo': _vuelo()},
          ]),
          200,
        );
      });
      await tester.pumpWidget(
        MaterialApp(home: ReservasPage(apiService: servicio)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ver comprobante XML'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final dialogo = find.byType(AlertDialog);
      final superficie = find
          .descendant(of: dialogo, matching: find.byType(Material))
          .first;
      expect(tester.getSize(superficie).width, lessThanOrEqualTo(460));
      final contenido = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(contenido.style?.fontFamily, 'monospace');
      expect(
        contenido.data,
        contains('\n  <detalle>Valor 59 &amp; texto</detalle>\n'),
      );
      final desplazamiento = find
          .descendant(of: dialogo, matching: find.byType(SingleChildScrollView))
          .last;
      await tester.drag(desplazamiento, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(dialogo, findsNothing);
    });
  }
}

ApiService _servicio(Future<http.Response> Function(http.Request) manejar) =>
    ApiService(
      baseUrl: Uri.parse('http://localhost:5000'),
      client: MockClient(manejar),
    )..establecerToken('jwt-activo');

Map<String, dynamic> _reserva({String estado = 'activa'}) => {
  'id': 'reserva-2',
  'vuelo_id': 'vuelo-1',
  'cantidad': 1,
  'subtotal': 50.0,
  'iva': 7.5,
  'porcentaje_iva': 15.0,
  'total': 57.5,
  'estado': estado,
  'creado_en': '2026-11-09T10:00:00Z',
};

Map<String, dynamic> _vuelo() => {
  'id': 'vuelo-1',
  'origen': 'Quito',
  'destino': 'Guayaquil',
  'fecha': '2026-11-20',
  'precio': 50,
  'asientos_disponibles': 10,
};
