import 'package:aplicacion_flutter/main.dart';
import 'package:aplicacion_flutter/pages/landing_page.dart';
import 'package:aplicacion_flutter/pages/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AeroTech abre la landing antes del login', (tester) async {
    await tester.pumpWidget(
      ReservasVuelosApp(
        globoBuilder: (_) => const SizedBox.square(dimension: 300),
      ),
    );
    expect(find.byType(LandingPage), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    expect(find.text('AeroTech'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
