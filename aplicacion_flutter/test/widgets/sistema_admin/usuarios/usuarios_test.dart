import 'dart:convert';

import 'package:aplicacion_flutter/models/usuario.dart';
import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:aplicacion_flutter/widgets/sistema_admin/usuarios/formulario_usuario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const operator = {
    'id': 'operator',
    'nombre': 'Operator',
    'correo': 'admin@example.test',
    'rol': 'ADMIN',
  };
  const other = {
    'id': 'other',
    'nombre': 'Other',
    'correo': 'other@example.test',
    'rol': 'USER',
  };

  testWidgets('ADMIN creation requires privilege acknowledgement', (t) async {
    Map<String, dynamic>? sent;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormularioUsuario(
            guardar: (data) async {
              sent = data;
              throw const ExcepcionApi('Test saved', codigo: 400);
            },
          ),
        ),
      ),
    );
    await t.enterText(
      find.byKey(const ValueKey('usuario_nombre')),
      'New Admin',
    );
    await t.enterText(
      find.byKey(const ValueKey('usuario_correo')),
      'admin2@example.test',
    );
    await t.enterText(
      find.byKey(const ValueKey('usuario_contrasena')),
      'SecurePass123',
    );
    await t.ensureVisible(find.byKey(const ValueKey('usuario_rol')));
    await t.tap(find.byKey(const ValueKey('usuario_rol')));
    await t.pumpAndSettle();
    await t.tap(find.text('ADMIN · Administrador').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Crear cuenta'));
    await t.pumpAndSettle();
    expect(sent, isNull);
    expect(
      find.text('Confirma que deseas otorgar acceso administrativo.'),
      findsOneWidget,
    );
    await t.ensureVisible(find.byType(CheckboxListTile));
    await t.tap(find.byType(CheckboxListTile));
    await t.pumpAndSettle();
    await t.tap(find.text('Crear cuenta'));
    await t.pumpAndSettle();
    expect(sent!['rol'], 'ADMIN');
  });

  test('administrative create and role change preserve operator identity and Bearer token', () async {
    final requests = <http.Request>[];
    final api = ApiService(
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/login')) {
          return http.Response(
            jsonEncode({'token': 'operator-token', 'usuario': operator}),
            200,
          );
        }
        expect(request.headers['authorization'], 'Bearer operator-token');
        if (request.url.path.endsWith('/rol')) {
          expect(request.method, 'PUT');
          expect(jsonDecode(request.body), {'rol': 'USER'});
        } else {
          expect(request.method, 'POST');
          expect(jsonDecode(request.body)['rol'], 'USER');
        }
        return http.Response(
          jsonEncode({'usuario': other}),
          request.method == 'POST' ? 201 : 200,
        );
      }),
    );
    await api.iniciarSesion(
      correo: 'admin@example.test',
      contrasena: 'OperatorPass1',
    );
    final dynamic dynamicApi = api;
    await dynamicApi.crearUsuarioAdministrado(
      nombre: 'Other',
      correo: 'other@example.test',
      contrasena: 'SecurePass123',
    );
    expect(api.usuarioActual!.id, 'operator');
    await dynamicApi.cambiarRolUsuario('other', 'USER');
    expect(api.usuarioActual!.id, 'operator');
    expect(requests, hasLength(3));
  });

  testWidgets('creation validates and keeps duplicate errors in the form', (
    t,
  ) async {
    var calls = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormularioUsuario(
            guardar: (data) async {
              calls++;
              expect(data['rol'], 'USER');
              throw const ExcepcionApi(
                'Ya existe una cuenta con ese correo.',
                codigo: 409,
              );
            },
          ),
        ),
      ),
    );
    await t.tap(find.text('Crear cuenta'));
    await t.pumpAndSettle();
    expect(calls, 0);
    await t.enterText(find.byKey(const ValueKey('usuario_nombre')), 'New User');
    await t.enterText(
      find.byKey(const ValueKey('usuario_correo')),
      'new@example.test',
    );
    await t.enterText(
      find.byKey(const ValueKey('usuario_contrasena')),
      'SecurePass123',
    );
    await t.ensureVisible(find.text('Crear cuenta'));
    await t.tap(find.text('Crear cuenta'));
    await t.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Ya existe una cuenta con ese correo.'), findsOneWidget);
    expect(find.byType(FormularioUsuario), findsOneWidget);
  });

  testWidgets(
    'role change requires exact confirmation and displays server rejection',
    (t) async {
      var calls = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConfirmarRolUsuario(
              usuario: Usuario.fromJson({...other, 'rol': 'ADMIN'}),
              guardar: () async {
                calls++;
                throw const ExcepcionApi(
                  'Debe permanecer al menos un administrador.',
                  codigo: 409,
                );
              },
            ),
          ),
        ),
      );
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirmar cambio'),
            )
            .onPressed,
        isNull,
      );
      await t.enterText(
        find.byKey(const ValueKey('confirmar_correo')),
        'other@example.test',
      );
      await t.pump();
      await t.tap(find.text('Confirmar cambio'));
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(
        find.text('Debe permanecer al menos un administrador.'),
        findsOneWidget,
      );
      expect(find.byType(ConfirmarRolUsuario), findsOneWidget);
    },
  );
}
