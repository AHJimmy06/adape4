import 'dart:convert';

import 'package:aplicacion_flutter/pages/sistema_admin_page.dart';
import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:aplicacion_flutter/theme/aerotech_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _AdminApi extends ApiService {
  _AdminApi(http.Client client, {this.admin = true})
    : super(client: client, baseUrl: Uri.parse('https://example.test')) {
    establecerToken('test-token');
  }
  final bool admin;
  @override
  bool get esAdministrador => admin;
}

void main() {
  late List<http.Request> requests;
  late Map<String, List<Map<String, dynamic>>> store;
  late String? conflict;
  var errorCarga = false;
  var estadoMutacion = 409;
  final departure = DateTime.now().add(const Duration(days: 3));
  String local(DateTime d) => '${d.toIso8601String().substring(0, 10)}T09:00';
  setUp(() {
    requests = [];
    conflict = null;
    errorCarga = false;
    estadoMutacion = 409;
    store = {
      'aeropuertos': [
        {
          'id': 'a1',
          'version': 3,
          'activo': true,
          'iata': 'UIO',
          'nombre': 'Mariscal Sucre',
          'ciudad': 'Quito',
          'pais': 'Ecuador',
          'codigo_pais': 'EC',
          'latitud': -0.12,
          'longitud': -78.35,
          'zona_horaria': 'America/Guayaquil',
        },
        {
          'id': 'a2',
          'version': 1,
          'activo': true,
          'iata': 'GYE',
          'nombre': 'José Joaquín',
          'ciudad': 'Guayaquil',
          'pais': 'Ecuador',
          'codigo_pais': 'EC',
          'latitud': -2.15,
          'longitud': -79.88,
          'zona_horaria': 'America/Guayaquil',
        },
      ],
      'aviones': [
        {
          'id': 'p1',
          'version': 4,
          'activo': true,
          'matricula': 'HC-ABC',
          'modelo': 'A320',
          'capacidad_total': 12,
          'clases': [
            {
              'codigo': 'ECO',
              'nombre': 'Económica',
              'fila_inicio': 1,
              'filas': 2,
              'columnas': [
                ['A', 'B', 'C'],
                ['D', 'E', 'F'],
              ],
              'capacidad': 12,
            },
          ],
        },
      ],
      'rutas': [],
      'vuelos': [],
    };
    store['rutas'] = [
      {
        'id': 'r1',
        'version': 2,
        'activo': true,
        'origen_id': 'a1',
        'destino_id': 'a2',
        'origen': store['aeropuertos']![0],
        'destino': store['aeropuertos']![1],
        'nombre': 'UIO → GYE',
      },
    ];
    store['vuelos'] = [
      {
        'id': 'f1',
        'version': 7,
        'activo': true,
        'codigo': 'AT101',
        'ruta': store['rutas']!.first,
        'avion': store['aviones']!.first,
        'salida_local': local(departure),
        'llegada_local': local(departure).replaceFirst('09:00', '10:00'),
        'asientos_disponibles': 12,
        'tiene_reservas': false,
        'tarifas': [
          {'clase_codigo': 'ECO', 'precio_centavos': 8950},
        ],
      },
    ];
  });
  Future<void> abrir(WidgetTester tester, {bool admin = true}) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _AdminApi(
      MockClient((r) async {
        requests.add(r);
        expect(r.headers['authorization'], 'Bearer test-token');
        if (errorCarga && r.method == 'GET') {
          return http.Response(
            jsonEncode({
              'error': {
                'codigo': 'indisponible',
                'mensaje': 'Servicio no disponible',
              },
            }),
            503,
          );
        }
        if (r.url.path == '/api/admin/usuarios') {
          return http.Response(
            jsonEncode({
              'usuarios': [
                {
                  'id': 'u1',
                  'nombre': 'Ana',
                  'correo': 'ana@example.test',
                  'rol': 'USER',
                },
              ],
            }),
            200,
          );
        }
        if (r.method != 'GET') {
          if (conflict != null) {
            return http.Response(
              jsonEncode({
                'error': {'codigo': conflict, 'mensaje': 'Versión obsoleta'},
              }),
              estadoMutacion,
              headers: {"content-type": "application/json; charset=utf-8"},
            );
          }
          return http.Response('{}', 200);
        }
        final key = r.url.path.split('/').last;
        return http.Response(
          jsonEncode({key: store[key]}),
          200,
          headers: {"content-type": "application/json; charset=utf-8"},
        );
      }),
      admin: admin,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AerotechTheme.light,
        home: SistemaAdminPage(apiService: api),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tab(WidgetTester t, String name) async {
    await t.tap(find.text(name).last);
    await t.pumpAndSettle();
  }

  Future<void> editar(WidgetTester t, String id) async {
    await t.tap(find.byKey(ValueKey('editar_$id')));
    await t.pumpAndSettle();
  }

  Future<void> guardar(WidgetTester t) async {
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
  }

  http.Request mutation() => requests.lastWhere((r) => r.method != 'GET');

  testWidgets('No ADMIN nunca carga ni muestra CRUD', (t) async {
    await abrir(t, admin: false);
    expect(find.text('Acceso exclusivo para ADMIN.'), findsOneWidget);
    expect(requests, isEmpty);
    expect(find.text('Crear registro'), findsNothing);
  });
  testWidgets('Navegación completa por cinco secciones y consulta ADMIN', (
    t,
  ) async {
    await abrir(t);
    expect(
      find.text('UIO · Mariscal Sucre'),
      findsOneWidget,
      reason: t
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .join(' | '),
    );
    await tab(t, 'Aviones');
    expect(find.text('HC-ABC · A320'), findsOneWidget);
    await tab(t, 'Rutas');
    expect(find.text('UIO → GYE'), findsOneWidget);
    await tab(t, 'Vuelos');
    expect(find.text('AT101'), findsOneWidget);
    await tab(t, 'Usuarios');
    expect(find.text('Ana'), findsOneWidget);
    expect(
      requests
          .firstWhere((r) => r.url.path.endsWith('/vuelos'))
          .url
          .queryParameters['admin'],
      'true',
    );
  });
  testWidgets('Aeropuerto edita coordenadas negativas con versión congelada', (
    t,
  ) async {
    await abrir(t);
    await editar(t, 'a1');
    await t.enterText(find.byKey(const ValueKey('latitud')), '-1.25');
    await t.enterText(find.byKey(const ValueKey('iata')), 'uio');
    await guardar(t);
    final req = mutation();
    expect(req.method, 'PUT');
    expect(req.url.path, '/api/sistema/aeropuertos/a1');
    final body = jsonDecode(req.body);
    expect(body['version'], 3);
    expect(body['latitud'], -1.25);
    expect(body['iata'], 'UIO');
  });
  testWidgets('Creación de aeropuerto no envía identificadores ni versión', (
    t,
  ) async {
    await abrir(t);
    await t.tap(find.byKey(const ValueKey('crear_aeropuertos')));
    await t.pumpAndSettle();
    for (final e in {
      'iata': 'cue',
      'nombre': 'Mariscal Lamar',
      'ciudad': 'Cuenca',
      'pais': 'Ecuador',
      'codigo_pais': 'ec',
      'latitud': '-2.889',
      'longitud': '-78.984',
    }.entries) {
      await t.enterText(find.byKey(ValueKey(e.key)), e.value);
    }
    await guardar(t);
    final req = mutation();
    expect(req.method, 'POST');
    final b = jsonDecode(req.body);
    expect(b['iata'], 'CUE');
    expect(b['codigo_pais'], 'EC');
    expect(b['zona_horaria'], 'America/Guayaquil');
    expect(b.containsKey('version'), false);
    expect(b.containsKey('id'), false);
  });
  testWidgets('Ruta usa FKs y rechaza origen igual a destino', (t) async {
    await abrir(t);
    await tab(t, 'Rutas');
    await editar(t, 'r1');
    await guardar(t);
    expect(jsonDecode(mutation().body), {
      'origen_id': 'a1',
      'destino_id': 'a2',
      'version': 2,
    });
    await editar(t, 'r1');
    await t.tap(find.byKey(const ValueKey('destino-a2')));
    await t.pumpAndSettle();
    await t.tap(find.text('UIO · Quito').last);
    await t.pumpAndSettle();
    await guardar(t);
    expect(
      find.text('El origen y el destino deben ser diferentes.'),
      findsOneWidget,
    );
  });
  testWidgets('Avión calcula cabina y no envía capacidad editable', (t) async {
    await abrir(t);
    await tab(t, 'Aviones');
    await editar(t, 'p1');
    expect(find.text('Capacidad total: 12 asientos'), findsOneWidget);
    await guardar(t);
    final b = jsonDecode(mutation().body);
    expect(b['version'], 4);
    expect(b.containsKey('capacidad_total'), false);
    expect(b['clases'][0]['columnas'], [
      ['A', 'B', 'C'],
      ['D', 'E', 'F'],
    ]);
  });
  testWidgets('Vuelo edita con centavos enteros, FKs y versión', (t) async {
    await abrir(t);
    await tab(t, 'Vuelos');
    await editar(t, 'f1');
    await t.enterText(find.byKey(const ValueKey('tarifa_ECO')), '100.05');
    await guardar(t);
    final b = jsonDecode(mutation().body);
    expect(b['version'], 7);
    expect(b['avion_id'], 'p1');
    expect(b['ruta_id'], 'r1');
    expect(b['tarifas'], [
      {'clase_codigo': 'ECO', 'precio_centavos': 10005},
    ]);
    expect(b.containsKey('asientos_disponibles'), false);
  });
  testWidgets('Calendario salida inicia mañana y formulario requiere fechas', (
    t,
  ) async {
    await abrir(t);
    await tab(t, 'Vuelos');
    await t.tap(find.byKey(const ValueKey('crear_vuelos')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('salida_local')));
    await t.pumpAndSettle();
    final picker = t.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    final now = DateTime.now();
    expect(picker.firstDate, DateTime(now.year, now.month, now.day + 1));
    await t.tap(find.text('Cancelar').last);
    await t.pumpAndSettle();
    expect(find.text('Guardar'), findsOneWidget);
  });
  testWidgets('Vuelo reservado bloquea editar y eliminar', (t) async {
    store['vuelos']!.first['tiene_reservas'] = true;
    await abrir(t);
    await tab(t, 'Vuelos');
    expect(
      t
          .widget<OutlinedButton>(find.byKey(const ValueKey('editar_f1')))
          .onPressed,
      isNull,
    );
    expect(
      t.widget<TextButton>(find.byKey(const ValueKey('eliminar_f1'))).onPressed,
      isNull,
    );
  });
  testWidgets('Conflicto descarta formulario, exige acuse y refresca', (
    t,
  ) async {
    await abrir(t);
    await editar(t, 'a1');
    conflict = 'version_conflicto';
    await guardar(t);
    expect(find.text('Los datos cambiaron'), findsOneWidget);
    expect(find.text('Guardar'), findsNothing);
    final before = requests.where((r) => r.method == 'GET').length;
    await t.tap(find.text('Entendido y actualizar'));
    await t.pumpAndSettle();
    expect(
      requests.where((r) => r.method == 'GET').length,
      greaterThan(before),
    );
    expect(find.text('Los datos cambiaron'), findsNothing);
  });
  testWidgets('Desactivar confirma y envía versión', (t) async {
    await abrir(t);
    await t.tap(find.byKey(const ValueKey('eliminar_a1')));
    await t.pumpAndSettle();
    expect(requests.where((r) => r.method == 'DELETE'), isEmpty);
    await t.tap(find.text('Confirmar'));
    await t.pumpAndSettle();
    expect(mutation().method, 'DELETE');
    expect(jsonDecode(mutation().body), {'version': 3});
  });
  testWidgets('Promoción de usuario requiere confirmación', (t) async {
    await abrir(t);
    await tab(t, 'Usuarios');
    await t.tap(find.text('Promover a ADMIN'));
    await t.pumpAndSettle();
    expect(requests.where((r) => r.method == 'POST'), isEmpty);
    await t.tap(find.text('Confirmar'));
    await t.pumpAndSettle();
    expect(mutation().url.path, '/api/admin/usuarios/u1/promover');
  });
  testWidgets('Catálogos vacíos conservan estados útiles y creación', (
    t,
  ) async {
    for (final key in store.keys.toList()) {
      store[key] = [];
    }
    await abrir(t);
    expect(find.text('Tu operación empieza aquí'), findsOneWidget);
    await tab(t, 'Vuelos');
    await t.tap(find.byKey(const ValueKey('crear_vuelos')));
    await t.pumpAndSettle();
    expect(
      find.text('Primero crea una ruta activa y un avión con cabina.'),
      findsOneWidget,
    );
    expect(find.byType(DropdownMenuItem<String>), findsNothing);
  });
  testWidgets('Cruce de zonas permite llegada civil anterior y delega UTC', (
    t,
  ) async {
    store['rutas']!.first['destino']['zona_horaria'] = 'America/Lima';
    store['vuelos']!.first['llegada_local'] = local(departure)
        .replaceFirst('09:00', '08:00');
    await abrir(t);
    await tab(t, 'Vuelos');
    await editar(t, 'f1');
    await guardar(t);
    expect(jsonDecode(mutation().body)['llegada_local'], endsWith('T08:00'));
  });
  testWidgets('Misma zona rechaza llegada anterior sin enviar mutación', (
    t,
  ) async {
    store['vuelos']!.first['llegada_local'] = local(departure)
        .replaceFirst('09:00', '08:00');
    await abrir(t);
    await tab(t, 'Vuelos');
    await editar(t, 'f1');
    await guardar(t);
    expect(
      find.text('La llegada debe ser posterior a la salida.'),
      findsOneWidget,
    );
    expect(requests.where((r) => r.method != 'GET'), isEmpty);
  });
  testWidgets('Bloqueo de catálogo del servidor deshabilita acciones', (
    t,
  ) async {
    store['aviones']!.first['bloqueado'] = true;
    store['aviones']!.first['motivo_bloqueo'] = 'Cabina con retención vigente';
    await abrir(t);
    await tab(t, 'Aviones');
    expect(find.text('Cabina con retención vigente'), findsOneWidget);
    expect(
      t
          .widget<OutlinedButton>(find.byKey(const ValueKey('editar_p1')))
          .onPressed,
      isNull,
    );
  });
  testWidgets(
    'Error de carga permite reintentar sin crear con datos ausentes',
    (t) async {
      errorCarga = true;
      await abrir(t);
      expect(find.text('Servicio no disponible'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.byKey(const ValueKey('crear_aeropuertos')),
            )
            .onPressed,
        isNull,
      );
      errorCarga = false;
      await t.tap(find.text('Reintentar'));
      await t.pumpAndSettle();
      expect(find.text('UIO · Mariscal Sucre'), findsOneWidget);
    },
  );
  testWidgets('Validación del servidor conserva formulario sin falso éxito', (
    t,
  ) async {
    await abrir(t);
    await editar(t, 'a1');
    conflict = 'iata_duplicado';
    estadoMutacion = 400;
    await guardar(t);
    expect(find.text('Versión obsoleta'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
    expect(find.text('Los datos cambiaron'), findsNothing);
  });
}
