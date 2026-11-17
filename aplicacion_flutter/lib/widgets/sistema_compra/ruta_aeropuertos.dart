import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/ruta_vuelo.dart';
import '../ruta_internacional_3d.dart';

typedef ConstructorRutaSistema = Widget Function(
  BuildContext context,
  RutaVuelo ruta,
);

class RutaAeropuertos extends StatelessWidget {
  const RutaAeropuertos({super.key, required this.ruta});
  final RutaVuelo ruta;
  @override
  Widget build(BuildContext context) => Container(
    height: 280,
    decoration: BoxDecoration(
      color: const Color(0xff09213f),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '${ruta.esNacional ? 'RUTA NACIONAL' : 'RUTA INTERNACIONAL 3D'} · Aeropuertos',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        Expanded(
          child: ruta.esInternacional
              ? RutaInternacional3D(ruta: ruta)
              : FutureBuilder<String>(
                  future: rootBundle.loadString(
                    'assets/maps/paises_rutas.json',
                  ),
                  builder: (context, snapshot) {
                    final countries = snapshot.hasData
                        ? (jsonDecode(snapshot.data!) as Map)['countries']
                              as Map
                        : {};
                    return CustomPaint(
                      size: Size.infinite,
                      painter: _MapaAeropuertos(
                        ruta,
                        countries[RutaVuelo.clavePais(ruta.paisOrigen)]
                            as List?,
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
            '${ruta.origen} → ${ruta.destino}',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    ),
  );
}

class _MapaAeropuertos extends CustomPainter {
  _MapaAeropuertos(this.ruta, this.rings);
  final RutaVuelo ruta;
  final List? rings;
  @override
  void paint(Canvas canvas, Size size) {
    final a = ruta.puntoOrigen, b = ruta.puntoDestino;
    if (a == null || b == null) return;
    final points = <GeoPoint>[
      a,
      b,
      if (rings != null)
        for (final ring in rings!)
          for (final p in ring as List)
            ((p[1] as num).toDouble(), (p[0] as num).toDouble()),
    ];
    final minLat = points.map((p) => p.$1).reduce(math.min),
        maxLat = points.map((p) => p.$1).reduce(math.max),
        minLon = points.map((p) => p.$2).reduce(math.min),
        maxLon = points.map((p) => p.$2).reduce(math.max);
    final scale = math.min(
      (size.width - 50) / math.max(.05, maxLon - minLon),
      (size.height - 30) / math.max(.05, maxLat - minLat),
    );
    Offset project(GeoPoint p) => Offset(
      size.width / 2 + (p.$2 - (minLon + maxLon) / 2) * scale,
      size.height / 2 - (p.$1 - (minLat + maxLat) / 2) * scale,
    );
    if (rings != null) {
      for (final ring in rings!) {
        final path = Path();
        var first = true;
        for (final p in ring as List) {
          final point = project((
            (p[1] as num).toDouble(),
            (p[0] as num).toDouble(),
          ));
          if (first) {
            path.moveTo(point.dx, point.dy);
            first = false;
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        path.close();
        canvas.drawPath(path, Paint()..color = const Color(0xff235978));
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white38
            ..style = PaintingStyle.stroke,
        );
      }
    }
    final pa = project(a), pb = project(b);
    canvas.drawLine(
      pa,
      pb,
      Paint()
        ..color = Colors.cyanAccent
        ..strokeWidth = 3,
    );
    for (final p in [pa, pb]) {
      canvas.drawCircle(p, 6, Paint()..color = Colors.amber);
    }
  }

  @override
  bool shouldRepaint(covariant _MapaAeropuertos old) =>
      old.ruta != ruta || old.rings != rings;
}
