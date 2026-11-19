import 'dart:async';

import 'package:aplicacion_flutter/widgets/sistema_admin/formulario_operacion.dart';
import 'package:aplicacion_flutter/widgets/sistema_admin/disponibilidad_avion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final datos = <String, dynamic>{
    'fecha': '2030-01-10',
    'zona_origen': 'America/Guayaquil',
    'zona_destino': 'America/New_York',
    'disponible': true,
    'ocupados': [
      {
        'codigo': 'AT101',
        'inicio_local': '2030-01-10T10:00',
        'fin_local': '2030-01-10T12:00',
      },
    ],
    'ventanas': [
      {
        'inicio_en': '2030-01-10T17:00:00Z',
        'fin_en': '2030-01-11T05:00:00Z',
        'inicio_local': '2030-01-10T12:00',
        'fin_local': '2030-01-11T00:00',
        'inicio_destino_local': '2030-01-10T12:00',
        'fin_destino_local': '2030-01-11T00:00',
      },
    ],
  };
  testWidgets('muestra ocupados y permite elegir un rango libre', (
    tester,
  ) async {
    DateTime? salida, llegada;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DisponibilidadAvion(
            datos: datos,
            cargando: false,
            onActualizar: () {},
            onSeleccionar: (s, l) {
              salida = s;
              llegada = l;
            },
          ),
        ),
      ),
    );
    expect(find.textContaining('AT101'), findsOneWidget);
    await tester.tap(find.text('Elegir intervalo'));
    await tester.pumpAndSettle();
    expect(find.byType(RangeSlider), findsOneWidget);
    await tester.tap(find.text('Aplicar horario'));
    await tester.pumpAndSettle();
    expect(salida, DateTime(2030, 1, 10, 12));
    expect(llegada, DateTime(2030, 1, 10, 13));
  });
  testWidgets('muestra conflicto y conserva el refresco', (tester) async {
    var consultas = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DisponibilidadAvion(
            datos: {
              ...datos,
              'disponible': false,
              'conflictos': [
                {
                  'fecha': '2030-01-11',
                  'codigo': 'AT102',
                  'inicio_local': '2030-01-11T10:00',
                  'fin_local': '2030-01-11T12:00',
                },
              ],
            },
            cargando: false,
            onActualizar: () {
              consultas++;
            },
            onSeleccionar: (_, _) {},
          ),
        ),
      ),
    );
    expect(find.textContaining('El avión ya tiene otro vuelo'), findsOneWidget);
    expect(find.textContaining('AT102'), findsOneWidget);
    await tester.tap(find.byTooltip('Actualizar horarios del avión'));
    expect(consultas, 1);
  });
  testWidgets('selección nocturna conserva día de salida y zona de destino', (
    tester,
  ) async {
    DateTime? salida, llegada;
    final ventana = {
      'inicio_en': '2030-01-11T04:00:00Z',
      'fin_en': '2030-01-12T05:00:00Z',
      'inicio_local': '2030-01-10T23:00',
      'fin_local': '2030-01-12T00:00',
      'inicio_destino_local': '2030-01-11T05:00',
      'fin_destino_local': '2030-01-12T06:00',
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DisponibilidadAvion(
            datos: {
              ...datos,
              'ventanas': [ventana],
            },
            cargando: false,
            onActualizar: () {},
            onSeleccionar: (s, l) {
              salida = s;
              llegada = l;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Elegir intervalo'));
    await tester.pumpAndSettle();
    tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged!(
      const RangeValues(120, 180),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar horario'));
    await tester.pumpAndSettle();
    expect(salida, DateTime(2030, 1, 10, 23, 59));
    expect(llegada, DateTime(2030, 1, 11, 8));
  });

  testWidgets(
    'cambio de avión descarta respuesta anterior y bloquea guardar ocupado',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final primera = Completer<Registro>();
      final segunda = Completer<Registro>();
      final peticiones = <Registro>[];
      var guardados = 0;
      final dia = DateTime.now()
          .add(const Duration(days: 4))
          .toIso8601String()
          .substring(0, 10);
      const clase = {
        'codigo': 'ECO',
        'nombre': 'Económica',
        'fila_inicio': 1,
        'filas': 1,
        'columnas': [
          ['A', 'B'],
        ],
      };
      const ruta = {
        'id': 'r1',
        'origen': {'zona_horaria': 'America/Guayaquil'},
        'destino': {'zona_horaria': 'America/Guayaquil'},
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FormularioOperacion(
              recurso: 'vuelos',
              registro: {
                'id': 'f1',
                'version': 1,
                'codigo': 'AT101',
                'ruta_id': 'r1',
                'avion_id': 'p1',
                'salida_local': '${dia}T09:00',
                'llegada_local': '${dia}T10:00',
                'tarifas': [
                  {'clase_codigo': 'ECO', 'precio_centavos': 10000},
                ],
              },
              catalogos: {
                'rutas': [ruta],
                'aviones': [
                  {
                    'id': 'p1',
                    'matricula': 'HC-1',
                    'modelo': 'A320',
                    'clases': [clase],
                  },
                  {
                    'id': 'p2',
                    'matricula': 'HC-2',
                    'modelo': 'A320',
                    'clases': [clase],
                  },
                ],
              },
              guardar: (_) async {
                guardados++;
              },
              consultarDisponibilidadAvion: (p) {
                peticiones.add(p);
                return peticiones.length == 1 ? primera.future : segunda.future;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('avion-p1')),
          )
          .onChanged!('p2');
      await tester.pump();
      segunda.complete({...datos, 'disponible': false, 'fecha': dia});
      await tester.pumpAndSettle();
      primera.complete({...datos, 'disponible': true, 'fecha': dia});
      await tester.pumpAndSettle();
      expect(peticiones.map((p) => p['avion_id']), ['p1', 'p2']);
      expect(
        find.textContaining('El avión ya tiene otro vuelo'),
        findsOneWidget,
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(guardados, 0);
    },
  );
}
