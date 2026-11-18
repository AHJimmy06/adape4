import 'dart:convert';

import 'package:aplicacion_flutter/models/usuario.dart';
import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:aplicacion_flutter/widgets/sistema_admin/usuarios/boton_estado_usuario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'desactivar requiere confirmación y conserva la sesión del operador',
    (t) async {
      var llamadas = 0;
      var cambios = 0;
      final api = ApiService(
        client: MockClient((r) async {
          if (r.url.path.endsWith('/login')) {
            return http.Response(
              jsonEncode({
                'token': 'token-admin',
                'usuario': {
                  'id': 'admin',
                  'nombre': 'Admin',
                  'correo': 'admin@example.test',
                  'rol': 'ADMIN',
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          llamadas++;
          expect(r.method, 'PUT');
          expect(r.url.path, '/api/admin/usuarios/otro/estado');
          expect(jsonDecode(r.body), {'activo': false});
          return http.Response(
            jsonEncode({
              'usuario': {
                'id': 'otro',
                'nombre': 'Otra cuenta',
                'correo': 'otra@example.test',
                'rol': 'USER',
                'activo': false,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await api.iniciarSesion(
        correo: 'admin@example.test',
        contrasena: 'ClaveSegura123',
      );
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BotonEstadoUsuario(
              apiService: api,
              usuario: const Usuario(
                id: 'otro',
                nombre: 'Otra cuenta',
                correo: 'otra@example.test',
              ),
              currentUserId: 'admin',
              onCambio: () => cambios++,
            ),
          ),
        ),
      );
      await t.tap(find.text('Desactivar'));
      await t.pumpAndSettle();
      expect(llamadas, 0);
      expect(find.text('Desactivar cuenta'), findsOneWidget);
      await t.tap(find.text('Confirmar desactivación'));
      await t.pumpAndSettle();
      expect(llamadas, 1);
      expect(cambios, 1);
      expect(api.usuarioActual?.id, 'admin');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('la propia cuenta no permite desactivación', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BotonEstadoUsuario(
            apiService: ApiService(),
            usuario: const Usuario(
              id: 'admin',
              nombre: 'Admin',
              correo: 'admin@example.test',
              rol: 'ADMIN',
            ),
            currentUserId: 'admin',
            onCambio: () {},
          ),
        ),
      ),
    );
    expect(
      t.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    expect(find.text('Activo'), findsOneWidget);
  });

  testWidgets('una cuenta inactiva puede reactivarse con confirmación', (
    t,
  ) async {
    var cambios = 0;
    final api = ApiService(
      client: MockClient((request) async {
        expect(jsonDecode(request.body), {'activo': true});
        return http.Response(
          jsonEncode({
            'usuario': {
              'id': 'otro',
              'nombre': 'Otra cuenta',
              'correo': 'otra@example.test',
              'rol': 'USER',
              'activo': true,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    )..establecerToken('token-admin');
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BotonEstadoUsuario(
            apiService: api,
            usuario: const Usuario(
              id: 'otro',
              nombre: 'Otra cuenta',
              correo: 'otra@example.test',
              activo: false,
            ),
            currentUserId: 'admin',
            onCambio: () => cambios++,
          ),
        ),
      ),
    );
    expect(find.text('Inactivo'), findsOneWidget);
    await t.tap(find.text('Reactivar'));
    await t.pumpAndSettle();
    await t.tap(find.text('Confirmar reactivación'));
    await t.pumpAndSettle();
    expect(cambios, 1);
    expect(t.takeException(), isNull);
  });
}
