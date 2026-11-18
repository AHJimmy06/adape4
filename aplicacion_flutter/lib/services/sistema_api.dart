import 'api_service.dart';

class SistemaApi {
  SistemaApi(this.apiService);
  final ApiService apiService;

  String _ruta(String ruta) => ruta.startsWith('/api/')
      ? ruta
      : '/api/sistema${ruta.startsWith('/') ? ruta : '/$ruta'}';

  Future<Map<String, dynamic>> _pedir(
    String metodo,
    String ruta, {
    Map<String, dynamic>? body,
    Map<String, String>? parametros,
    bool requiereToken = true,
  }) async {
    final datos = await apiService.solicitarSistema(
      metodo,
      _ruta(ruta),
      cuerpo: body,
      parametros: parametros,
      requiereToken: requiereToken,
    );
    if (datos is Map<String, dynamic>) return datos;
    throw const ExcepcionApi('El servicio devolvió un formato no válido.');
  }

  Future<Map<String, dynamic>> get(
    String ruta, {
    Map<String, String>? parametros,
    bool requiereToken = true,
  }) =>
      _pedir('GET', ruta, parametros: parametros, requiereToken: requiereToken);
  Future<List<Map<String, dynamic>>> lista(
    String ruta,
    String clave, {
    Map<String, String>? parametros,
    bool requiereToken = true,
  }) async {
    final datos = await get(
      ruta,
      parametros: parametros,
      requiereToken: requiereToken,
    );
    final lista = datos[clave];
    if (lista is! List) {
      throw const ExcepcionApi('El servicio no devolvió la lista solicitada.');
    }
    return lista.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> post(
    String ruta, {
    Map<String, dynamic>? body,
  }) => _pedir('POST', ruta, body: body);
  Future<Map<String, dynamic>> put(String ruta, {Map<String, dynamic>? body}) =>
      _pedir('PUT', ruta, body: body);
  Future<Map<String, dynamic>> delete(
    String ruta, {
    Map<String, dynamic>? body,
  }) => _pedir('DELETE', ruta, body: body);
  Future<String> xml(String ruta) =>
      apiService.solicitarXmlSistema(_ruta(ruta));
}
