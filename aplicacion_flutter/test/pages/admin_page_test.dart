import 'dart:convert';

import 'package:aplicacion_flutter/models/usuario.dart';
import 'package:aplicacion_flutter/models/vuelo.dart';
import 'package:aplicacion_flutter/pages/admin_page.dart';
import 'package:aplicacion_flutter/services/api_service.dart';
import 'package:aplicacion_flutter/theme/aerotech_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeAdminApi extends ApiService {
  bool admin = true;
  int promotions = 0;
  int creations = 0;
  int searches = 0;
  int edits = 0;
  int deletions = 0;
  int? sentVersion;
  String? mutationCode;
  List<Vuelo> flights = [
    Vuelo.fromJson({
      'id': 'v1',
      'origen': 'Quito, Ecuador',
      'destino': 'Lima, Perú',
      'fecha': DateTime.now()
          .add(const Duration(days: 2))
          .toIso8601String()
          .substring(0, 10),
      'hora_salida': '09:00:00',
      'hora_llegada': '11:00:00',
      'precio': 99.5,
      'asientos_disponibles': 0,
      'version': 4,
    }),
  ];
  @override
  Future<List<Vuelo>> buscarVuelos({
    String? origen,
    String? destino,
    String? fecha,
  }) async {
    searches++;
    return flights;
  }

  @override
  Future<Vuelo> actualizarVuelo({
    required String id,
    required int version,
    required String origen,
    required String destino,
    required String fecha,
    required String horaSalida,
    required String horaLlegada,
    required double precio,
    required int asientosDisponibles,
  }) async {
    edits++;
    sentVersion = version;
    if (mutationCode != null) {
      throw ExcepcionApi('Conflicto', codigo: 409, codigoError: mutationCode);
    }
    expect(asientosDisponibles, 0);
    final flight = Vuelo.fromJson({
      'id': id,
      'origen': origen,
      'destino': destino,
      'fecha': fecha,
      'hora_salida': horaSalida,
      'hora_llegada': horaLlegada,
      'precio': precio,
      'asientos_disponibles': asientosDisponibles,
      'version': version + 1,
    });
    flights = [flight];
    return flight;
  }

  @override
  Future<Map<String, dynamic>> eliminarVuelo(
    String id, {
    required int version,
  }) async {
    deletions++;
    sentVersion = version;
    if (mutationCode != null) {
      throw ExcepcionApi('Conflicto', codigo: 409, codigoError: mutationCode);
    }
    flights = [];
    return {'mensaje': 'Vuelo eliminado correctamente.'};
  }

  int? error;
  List<Usuario> users = [
    const Usuario(id: 'u2', nombre: 'Ana', correo: 'ana@example.com'),
  ];
  @override
  bool get esAdministrador => admin;
  @override
  Future<Usuario> obtenerPerfil() async {
    admin = true;
    return const Usuario(
      id: 'u1',
      nombre: 'Admin',
      correo: 'admin@example.com',
      rol: 'ADMIN',
    );
  }

  @override
  Future<List<Usuario>> listarUsuarios() async {
    if (error != null) throw ExcepcionApi('Operación rechazada', codigo: error);
    return users;
  }

  @override
  Future<Usuario> promoverUsuario(String id) async {
    if (error != null) throw ExcepcionApi('Operación rechazada', codigo: error);
    promotions++;
    return Usuario(
      id: id,
      nombre: 'Ana',
      correo: 'ana@example.com',
      rol: 'ADMIN',
    );
  }

  @override
  Future<Vuelo> crearVuelo({
    required String origen,
    required String destino,
    required String fecha,
    required String horaSalida,
    required String horaLlegada,
    required double precio,
    required int asientosDisponibles,
  }) async {
    if (error != null) throw ExcepcionApi('Operación rechazada', codigo: error);
    creations++;
    expect(origen, 'Quito, Ecuador');
    expect(destino, 'Lima, Perú');
    expect(precio, 99.5);
    expect(asientosDisponibles, 20);
    return Vuelo(
      id: 'v',
      origen: origen,
      destino: destino,
      fecha: fecha,
      horaSalida: horaSalida,
      horaLlegada: horaLlegada,
      precio: precio,
      asientosDisponibles: asientosDisponibles,
    );
  }
}

Future<void> open(WidgetTester tester, ApiService api) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AerotechTheme.light,
      home: AdminPage(apiService: api),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> fillFlight(WidgetTester tester) async {
  final values = [
    'Quito, Ecuador',
    'Lima, Perú',
    DateTime.now()
        .add(const Duration(days: 2))
        .toIso8601String()
        .substring(0, 10),
    '09:00',
    '11:00',
    '99.5',
    '20',
  ];
  for (var i = 0; i < values.length; i++) {
    final field = find.byKey(ValueKey('flight-field-$i'));
    await tester.ensureVisible(field);
    if (i == 2) {
      tester.widget<TextFormField>(field).controller!.text = values[i];
      await tester.pump();
    } else {
      await tester.enterText(field, values[i]);
    }
  }
}

void main() {
  testWidgets('editar conserva version y permite cero asientos restantes', (
    tester,
  ) async {
    final api = FakeAdminApi();
    await open(tester, api);
    expect(api.searches, 1);
    await tapVisible(tester, find.byKey(const ValueKey('edit-flight-v1')));
    expect(find.text('Editar vuelo'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('flight-field-3')))
          .controller!
          .text,
      '09:00',
    );
    await tapVisible(tester, find.text('Guardar cambios'));
    expect(api.edits, 1);
    expect(api.sentVersion, 4);
    expect(api.searches, 2);
    expect(find.text('Vuelo actualizado correctamente.'), findsOneWidget);
    expect(find.text('Editar vuelo'), findsNothing);
  });
  testWidgets('edicion obsoleta avisa y refresca al aceptar sin reenviar', (
    tester,
  ) async {
    final api = FakeAdminApi()..mutationCode = 'vuelo_modificado';
    await open(tester, api);
    await tapVisible(tester, find.byKey(const ValueKey('edit-flight-v1')));
    await tapVisible(tester, find.text('Guardar cambios'));
    expect(find.text('El vuelo cambió'), findsOneWidget);
    expect(api.searches, 1);
    expect(api.edits, 1);
    await tapVisible(tester, find.text('Aceptar'));
    expect(api.searches, 2);
    expect(api.edits, 1);
    expect(find.text('Editar vuelo'), findsNothing);
    expect(find.text('Vuelo actualizado correctamente.'), findsNothing);
  });
  testWidgets('eliminacion requiere confirmar, envia version y refresca', (
    tester,
  ) async {
    final api = FakeAdminApi();
    await open(tester, api);
    await tapVisible(tester, find.byKey(const ValueKey('delete-flight-v1')));
    await tapVisible(tester, find.text('Cancelar'));
    expect(api.deletions, 0);
    await tapVisible(tester, find.byKey(const ValueKey('delete-flight-v1')));
    await tapVisible(tester, find.text('Eliminar vuelo'));
    expect(api.deletions, 1);
    expect(api.sentVersion, 4);
    expect(api.searches, 2);
    expect(find.byKey(const ValueKey('delete-flight-v1')), findsNothing);
  });
  testWidgets(
    'eliminacion obsoleta refresca sin reintentar ni quitar el vuelo',
    (tester) async {
      final api = FakeAdminApi()..mutationCode = 'vuelo_modificado';
      await open(tester, api);
      await tapVisible(tester, find.byKey(const ValueKey('delete-flight-v1')));
      await tapVisible(tester, find.text('Eliminar vuelo'));
      expect(find.text('El vuelo cambió'), findsOneWidget);
      expect(api.searches, 1);
      expect(api.deletions, 1);
      await tapVisible(tester, find.text('Aceptar'));
      expect(api.searches, 2);
      expect(api.deletions, 1);
      expect(find.byKey(const ValueKey('delete-flight-v1')), findsOneWidget);
      expect(find.text('Vuelo eliminado correctamente.'), findsNothing);
    },
  );

  testWidgets('reservas activas bloquean eliminar y refrescan tras aceptar', (
    tester,
  ) async {
    final api = FakeAdminApi()..mutationCode = 'vuelo_con_reservas';
    await open(tester, api);
    await tapVisible(tester, find.byKey(const ValueKey('delete-flight-v1')));
    await tapVisible(tester, find.text('Eliminar vuelo'));
    expect(find.text('No se puede eliminar este vuelo'), findsOneWidget);
    expect(api.searches, 1);
    await tapVisible(tester, find.text('Aceptar'));
    expect(api.searches, 2);
    expect(api.deletions, 1);
    expect(find.byKey(const ValueKey('delete-flight-v1')), findsOneWidget);
    expect(find.text('Vuelo eliminado correctamente.'), findsNothing);
  });
  for (final primero in [3, 4]) {
    testWidgets('horas con espacios se comparan editando primero $primero', (
      tester,
    ) async {
      await open(tester, FakeAdminApi());
      final segundo = primero == 3 ? 4 : 3;
      for (final index in [primero, segundo]) {
        final campo = find.byKey(ValueKey('flight-field-$index'));
        await tester.ensureVisible(campo);
        await tester.enterText(campo, index == 3 ? ' 12:00 ' : ' 11:00 ');
      }
      await tester.pumpAndSettle();
      expect(
        find.text('La llegada debe ser posterior a la salida.'),
        findsNWidgets(2),
      );
      final campo = find.byKey(const ValueKey('flight-field-4'));
      await tester.ensureVisible(campo);
      await tester.enterText(campo, ' 13:00 ');
      await tester.pumpAndSettle();
      expect(
        find.text('La llegada debe ser posterior a la salida.'),
        findsNothing,
      );
    });
  }

  testWidgets('controles en vivo bloquean letras y calendario solo futuro', (
    tester,
  ) async {
    await open(tester, FakeAdminApi());
    expect(find.text('Campo obligatorio.'), findsNWidgets(7));
    final precio = find.byKey(const ValueKey('flight-field-5'));
    await tester.ensureVisible(precio);
    await tester.enterText(precio, '25.50');
    await tester.enterText(precio, 'letras');
    expect(tester.widget<TextFormField>(precio).controller!.text, '25.50');
    final asientos = find.byKey(const ValueKey('flight-field-6'));
    await tester.ensureVisible(asientos);
    await tester.enterText(asientos, '12');
    await tester.enterText(asientos, 'abc');
    expect(tester.widget<TextFormField>(asientos).controller!.text, '12');
    final llegada = find.byKey(const ValueKey('flight-field-4'));
    final salida = find.byKey(const ValueKey('flight-field-3'));
    await tester.ensureVisible(llegada);
    await tester.enterText(llegada, '10:00');
    await tester.ensureVisible(salida);
    await tester.enterText(salida, '11:00');
    await tester.pumpAndSettle();
    expect(
      find.text('La llegada debe ser posterior a la salida.'),
      findsNWidgets(2),
    );
    await tester.enterText(salida, '09:00');
    await tester.pumpAndSettle();
    expect(
      find.text('La llegada debe ser posterior a la salida.'),
      findsNothing,
    );
    final fecha = find.byKey(const ValueKey('flight-field-2'));
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: fecha, matching: find.byType(TextField)),
          )
          .readOnly,
      isTrue,
    );
    await tapVisible(tester, find.byTooltip('Elegir fecha'));
    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    final ahora = DateTime.now().toUtc().subtract(const Duration(hours: 5));
    expect(picker.firstDate, DateTime(ahora.year, ahora.month, ahora.day + 1));
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(fecha).controller!.text, isNotEmpty);
  });

  testWidgets(
    'un token no permite ver el panel; actualizar perfil habilita promoción recibida',
    (tester) async {
      final api = ApiService(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'usuario': {
                'id': 'u',
                'nombre': 'Admin',
                'correo': 'a@b.c',
                'rol': 'ADMIN',
              },
            }),
            200,
          ),
        ),
      )..establecerToken('token');
      await open(tester, api);
      expect(
        find.text('Acceso exclusivo para administradores.'),
        findsOneWidget,
      );
      expect(find.text('Crear vuelo'), findsNothing);
      // A second mock response must contain a user list to finish refreshing.
      final fake = FakeAdminApi()..admin = false;
      await open(tester, fake);
      await tapVisible(tester, find.text('Actualizar perfil'));
      expect(find.text('Crear vuelo'), findsOneWidget);
    },
  );
  testWidgets('formulario valida y crea un vuelo sin desbordes a 320x640', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeAdminApi();
    await open(tester, api);
    await tapVisible(tester, find.text('Guardar vuelo'));
    expect(api.creations, 0);
    expect(find.text('Campo obligatorio.'), findsNWidgets(7));
    await fillFlight(tester);
    await tapVisible(tester, find.text('Guardar vuelo'));
    expect(api.creations, 1);
    expect(find.text('Vuelo creado correctamente.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('promoción requiere confirmación y actualiza rol', (
    tester,
  ) async {
    final api = FakeAdminApi();
    await open(tester, api);
    await tapVisible(tester, find.text('Convertir en administrador'));
    expect(find.text('¿Convertir en administrador?'), findsOneWidget);
    await tapVisible(tester, find.text('Cancelar'));
    expect(api.promotions, 0);
    await tapVisible(tester, find.text('Convertir en administrador'));
    await tapVisible(tester, find.text('Confirmar'));
    expect(api.promotions, 1);
    expect(find.text('ADMIN'), findsOneWidget);
    expect(find.text('Convertir en administrador'), findsNothing);
  });
  testWidgets('403 bloquea acciones y 409 muestra error sin éxito falso', (
    tester,
  ) async {
    final api = FakeAdminApi();
    await open(tester, api);
    api.error = 409;
    await tapVisible(tester, find.text('Convertir en administrador'));
    await tapVisible(tester, find.text('Confirmar'));
    expect(find.text('Operación rechazada'), findsOneWidget);
    expect(api.promotions, 0);
    expect(find.text('Convertir en administrador'), findsOneWidget);
    api.error = 403;
    await tapVisible(tester, find.byTooltip('Actualizar usuarios'));
    expect(find.text('Acceso exclusivo para administradores.'), findsOneWidget);
    expect(find.text('Crear vuelo'), findsNothing);
  });
  testWidgets(
    'rechaza país ausente, fecha inexistente, horas y valores inválidos',
    (tester) async {
      final api = FakeAdminApi();
      await open(tester, api);
      final values = [
        'Quito',
        'Lima',
        '2026-02-30',
        '25:00',
        '09:99',
        'NaN',
        '0',
      ];
      for (var i = 0; i < values.length; i++) {
        final field = find.byKey(ValueKey('flight-field-$i'));
        await tester.ensureVisible(field);
        if (i == 2) {
          tester.widget<TextFormField>(field).controller!.text = values[i];
          await tester.pump();
        } else {
          await tester.enterText(field, values[i]);
        }
      }
      await tapVisible(tester, find.text('Guardar vuelo'));
      expect(api.creations, 0);
      expect(
        find.text('Usa el formato Ciudad, País (máximo 240 caracteres).'),
        findsNWidgets(2),
      );
      expect(
        find.text('Selecciona una fecha válida en el calendario.'),
        findsOneWidget,
      );
      expect(find.text('Usa una hora válida HH:MM.'), findsNWidgets(2));
      expect(find.text('Campo obligatorio.'), findsOneWidget);
      expect(
        find.text('Ingresa entre 1 y 2147483647 asientos.'),
        findsOneWidget,
      );
    },
  );
}
