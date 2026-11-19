import 'package:aplicacion_flutter/widgets/sistema_admin/resumen_ruta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const catalogo = [
    {
      'id': 'uio',
      'iata': 'UIO',
      'nombre': 'Aeropuerto Internacional Mariscal Sucre',
      'ciudad': 'Quito',
      'pais': 'Ecuador',
    },
    {
      'id': 'gye',
      'iata': 'GYE',
      'nombre': 'Aeropuerto Internacional José Joaquín de Olmedo',
      'ciudad': 'Guayaquil',
      'pais': 'Ecuador',
    },
  ];

  testWidgets('muestra nombres completos y ubicaciones en pantalla angosta', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: ResumenRuta(
                  ruta: {'origen': catalogo.first, 'destino': catalogo.last},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Aeropuerto de origen'), findsOneWidget);
    expect(find.text('Aeropuerto de destino'), findsOneWidget);
    expect(
      find.text('Aeropuerto Internacional Mariscal Sucre'),
      findsOneWidget,
    );
    expect(
      find.text('Aeropuerto Internacional José Joaquín de Olmedo'),
      findsOneWidget,
    );
    expect(find.text('UIO'), findsOneWidget);
    expect(find.text('GYE'), findsOneWidget);
    expect(find.text('Quito, Ecuador'), findsOneWidget);
    expect(find.text('Guayaquil, Ecuador'), findsOneWidget);
    expect(
      t.getTopLeft(find.text('Aeropuerto de destino')).dy,
      greaterThan(t.getTopLeft(find.text('Aeropuerto de origen')).dy),
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('resuelve catálogo por ID o IATA y respeta nombres expandidos', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResumenRuta(
            ruta: const {
              'origen_id': 'uio',
              'origen': {'nombre': '', 'ciudad': null},
              'destino': {'iata': 'GYE', 'nombre': 'Nombre actualizado'},
            },
            aeropuertos: catalogo,
          ),
        ),
      ),
    );
    expect(
      find.text('Aeropuerto Internacional Mariscal Sucre'),
      findsOneWidget,
    );
    expect(find.text('Nombre actualizado'), findsOneWidget);
    expect(find.text('Quito, Ecuador'), findsOneWidget);
    expect(find.text('Guayaquil, Ecuador'), findsOneWidget);
    expect(
      ResumenRuta.titulo(const {
        'origen_id': 'uio',
        'destino_id': 'gye',
      }, catalogo),
      'UIO → GYE',
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('datos ausentes nunca imprimen null ni inventan aeropuertos', (
    t,
  ) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ResumenRuta(ruta: {})),
      ),
    );
    expect(find.text('Aeropuerto no disponible'), findsNWidgets(2));
    expect(find.textContaining('null'), findsNothing);
    expect(ResumenRuta.titulo({}, catalogo), 'Origen → Destino');
    expect(
      ResumenRuta.aeropuerto({'origen_id': 'no-existe'}, 'origen', catalogo),
      isEmpty,
    );
    expect(t.takeException(), isNull);
  });
}
