import 'package:aplicacion_flutter/models/ruta_vuelo.dart';
import 'package:aplicacion_flutter/widgets/ruta_internacional_3d.dart';
import 'package:flutter/material.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settleSource(WidgetTester tester, bool Function() loaded) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    if (loaded()) return;
    if (!DateTime.now().isBefore(deadline)) break;
  }
  fail('El visor 3D no se creó dentro del límite de 10 segundos.');
}

Widget route(String destination, ValueChanged<Flutter3DViewer> capture) =>
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: RutaInternacional3D(
            ruta: RutaVuelo('Quito, Ecuador', destination),
            envolverVisor: (viewer) {
              capture(viewer);
              return const SizedBox(key: ValueKey('captured-viewer'));
            },
          ),
        ),
      ),
    );
void main() {
  testWidgets(
    'callbacks retained from known route cannot crash unknown replacement',
    (tester) async {
      Flutter3DViewer? first;
      await tester.pumpWidget(route('Miami, USA', (v) => first = v));
      await settleSource(tester, () => first != null);
      expect(first, isNotNull);
      final load = first!.onLoad!, error = first!.onError!;
      await tester.pumpWidget(
        route('City, Atlantis', (_) {
          fail('Unknown route created a viewer');
        }),
      );
      expect(() => load('late load'), returnsNormally);
      expect(() => error('late error'), returnsNormally);
      await tester.pump();
      expect(
        find.textContaining('No se muestra una ruta inventada'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'stale error cannot poison known replacement or call old controller',
    (tester) async {
      Flutter3DViewer? first, second;
      await tester.pumpWidget(route('Miami, USA', (v) => first = v));
      await settleSource(tester, () => first != null);
      expect(first, isNotNull);
      final load = first!.onLoad!, error = first!.onError!;
      await tester.pumpWidget(route('Madrid, España', (v) => second = v));
      await settleSource(tester, () => second != null);
      expect(second, isNotNull);
      expect(second!.src, isNot(first!.src));
      // Test viewers never initialize their controllers; any stale controller call
      // throws, so returnsNormally also proves that no controller is called.
      expect(() => load('late load'), returnsNormally);
      expect(() => error('late error'), returnsNormally);
      await tester.pump();
      expect(find.byKey(const ValueKey('captured-viewer')), findsOneWidget);
      expect(find.textContaining('No se pudo cargar'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(() => load('after dispose'), returnsNormally);
      expect(() => error('after dispose'), returnsNormally);
      expect(() => second!.onLoad!('after dispose'), returnsNormally);
      expect(() => second!.onError!('after dispose'), returnsNormally);
      expect(tester.takeException(), isNull);
    },
  );
}
