import 'dart:convert';

import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:aplicacion_flutter/services/sistema_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'cambiar estado de otra cuenta conserva la sesión administradora',
    () async {
      final api = ApiService(
        client: MockClient((r) async {
          if (r.url.path.endsWith('/login')) {
            return http.Response(
              jsonEncode({
                'token': 'admin-token',
                'usuario': {
                  'id': 'admin',
                  'nombre': 'Admin',
                  'correo': 'admin@example.test',
                  'rol': 'ADMIN',
                },
              }),
              200,
            );
          }
          expect(r.method, 'PUT');
          expect(r.url.path, '/api/admin/usuarios/otro/estado');
          expect(r.headers['authorization'], 'Bearer admin-token');
          expect(jsonDecode(r.body), {'activo': false});
          return http.Response(
            jsonEncode({
              'usuario': {
                'id': 'otro',
                'nombre': 'Otro',
                'correo': 'otro@example.test',
                'rol': 'USER',
                'activo': false,
              },
            }),
            200,
          );
        }),
      );
      await api.iniciarSesion(
        correo: 'admin@example.test',
        contrasena: 'test-password',
      );
      expect((await api.cambiarEstadoUsuario('otro', false)).id, 'otro');
      expect(api.usuarioActual?.id, 'admin');
      expect(api.tieneSesion, isTrue);
    },
  );
  test(
    'consulta pública sin JWT y operaciones protegidas conservan sesión',
    () async {
      final api = ApiService(
        client: MockClient((r) async {
          expect(r.headers['authorization'], isNull);
          return http.Response('{"vuelos":[]}', 200);
        }),
      );
      expect(api.tieneSesion, isFalse);
      await SistemaApi(api).lista('/vuelos', 'vuelos', requiereToken: false);
      await expectLater(
        SistemaApi(api).post('/pedidos'),
        throwsA(isA<ExcepcionApi>()),
      );
      api.establecerToken('test-token');
      expect(api.tieneSesion, isTrue);
      api.cerrarSesion();
      expect(api.tieneSesion, isFalse);
    },
  );
}
