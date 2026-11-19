import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/aerotech_theme.dart';

typedef ConstructorMapaAeropuerto = Widget Function(
  BuildContext context,
  LatLng centro,
  ValueChanged<LatLng> seleccionar,
);

/// La selección es provisional: solo se devuelve al confirmar el modal.
class SelectorUbicacionAeropuerto extends StatefulWidget {
  const SelectorUbicacionAeropuerto({
    super.key,
    this.inicial,
    this.mapaBuilder,
  });

  final LatLng? inicial;
  final ConstructorMapaAeropuerto? mapaBuilder;

  static bool coordenadasValidas(LatLng? punto) =>
      punto != null &&
      punto.latitude.isFinite &&
      punto.longitude.isFinite &&
      punto.latitude.abs() <= 90 &&
      punto.longitude.abs() <= 180;

  @override
  State<SelectorUbicacionAeropuerto> createState() =>
      _SelectorUbicacionAeropuertoState();
}

class _SelectorUbicacionAeropuertoState
    extends State<SelectorUbicacionAeropuerto> {
  final _mapa = MapController();
  LatLng? _seleccion;
  bool _errorMapa = false;

  @override
  void initState() {
    super.initState();
    if (SelectorUbicacionAeropuerto.coordenadasValidas(widget.inicial)) {
      _seleccion = widget.inicial;
    }
  }

  @override
  void dispose() {
    _mapa.dispose();
    super.dispose();
  }

  void _seleccionar(LatLng punto) {
    if (SelectorUbicacionAeropuerto.coordenadasValidas(punto)) {
      setState(() => _seleccion = punto);
    }
  }

  void _avisoMapa() {
    if (!mounted || _errorMapa) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_errorMapa) setState(() => _errorMapa = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final centro = _seleccion ?? const LatLng(-1.8312, -78.1834);
    final alto = math.min(MediaQuery.sizeOf(context).height * .9, 720.0);
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 920,
        height: alto,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  const Icon(Icons.place_outlined, color: AerotechTheme.blue),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Ubica el aeropuerto',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: AerotechTheme.navy,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar mapa',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Acerca el mapa y pulsa el punto exacto del aeropuerto.',
              ),
            ),
            Expanded(
              child: ClipRect(
                child:
                    widget.mapaBuilder?.call(context, centro, _seleccionar) ??
                    Stack(
                      children: [
                        FlutterMap(
                          key: const ValueKey('mapa_ubicacion_aeropuerto'),
                          mapController: _mapa,
                          options: MapOptions(
                            initialCenter: LatLng(
                              centro.latitude.clamp(-85, 85),
                              centro.longitude,
                            ),
                            initialZoom: _seleccion == null ? 6 : 13,
                            minZoom: 2,
                            maxZoom: 19,
                            interactionOptions: const InteractionOptions(
                              flags:
                                  InteractiveFlag.all & ~InteractiveFlag.rotate,
                            ),
                            onTap: (_, punto) => _seleccionar(punto),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'ec.aerotech.reservas',
                              maxZoom: 19,
                              errorTileCallback: (_, _, _) => _avisoMapa(),
                            ),
                            if (_seleccion != null)
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: _seleccion!,
                                    width: 48,
                                    height: 48,
                                    alignment: Alignment.topCenter,
                                    child: const Icon(
                                      Icons.location_pin,
                                      size: 48,
                                      color: AerotechTheme.blue,
                                      semanticLabel: 'Ubicación seleccionada',
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Material(
                            borderRadius: BorderRadius.circular(12),
                            child: Column(
                              children: [
                                IconButton(
                                  tooltip: 'Acercar mapa',
                                  icon: const Icon(Icons.add),
                                  onPressed: () => _mapa.move(
                                    _mapa.camera.center,
                                    math.min(19, _mapa.camera.zoom + 1),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Alejar mapa',
                                  icon: const Icon(Icons.remove),
                                  onPressed: () => _mapa.move(
                                    _mapa.camera.center,
                                    math.max(2, _mapa.camera.zoom - 1),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Material(
                            color: Colors.white,
                            child: TextButton(
                              onPressed: () => launchUrl(
                                Uri.parse(
                                  'https://www.openstreetmap.org/copyright',
                                ),
                              ),
                              child: const Text(
                                '© OpenStreetMap contributors',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_errorMapa)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'No se pudo cargar parte del mapa. Puedes cancelar e ingresar las coordenadas manualmente.',
                        style: TextStyle(color: AerotechTheme.textSecondary),
                      ),
                    ),
                  Text(
                    _seleccion == null
                        ? 'Selecciona un punto para continuar.'
                        : 'Latitud: ${_seleccion!.latitude.toStringAsFixed(6)}\nLongitud: ${_seleccion!.longitude.toStringAsFixed(6)}',
                    key: const ValueKey('coordenadas_seleccionadas'),
                    style: const TextStyle(color: AerotechTheme.navy),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton.icon(
                        key: const ValueKey('confirmar_ubicacion_mapa'),
                        onPressed: _seleccion == null
                            ? null
                            : () => Navigator.pop(context, _seleccion),
                        icon: const Icon(Icons.check),
                        label: const Text('Usar ubicación'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
