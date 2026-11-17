import 'package:aplicacion_flutter/models/usuario.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('roles desconocidos no conceden administración', () {
    for (final role in [null, 'admin', 'OWNER', 'USER']) {
      final user = Usuario.fromJson({
        'id': '1',
        'nombre': 'Ana',
        'correo': 'a@b.c',
        'rol': role,
      });
      expect(user.rol, 'USER');
      expect(user.esAdministrador, isFalse);
    }
    expect(
      Usuario.fromJson({
        'id': '1',
        'nombre': 'Ana',
        'correo': 'a@b.c',
        'rol': 'ADMIN',
      }).esAdministrador,
      isTrue,
    );
  });
}
