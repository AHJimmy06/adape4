import 'dart:convert';

import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'editar y eliminar vuelo envian version y autorizacion sin reintentos',
    () async {
      final requests = <http.Request>[];
      final api = ApiService(
        client: MockClient((request) async {
          requests.add(request);
          expect(request.url.path, '/api/vuelos/v1');
          expect(request.headers['authorization'], 'Bearer admin');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['version'], 4);
          if (request.method == 'PUT') {
            expect(body['asientos_disponibles'], 0);
            expect(body['origen'], 'Quito, Ecuador');
            return http.Response(
              jsonEncode({
                'vuelo': {...body, 'id': 'v1', 'version': 5},
              }),
              200,
            );
          }
          expect(request.method, 'DELETE');
          expect(body, {'version': 4});
          return http.Response(
            jsonEncode({'mensaje': 'Vuelo eliminado.'}),
            200,
          );
        }),
      )..establecerToken('admin');
      final dynamic dynamicApi = api;
      final dynamic flight = await dynamicApi.actualizarVuelo(
        id: 'v1',
        version: 4,
        origen: 'Quito, Ecuador',
        destino: 'Lima, Peru',
        fecha: '2030-01-01',
        horaSalida: '09:00',
        horaLlegada: '11:00',
        precio: 50.0,
        asientosDisponibles: 0,
      );
      expect(flight.version, 5);
      final result = await dynamicApi.eliminarVuelo('v1', version: 4);
      expect(result['mensaje'], 'Vuelo eliminado.');
      expect(requests, hasLength(2));
    },
  );
  test('conserva codigo de error sin cambiar estado HTTP ni mensaje', () async {
    for (final codigoError in ['asientos_insuficientes', 'correo_registrado']) {
      final api = ApiService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'codigo': codigoError, 'mensaje': 'Conflicto'},
            }),
            409,
          ),
        ),
      );
      api.establecerToken('test');
      try {
        await api.reservarVuelo(vueloId: 'v1');
        fail('Debía fallar');
      } on ExcepcionApi catch (error) {
        expect(error.codigo, 409);
        expect(error.mensaje, 'Conflicto');
        expect((error as dynamic).codigoError, codigoError);
      }
    }
  });
  const baseUrl = 'http://localhost:5000';

  test('roles, perfil, promoción y vuelos usan contratos protegidos', () async {
    var role = 'ADMIN';
    final client = MockClient((request) async {
      final user = {
        'id': 'u1',
        'nombre': 'Ana',
        'correo': 'a@b.c',
        'rol': role,
      };
      if (request.url.path == '/api/auth/login') {
        return http.Response(
          jsonEncode({'token': 'jwt', 'usuario': user}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      expect(request.headers['authorization'], 'Bearer jwt');
      if (request.url.path == '/api/auth/perfil') {
        expect(request.method, 'GET');
        return http.Response(jsonEncode({'usuario': user}), 200);
      }
      if (request.url.path == '/api/admin/usuarios') {
        expect(request.method, 'GET');
        return http.Response(
          jsonEncode({
            'usuarios': [user],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (request.url.path.endsWith('/promover')) {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/admin/usuarios/u2/promover');
        expect(request.body, isEmpty);
        return http.Response(
          jsonEncode({
            'usuario': {...user, 'id': 'u2', 'rol': 'ADMIN'},
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      expect(request.url.path, '/api/vuelos');
      expect(request.method, 'POST');
      final flight = jsonDecode(request.body) as Map<String, dynamic>;
      expect(flight, {
        'origen': 'Quito, Ecuador',
        'destino': 'Lima, Perú',
        'fecha': '2026-12-01',
        'hora_salida': '09:00',
        'hora_llegada': '11:00',
        'precio': 99.5,
        'asientos_disponibles': 20,
      });
      return http.Response(
        jsonEncode({
          'vuelo': {...flight, 'id': 'v1'},
        }),
        201,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final api = ApiService(client: client, baseUrl: Uri.parse(baseUrl));
    await api.iniciarSesion(correo: 'a@b.c', contrasena: 'secret');
    expect(api.esAdministrador, isTrue);
    expect(api.usuarioActual!.id, 'u1');
    expect((await api.listarUsuarios()).single.rol, 'ADMIN');
    expect((await api.promoverUsuario('u2')).rol, 'ADMIN');
    expect(
      (await api.crearVuelo(
        origen: 'Quito, Ecuador',
        destino: 'Lima, Perú',
        fecha: '2026-12-01',
        horaSalida: '09:00',
        horaLlegada: '11:00',
        precio: 99.5,
        asientosDisponibles: 20,
      )).id,
      'v1',
    );
    role = 'USER';
    await api.obtenerPerfil();
    expect(api.esAdministrador, isFalse);
    api.cerrarSesion();
    expect(api.usuarioActual, isNull);
    expect(api.esAdministrador, isFalse);
    await expectLater(api.obtenerPerfil(), throwsA(isA<ExcepcionApi>()));
    role = 'ADMIN';
    await api.iniciarSesion(correo: 'a@b.c', contrasena: 'secret');
    api.establecerToken('replacement');
    expect(api.esAdministrador, isFalse);
    expect(api.usuarioActual, isNull);
  });

  test('login sin rol queda USER y errores 403/409 se conservan', () async {
    var status = 403;
    final client = MockClient((request) async {
      if (request.url.path == '/api/auth/login') {
        return http.Response(
          jsonEncode({
            'token': 'jwt',
            'usuario': {'id': 'u', 'nombre': 'Ana', 'correo': 'a@b.c'},
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response(
        jsonEncode({
          'error': {'mensaje': 'Operación rechazada'},
        }),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final api = ApiService(client: client, baseUrl: Uri.parse(baseUrl));
    await api.iniciarSesion(correo: 'a@b.c', contrasena: 'secret');
    expect(api.usuarioActual!.rol, 'USER');
    await expectLater(
      api.listarUsuarios(),
      throwsA(isA<ExcepcionApi>().having((e) => e.codigo, 'codigo', 403)),
    );
    status = 409;
    await expectLater(
      api.promoverUsuario('u2'),
      throwsA(isA<ExcepcionApi>().having((e) => e.codigo, 'codigo', 409)),
    );
  });

  test('buscarVuelos envía los filtros y analiza la respuesta JSON', () async {
    final cliente = MockClient((solicitud) async {
      expect(solicitud.method, 'GET');
      expect(solicitud.url.path, '/api/vuelos');
      expect(solicitud.url.queryParameters, {
        'origen': 'Quito',
        'destino': 'Guayaquil',
      });
      return http.Response(
        jsonEncode([
          {
            'id': 2,
            'origen': 'Quito',
            'destino': 'Guayaquil',
            'fecha': '2026-11-20',
            'hora_salida': '09:45',
            'hora_llegada': '10:30',
            'precio': 89.5,
            'asientos_disponibles': 3,
          },
        ]),
        200,
      );
    });
    final servicio = ApiService(baseUrl: Uri.parse(baseUrl), client: cliente);

    final vuelos = await servicio.buscarVuelos(
      origen: 'Quito',
      destino: 'Guayaquil',
    );

    expect(vuelos, hasLength(1));
    expect(vuelos.single.precio, 89.5);
    cliente.close();
  });

  test('registrarUsuario envía los datos al endpoint de registro', () async {
    final cliente = MockClient((solicitud) async {
      expect(solicitud.method, 'POST');
      expect(solicitud.url.path, '/api/usuarios/registro');
      expect(jsonDecode(solicitud.body), {
        'nombre': 'Ana Pérez',
        'correo': 'ana@example.com',
        'contrasena': 'clave-segura',
      });
      return http.Response(jsonEncode({'mensaje': 'Usuario creado'}), 201);
    });
    final servicio = ApiService(baseUrl: Uri.parse(baseUrl), client: cliente);

    final respuesta = await servicio.registrarUsuario(
      nombre: 'Ana Pérez',
      correo: 'ana@example.com',
      contrasena: 'clave-segura',
    );

    expect(respuesta['mensaje'], 'Usuario creado');
    cliente.close();
  });

  test(
    'iniciarSesion guarda el token en memoria para rutas protegidas',
    () async {
      final cliente = MockClient((solicitud) async {
        if (solicitud.url.path == '/api/auth/login') {
          expect(jsonDecode(solicitud.body), {
            'correo': 'ana@example.com',
            'contrasena': 'clave-segura',
          });
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'mensaje': 'Inicio de sesión correcto',
                'token': 'jwt-de-prueba',
                'usuario': {
                  'id': 'usuario-4',
                  'nombre': 'Ana Pérez',
                  'correo': 'ana@example.com',
                },
              }),
            ),
            200,
          );
        }
        if (solicitud.url.path == '/api/reservas') {
          expect(solicitud.headers['authorization'], 'Bearer jwt-de-prueba');
          expect(jsonDecode(solicitud.body), {
            'vuelo_id': '9c6ef30c-7796-4c4f-a515-954d71c6a3db',
            'cantidad': 1,
          });
          return http.Response(
            jsonEncode({
              'mensaje': 'Reserva creada',
              'reserva_id': '2a1174bb-0044-47a9-82c5-99ad8945efb3',
              'total': 89.5,
              'estado': 'confirmada',
            }),
            201,
          );
        }
        fail('Ruta inesperada: ${solicitud.url}');
      });
      final servicio = ApiService(baseUrl: Uri.parse(baseUrl), client: cliente);

      await servicio.iniciarSesion(
        correo: 'ana@example.com',
        contrasena: 'clave-segura',
      );
      final reserva = await servicio.reservarVuelo(
        vueloId: '9c6ef30c-7796-4c4f-a515-954d71c6a3db',
      );

      expect(reserva['reserva_id'], '2a1174bb-0044-47a9-82c5-99ad8945efb3');
      cliente.close();
    },
  );

  test('cancelarReserva envía DELETE con autorización', () async {
    final cliente = MockClient((solicitud) async {
      expect(solicitud.method, 'DELETE');
      expect(
        solicitud.url.path,
        '/api/reservas/2a1174bb-0044-47a9-82c5-99ad8945efb3',
      );
      expect(solicitud.headers['authorization'], 'Bearer jwt-activo');
      return http.Response(jsonEncode({'mensaje': 'Reserva cancelada'}), 200);
    });
    final servicio = ApiService(baseUrl: Uri.parse(baseUrl), client: cliente);
    servicio.establecerToken('jwt-activo');

    await servicio.cancelarReserva('2a1174bb-0044-47a9-82c5-99ad8945efb3');

    cliente.close();
  });

  test('obtenerReservas solicita la lista usando el token', () async {
    final cliente = MockClient((solicitud) async {
      expect(solicitud.method, 'GET');
      expect(solicitud.url.path, '/api/reservas');
      expect(solicitud.headers['authorization'], 'Bearer jwt-activo');
      return http.Response(
        jsonEncode([
          {
            'id': '2a1174bb-0044-47a9-82c5-99ad8945efb3',
            'vuelo_id': '9c6ef30c-7796-4c4f-a515-954d71c6a3db',
            'cantidad': 1,
            'subtotal': 89.5,
            'iva': 13.43,
            'porcentaje_iva': 15.0,
            'total': 102.93,
            'estado': 'confirmada',
            'creado_en': '2026-11-08T10:00:00Z',
          },
        ]),
        200,
      );
    });
    final servicio = ApiService(baseUrl: Uri.parse(baseUrl), client: cliente);
    servicio.establecerToken('jwt-activo');

    final reservas = await servicio.obtenerReservas();

    expect(reservas, hasLength(1));
    expect(reservas.single.vueloId, '9c6ef30c-7796-4c4f-a515-954d71c6a3db');
    expect(reservas.single.iva, 13.43);
    cliente.close();
  });

  test('obtenerComprobanteXml solicita el XML de la reserva con JWT', () async {
    const xml =
        '<?xml version="1.0"?><comprobante><total>102.93</total></comprobante>';
    final cliente = MockClient((solicitud) async {
      expect(solicitud.method, 'GET');
      expect(solicitud.url.path, '/api/reservas/reserva-2/comprobante.xml');
      expect(solicitud.headers['authorization'], 'Bearer jwt-activo');
      expect(solicitud.headers['accept'], 'application/xml');
      return http.Response.bytes(
        utf8.encode(xml),
        200,
        headers: {'content-type': 'application/xml; charset=utf-8'},
      );
    });
    final servicio = ApiService(baseUrl: Uri.parse(baseUrl), client: cliente);
    servicio.establecerToken('jwt-activo');

    final resultado = await servicio.obtenerComprobanteXml('reserva-2');

    expect(resultado, xml);
    cliente.close();
  });

  test(
    'una respuesta de error del API produce una excepción visible',
    () async {
      final cliente = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'codigo': 'asientos_insuficientes',
              'mensaje': 'No hay asientos disponibles.',
            },
          }),
          409,
        ),
      );
      final servicio = ApiService(baseUrl: Uri.parse(baseUrl), client: cliente);

      await expectLater(
        servicio.buscarVuelos(),
        throwsA(
          isA<ExcepcionApi>().having(
            (error) => error.mensaje,
            'mensaje',
            'No hay asientos disponibles.',
          ),
        ),
      );
      cliente.close();
    },
  );
}
