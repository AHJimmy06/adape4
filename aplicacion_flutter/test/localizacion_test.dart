import 'package:aplicacion_flutter/main.dart';
import 'package:aplicacion_flutter/pages/landing_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('calendarios y controles del sistema se muestran en español', (
    t,
  ) async {
    await t.pumpWidget(
      ReservasVuelosApp(globoBuilder: (_) => const SizedBox()),
    );
    await t.pumpAndSettle();
    final context = t.element(find.byType(LandingPage));
    expect(Localizations.localeOf(context).languageCode, 'es');
    expect(
      MaterialLocalizations.of(context).formatMonthYear(DateTime(2026, 11)),
      contains('noviembre'),
    );
    expect(
      MaterialLocalizations.of(context).cancelButtonLabel.toLowerCase(),
      'cancelar',
    );
  });
}
