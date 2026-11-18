import 'dart:async';

import 'package:aplicacion_flutter/widgets/sistema_admin/formulario_operacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const clases = [
  {
    'codigo': 'EJEC',
    'nombre': 'Ejecutiva',
    'fila_inicio': 1,
    'filas': 2,
    'columnas': [
      ['A', 'C'],
      ['D', 'F'],
    ],
  },
  {
    'codigo': 'ECO',
    'nombre': 'Económica',
    'fila_inicio': 3,
    'filas': 4,
    'columnas': [
      ['A', 'B', 'C'],
      ['D', 'E', 'F'],
    ],
  },
];
const catalogos = <String, List<Registro>>{
  'aviones': [
    {'id': 'a1', 'matricula': 'HC-001', 'modelo': 'A320', 'clases': clases},
  ],
  'rutas': [
    {
      'id': 'r1',
      'origen': {
        'id': 'uio',
        'iata': 'UIO',
        'zona_horaria': 'America/Guayaquil',
      },
      'destino': {
        'id': 'gye',
        'iata': 'GYE',
        'zona_horaria': 'America/Guayaquil',
      },
    },
  ],
};
void main() {
  testWidgets('aeropuerto expone capacidad y franja con ingreso numérico', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormularioOperacion(
            recurso: 'aeropuertos',
            catalogos: const {},
            guardar: (_) async {},
          ),
        ),
      ),
    );
    final campo = find.byKey(const ValueKey('capacidad_aterrizajes'));
    expect(campo, findsOneWidget);
    await t.ensureVisible(campo);
    await t.enterText(campo, '12x');
    expect(t.widget<TextFormField>(campo).controller!.text, '12');
    expect(find.byKey(const ValueKey('franja_minutos')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('clases usan tabla con una sola cabecera y capacidad calculada', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormularioOperacion(
            recurso: 'aviones',
            registro: const {
              'id': 'a1',
              'matricula': 'HC-001',
              'modelo': 'A320',
              'clases': clases,
            },
            catalogos: catalogos,
            guardar: (_) async {},
          ),
        ),
      ),
    );
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Primera fila'), findsOneWidget);
    expect(t.widget<DataTable>(find.byType(DataTable)).rows.length, 2);
    expect(find.text('Capacidad total: 32 asientos'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'código automático y tarifas en tabla; disponibilidad no se inventa',
    (t) async {
      final respuesta = Completer<Registro>();
      Registro? consulta;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FormularioOperacion(
              recurso: 'vuelos',
              registro: const {
                'id': 'v1',
                'codigo': 'AT101',
                'ruta_id': 'r1',
                'avion_id': 'a1',
                'salida_local': '2099-12-20T09:00',
                'llegada_local': '2099-12-20T10:00',
              },
              catalogos: catalogos,
              guardar: (_) async {},
              consultarDisponibilidad: (p) {
                consulta = p;
                return respuesta.future;
              },
            ),
          ),
        ),
      );
      await t.pump();
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('AT101'), findsOneWidget);
      expect(find.byKey(const ValueKey('codigo')), findsNothing);
      expect(consulta?['aeropuerto_id'], 'gye');
      expect(consulta?['vuelo_id'], 'v1');
      respuesta.complete({
        'capacidad_aterrizajes': 10,
        'franja_minutos': 60,
        'programados': 3,
        'disponibles': 7,
        'inicio_local': '2099-12-20T10:00',
        'fin_local': '2099-12-20T11:00',
      });
      await t.pumpAndSettle();
      expect(find.textContaining('7 aterrizajes disponibles'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('la respuesta anterior no pisa los cupos de una ruta nueva', (
    t,
  ) async {
    final primera = Completer<Registro>(), segunda = Completer<Registro>();
    final rutas = [
      ...catalogos['rutas']!,
      {
        'id': 'r2',
        'origen': catalogos['rutas']!.first['origen'],
        'destino': {
          'id': 'cue',
          'iata': 'CUE',
          'zona_horaria': 'America/Guayaquil',
        },
      },
    ];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormularioOperacion(
            recurso: 'vuelos',
            registro: const {
              'id': 'v1',
              'codigo': 'AT101',
              'ruta_id': 'r1',
              'avion_id': 'a1',
              'salida_local': '2099-12-20T09:00',
              'llegada_local': '2099-12-20T10:00',
            },
            catalogos: {...catalogos, 'rutas': rutas},
            guardar: (_) async {},
            consultarDisponibilidad: (p) =>
                p['aeropuerto_id'] == 'gye' ? primera.future : segunda.future,
          ),
        ),
      ),
    );
    await t.pump();
    final selector = t.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('ruta-r1')),
    );
    selector.onChanged!('r2');
    await t.pump();
    segunda.complete({
      'capacidad_aterrizajes': 10,
      'franja_minutos': 60,
      'programados': 3,
      'disponibles': 7,
    });
    await t.pumpAndSettle();
    expect(find.textContaining('7 aterrizajes disponibles'), findsOneWidget);
    primera.complete({
      'capacidad_aterrizajes': 10,
      'franja_minutos': 60,
      'programados': 10,
      'disponibles': 0,
    });
    await t.pumpAndSettle();
    expect(find.textContaining('7 aterrizajes disponibles'), findsOneWidget);
    expect(find.textContaining('0 aterrizajes disponibles'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
