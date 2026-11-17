import 'dart:math' as math;

import 'package:flutter/material.dart';

class AvionIlustracion extends StatelessWidget {
  const AvionIlustracion({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Ilustración de avión de AeroTech',
      child: ExcludeSemantics(
        child: CustomPaint(
          painter: _PintorAvion(),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _PintorAvion extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    const double anchoDiseno = 360;
    const double altoDiseno = 240;
    final double escala = math.min(
      size.width / anchoDiseno,
      size.height / altoDiseno,
    );

    canvas.save();
    canvas.translate(
      (size.width - anchoDiseno * escala) / 2,
      (size.height - altoDiseno * escala) / 2,
    );
    canvas.scale(escala);

    _pintarResplandor(canvas);
    _pintarRuta(canvas);
    _pintarAvion(canvas);

    canvas.restore();
  }

  void _pintarResplandor(Canvas canvas) {
    final Rect halo = Rect.fromCircle(
      center: const Offset(188, 114),
      radius: 96,
    );
    canvas.drawCircle(
      const Offset(188, 114),
      96,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x3355D8E6), Color(0x0055D8E6)],
        ).createShader(halo),
    );

    final Paint estrella = Paint()..color = const Color(0x99BCEAF2);
    for (final Offset punto in const [
      Offset(53, 74),
      Offset(294, 45),
      Offset(317, 167),
      Offset(74, 190),
      Offset(265, 211),
    ]) {
      canvas.drawCircle(punto, 1.7, estrella);
    }
  }

  void _pintarRuta(Canvas canvas) {
    final Path ruta = Path()
      ..moveTo(22, 159)
      ..cubicTo(94, 50, 246, 207, 337, 65);

    final Paint punto = Paint()
      ..color = const Color(0x9979DCE8)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final tramo in ruta.computeMetrics()) {
      double distancia = 0;
      while (distancia < tramo.length) {
        final double fin = math.min(distancia + 4, tramo.length);
        canvas.drawPath(tramo.extractPath(distancia, fin), punto);
        distancia += 11;
      }
    }

    canvas.drawCircle(
      const Offset(22, 159),
      4,
      Paint()..color = const Color(0xFF75DCE8),
    );
  }

  void _pintarAvion(Canvas canvas) {
    canvas.save();
    canvas.translate(190, 118);
    canvas.rotate(-0.58);

    final Path alas = Path()
      ..moveTo(-11, -20)
      ..lineTo(-82, -2)
      ..lineTo(-98, 8)
      ..lineTo(-93, 16)
      ..lineTo(-34, 9)
      ..lineTo(-11, 5)
      ..lineTo(11, 5)
      ..lineTo(34, 9)
      ..lineTo(93, 16)
      ..lineTo(98, 8)
      ..lineTo(82, -2)
      ..lineTo(11, -20)
      ..close();

    final Path cola = Path()
      ..moveTo(-7, 43)
      ..lineTo(-34, 57)
      ..lineTo(-39, 67)
      ..lineTo(-9, 62)
      ..lineTo(9, 62)
      ..lineTo(39, 67)
      ..lineTo(34, 57)
      ..lineTo(7, 43)
      ..close();

    final Path fuselaje = Path()
      ..moveTo(0, -91)
      ..cubicTo(8, -82, 11, -70, 11, -55)
      ..lineTo(10, 37)
      ..lineTo(17, 60)
      ..lineTo(13, 70)
      ..lineTo(4, 64)
      ..lineTo(0, 57)
      ..lineTo(-4, 64)
      ..lineTo(-13, 70)
      ..lineTo(-17, 60)
      ..lineTo(-10, 37)
      ..lineTo(-11, -55)
      ..cubicTo(-11, -70, -8, -82, 0, -91)
      ..close();

    final Rect superficie = const Rect.fromLTRB(-100, -95, 100, 75);

    canvas.drawPath(
      alas,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8FEAF0), Color(0xFF318FBD), Color(0xFF155080)],
        ).createShader(superficie),
    );
    canvas.drawPath(
      cola,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF4ABBD0), Color(0xFF164C79)],
        ).createShader(superficie),
    );

    final Paint motor = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFE8FBFC), Color(0xFF3D99BA)],
      ).createShader(const Rect.fromLTRB(-40, -3, 40, 30));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(-37, -4, -20, 30),
        const Radius.circular(8),
      ),
      motor,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(20, -4, 37, 30),
        const Radius.circular(8),
      ),
      motor,
    );

    canvas.drawPath(
      fuselaje,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFB9F4F5), Color(0xFFFFFFFF), Color(0xFF66C9DC)],
        ).createShader(const Rect.fromLTRB(-16, -92, 16, 72)),
    );
    canvas.drawPath(
      fuselaje,
      Paint()
        ..color = const Color(0x77FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    canvas.drawOval(
      const Rect.fromLTRB(-4, -78, 4, -61),
      Paint()..color = const Color(0xFF123E65),
    );
    final Paint ventanilla = Paint()..color = const Color(0xFF22739A);
    for (final double y in const [-47, -37, -27, -17, -7]) {
      canvas.drawCircle(Offset(0, y), 1.6, ventanilla);
    }

    canvas.drawLine(
      const Offset(-80, 3),
      const Offset(-27, -9),
      Paint()
        ..color = const Color(0x99FFFFFF)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      const Offset(27, -9),
      const Offset(80, 3),
      Paint()
        ..color = const Color(0x99FFFFFF)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PintorAvion oldDelegate) => false;
}
