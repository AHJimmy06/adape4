import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aplicacion_flutter/utils/modelo_ruta_glb.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> document(Uint8List bytes) {
  final length = ByteData.sublistView(bytes).getUint32(12, Endian.little);
  return jsonDecode(utf8.decode(bytes.sublist(20, 20 + length)))
      as Map<String, dynamic>;
}

List<List<double>> samples(
  Uint8List bytes,
  Map<String, dynamic> doc,
  int accessor,
) {
  final item = doc['accessors'][accessor],
      view = doc['bufferViews'][item['bufferView']];
  final width = item['type'] == 'VEC4' ? 4 : 3;
  final jsonLength = ByteData.sublistView(bytes).getUint32(12, Endian.little);
  final offset =
      28 +
      jsonLength +
      (view['byteOffset'] as int) +
      (item['byteOffset'] as int? ?? 0);
  final data = ByteData.sublistView(bytes);
  return List.generate(
    item['count'] as int,
    (i) => List.generate(
      width,
      (j) => data.getFloat32(offset + (i * width + j) * 4, Endian.little),
    ),
  );
}

void main() {
  test('country endpoints are geographic and arc is raised', () {
    final a = vectorPais((-1.8, -78.2)), b = vectorPais((39, -98));
    for (var i = 0; i < 3; i++) {
      expect(
        puntoArco((-1.8, -78.2), (39, -98), 0)[i],
        closeTo(a[i] * 1.055, 1e-9),
      );
      expect(
        puntoArco((-1.8, -78.2), (39, -98), 1)[i],
        closeTo(b[i] * 1.055, 1e-9),
      );
    }
    final mid = puntoArco((-1.8, -78.2), (39, -98), .5);
    expect(math.sqrt(mid.fold(0.0, (a, b) => a + b * b)), closeTo(1.305, 1e-9));
  });
  test('derived GLB preserves base and geometry, selects route, loops with tangent nose', () {
    final file = File(rutaModeloBase),
        base = file.readAsBytesSync(),
        before = Uint8List.fromList(base);
    final bytes = crearModeloRuta(base, (-1.8, -78.2), (39, -98));
    expect(base, orderedEquals(before));
    expect(file.readAsBytesSync(), orderedEquals(before));
    final doc = document(bytes), original = document(base);
    for (var i = 0; i < 4; i++) {
      expect(doc['meshes'][i], equals(original['meshes'][i]));
    }
    expect(doc['images'], original['images']);
    expect(doc['materials'], original['materials']);
    expect(doc['nodes'], hasLength(7));
    expect(doc['scenes'][0]['nodes'], [0]);
    expect(doc['animations'], hasLength(1));
    final samplers = doc['animations'][0]['samplers'];
    final positions = samples(bytes, doc, samplers[0]['output'] as int);
    final rotations = samples(bytes, doc, samplers[1]['output'] as int);
    for (var j = 0; j < 3; j++) {
      expect(
        positions.first[j],
        closeTo(puntoArco((-1.8, -78.2), (39, -98), 0)[j], 1e-6),
      );
      expect(
        positions[112][j],
        closeTo(puntoArco((-1.8, -78.2), (39, -98), 1)[j], 1e-6),
      );
      expect(positions.last[j], closeTo(positions.first[j], 1e-6));
    }
    for (final q in rotations) {
      expect(q.every((v) => v.isFinite), isTrue);
      expect(q.fold(0.0, (a, v) => a + v * v), closeTo(1, 1e-5));
    }
    // Rotate aircraft nose (-Z) and compare with first outbound tangent.
    final q = rotations[40], x = q[0], y = q[1], z = q[2], w = q[3];
    final front = [
      -2 * (x * z + y * w),
      -2 * (y * z - x * w),
      -(1 - 2 * (x * x + y * y)),
    ];
    final delta = List.generate(3, (i) => positions[41][i] - positions[39][i]);
    final norm = math.sqrt(delta.fold(0.0, (a, v) => a + v * v));
    final alignment = List.generate(
      3,
      (i) => front[i] * delta[i] / norm,
    ).reduce((a, b) => a + b);
    expect(alignment, greaterThan(.999));
    final loopDot = List.generate(
      4,
      (i) => rotations.first[i] * rotations.last[i],
    ).reduce((a, b) => a + b).abs();
    expect(loopDot, closeTo(1, 1e-5));
  });
}
