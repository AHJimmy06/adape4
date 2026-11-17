import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/ruta_vuelo.dart';
import 'ruta_internacional_3d.dart';

class MapaRutaVuelo extends StatefulWidget {
  const MapaRutaVuelo({
    super.key,
    required this.origen,
    required this.destino,
    this.constructorVisor,
  });
  final String origen;
  final String destino;
  final ConstructorVisorRuta? constructorVisor;
  @override
  State<MapaRutaVuelo> createState() => _MapaRutaVueloState();
}

class _MapaRutaVueloState extends State<MapaRutaVuelo>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );
  Map<String, dynamic> _countries = {};
  @override
  void initState() {
    super.initState();
    _loadOutlines();
  }

  Future<void> _loadOutlines() async {
    try {
      final json = jsonDecode(
        await rootBundle.loadString('assets/maps/paises_rutas.json'),
      ) as Map<String, dynamic>;
      if (mounted) {
        setState(() => _countries = json['countries'] as Map<String, dynamic>);
      }
    } catch (_) {
      /* A labeled schematic is used when the outline is unavailable. */
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateMotion();
  }

  @override
  void didUpdateWidget(covariant MapaRutaVuelo oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateMotion();
  }

  void _updateMotion() {
    final route = RutaVuelo(widget.origen, widget.destino);
    if (MediaQuery.disableAnimationsOf(context) || !route.esNacional) {
      _controller.stop();
      _controller.value = .5;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = RutaVuelo(widget.origen, widget.destino);
    final rings = _countries[RutaVuelo.clavePais(route.paisOrigen)] as List?;
    final geographic =
        route.puntoOrigen != null &&
        route.puntoDestino != null &&
        rings != null;
    final labels = route.esInternacional
        ? (route.paisOrigen!, route.paisDestino!)
        : (RutaVuelo.ciudad(widget.origen), RutaVuelo.ciudad(widget.destino));
    return Container(
      height: 310,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF09213F), Color(0xFF164E70)],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              route.esNacional
                  ? 'RUTA NACIONAL · ${route.paisOrigen}'
                  : route.esInternacional
                  ? 'RUTA INTERNACIONAL · MODELO 3D AEROTECH'
                  : 'RUTA SIN PAÍS IDENTIFICADO',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                letterSpacing: 1,
              ),
            ),
          ),
          Expanded(
            child: route.esInternacional
                ? RutaInternacional3D(
                    ruta: route,
                    constructorVisor: widget.constructorVisor,
                  )
                : route.esNacional
                ? Semantics(
                    label: geographic
                        ? 'Mapa de la ruta ${widget.origen} a ${widget.destino}'
                        : 'Esquema de la ruta ${widget.origen} a ${widget.destino}',
                    image: true,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) => CustomPaint(
                        key: const ValueKey('mapa-nacional-2d'),
                        size: Size.infinite,
                        painter: _DomesticPainter(
                          rings: geographic ? rings : null,
                          origin: geographic ? route.puntoOrigen : null,
                          destination: geographic ? route.puntoDestino : null,
                          progress: _controller.value,
                        ),
                      ),
                    ),
                  )
                : const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Ubicación geográfica no disponible. Indique Ciudad, País para identificar la ruta.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    labels.$1,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    Icons.flight_takeoff,
                    color: Colors.cyan,
                    size: 20,
                  ),
                ),
                Expanded(
                  child: Text(
                    labels.$2,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              route.esNacional
                  ? geographic
                        ? 'Contorno Natural Earth · ruta entre ciudades'
                        : 'Esquema punto a punto · ubicación geográfica no disponible'
                  : route.esInternacional
                  ? 'Ruta entre países · puntos de referencia aproximados'
                  : 'Sin coordenadas inventadas',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _DomesticPainter extends CustomPainter {
  _DomesticPainter({
    required this.rings,
    required this.origin,
    required this.destination,
    required this.progress,
  });
  final List? rings;
  final GeoPoint? origin, destination;
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    Offset a, b;
    if (rings != null && origin != null && destination != null) {
      // Frame the mainland containing both selected cities; remote island rings
      // remain outside the viewport rather than distorting this local route.
      final all = rings!.expand((r) => r as List).cast<List>();
      final latitudes = all.map((p) => (p[1] as num).toDouble()).toList();
      final longitudes = all.map((p) => (p[0] as num).toDouble()).toList();
      var minX = longitudes.reduce(math.min),
          maxX = longitudes.reduce(math.max);
      final minY = latitudes.reduce(math.min),
          maxY = latitudes.reduce(math.max);
      // Ecuador's distant Galapagos are not the mainland city-route viewport.
      if (origin!.$2 > -82 &&
          destination!.$2 > -82 &&
          minX < -89 &&
          maxX > -82) {
        minX = -81.5;
        maxX = math.max(maxX, -75);
      }
      final scale = math.min(
        (size.width - 40) / (maxX - minX),
        (size.height - 24) / (maxY - minY),
      );
      Offset project(double lat, double lon) => Offset(
        size.width / 2 + (lon - (minX + maxX) / 2) * scale,
        size.height / 2 - (lat - (minY + maxY) / 2) * scale,
      );
      canvas.save();
      canvas.clipRect(Offset.zero & size);
      final path = Path()..fillType = PathFillType.evenOdd;
      for (final ring in rings!) {
        final points = ring as List;
        if (points.isEmpty) continue;
        var first = true;
        for (final p in points) {
          final point = project(
            (p[1] as num).toDouble(),
            (p[0] as num).toDouble(),
          );
          if (first) {
            path.moveTo(point.dx, point.dy);
            first = false;
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        path.close();
      }
      canvas.drawPath(path, Paint()..color = const Color(0xFF247888));
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF59CAD0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      canvas.restore();
      a = project(origin!.$1, origin!.$2);
      b = project(destination!.$1, destination!.$2);
    } else {
      a = Offset(size.width * .19, size.height * .62);
      b = Offset(size.width * .81, size.height * .35);
    }
    final line = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 2;
    canvas.drawLine(a, b, line);
    for (final p in [a, b]) {
      canvas.drawCircle(
        p,
        7,
        Paint()..color = Colors.cyan.withValues(alpha: .2),
      );
      canvas.drawCircle(p, 3, Paint()..color = Colors.white);
    }
    final point = Offset.lerp(a, b, progress)!;
    canvas.save();
    canvas.translate(point.dx, point.dy);
    canvas.rotate(math.atan2(b.dy - a.dy, b.dx - a.dx) + math.pi / 2);
    final text = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(Icons.flight.codePoint),
        style: TextStyle(
          fontSize: 24,
          fontFamily: Icons.flight.fontFamily,
          package: Icons.flight.fontPackage,
          color: Colors.white,
        ),
      ),
    )..layout();
    text.paint(canvas, Offset(-text.width / 2, -text.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DomesticPainter old) =>
      old.progress != progress ||
      old.rings != rings ||
      old.origin != origin ||
      old.destination != destination;
}
