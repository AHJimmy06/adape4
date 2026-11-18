import 'dart:convert';
import 'dart:math';

String nuevaClaveOperacion() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

String dinero(dynamic cents) {
  final n = (cents as num?)?.toInt() ?? 0;
  return 'USD ${n ~/ 100}.${(n.abs() % 100).toString().padLeft(2, '0')}';
}

class CheckoutOperacion {
  String? _payload, _key;
  String preparar(
    String vuelo,
    List<String> codes, {
    List<Map<String, dynamic>>? pasajeros,
  }) {
    final sorted = [...codes]..sort();
    final normalizados =
        pasajeros?.map((p) {
          final correo = p['correo_usuario']?.toString().trim().toLowerCase();
          return {
            'asiento': p['asiento'],
            'correo_usuario': correo == null || correo.isEmpty ? null : correo,
            'categoria': correo != null && correo.isNotEmpty
                ? 'adulto'
                : p['categoria'] ?? 'adulto',
            'maletas_adicionales': p['maletas_adicionales'] ?? 0,
          };
        }).toList()?..sort(
          (a, b) => a['asiento'].toString().compareTo(b['asiento'].toString()),
        );
    final payload = jsonEncode([
      vuelo,
      sorted,
      if (pasajeros != null) normalizados,
    ]);
    if (payload != _payload) {
      _payload = payload;
      _key = nuevaClaveOperacion();
    }
    return _key!;
  }

  void limpiar() {
    _payload = null;
    _key = null;
  }
}
