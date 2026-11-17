import 'package:aplicacion_flutter/widgets/globo_vuelos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renderiza el globo de vuelos con semántica accesible', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 320, height: 320, child: GloboVuelos()),
          ),
        ),
      ),
    );

    expect(
      find.bySemanticsLabel('Globo 3D de AeroTech con aviones en rutas'),
      findsOneWidget,
    );
    expect(find.byType(GloboVuelos), findsOneWidget);
    expect(find.byType(Flutter3DViewer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
