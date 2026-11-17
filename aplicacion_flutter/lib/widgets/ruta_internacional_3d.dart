import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';

import '../models/ruta_vuelo.dart';
import '../utils/modelo_ruta_glb.dart';
import '../utils/modelo_ruta_archivo_web.dart'
    if (dart.library.io) '../utils/modelo_ruta_archivo_io.dart';

typedef ConstructorVisorRuta = Widget Function(
  BuildContext context,
  String source,
  bool reducedMotion,
);

class RutaInternacional3D extends StatefulWidget {
  const RutaInternacional3D({
    super.key,
    required this.ruta,
    this.constructorVisor,
    this.envolverVisor,
  });
  final RutaVuelo ruta;
  final ConstructorVisorRuta? constructorVisor;
  @visibleForTesting
  final Widget Function(Flutter3DViewer viewer)? envolverVisor;
  @override
  State<RutaInternacional3D> createState() => _RutaInternacional3DState();
}

class _RutaInternacional3DState extends State<RutaInternacional3D> {
  final _controller = Flutter3DController();
  ModeloRutaArchivo? _model;
  bool _failed = false, _loaded = false, _reduce = false;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RutaInternacional3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ruta.origen != widget.ruta.origen ||
        oldWidget.ruta.destino != widget.ruta.destino) {
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    final previous = _model;
    _model = null;
    _failed = false;
    _loaded = false;
    if (previous != null) unawaited(previous.dispose());
    final a = widget.ruta.centroOrigen, b = widget.ruta.centroDestino;
    if (a == null || b == null) return;
    try {
      final bytes = await rootBundle.load(rutaModeloBase);
      final model = await ModeloRutaArchivo.crear(
        crearModeloRuta(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          a,
          b,
        ),
      );
      if (!mounted || request != _request) {
        await model.dispose();
        return;
      }
      setState(() => _model = model);
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (_loaded && reduce != _reduce) {
      if (reduce) {
        _controller.pauseAnimation();
      } else {
        _controller.playAnimation(animationName: 'Selected country flight');
      }
    }
    _reduce = reduce;
  }

  bool _isCurrent(int request, ModeloRutaArchivo model) =>
      mounted && request == _request && identical(model, _model);

  void _onLoad(int request, ModeloRutaArchivo model, RutaVuelo route) {
    if (!_isCurrent(request, model)) return;
    final a = route.centroOrigen!, b = route.centroDestino!;
    final midpoint = puntoArco(a, b, .5);
    // glTF's +Z-facing camera is rotated toward the selected geographic arc.
    final theta = math.atan2(midpoint[0], midpoint[2]) * 180 / math.pi;
    final phi =
        math.acos(
          midpoint[1] / math.sqrt(midpoint.fold(0.0, (s, v) => s + v * v)),
        ) *
        180 /
        math.pi;
    _controller.setCameraOrbit(theta, phi, 140);
    if (!_reduce) {
      _controller.playAnimation(animationName: 'Selected country flight');
    }
    setState(() => _loaded = true);
  }

  @override
  void dispose() {
    ++_request;
    final model = _model;
    if (model != null) unawaited(model.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final located =
        widget.ruta.centroOrigen != null && widget.ruta.centroDestino != null;
    if (!located || _failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            !located
                ? 'Ubicación geográfica no disponible para estos países. No se muestra una ruta inventada.'
                : 'No se pudo cargar el modelo 3D de esta ruta.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    final model = _model;
    if (model == null) return const Center(child: CircularProgressIndicator());
    if (widget.constructorVisor != null) {
      return widget.constructorVisor!(context, model.src, _reduce);
    }
    final request = _request;
    final route = widget.ruta;
    return Semantics(
      label:
          'Modelo 3D AeroTech: ${widget.ruta.paisOrigen} a ${widget.ruta.paisDestino}',
      image: true,
      child: _wrapViewer(
        Flutter3DViewer(
          key: ValueKey(model.src),
          src: model.src,
          controller: _controller,
          progressBarColor: Colors.cyan,
          enableTouch: true,
          onLoad: (_) => _onLoad(request, model, route),
          onError: (_) {
            if (_isCurrent(request, model)) setState(() => _failed = true);
          },
        ),
      ),
    );
  }

  Widget _wrapViewer(Flutter3DViewer viewer) =>
      widget.envolverVisor?.call(viewer) ?? viewer;
}
