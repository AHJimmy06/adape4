import 'dart:io';
import 'dart:typed_data';

import 'package:aplicacion_flutter/utils/modelo_ruta_archivo_io.dart';
import 'package:aplicacion_flutter/utils/modelo_ruta_archivo_web.dart' as web;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'native source is owned temporary GLB with exact bytes and cleanup',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final model = await ModeloRutaArchivo.crear(bytes);
      final file = File.fromUri(Uri.parse(model.src));
      expect(file.readAsBytesSync(), orderedEquals(bytes));
      expect(file.path, endsWith('route.glb'));
      await model.dispose();
      expect(file.existsSync(), isFalse);
      expect(file.parent.existsSync(), isFalse);
      await model.dispose();
    },
  );
  test('web source contains the exact derived binary', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final model = await web.ModeloRutaArchivo.crear(bytes);
    expect(Uri.parse(model.src).data!.contentAsBytes(), orderedEquals(bytes));
    await model.dispose();
  });
}
