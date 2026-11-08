import 'dart:convert';

import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const baseUrl = 'http://localhost:5000';

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
