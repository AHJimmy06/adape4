import 'dart:convert';

import 'package:aplicacion_flutter/pages/sistema_vuelos_page.dart';
import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:aplicacion_flutter/services/sistema_api.dart';
import 'package:aplicacion_flutter/widgets/sistema_compra/compra_sistema_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'sistema_vuelos_page_test.dart' show airport, cabin, flight, seat, order;

http.Response respuesta(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  testWidgets('cabina pública con 401 termina sin reintentos infinitos', (
    t,
  ) async {
    var llamadas = 0;
    final api = ApiService(
      client: MockClient((r) async {
        llamadas++;
        return http.Response(
          '{"error":{"mensaje":"Servicio protegido"}}',
          401,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompraSistemaDialog(
            api: SistemaApi(api),
            vuelo: flight,
            launcher: (_) async => false,
            onRefresh: () {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(llamadas, 1);
    expect(find.text('Servicio protegido'), findsOneWidget);
    expect(find.text('Reintentar cabina'), findsOneWidget);
  });
  for (final escenario in ['registro', 'ocupado', 'token_vencido']) {
    testWidgets('compra invitada: $escenario preserva reglas de acceso', (
      t,
    ) async {
      await t.binding.setSurfaceSize(const Size(1100, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      var mapas = 0;
      final operaciones = <String>[];
      final cuerpos = <Map<String, dynamic>>[];
      final api = ApiService(
        client: MockClient((r) async {
          if (r.url.path.endsWith('/asientos')) {
            mapas++;
            return respuesta({
              'clases': [cabin],
              'asientos': [
                seat(
                  '1A',
                  escenario == 'ocupado' && mapas > 1 ? 'ocupado' : 'libre',
                ),
              ],
            });
          }
          operaciones.add(r.url.path);
          if (r.url.path.endsWith('/login')) {
            return respuesta({
              'token': 'nuevo-token',
              'usuario': {
                'id': 'u',
                'nombre': 'Ana',
                'correo': 'ana@example.test',
                'rol': 'USER',
              },
            });
          }
          if (r.url.path.endsWith('/registro')) {
            return respuesta({
              'usuario': {'id': 'u'},
            });
          }
          cuerpos.add(Map<String, dynamic>.from(jsonDecode(r.body) as Map));
          if (escenario == 'token_vencido' && cuerpos.length == 1) {
            return http.Response(
              jsonEncode({
                'error': {'mensaje': 'Sesión vencida'},
              }),
              401,
              headers: {'content-type': 'application/json'},
            );
          }
          expect(r.headers['Authorization'], 'Bearer nuevo-token');
          return respuesta({'pedido': order('pendiente_pago')});
        }),
      );
      if (escenario == 'token_vencido') api.establecerToken('vencido');
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompraSistemaDialog(
              api: SistemaApi(api),
              vuelo: flight,
              launcher: (_) async => false,
              onRefresh: () {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('asiento-1A')));
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(find.byKey(const ValueKey('asiento-1A')));
      await t.pumpAndSettle();
      await t.tap(find.text('Continuar con 1 asiento(s)'));
      await t.pumpAndSettle();
      if (escenario == 'registro') {
        await t.tap(find.text('Crear cuenta'));
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const ValueKey('compra-nombre')),
          'Ana Prueba',
        );
      } else {
        await t.tap(find.text('Ya tengo cuenta'));
        await t.pumpAndSettle();
      }
      await t.enterText(
        find.byKey(const ValueKey('compra-correo')),
        'ana@example.test',
      );
      await t.enterText(
        find.byKey(const ValueKey('compra-contrasena')),
        'password123',
      );
      await t.tap(
        find.text(
          escenario == 'registro'
              ? 'Crear cuenta y continuar'
              : 'Iniciar sesión y continuar',
        ),
      );
      await t.pumpAndSettle();
      if (escenario == 'ocupado') {
        expect(cuerpos, isEmpty);
        expect(
          find.textContaining('La disponibilidad cambió mientras ingresabas'),
          findsOneWidget,
        );
        expect(find.text('Continuar con 0 asiento(s)'), findsOneWidget);
      } else {
        expect(cuerpos.length, escenario == 'token_vencido' ? 2 : 1);
        if (escenario == 'token_vencido') expect(cuerpos.first, cuerpos.last);
        if (escenario == 'registro') {
          expect(operaciones.take(2), [
            '/api/usuarios/registro',
            '/api/auth/login',
          ]);
        }
        expect(find.text('Pedido · Stripe TEST'), findsOneWidget);
      }
      await t.pumpWidget(const SizedBox());
    });
  }
  testWidgets('rango usa ambos límites inclusivos y se puede quitar', (
    t,
  ) async {
    Map<String, String>? parametros;
    final api = ApiService(
      client: MockClient((r) async {
        if (r.url.path.endsWith('/vuelos')) parametros = r.url.queryParameters;
        return respuesta(
          r.url.path.endsWith('/aeropuertos')
              ? {
                  'aeropuertos': [airport],
                }
              : {'vuelos': []},
        );
      }),
    );
    await t.pumpWidget(MaterialApp(home: SistemaVuelosPage(apiService: api)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('filtro-rango-fechas')));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.edit_outlined));
    await t.pumpAndSettle();
    final year = DateTime.now().year + 1;
    final campos = find.byType(TextField);
    await t.enterText(campos.at(0), '01/02/$year');
    await t.enterText(campos.at(1), '01/05/$year');
    await t.tap(find.text('Aplicar rango'));
    await t.pumpAndSettle();
    await t.tap(find.text('Buscar vuelos'));
    await t.pumpAndSettle();
    expect(parametros?['fecha_desde'], '$year-01-02');
    expect(parametros?['fecha_hasta'], '$year-01-05');
    expect(parametros!.containsKey('fecha'), isFalse);
    await t.tap(find.byTooltip('Quitar rango'));
    await t.pumpAndSettle();
    await t.tap(find.text('Buscar vuelos'));
    await t.pumpAndSettle();
    expect(parametros!.containsKey('fecha_desde'), isFalse);
    expect(parametros!.containsKey('fecha_hasta'), isFalse);
  });

  testWidgets('cancelar identificación conserva selección sin crear pedido', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    var compras = 0;
    final api = ApiService(
      client: MockClient((r) async {
        if (r.method != 'GET') compras++;
        return respuesta({
          'clases': [cabin],
          'asientos': [seat('1A', 'libre')],
        });
      }),
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompraSistemaDialog(
            api: SistemaApi(api),
            vuelo: flight,
            launcher: (_) async => false,
            onRefresh: () {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('asiento-1A')));
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(find.byKey(const ValueKey('asiento-1A')));
    await t.pumpAndSettle();
    await t.tap(find.text('Continuar con 1 asiento(s)'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Cerrar').last);
    await t.pumpAndSettle();
    expect(compras, 0);
    expect(find.text('Continuar con 1 asiento(s)'), findsOneWidget);
    expect(find.text('Seleccionados: 1A'), findsOneWidget);
  });
  testWidgets('invitado explora precios sin consultar pedidos privados', (
    t,
  ) async {
    final consultas = <String>[];
    final api = ApiService(
      client: MockClient((r) async {
        consultas.add(r.url.path);
        expect(r.headers.containsKey('Authorization'), isFalse);
        return respuesta(
          r.url.path.endsWith('/aeropuertos')
              ? {
                  'aeropuertos': [airport],
                }
              : {
                  'vuelos': [flight],
                },
        );
      }),
    );
    await t.pumpWidget(MaterialApp(home: SistemaVuelosPage(apiService: api)));
    await t.pumpAndSettle();
    expect(consultas, contains('/api/sistema/vuelos'));
    expect(consultas.any((p) => p.endsWith('/pedidos')), isFalse);
    expect(find.text('Mis reservas'), findsNothing);
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.textContaining('Aeropuertos reales'), findsNothing);
    expect(find.text('Rango de fechas'), findsOneWidget);
    final titulo = t.widget<Text>(find.text('Tu próximo destino empieza aquí'));
    expect(titulo.style!.fontSize, greaterThanOrEqualTo(42));
    expect(titulo.style!.fontFamily, 'AeroTechDisplay');
  });

  testWidgets('selección invitada se conserva y autentica solo al continuar', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final pasos = <String>[];
    var compras = 0;
    final api = ApiService(
      client: MockClient((r) async {
        pasos.add('${r.method} ${r.url.path}');
        if (r.url.path.endsWith('/asientos')) {
          return respuesta({
            'clases': [cabin],
            'asientos': [seat('1A', 'libre')],
          });
        }
        if (r.url.path.endsWith('/login')) {
          return respuesta({
            'token': 'invitado-autenticado',
            'usuario': {
              'id': 'u',
              'nombre': 'Ana',
              'correo': 'ana@example.test',
              'rol': 'USER',
            },
          });
        }
        compras++;
        expect(r.headers['Authorization'], 'Bearer invitado-autenticado');
        expect(jsonDecode(r.body)['asientos'], ['1A']);
        return respuesta({
          'pedido': {
            ...order('pendiente_pago'),
            'asientos': [
              {'codigo': '1A', 'clase_codigo': 'ECO'},
            ],
          },
        });
      }),
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompraSistemaDialog(
            api: SistemaApi(api),
            vuelo: flight,
            launcher: (_) async => false,
            onRefresh: () {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('asiento-1A')));
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(find.byKey(const ValueKey('asiento-1A')));
    await t.pumpAndSettle();
    expect(compras, 0);
    expect(pasos.any((p) => p.contains('/login')), isFalse);
    await t.tap(find.text('Continuar con 1 asiento(s)'));
    await t.pumpAndSettle();
    expect(find.text('Identifícate para continuar'), findsOneWidget);
    expect(compras, 0);
    expect(find.byKey(const ValueKey('compra-nombre')), findsOneWidget);
    await t.tap(find.text('Ya tengo cuenta'));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('compra-correo')),
      'ana@example.test',
    );
    await t.enterText(
      find.byKey(const ValueKey('compra-contrasena')),
      'password123',
    );
    await t.tap(find.text('Iniciar sesión y continuar'));
    await t.pumpAndSettle();
    expect(compras, 1);
    expect(pasos.where((p) => p.endsWith('/asientos')).length, 2);
    expect(find.text('1A · ECO'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
