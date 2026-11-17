import 'dart:async';

import 'package:aplicacion_flutter/models/vuelo.dart';
import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:aplicacion_flutter/widgets/reserva_visual_dialog.dart';
import 'package:aplicacion_flutter/widgets/cabina_asientos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Vuelo flightWithAvailability(int available) => Vuelo(
  id: flight.id,
  origen: flight.origen,
  destino: flight.destino,
  fecha: flight.fecha,
  horaSalida: flight.horaSalida,
  horaLlegada: flight.horaLlegada,
  precio: flight.precio,
  asientosDisponibles: available,
);

const flight = Vuelo(
  id: 'v1',
  origen: 'Quito',
  destino: 'Guayaquil',
  fecha: '2026-11-20',
  horaSalida: '08:00',
  horaLlegada: '09:00',
  precio: 75,
  asientosDisponibles: 8,
);

Future<void> openDialog(
  WidgetTester tester,
  Future<String> Function(int) confirm, {
  Vuelo selectedFlight = flight,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (_) => MediaQuery(
                  data: const MediaQueryData(disableAnimations: true),
                  child: ReservaVisualDialog(
                    vuelo: selectedFlight,
                    onConfirm: confirm,
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> seats(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Continuar a la cabina'));
  await tester.tap(find.text('Continuar a la cabina'));
  await tester.pumpAndSettle();
}

Future<void> doubleSeat(WidgetTester tester, String label) async {
  final seat = find.byKey(ValueKey('seat-$label'));
  final scrollable = find.descendant(
    of: find.byType(CabinaAsientos),
    matching: find.byType(Scrollable),
  );
  if (scrollable.evaluate().isNotEmpty) {
    await tester.ensureVisible(find.byType(CabinaAsientos));
    await tester.scrollUntilVisible(seat, 48, scrollable: scrollable);
  }
  await Scrollable.ensureVisible(tester.element(seat), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(seat);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(seat);
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  for (final available in [0, 2, 30]) {
    testWidgets('selection honors actual availability $available', (
      tester,
    ) async {
      var calls = 0;
      await openDialog(
        tester,
        (_) async {
          calls++;
          return 'Listo';
        },
        selectedFlight: Vuelo(
          id: flight.id,
          origen: flight.origen,
          destino: flight.destino,
          fecha: flight.fecha,
          horaSalida: flight.horaSalida,
          horaLlegada: flight.horaLlegada,
          precio: flight.precio,
          asientosDisponibles: available,
        ),
      );
      await seats(tester);
      final confirm = find.byKey(const ValueKey('confirm-booking'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      final expected = available;
      for (var index = 0; index < available; index++) {
        await doubleSeat(tester, '${index ~/ 4 + 1}${'ABCD'[index % 4]}');
      }
      final cabin = tester.widget<CabinaAsientos>(find.byType(CabinaAsientos));
      expect(cabin.selectedSeats.length, expected);
      expect(cabin.maxSeleccion, expected);
      expect(calls, 0);
      expect(
        tester.widget<FilledButton>(confirm).onPressed == null,
        expected == 0,
      );
      await tester.ensureVisible(find.text('Cancelar'));
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(calls, 0);
    });
  }

  testWidgets('preview identifies route and cancellation never books', (
    tester,
  ) async {
    var calls = 0;
    await openDialog(tester, (_) async {
      calls++;
      return 'Listo';
    });
    expect(find.text('Quito → Guayaquil'), findsOneWidget);
    expect(find.text('Tu próxima aventura'), findsOneWidget);
    expect(calls, 0);
    await tester.ensureVisible(find.text('Cancelar'));
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byType(ReservaVisualDialog), findsNothing);
  });

  testWidgets(
    'seat preference, explicit confirmation and duplicate protection',
    (tester) async {
      var calls = 0;
      final response = Completer<String>();
      var quantitySent = 0;
      await openDialog(tester, (quantity) {
        calls++;
        quantitySent = quantity;
        return response.future;
      });
      await seats(tester);
      expect(calls, 0);
      expect(find.textContaining('no se guarda ni garantiza'), findsNothing);
      expect(
        find.textContaining('Doble clic para marcar o desmarcar.'),
        findsNothing,
      );
      await doubleSeat(tester, '2A');
      await doubleSeat(tester, '2B');
      await tester.pump();
      expect(find.text('Asientos seleccionados (2): 2A, 2B'), findsOneWidget);
      expect(find.text('Subtotal: USD 150.00'), findsOneWidget);
      await tester.ensureVisible(find.text('Confirmar reserva'));
      await tester.tap(find.text('Confirmar reserva'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-booking')));
      await tester.pump();
      expect(
        tester.widget<CabinaAsientos>(find.byType(CabinaAsientos)).enabled,
        isFalse,
      );
      expect(calls, 1);
      expect(quantitySent, 2);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('confirm-booking')))
            .onPressed,
        isNull,
      );
      response.complete('Reserva confirmada.');
      await tester.pumpAndSettle();
      expect(find.byType(ReservaVisualDialog), findsNothing);
    },
  );

  testWidgets('failure preserves preference and allows deliberate retry', (
    tester,
  ) async {
    var calls = 0;
    await openDialog(tester, (quantity) async {
      expect(quantity, 10);
      calls++;
      if (calls == 1) throw Exception('Offline');
      return 'Listo';
    }, selectedFlight: flightWithAvailability(30));
    await seats(tester);
    for (var index = 0; index < 10; index++) {
      await doubleSeat(tester, '${index ~/ 4 + 1}${'ABCD'[index % 4]}');
    }
    await tester.pump();
    await tester.ensureVisible(find.text('Confirmar reserva'));
    await tester.tap(find.text('Confirmar reserva'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudo confirmar'), findsOneWidget);
    expect(
      tester
          .widget<CabinaAsientos>(find.byType(CabinaAsientos))
          .selectedSeats
          .length,
      10,
    );
    await tester.tap(find.text('Confirmar reserva'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets(
    'otro conflicto HTTP 409 conserva seleccion y permite reintentar',
    (tester) async {
      var intentos = 0;
      await openDialog(tester, (cantidad) async {
        expect(cantidad, 1);
        intentos++;
        if (intentos == 1) {
          throw const ExcepcionApi(
            'Otro conflicto de la reserva.',
            codigo: 409,
          );
        }
        return 'Reserva confirmada.';
      });
      await seats(tester);
      await doubleSeat(tester, '1A');
      await tester.ensureVisible(find.text('Confirmar reserva'));
      await tester.tap(find.text('Confirmar reserva'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Otro conflicto de la reserva.'), findsOneWidget);
      expect(
        tester
            .widget<CabinaAsientos>(find.byType(CabinaAsientos))
            .selectedSeats,
        {'1A'},
      );
      await tester.tap(find.text('Confirmar reserva'));
      await tester.pumpAndSettle();
      expect(intentos, 2);
      expect(find.byType(ReservaVisualDialog), findsNothing);
    },
  );

  testWidgets('mobile preview and cabin remain scrollable without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openDialog(
      tester,
      (_) async => 'Listo',
      selectedFlight: flightWithAvailability(30),
    );
    expect(tester.takeException(), isNull);
    await seats(tester);
    await doubleSeat(tester, '8B');
    expect(
      tester.widget<CabinaAsientos>(find.byType(CabinaAsientos)).selectedSeats,
      {'8B'},
    );
    expect(find.byKey(const ValueKey('seat-8C')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Cancelar'));
    await tester.ensureVisible(find.text('Cancelar'));
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
  });
}
