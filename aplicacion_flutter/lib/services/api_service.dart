import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/reserva.dart';
import '../models/vuelo.dart';

class ApiService {
  ApiService({http.Client? client, Uri? baseUrl})
    : _cliente = client ?? http.Client(),
      _urlBase =
          baseUrl ??
          Uri.parse(
            const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: 'http://10.0.2.2:5000',
            ),
          );

  final http.Client _cliente;
  final Uri _urlBase;
  String? _token;

  void establecerToken(String token) => _token = token;

  void cerrarSesion() => _token = null;

  Future<Map<String, dynamic>> registrarUsuario({
    required String nombre,
    required String correo,
    required String contrasena,
  }) {
    return _enviarMapa(
      'POST',
      '/api/usuarios/registro',
      cuerpo: {'nombre': nombre, 'correo': correo, 'contrasena': contrasena},
    );
  }

  Future<Map<String, dynamic>> iniciarSesion({
    required String correo,
    required String contrasena,
  }) async {
    final respuesta = await _enviarMapa(
      'POST',
      '/api/auth/login',
      cuerpo: {'correo': correo, 'contrasena': contrasena},
    );
    final token = respuesta['token'] ?? respuesta['access_token'];
    if (token is! String || token.isEmpty) {
      throw const ExcepcionApi('La respuesta no incluyó un token de acceso.');
    }
    _token = token;
    return respuesta;
  }

  Future<List<Vuelo>> buscarVuelos({
    String? origen,
    String? destino,
    String? fecha,
  }) async {
    final parametros = <String, String>{};
    if (origen != null && origen.trim().isNotEmpty) {
      parametros['origen'] = origen.trim();
    }
    if (destino != null && destino.trim().isNotEmpty) {
      parametros['destino'] = destino.trim();
    }
    if (fecha != null && fecha.trim().isNotEmpty) {
      parametros['fecha'] = fecha.trim();
    }
    final respuesta = await _cliente.get(
      _url('/api/vuelos', parametros: parametros),
      headers: _encabezados(),
    );
    final datos = _decodificar(respuesta);
    final lista = datos is List
        ? datos
        : (datos as Map<String, dynamic>)['vuelos'];
    if (lista is! List) {
      throw const ExcepcionApi(
        'La respuesta de vuelos no tiene un formato válido.',
      );
    }
    return lista
        .map(
          (elemento) =>
              Vuelo.fromJson(Map<String, dynamic>.from(elemento as Map)),
        )
        .toList();
  }

  Future<Map<String, dynamic>> reservarVuelo({
    required String vueloId,
    int cantidad = 1,
  }) {
    return _enviarMapa(
      'POST',
      '/api/reservas',
      requiereToken: true,
      cuerpo: {'vuelo_id': vueloId, 'cantidad': cantidad},
    );
  }

  Future<List<Reserva>> obtenerReservas() async {
    final respuesta = await _cliente.get(
      _url('/api/reservas'),
      headers: _encabezados(requiereToken: true),
    );
    final datos = _decodificar(respuesta);
    final lista = datos is List
        ? datos
        : (datos as Map<String, dynamic>)['reservas'];
    if (lista is! List) {
      throw const ExcepcionApi(
        'La respuesta de reservas no tiene un formato válido.',
      );
    }
    return lista
        .map(
          (elemento) =>
              Reserva.fromJson(Map<String, dynamic>.from(elemento as Map)),
        )
        .toList();
  }

  Future<void> cancelarReserva(String reservaId) async {
    final respuesta = await _cliente.delete(
      _url('/api/reservas/$reservaId'),
      headers: _encabezados(requiereToken: true),
    );
    _decodificar(respuesta);
  }

  Future<String> obtenerComprobanteXml(String reservaId) async {
    final encabezados = _encabezados(requiereToken: true)
      ..['Accept'] = 'application/xml';
    final respuesta = await _cliente.get(
      _url('/api/reservas/${Uri.encodeComponent(reservaId)}/comprobante.xml'),
      headers: encabezados,
    );
    if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
      _decodificar(respuesta);
    }
    if (!(respuesta.headers['content-type'] ?? '').toLowerCase().startsWith(
      'application/xml',
    )) {
      throw const ExcepcionApi('El comprobante no se recibio en formato XML.');
    }
    return utf8.decode(respuesta.bodyBytes);
  }

  Future<Map<String, dynamic>> _enviarMapa(
    String metodo,
    String ruta, {
    Map<String, dynamic>? cuerpo,
    bool requiereToken = false,
  }) async {
    final solicitud = http.Request(metodo, _url(ruta));
    solicitud.headers.addAll(_encabezados(requiereToken: requiereToken));
    if (cuerpo != null) solicitud.body = jsonEncode(cuerpo);
    final flujo = await _cliente.send(solicitud);
    final respuesta = await http.Response.fromStream(flujo);
    final datos = _decodificar(respuesta);
    if (datos is Map<String, dynamic>) return datos;
    return {'resultado': datos};
  }

  dynamic _decodificar(http.Response respuesta) {
    final texto = utf8.decode(respuesta.bodyBytes);
    dynamic datos;
    if (texto.trim().isNotEmpty) {
      try {
        datos = jsonDecode(texto);
      } on FormatException {
        datos = {'mensaje': texto};
      }
    } else {
      datos = <String, dynamic>{};
    }
    if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
      final mapa = datos is Map<String, dynamic>
          ? datos
          : const <String, dynamic>{};
      final detalle = mapa['error'];
      final mensaje = detalle is Map<String, dynamic>
          ? detalle['mensaje'] ?? detalle['codigo']
          : detalle ?? mapa['mensaje'] ?? 'Error ${respuesta.statusCode}';
      throw ExcepcionApi(mensaje.toString(), codigo: respuesta.statusCode);
    }
    return datos;
  }

  Map<String, String> _encabezados({bool requiereToken = false}) {
    final encabezados = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (requiereToken) {
      final token = _token;
      if (token == null || token.isEmpty) {
        throw const ExcepcionApi('Inicia sesión para continuar.');
      }
      encabezados['Authorization'] = 'Bearer $token';
    }
    return encabezados;
  }

  Uri _url(String ruta, {Map<String, String>? parametros}) {
    final base = _urlBase.toString().replaceFirst(RegExp(r'/$'), '');
    return Uri.parse('$base$ruta').replace(queryParameters: parametros);
  }
}

class ExcepcionApi implements Exception {
  const ExcepcionApi(this.mensaje, {this.codigo});

  final String mensaje;
  final int? codigo;

  @override
  String toString() => mensaje;
}
