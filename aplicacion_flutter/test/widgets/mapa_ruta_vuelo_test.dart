import 'package:aplicacion_flutter/widgets/mapa_ruta_vuelo.dart';
import 'package:aplicacion_flutter/widgets/ruta_internacional_3d.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> showMap(
  WidgetTester tester,
  String origin,
  String destination, {
  ConstructorVisorRuta? viewer,
}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: MapaRutaVuelo(
            origen: origin,
            destino: destination,
            constructorVisor: viewer,
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 250)),
  );
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('domestic known legacy route uses geographic 2D and settles', (
    tester,
  ) async {
    await showMap(tester, 'Cuenca', 'Quito');
    expect(find.text('Cuenca'), findsOneWidget);
    expect(find.text('Quito'), findsOneWidget);
    expect(find.byKey(const ValueKey('mapa-nacional-2d')), findsOneWidget);
    expect(
      find.bySemanticsLabel('Mapa de la ruta Cuenca a Quito'),
      findsOneWidget,
    );
    expect(find.byType(RutaInternacional3D), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('exact trimmed matching countries use domestic map', (
    tester,
  ) async {
    await showMap(tester, 'Quito, Ecuador ', 'Cuenca, Ecuador');
    expect(find.byKey(const ValueKey('mapa-nacional-2d')), findsOneWidget);
    expect(find.textContaining('RUTA NACIONAL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'international uses derived login model and only country labels',
    (tester) async {
      String? source;
      bool? reduced;
      await showMap(
        tester,
        'Quito, Ecuador',
        'Miami, USA',
        viewer: (context, src, motion) {
          source = src;
          reduced = motion;
          return const SizedBox(key: ValueKey('test-real-glb'));
        },
      );
      expect(find.byType(RutaInternacional3D), findsOneWidget);
      expect(find.text('Ecuador'), findsOneWidget);
      expect(find.text('USA'), findsOneWidget);
      expect(find.textContaining('Quito'), findsNothing);
      expect(find.textContaining('Miami'), findsNothing);
      expect(source, isNotNull);
      expect(source, startsWith('file:'));
      expect(reduced, isTrue);
      expect(find.byKey(const ValueKey('test-real-glb')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('unknown country route never renders unrelated 3D flight', (
    tester,
  ) async {
    await showMap(tester, 'Quito, Ecuador', 'City, Atlantis');
    expect(find.text('Atlantis'), findsOneWidget);
    expect(
      find.textContaining('No se muestra una ruta inventada'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('unknown legacy route keeps labels and honest notice', (
    tester,
  ) async {
    await showMap(tester, 'Ciudad desconocida', 'Quito');
    expect(find.text('Ciudad desconocida'), findsOneWidget);
    expect(find.textContaining('geográfica no disponible'), findsOneWidget);
    expect(find.byType(RutaInternacional3D), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('unknown domestic cities use explicitly labeled schematic', (
    tester,
  ) async {
    await showMap(tester, 'First, Ecuador', 'Second, Ecuador');
    expect(find.textContaining('Esquema punto a punto'), findsOneWidget);
    expect(find.byKey(const ValueKey('mapa-nacional-2d')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
