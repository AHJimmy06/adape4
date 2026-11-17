import 'package:aplicacion_flutter/widgets/tarjeta_destino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tarjeta móvil con texto grande y vuelo agotado', (t) async {
    await t.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(1.3)),
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: TarjetaDestino(
              vuelo: {
                'codigo': 'AT101',
                'ruta': {
                  'origen': {'ciudad': 'Quito', 'iata': 'UIO'},
                  'destino': {'ciudad': 'Guayaquil', 'iata': 'GYE'},
                },
                'asientos_disponibles': 0,
              },
            ),
          ),
        ),
      ),
    );
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(t.takeException(), isNull);
  });
  testWidgets('muestra destino, precio con IVA y disponibilidad real', (
    t,
  ) async {
    var abierto = false;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: TarjetaDestino(
                vuelo: const {
                  'codigo': 'AT101',
                  'ruta': {
                    'origen': {'ciudad': 'Quito', 'iata': 'UIO'},
                    'destino': {'ciudad': 'Guayaquil', 'iata': 'GYE'},
                  },
                  'salida_local': '2027-01-20T09:00',
                  'llegada_local': '2027-01-20T10:00',
                  'precio_desde_centavos': 1000,
                  'asientos_disponibles': 4,
                  'tarifas': [],
                },
                onReservar: () => abierto = true,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Guayaquil (GYE)'), findsOneWidget);
    expect(find.text('USD 11.50'), findsOneWidget);
    expect(find.textContaining('4 disponibles'), findsOneWidget);
    expect(find.textContaining('IVA incluido'), findsOneWidget);
    await t.ensureVisible(find.text('Reservar'));
    await t.tap(find.text('Reservar'));
    expect(abierto, isTrue);
    expect(t.takeException(), isNull);
  });
}
