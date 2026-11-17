import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aplicacion_flutter/widgets/presentacion/dialogo_aerotech.dart';
import 'package:aplicacion_flutter/widgets/sistema_admin/formulario_operacion.dart';
import 'package:aplicacion_flutter/pages/sistema_reservas_page.dart';
import 'package:aplicacion_flutter/theme/aerotech_theme.dart';
import 'package:aplicacion_flutter/services/sistema_api.dart';
import 'package:aplicacion_flutter/services/api_service.dart';

import '../../pages/sistema_reservas_page_test.dart' show reserva;

void main() {
  test('fechas con zona explícita sin depender del dispositivo', () {
    expect(
      fechaLegible('2099-12-20T14:30:00Z', horaEcuador: true),
      '20 dic 2099 · 09:30 Ecuador (UTC−5)',
    );
    expect(
      fechaLegible('2099-12-20T09:30:00-05:00', horaEcuador: true),
      '20 dic 2099 · 09:30 Ecuador (UTC−5)',
    );
    expect(
      fechaLegible('2099-12-20T02:30:00Z', horaEcuador: true),
      '19 dic 2099 · 21:30 Ecuador (UTC−5)',
    );
    expect(
      fechaLegible('2099-12-20T09:30', zona: 'America/Guayaquil'),
      '20 dic 2099 · 09:30 America/Guayaquil',
    );
    expect(
      fechaLegible('2099-12-20T09:30', horaEcuador: true),
      contains('zona no especificada'),
    );
    expect(fechaLegible('sin fecha'), 'Fecha por confirmar');
    expect(fechaLegible(null), 'Fecha por confirmar');
    expect(estadoLegible('desconocido'), 'Estado por verificar');
  });

  testWidgets(
    'formulario móvil conserva desplazamiento con teclado y texto grande',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        MaterialApp(
          theme: AerotechTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: FormularioOperacion(
              recurso: 'aeropuertos',
              catalogos: const {},
              guardar: (_) async {},
            ),
          ),
        ),
      );
      expect(find.text('DATOS DEL REGISTRO'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('zona_horaria')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Guardar'), findsOneWidget);
    },
  );

  testWidgets(
    'cancelación móvil mantiene controles y acciones sin desbordamiento',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AerotechTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: CancelacionSistemaDialog(
              api: SistemaApi(ApiService()),
              reserva: reserva(),
            ),
          ),
        ),
      );
      await tester.ensureVisible(
        find.widgetWithText(CheckboxListTile, '1A · ECO'),
      );
      await tester.tap(find.widgetWithText(CheckboxListTile, '1A · ECO'));
      await tester.pumpAndSettle();
      expect(find.text('Reembolso estimado: USD 11.50'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
