import 'dart:convert';

import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:aplicacion_flutter/services/sistema_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'sistema comparte JWT y conserva filtros, cuerpo y códigos de error',
    () async {
      final api = ApiService(
        baseUrl: Uri.parse('http://localhost:5000'),
        client: MockClient((r) async {
          expect(r.headers['authorization'], 'Bearer prueba');
          if (r.method == 'GET') {
            expect(r.url.path, '/api/sistema/vuelos');
            expect(r.url.queryParameters, {'origen_id': 'uio'});
            return http.Response(
              jsonEncode({
                'vuelos': [
                  {'id': 'v1'},
                ],
              }),
              200,
            );
          }
          expect(r.url.path, '/api/sistema/pedidos');
          expect(jsonDecode(r.body), {
            'asientos': ['1A'],
          });
          return http.Response(
            jsonEncode({
              'error': {
                'codigo': 'asiento_ocupado',
                'mensaje': 'No disponible',
              },
            }),
            409,
          );
        }),
      );
      api.establecerToken('prueba');
      final sistema = SistemaApi(api);
      expect(
        (await sistema.lista(
          '/vuelos',
          'vuelos',
          parametros: {'origen_id': 'uio'},
        )).single['id'],
        'v1',
      );
      await expectLater(
        sistema.post(
          '/pedidos',
          body: {
            'asientos': ['1A'],
          },
        ),
        throwsA(
          isA<ExcepcionApi>().having(
            (e) => e.codigoError,
            'codigoError',
            'asiento_ocupado',
          ),
        ),
      );
    },
  );
  test('comprobante XML usa ruta nueva y sesión existente', () async {
    final api = ApiService(
      client: MockClient((r) async {
        expect(r.url.path, '/api/sistema/reservas/r1/comprobante.xml');
        expect(r.headers['authorization'], 'Bearer prueba');
        expect(r.headers['accept'], 'application/xml');
        return http.Response.bytes(utf8.encode('<reserva>José</reserva>'), 200);
      }),
    );
    api.establecerToken('prueba');
    expect(
      await SistemaApi(api).xml('/reservas/r1/comprobante.xml'),
      '<reserva>José</reserva>',
    );
  });
}
