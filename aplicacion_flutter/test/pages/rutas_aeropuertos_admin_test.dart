import 'dart:convert';

import 'package:aplicacion_flutter/models/usuario.dart';
import 'package:aplicacion_flutter/pages/sistema_admin_page.dart';
import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:aplicacion_flutter/theme/aerotech_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _ApiAdmin extends ApiService {
  _ApiAdmin(http.Client client)
    : super(client: client, baseUrl: Uri.parse('https://example.test')) {
    establecerToken('token');
  }

  @override
  bool get esAdministrador => true;

  @override
  Usuario get usuarioActual => const Usuario(
    id: 'operador',
    nombre: 'Admin',
    correo: 'admin@example.test',
    rol: 'ADMIN',
  );
}

void main() {
  testWidgets('rutas identifica ambos aeropuertos y conserva acciones', (
    t,
  ) async {
    final solicitudes = <http.Request>[];
    final aeropuertos = [
      {
        'id': 'a1',
        'iata': 'UIO',
        'nombre': 'Aeropuerto Internacional Mariscal Sucre',
        'ciudad': 'Quito',
        'pais': 'Ecuador',
      },
      {
        'id': 'a2',
        'iata': 'GYE',
        'nombre': 'Aeropuerto Internacional José Joaquín de Olmedo',
        'ciudad': 'Guayaquil',
        'pais': 'Ecuador',
      },
    ];
    final cliente = MockClient((r) async {
      solicitudes.add(r);
      final recurso = r.url.path.split('/').last;
      return http.Response(
        jsonEncode({
          recurso: switch (recurso) {
            'aeropuertos' => aeropuertos,
            'rutas' => [
              {
                'id': 'r1',
                'version': 3,
                'nombre': 'UIO → GYE',
                'origen_id': 'a1',
                'destino_id': 'a2',
                'origen': {'iata': 'UIO'},
                'destino': {'iata': 'GYE'},
                'activo': true,
              },
              {
                'id': 'r2',
                'version': 1,
                'nombre': 'Ruta protegida',
                'origen_id': 'a1',
                'destino_id': 'a2',
                'activo': true,
                'bloqueado': true,
              },
            ],
            _ => [],
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    await t.pumpWidget(
      MaterialApp(
        theme: AerotechTheme.light,
        home: SistemaAdminPage(apiService: _ApiAdmin(cliente)),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Rutas').last);
    await t.pumpAndSettle();
    expect(find.text('Aeropuerto Internacional Mariscal Sucre'), findsWidgets);
    expect(
      find.text('Aeropuerto Internacional José Joaquín de Olmedo'),
      findsWidgets,
    );
    expect(find.text('Quito, Ecuador'), findsWidgets);
    expect(find.text('Guayaquil, Ecuador'), findsWidgets);
    final editar = t.widget<OutlinedButton>(
      find.byKey(const ValueKey('editar_r1')),
    );
    final desactivar = t.widget<TextButton>(
      find.byKey(const ValueKey('eliminar_r1')),
    );
    expect(editar.onPressed, isNotNull);
    expect(desactivar.onPressed, isNotNull);
    expect(
      t
          .widget<OutlinedButton>(find.byKey(const ValueKey('editar_r2')))
          .onPressed,
      isNull,
    );
    expect(
      t.widget<TextButton>(find.byKey(const ValueKey('eliminar_r2'))).onPressed,
      isNull,
    );
    expect(solicitudes.every((r) => r.method == 'GET'), isTrue);
    await t.ensureVisible(find.byKey(const ValueKey('eliminar_r1')));
    await t.tap(find.byKey(const ValueKey('eliminar_r1')));
    await t.pumpAndSettle();
    expect(find.text('Desactivar registro'), findsOneWidget);
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(solicitudes.every((r) => r.method == 'GET'), isTrue);
  });
}
