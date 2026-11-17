import 'package:aplicacion_flutter/widgets/cabina_asientos.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> doubleSeat(WidgetTester tester, String seat) async {
  await tester.tap(find.byKey(ValueKey('seat-$seat')));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.byKey(ValueKey('seat-$seat')));
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets(
    'single click does not select; double clicks independently toggle within limit',
    (tester) async {
      final selected = <String>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => CabinaAsientos(
                selectedSeats: selected,
                maxSeleccion: 2,
                onToggle: (seat) => setState(() {
                  if (!selected.remove(seat)) selected.add(seat);
                }),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('seat-1A')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(selected, isEmpty);
      await doubleSeat(tester, '1A');
      await doubleSeat(tester, '1B');
      expect(selected, {'1A', '1B'});
      expect(find.byKey(const ValueKey('seat-1C')), findsNothing);
      expect(selected, {'1A', '1B'});
      await doubleSeat(tester, '1A');
      expect(selected, {'1B'});
      await doubleSeat(tester, '1A');
      expect(selected, {'1A', '1B'});
    },
  );
  testWidgets('zero limit and disabled cabin reject gestures', (tester) async {
    var calls = 0;
    for (final enabled in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CabinaAsientos(
              selectedSeats: const {},
              maxSeleccion: enabled ? 0 : 2,
              enabled: enabled,
              onToggle: (_) => calls++,
            ),
          ),
        ),
      );
      if (enabled) {
        expect(find.byKey(const ValueKey('seat-1A')), findsNothing);
      } else {
        await doubleSeat(tester, '1A');
      }
    }
    expect(calls, 0);
  });
  testWidgets('all 30 seats are selectable with no phantom final-row seats', (
    tester,
  ) async {
    final selected = <String>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CabinaAsientos(
              selectedSeats: selected,
              maxSeleccion: 30,
              onToggle: (seat) => setState(() {
                if (!selected.remove(seat)) selected.add(seat);
              }),
            ),
          ),
        ),
      ),
    );
    for (var index = 0; index < 30; index++) {
      final label = '${index ~/ 4 + 1}${'ABCD'[index % 4]}';
      final seat = find.byKey(ValueKey('seat-$label'));
      await tester.scrollUntilVisible(
        seat,
        48,
        scrollable: find.byType(Scrollable),
      );
      await doubleSeat(tester, label);
    }
    expect(selected.length, 30);
    expect(find.byKey(const ValueKey('seat-8B')), findsOneWidget);
    expect(find.byKey(const ValueKey('seat-8C')), findsNothing);
    expect(find.byKey(const ValueKey('seat-8D')), findsNothing);
    await doubleSeat(tester, '8B');
    expect(selected.length, 29);
    expect(selected.contains('8B'), isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('large inventories build only a bounded viewport', (
    tester,
  ) async {
    for (final available in [-1, 1000, 2147483647]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CabinaAsientos(
              selectedSeats: const {},
              maxSeleccion: available,
              onToggle: (_) {},
            ),
          ),
        ),
      );
      expect(find.byType(InkWell).evaluate().length, lessThan(50));
      if (available < 0) expect(find.byType(InkWell), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('keyboard activates focused seat', (tester) async {
    final selected = <String>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CabinaAsientos(
            selectedSeats: selected,
            maxSeleccion: 2,
            onToggle: selected.add,
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, {'1A'});
  });
}
