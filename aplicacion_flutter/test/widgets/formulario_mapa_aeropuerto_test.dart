import 'package:aplicacion_flutter/widgets/sistema_admin/formulario_operacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const aeropuerto = <String, dynamic>{
  'id': 'a1',
  'version': 7,
  'iata': 'UIO',
  'nombre': 'Mariscal Sucre',
  'ciudad': 'Quito',
  'pais': 'Ecuador',
  'codigo_pais': 'EC',
  'latitud': -0.129167,
  'longitud': -78.3575,
  'zona_horaria': 'America/Guayaquil',
  'capacidad_aterrizajes': 10,
  'franja_minutos': 60,
};

void main() {
  Future<void> formulario(
    WidgetTester t, {
    Future<void> Function(Registro)? guardar,
    ValueChanged<LatLng>? centro,
  }) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormularioOperacion(
            recurso: 'aeropuertos',
            registro: aeropuerto,
            catalogos: const {},
            guardar: guardar ?? (_) async {},
            mapaAeropuertoBuilder: (_, punto, seleccionar) {
              centro?.call(punto);
              return Center(
                child: TextButton(
                  onPressed: () => seleccionar(const LatLng(-2.1574, -79.8836)),
                  child: const Text('Elegir Guayaquil'),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String valor(WidgetTester t, String clave) =>
      t.widget<TextFormField>(find.byKey(ValueKey(clave))).controller!.text;
  Future<void> abrirMapa(WidgetTester t) async {
    final boton = find.byKey(const ValueKey('elegir_ubicacion_mapa'));
    await t.ensureVisible(boton);
    await t.tap(boton);
    await t.pumpAndSettle();
  }

  testWidgets('crear aeropuerto permite elegir coordenadas desde un mapa', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormularioOperacion(
            recurso: 'aeropuertos',
            catalogos: const {},
            guardar: (_) async {},
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('elegir_ubicacion_mapa')), findsOneWidget);
    expect(find.byKey(const ValueKey('latitud')), findsOneWidget);
    expect(find.byKey(const ValueKey('longitud')), findsOneWidget);
  });

  testWidgets(
    'confirmar actualiza ambas coordenadas y conserva contrato al guardar',
    (t) async {
      Registro? enviado;
      LatLng? centro;
      await formulario(
        t,
        guardar: (p) async => enviado = p,
        centro: (p) => centro = p,
      );
      await abrirMapa(t);
      expect(centro, const LatLng(-0.129167, -78.3575));
      await t.tap(find.text('Elegir Guayaquil'));
      await t.pump();
      await t.tap(find.text('Usar ubicación'));
      await t.pumpAndSettle();
      expect(valor(t, 'latitud'), '-2.157400');
      expect(valor(t, 'longitud'), '-79.883600');
      expect(valor(t, 'zona_horaria'), 'America/Guayaquil');
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();
      expect(enviado?['latitud'], -2.1574);
      expect(enviado?['longitud'], -79.8836);
      expect(enviado?['capacidad_aterrizajes'], 10);
      expect(enviado?['franja_minutos'], 60);
      expect(enviado?['version'], 7);
    },
  );

  testWidgets('cancelar mapa mantiene valores del formulario', (t) async {
    await formulario(t);
    await abrirMapa(t);
    await t.tap(find.text('Elegir Guayaquil'));
    await t.pump();
    await t.tap(find.widgetWithText(TextButton, 'Cancelar').last);
    await t.pumpAndSettle();
    expect(valor(t, 'latitud'), '-0.129167');
    expect(valor(t, 'longitud'), '-78.3575');
  });

  testWidgets('ingreso manual sigue validando rangos antes de guardar', (
    t,
  ) async {
    var guardado = false;
    await formulario(t, guardar: (_) async => guardado = true);
    final latitud = find.byKey(const ValueKey('latitud'));
    await t.ensureVisible(latitud);
    await t.enterText(latitud, '91');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(guardado, isFalse);
    expect(find.text('Entre -90 y 90'), findsOneWidget);
  });
}
