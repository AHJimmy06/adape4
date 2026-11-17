import 'package:aplicacion_flutter/validators/validaciones_autenticacion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizacion conserva FEFF y recorta todos los espacios Python', () {
    final puntos = [
      9,
      10,
      11,
      12,
      13,
      28,
      29,
      30,
      31,
      32,
      133,
      160,
      5760,
      ...List.generate(11, (i) => 8192 + i),
      8232,
      8233,
      8239,
      8287,
      12288,
    ];
    for (final punto in puntos) {
      final espacio = String.fromCharCode(punto);
      expect(
        ValidacionesAutenticacion.recortarComoApi(
          '${espacio}a@example.test$espacio',
        ),
        'a@example.test',
      );
      expect(
        ValidacionesAutenticacion.correo('a${espacio}b@example.test'),
        isNotNull,
      );
    }
    expect(
      ValidacionesAutenticacion.recortarComoApi('\ufeffa@example.test\ufeff'),
      '\ufeffa@example.test\ufeff',
    );
  });

  test('espacios Python rechazan U0085 y U001C internos y conservan FEFF', () {
    for (final espacio in ['\u0085', '\u001c']) {
      expect(ValidacionesAutenticacion.nombre(espacio), isNotNull);
      expect(
        ValidacionesAutenticacion.correo('a${espacio}b@example.test'),
        isNotNull,
      );
      expect(
        ValidacionesAutenticacion.correo('${espacio}a@example.test$espacio'),
        isNull,
      );
    }
    expect(ValidacionesAutenticacion.nombre('\ufeff'), isNull);
    expect(ValidacionesAutenticacion.correo('a\ufeffb@example.test'), isNull);
    expect(ValidacionesAutenticacion.nombre('\ufeff${'x' * 120}'), isNotNull);
  });

  test(
    'registro aplica límites de contraseña de la API sin recortar espacios',
    () {
      for (final longitud in [0, 8, 9, 257]) {
        expect(
          ValidacionesAutenticacion.contrasenaRegistro('x' * longitud),
          isNotNull,
        );
      }
      for (final longitud in [10, 256]) {
        expect(
          ValidacionesAutenticacion.contrasenaRegistro('x' * longitud),
          isNull,
        );
      }
      expect(ValidacionesAutenticacion.contrasenaRegistro(' ' * 10), isNull);
      expect(ValidacionesAutenticacion.contrasenaRegistro('😀' * 10), isNull);
      expect(ValidacionesAutenticacion.contrasenaRegistro('😀' * 256), isNull);
      expect(
        ValidacionesAutenticacion.contrasenaRegistro('😀' * 257),
        isNotNull,
      );
    },
  );
  test('login conserva contraseña no vacía sin imponer mínimo de registro', () {
    expect(ValidacionesAutenticacion.contrasenaLogin(''), isNotNull);
    expect(ValidacionesAutenticacion.contrasenaLogin(null), isNotNull);
    for (final valor in ['x', '123456789', ' ']) {
      expect(ValidacionesAutenticacion.contrasenaLogin(valor), isNull);
    }
  });
  test('nombre equivale a longitud recortada entre uno y ciento veinte', () {
    expect(ValidacionesAutenticacion.nombre('   '), isNotNull);
    expect(ValidacionesAutenticacion.nombre(null), isNotNull);
    expect(ValidacionesAutenticacion.nombre('  A  '), isNull);
    expect(ValidacionesAutenticacion.nombre('x' * 120), isNull);
    expect(ValidacionesAutenticacion.nombre('x' * 121), isNotNull);
    expect(ValidacionesAutenticacion.nombre('😀' * 120), isNull);
    expect(ValidacionesAutenticacion.nombre('😀' * 121), isNotNull);
  });
  test('correo requiere partes con arroba y punto sin espacios interiores', () {
    for (final valor in [null, '', 'a', 'a@b', 'a@@b.test', 'a b@c.test']) {
      expect(ValidacionesAutenticacion.correo(valor), isNotNull);
    }
    expect(ValidacionesAutenticacion.correo(' A@B.test '), isNull);
  });
}
