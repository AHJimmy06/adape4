import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';

class GloboVuelos extends StatefulWidget {
  const GloboVuelos({super.key, this.animar = true});

  final bool animar;

  static const String semanticLabel =
      'Globo 3D de AeroTech con aviones en rutas';

  @override
  State<GloboVuelos> createState() => _GloboVuelosState();
}

class _GloboVuelosState extends State<GloboVuelos> {
  static const String _rutaModeloNativa = 'assets/models/aerotech_globo.glb';
  static const String _rutaModeloWeb =
      'assets/assets/models/aerotech_globo.glb';
  static const String _nombreAnimacion = 'Orbitas de vuelos';

  final Flutter3DController _controlador = Flutter3DController();
  bool _modeloCargado = false;
  bool _errorDeCarga = false;

  void _alCargarModelo(String _) {
    // El tercer argumento es porcentaje de encuadre, no distancia en metros.
    _controlador.setCameraOrbit(28, 70, 130);
    if (widget.animar) {
      _controlador.playAnimation(animationName: _nombreAnimacion);
      _controlador.startRotation(rotationSpeed: 4);
    }
    if (mounted) setState(() => _modeloCargado = true);
  }

  void _alFallarCarga(String _) {
    if (mounted) setState(() => _errorDeCarga = true);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 420.0;
        final side = math.min(maxWidth, 440.0);

        return Semantics(
          label: GloboVuelos.semanticLabel,
          image: true,
          child: ExcludeSemantics(
            child: SizedBox.square(
              dimension: side,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x353AC3D5), Color(0x003AC3D5)],
                    stops: [0.58, 1],
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (!_errorDeCarga)
                      Flutter3DViewer(
                        key: const ValueKey('visor-globo-aerotech'),
                        src: kIsWeb ? _rutaModeloWeb : _rutaModeloNativa,
                        controller: _controlador,
                        progressBarColor: Colors.transparent,
                        activeGestureInterceptor: true,
                        enableTouch: true,
                        onLoad: _alCargarModelo,
                        onError: _alFallarCarga,
                      ),
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [Color(0x00000000), Color(0x0B087DB1)],
                            stops: [0.72, 1],
                          ),
                        ),
                        child: SizedBox.square(dimension: side),
                      ),
                    ),
                    if (!_modeloCargado && !_errorDeCarga)
                      const _CargandoModelo(),
                    if (_errorDeCarga) const _ErrorModelo(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CargandoModelo extends StatelessWidget {
  const _CargandoModelo();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Center(
        child: SizedBox.square(
          dimension: 30,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: Color(0xFF47C4D1),
          ),
        ),
      ),
    );
  }
}

class _ErrorModelo extends StatelessWidget {
  const _ErrorModelo();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.public_rounded, size: 46, color: Color(0xFF47C4D1)),
          SizedBox(height: 12),
          Text(
            'No se pudo cargar el modelo 3D.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF526579)),
          ),
        ],
      ),
    );
  }
}
