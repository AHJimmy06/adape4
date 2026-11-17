// Reglas de entrada equivalentes a backend/services.py.
class ValidacionesAutenticacion {
  // Python str.strip e \s incluyen separadores que Dart trata distinto.
  static const _espaciosPython =
      r'\u0009-\u000D\u001C-\u0020\u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000';
  static final _bordes = RegExp(
    '^[$_espaciosPython]+|[$_espaciosPython]+'
    r'$',
  );
  static final _correo = RegExp(
    '^[^$_espaciosPython@]+@[^$_espaciosPython@]+'
    r'\.'
    '[^$_espaciosPython@]+'
    r'$',
  );

  static String recortarComoApi(String valor) => valor.replaceAll(_bordes, '');

  static String? nombre(String? valor) {
    final nombre = recortarComoApi(valor ?? '');
    if (nombre.isEmpty) return 'Ingresa tu nombre';
    if (nombre.runes.length > 120) {
      return 'El nombre no puede superar 120 caracteres';
    }
    return null;
  }

  static String? correo(String? valor) {
    final correo = recortarComoApi(valor ?? '');
    if (correo.isEmpty) return 'Ingresa tu correo';
    if (!_correo.hasMatch(correo)) {
      return 'Ingresa un correo electrónico válido';
    }
    return null;
  }

  static String? contrasenaRegistro(String? valor) {
    final longitud = (valor ?? '').runes.length;
    return longitud < 10 || longitud > 256
        ? 'Usa entre 10 y 256 caracteres'
        : null;
  }

  static String? contrasenaLogin(String? valor) =>
      valor == null || valor.isEmpty ? 'Ingresa tu contraseña' : null;
}
