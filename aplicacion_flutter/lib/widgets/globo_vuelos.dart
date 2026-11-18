import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';
// El visor web declarativo evita depender del puente JS de los comandos.
// La versión está fijada en pubspec.lock; la API pública no expone autoplay.
// ignore: implementation_imports
import 'package:flutter_3d_controller/src/core/modules/model_viewer/model_viewer.dart';

class GloboVuelos extends StatefulWidget {
  const GloboVuelos({
    super.key,
    this.animar = true,
    this.tamanoMaximo = 440,
    this.encuadre = 130,
  });

  final bool animar;
  final double tamanoMaximo;
  final double encuadre;

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
    _controlador.setCameraOrbit(28, 70, widget.encuadre);
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
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : widget.tamanoMaximo;
        final side = math.min(
          math.min(maxWidth, maxHeight),
          widget.tamanoMaximo,
        );

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
                    if (!_errorDeCarga && kIsWeb)
                      ModelViewer(
                        src: _rutaModeloWeb,
                        alt: GloboVuelos.semanticLabel,
                        debugLogging: false,
                        autoPlay: widget.animar,
                        animationName: _nombreAnimacion,
                        autoRotate: widget.animar,
                        rotationPerSecond: '4deg',
                        cameraOrbit: '28deg 70deg ${widget.encuadre}%',
                        cameraControls: true,
                        disableTap: true,
                        interactionPrompt: InteractionPrompt.none,
                        progressBarColor: Colors.transparent,
                        backgroundColor: Colors.transparent,
                        onLoad: (_) {
                          if (mounted) setState(() => _modeloCargado = true);
                        },
                        onError: _alFallarCarga,
                      ),
                    if (!_errorDeCarga && !kIsWeb)
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
                    if (!kIsWeb && !_modeloCargado && !_errorDeCarga)
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
