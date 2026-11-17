abstract final class ValidacionOperaciones {
  static String? requerido(String? value) =>
      value == null || value.trim().isEmpty ? 'Campo obligatorio' : null;
  static int? centavos(String value) {
    if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(value.trim())) return null;
    final partes = value.trim().split('.');
    final total =
        int.parse(partes.first) * 100 +
        int.parse(partes.length == 1 ? '0' : partes.last.padRight(2, '0'));
    return total >= 50 ? total : null;
  }

  static String? coordenada(String? value, int limite) {
    final numero = double.tryParse(value ?? '');
    return numero == null || !numero.isFinite || numero.abs() > limite
        ? 'Entre -$limite y $limite'
        : null;
  }

  static int capacidad(Map<String, dynamic> clase) {
    final columnas = clase['columnas'] as List? ?? [];
    return (clase['filas'] as int? ?? 0) *
        columnas.fold<int>(0, (s, g) => s + (g as List).length);
  }

  static String? errorCabina(List<Map<String, dynamic>> clases) {
    if (clases.isEmpty) return 'Agrega al menos una clase.';
    final codigos = <String>{};
    final filasOcupadas = <int>{};
    var total = 0;
    for (final clase in clases) {
      final codigo = clase['codigo']?.toString() ?? '';
      if (!RegExp(r'^[A-Z0-9]{1,8}$').hasMatch(codigo) ||
          !codigos.add(codigo)) {
        return 'Los códigos de clase deben ser únicos.';
      }
      if (requerido(clase['nombre']?.toString()) != null) {
        return 'Indica el nombre de cada clase.';
      }
      final inicio = clase['fila_inicio'] as int? ?? 0;
      final filas = clase['filas'] as int? ?? 0;
      if (inicio < 1 || filas < 1 || inicio + filas > 1001) {
        return 'Filas positivas, máximo 1000.';
      }
      for (var n = inicio; n < inicio + filas; n++) {
        if (!filasOcupadas.add(n)) {
          return 'Las filas de las clases no pueden solaparse.';
        }
      }
      final letras = <String>{};
      final grupos = clase['columnas'] as List? ?? [];
      if (grupos.isEmpty) return 'Indica las columnas de cada clase.';
      for (final grupo in grupos) {
        if ((grupo as List).isEmpty) return 'Cada grupo debe incluir columnas.';
        for (final letra in grupo) {
          if (!RegExp(r'^[A-Z]$').hasMatch(letra.toString()) ||
              !letras.add(letra.toString())) {
            return 'Columnas A–Z sin letras repetidas en cada clase.';
          }
        }
      }
      total += capacidad(clase);
    }
    return total < 1 || total > 1000
        ? 'La capacidad total debe ser de 1 a 1000 asientos.'
        : null;
  }
}
