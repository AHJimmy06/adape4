import 'dart:convert';

import 'package:aplicacion_flutter/models/usuario.dart';
import 'package:aplicacion_flutter/pages/sistema_admin_page.dart';
import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:aplicacion_flutter/widgets/sistema_admin/formulario_operacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _ApiAdmin extends ApiService {
  _ApiAdmin(http.Client client)
    : super(client: client, baseUrl: Uri.parse('https://example.test')) {
    establecerToken('test-token');
  }
  @override
  bool get esAdministrador => true;
  @override
  Usuario get usuarioActual => const Usuario(
    id: 'u1',
    nombre: 'Ana',
    correo: 'ana@example.test',
    rol: 'ADMIN',
  );
}

void main() {
  for (final codigo in ['avion_ocupado', 'aeropuerto_sin_cupo', 'conflicto']) {
    testWidgets('guardado con $codigo conserva o descarta según causa', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fecha = DateTime.now()
          .add(const Duration(days: 3))
          .toIso8601String()
          .substring(0, 10);
      const aeropuerto = {
        'id': 'a1',
        'iata': 'UIO',
        'nombre': 'Quito',
        'zona_horaria': 'America/Guayaquil',
        'activo': true,
      };
      const destino = {
        'id': 'a2',
        'iata': 'GYE',
        'nombre': 'Guayaquil',
        'zona_horaria': 'America/Guayaquil',
        'activo': true,
      };
      const clase = {
        'codigo': 'ECO',
        'nombre': 'Económica',
        'fila_inicio': 1,
        'filas': 2,
        'columnas': [
          ['A', 'B'],
        ],
        'capacidad': 4,
      };
      const avion = {
        'id': 'p1',
        'matricula': 'HC-ABC',
        'modelo': 'A320',
        'activo': true,
        'clases': [clase],
      };
      const ruta = {
        'id': 'r1',
        'origen': aeropuerto,
        'destino': destino,
        'activo': true,
      };
      var consultas = 0;
      var mutaciones = 0;
      final catalogos = {
        'aeropuertos': [aeropuerto, destino],
        'aviones': [avion],
        'rutas': [ruta],
        'vuelos': [
          {
            'id': 'f1',
            'version': 2,
            'codigo': 'AT101',
            'activo': true,
            'ruta': ruta,
            'avion': avion,
            'salida_local': '${fecha}T09:00',
            'llegada_local': '${fecha}T10:00',
            'tarifas': [
              {'clase_codigo': 'ECO', 'precio_centavos': 10000},
            ],
          },
        ],
      };
      final api = _ApiAdmin(
        MockClient((request) async {
          if (request.method != 'GET') {
            mutaciones++;
            return http.Response(
              jsonEncode({
                'error': {
                  'codigo': codigo,
                  'mensaje': 'Conflicto de prueba: $codigo',
                },
              }),
              409,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          final recurso = request.url.path.split('/').last;
          if (recurso == 'usuarios') return http.Response('[]', 200);
          if (recurso == 'disponibilidad-avion') {
            consultas++;
            expect(request.url.queryParameters['vuelo_id'], 'f1');
            expect(request.url.queryParameters['avion_id'], 'p1');
            return http.Response(
              jsonEncode({
                'fecha': fecha,
                'zona_origen': 'America/Guayaquil',
                'zona_destino': 'America/Guayaquil',
                'ventanas': [],
                'ocupados': [],
                'conflictos': [],
                'disponible': consultas == 1,
              }),
              200,
            );
          }
          if (recurso == 'disponibilidad-aeropuerto') {
            return http.Response('{"disponibles": 3}', 200);
          }
          return http.Response(
            jsonEncode({recurso: catalogos[recurso]}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(home: SistemaAdminPage(apiService: api)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vuelos').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editar_f1')),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '),
      );
      await tester.tap(find.byKey(const ValueKey('editar_f1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('tarifa_ECO')),
        '123.45',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(mutaciones, 1);
      if (codigo != 'conflicto') {
        expect(find.byType(FormularioOperacion), findsOneWidget);
        expect(find.text('Los datos cambiaron'), findsNothing);
        expect(find.text('Conflicto de prueba: $codigo'), findsOneWidget);
        expect(consultas, 2);
        final campo = tester.widget<TextFormField>(
          find.byKey(const ValueKey('tarifa_ECO')),
        );
        expect(campo.controller!.text, '123.45');
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();
        expect(
          mutaciones,
          1,
          reason: 'No vuelve a guardar una propuesta ocupada.',
        );
      } else {
        expect(find.byType(FormularioOperacion), findsNothing);
        expect(find.text('Los datos cambiaron'), findsOneWidget);
      }
    });
  }
}
