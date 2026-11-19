import 'package:aplicacion_flutter/widgets/sistema_admin/selector_ubicacion_aeropuerto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const quito = LatLng(-0.129167, -78.3575);
const guayaquil = LatLng(-2.1574, -79.8836);

void main() {
  Future<void> abrir(
    WidgetTester t, {
    LatLng? inicial,
    ValueChanged<LatLng?>? resultado,
    ValueChanged<LatLng>? centro,
  }) async {
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final elegido = await showDialog<LatLng>(
                  context: context,
                  builder: (_) => SelectorUbicacionAeropuerto(
                    inicial: inicial,
                    mapaBuilder: (_, punto, seleccionar) {
                      centro?.call(punto);
                      return Center(
                        child: TextButton(
                          onPressed: () => seleccionar(guayaquil),
                          child: const Text('Punto Guayaquil'),
                        ),
                      );
                    },
                  ),
                );
                resultado?.call(elegido);
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Abrir'));
    await t.pumpAndSettle();
  }

  testWidgets('sin coordenadas exige elegir punto antes de confirmar', (
    t,
  ) async {
    LatLng? elegido;
    await abrir(t, resultado: (p) => elegido = p);
    final confirmar = find.byKey(const ValueKey('confirmar_ubicacion_mapa'));
    expect(t.widget<FilledButton>(confirmar).onPressed, isNull);
    await t.tap(find.text('Punto Guayaquil'));
    await t.pump();
    expect(t.widget<FilledButton>(confirmar).onPressed, isNotNull);
    expect(find.textContaining('Latitud: -2.157400'), findsOneWidget);
    await t.tap(confirmar);
    await t.pumpAndSettle();
    expect(elegido, guayaquil);
  });

  testWidgets(
    'edición centra el mapa y permite conservar ubicación existente',
    (t) async {
      LatLng? centro, elegido;
      await abrir(
        t,
        inicial: quito,
        centro: (p) => centro = p,
        resultado: (p) => elegido = p,
      );
      expect(centro, quito);
      await t.tap(find.text('Usar ubicación'));
      await t.pumpAndSettle();
      expect(elegido, quito);
    },
  );

  testWidgets('cancelar descarta la selección provisional', (t) async {
    LatLng? elegido = quito;
    await abrir(t, inicial: quito, resultado: (p) => elegido = p);
    await t.tap(find.text('Punto Guayaquil'));
    await t.pump();
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(elegido, isNull);
  });

  testWidgets('modal se adapta a 320 píxeles de ancho', (t) async {
    t.view.physicalSize = const Size(320, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await abrir(t, inicial: quito);
    expect(find.text('Usar ubicación'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  test('rechaza coordenadas fuera de rango o no finitas', () {
    expect(SelectorUbicacionAeropuerto.coordenadasValidas(null), isFalse);
    expect(
      SelectorUbicacionAeropuerto.coordenadasValidas(const LatLng(91, 0)),
      isFalse,
    );
    expect(
      SelectorUbicacionAeropuerto.coordenadasValidas(const LatLng(0, -181)),
      isFalse,
    );
    expect(
      SelectorUbicacionAeropuerto.coordenadasValidas(
        const LatLng(double.nan, 0),
      ),
      isFalse,
    );
    expect(
      SelectorUbicacionAeropuerto.coordenadasValidas(
        const LatLng(0, double.infinity),
      ),
      isFalse,
    );
    expect(
      SelectorUbicacionAeropuerto.coordenadasValidas(const LatLng(90, 180)),
      isTrue,
    );
  });
}
