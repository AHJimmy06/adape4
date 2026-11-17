import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/ruta_vuelo.dart';

const rutaModeloBase = 'assets/models/aerotech_globo.glb';

typedef Vec3 = List<double>;
Vec3 _add(Vec3 a, Vec3 b) => List.generate(3, (i) => a[i] + b[i]);
Vec3 _scale(Vec3 a, double s) => a.map((v) => v * s).toList();
double _dot(Vec3 a, Vec3 b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
Vec3 _cross(Vec3 a, Vec3 b) => [
  a[1] * b[2] - a[2] * b[1],
  a[2] * b[0] - a[0] * b[2],
  a[0] * b[1] - a[1] * b[0],
];
Vec3 _unit(Vec3 a) => _scale(a, 1 / math.sqrt(_dot(a, a)));
Vec3 vectorPais(GeoPoint point) {
  final lat = point.$1 * math.pi / 180, lon = point.$2 * math.pi / 180;
  return [
    math.cos(lat) * math.cos(lon),
    math.sin(lat),
    math.cos(lat) * math.sin(lon),
  ];
}

/// Great-circle interpolation with a small raised arc, not a fixed sample flight.
Vec3 puntoArco(GeoPoint origin, GeoPoint destination, double progress) {
  final a = vectorPais(origin), b = vectorPais(destination);
  final angle = math.acos(_dot(a, b).clamp(-1.0, 1.0));
  Vec3 radial;
  if (angle < 1e-7) {
    return _scale(a, 1.055);
  } else if (math.pi - angle < 1e-7) {
    final axis = _unit(_cross(a, a[1].abs() < .9 ? [0, 1, 0] : [1, 0, 0]));
    radial = _add(
      _scale(a, math.cos(math.pi * progress)),
      _scale(axis, math.sin(math.pi * progress)),
    );
  } else {
    radial = _add(
      _scale(a, math.sin((1 - progress) * angle) / math.sin(angle)),
      _scale(b, math.sin(progress * angle) / math.sin(angle)),
    );
  }
  return _scale(
    radial,
    1.055 + .25 * math.pow(math.sin(math.pi * progress), 2),
  );
}

List<double> _orientation(Vec3 forward, Vec3 radial) {
  final front = _unit(forward), right = _unit(_cross(forward, radial));
  final up = _cross(right, front);
  final m = List.generate(3, (i) => [right[i], up[i], -front[i]]);
  final trace = m[0][0] + m[1][1] + m[2][2];
  if (trace > 0) {
    final r = math.sqrt(1 + trace) * 2;
    return [
      (m[2][1] - m[1][2]) / r,
      (m[0][2] - m[2][0]) / r,
      (m[1][0] - m[0][1]) / r,
      r / 4,
    ];
  }
  var i = 0;
  for (var k = 1; k < 3; k++) {
    if (m[k][k] > m[i][i]) i = k;
  }
  final j = (i + 1) % 3, k = (i + 2) % 3;
  final r = math.sqrt(1 + m[i][i] - m[j][j] - m[k][k]) * 2;
  final q = List<double>.filled(4, 0);
  q[i] = r / 4;
  q[j] = (m[j][i] + m[i][j]) / r;
  q[k] = (m[k][i] + m[i][k]) / r;
  q[3] = (m[k][j] - m[j][k]) / r;
  return q;
}

/// Reuses immutable globe, texture, materials and aircraft from the login GLB.
/// Only the selected trajectory, its markers and animation are reachable.
Uint8List crearModeloRuta(
  Uint8List base,
  GeoPoint origin,
  GeoPoint destination,
) {
  final header = ByteData.sublistView(base);
  if (header.getUint32(0, Endian.little) != 0x46546c67 ||
      header.getUint32(4, Endian.little) != 2) {
    throw const FormatException('Invalid GLB 2.0 model');
  }
  final jsonLength = header.getUint32(12, Endian.little);
  final gltf = jsonDecode(
    utf8.decode(base.sublist(20, 20 + jsonLength)),
  ) as Map<String, dynamic>;
  final binStart = 20 + jsonLength + 8;
  final binLength = header.getUint32(20 + jsonLength, Endian.little);
  final binary = BytesBuilder(copy: false)
    ..add(base.sublist(binStart, binStart + binLength));
  int accessor(List<List<double>> rows, String type) {
    final bytes = ByteData(rows.length * rows.first.length * 4);
    var p = 0;
    for (final row in rows) {
      for (final v in row) {
        bytes.setFloat32(p, v, Endian.little);
        p += 4;
      }
    }
    final views = gltf['bufferViews'] as List,
        accessors = gltf['accessors'] as List;
    final index = accessors.length;
    views.add({
      'buffer': 0,
      'byteOffset': binary.length,
      'byteLength': bytes.lengthInBytes,
    });
    accessors.add({
      'bufferView': views.length - 1,
      'componentType': 5126,
      'count': rows.length,
      'type': type,
      'min': List.generate(
        rows.first.length,
        (i) => rows.map((r) => r[i]).reduce(math.min),
      ),
      'max': List.generate(
        rows.first.length,
        (i) => rows.map((r) => r[i]).reduce(math.max),
      ),
    });
    binary.add(bytes.buffer.asUint8List());
    return index;
  }

  Vec3 tangent(double p) => _unit(
    _add(
      puntoArco(origin, destination, (p + .0001).clamp(0.0, 1.0)),
      _scale(puntoArco(origin, destination, (p - .0001).clamp(0.0, 1.0)), -1),
    ),
  );
  final same = _dot(vectorPais(origin), vectorPais(destination)) > .999999999;
  // Alias-spelling mismatches still classify international; coincident centroids
  // have a stationary aircraft instead of an invented detour.
  final times = <List<double>>[],
      positions = <List<double>>[],
      rotations = <List<double>>[];
  for (var i = 0; i <= 256; i++) {
    final t = i / 8;
    double p, sign = 1, turn = 0;
    if (t <= 14) {
      p = t / 14;
    } else if (t <= 16) {
      p = 1;
      turn = math.pi * (t - 14) / 2;
    } else if (t <= 30) {
      p = 1 - (t - 16) / 14;
      sign = -1;
    } else {
      p = 0;
      sign = -1;
      turn = math.pi * (t - 30) / 2;
    }
    final position = puntoArco(origin, destination, p),
        radial = _unit(position);
    final forward = same ? _unit(_cross(radial, [0, 1, 0])) : tangent(p);
    final q = _orientation(
      _add(
        _scale(forward, sign * math.cos(turn)),
        _scale(_unit(_cross(forward, radial)), math.sin(turn)),
      ),
      radial,
    );
    if (rotations.isNotEmpty &&
        List.generate(
              4,
              (j) => q[j] * rotations.last[j],
            ).reduce((a, b) => a + b) <
            0) {
      for (var j = 0; j < 4; j++) {
        q[j] = -q[j];
      }
    }
    times.add([t]);
    positions.add(position);
    rotations.add(q);
  }
  final vertices = <List<double>>[], normals = <List<double>>[];
  for (var i = 0; i <= 96; i++) {
    final p = i / 96,
        point = puntoArco(origin, destination, p),
        radial = _unit(point);
    final side = same
        ? _unit(_cross(radial, [0, 1, 0]))
        : _unit(_cross(tangent(p), radial));
    vertices.add(_add(point, _scale(side, -.003)));
    vertices.add(_add(point, _scale(side, .003)));
    normals.add(radial);
    normals.add(radial);
  }
  final primitive = gltf['meshes'][4]['primitives'][0];
  primitive['attributes']['POSITION'] = accessor(vertices, 'VEC3');
  primitive['attributes']['NORMAL'] = accessor(normals, 'VEC3');
  gltf['nodes'] = [
    {
      'name': 'Selected country route',
      'children': [1, 2, 3, 4, 5, 6],
    },
    {'name': 'Planeta AeroTech', 'mesh': 0},
    {'name': 'Halo atmosferico', 'mesh': 1},
    {
      'name': 'Selected aircraft',
      'mesh': 2,
      'scale': [.85, .85, .85],
      'translation': positions.first,
      'rotation': rotations.first,
    },
    {'name': 'Selected arc', 'mesh': 4},
    {
      'name': 'Origin country',
      'mesh': 3,
      'translation': _scale(vectorPais(origin), 1.008),
    },
    {
      'name': 'Destination country',
      'mesh': 3,
      'translation': _scale(vectorPais(destination), 1.008),
    },
  ];
  final input = accessor(times, 'SCALAR');
  gltf['animations'] = [
    {
      'name': 'Selected country flight',
      'samplers': [
        {
          'input': input,
          'output': accessor(positions, 'VEC3'),
          'interpolation': 'LINEAR',
        },
        {
          'input': input,
          'output': accessor(rotations, 'VEC4'),
          'interpolation': 'LINEAR',
        },
      ],
      'channels': [
        {
          'sampler': 0,
          'target': {'node': 3, 'path': 'translation'},
        },
        {
          'sampler': 1,
          'target': {'node': 3, 'path': 'rotation'},
        },
      ],
    },
  ];
  gltf['scenes'] = [
    {
      'nodes': [0],
    },
  ];
  gltf['scene'] = 0;
  gltf['buffers'] = [
    {'byteLength': binary.length},
  ];
  final jsonBytes = BytesBuilder()..add(utf8.encode(jsonEncode(gltf)));
  while (jsonBytes.length % 4 != 0) {
    jsonBytes.addByte(32);
  }
  final body = binary.takeBytes(), json = jsonBytes.takeBytes();
  final result = ByteData(12 + 8 + json.length + 8 + body.length);
  result.setUint32(0, 0x46546c67, Endian.little);
  result.setUint32(4, 2, Endian.little);
  result.setUint32(8, result.lengthInBytes, Endian.little);
  result.setUint32(12, json.length, Endian.little);
  result.setUint32(16, 0x4e4f534a, Endian.little);
  final out = result.buffer.asUint8List()..setRange(20, 20 + json.length, json);
  result.setUint32(20 + json.length, body.length, Endian.little);
  result.setUint32(24 + json.length, 0x004e4942, Endian.little);
  out.setRange(28 + json.length, out.length, body);
  return out;
}
