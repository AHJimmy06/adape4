import 'package:flutter/material.dart';

import '../../theme/aerotech_theme.dart';

/// Identifica los aeropuertos sin depender de que la ruta venga expandida.
class ResumenRuta extends StatelessWidget {
  const ResumenRuta({
    super.key,
    required this.ruta,
    this.aeropuertos = const [],
  });

  final Map<String, dynamic> ruta;
  final List<Map<String, dynamic>> aeropuertos;

  static String _texto(dynamic valor) => valor?.toString().trim() ?? '';

  static Map<String, dynamic> aeropuerto(
    Map<String, dynamic> ruta,
    String extremo,
    List<Map<String, dynamic>> catalogo,
  ) {
    final datos = ruta[extremo] is Map
        ? Map<String, dynamic>.from(ruta[extremo] as Map)
        : <String, dynamic>{};
    final id = _texto(datos['id']).isNotEmpty
        ? _texto(datos['id'])
        : _texto(ruta['${extremo}_id']);
    final iata = _texto(datos['iata']);
    final encontrado = catalogo.where(
      (a) => id.isNotEmpty
          ? _texto(a['id']) == id
          : iata.isNotEmpty && _texto(a['iata']) == iata,
    );
    return {
      if (encontrado.isNotEmpty) ...encontrado.first,
      for (final entrada in datos.entries)
        if (_texto(entrada.value).isNotEmpty) entrada.key: entrada.value,
    };
  }

  static String titulo(
    Map<String, dynamic> ruta,
    List<Map<String, dynamic>> catalogo,
  ) {
    final nombre = _texto(ruta['nombre']);
    if (nombre.isNotEmpty) return nombre;
    final origen = _texto(aeropuerto(ruta, 'origen', catalogo)['iata']);
    final destino = _texto(aeropuerto(ruta, 'destino', catalogo)['iata']);
    return '${origen.isEmpty ? 'Origen' : origen} → ${destino.isEmpty ? 'Destino' : destino}';
  }

  @override
  Widget build(BuildContext context) {
    final origen = _AeropuertoRuta(
      etiqueta: 'Aeropuerto de origen',
      icono: Icons.flight_takeoff,
      datos: aeropuerto(ruta, 'origen', aeropuertos),
    );
    final destino = _AeropuertoRuta(
      etiqueta: 'Aeropuerto de destino',
      icono: Icons.flight_land,
      datos: aeropuerto(ruta, 'destino', aeropuertos),
    );
    return LayoutBuilder(
      builder: (context, limites) => limites.maxWidth < 620
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [origen, const SizedBox(height: 12), destino],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: origen),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 28),
                  child: Icon(Icons.arrow_forward, color: AerotechTheme.blue),
                ),
                Expanded(child: destino),
              ],
            ),
    );
  }
}

class _AeropuertoRuta extends StatelessWidget {
  const _AeropuertoRuta({
    required this.etiqueta,
    required this.icono,
    required this.datos,
  });

  final String etiqueta;
  final IconData icono;
  final Map<String, dynamic> datos;

  @override
  Widget build(BuildContext context) {
    final nombre = ResumenRuta._texto(datos['nombre']);
    final iata = ResumenRuta._texto(datos['iata']);
    final ubicacion = [
      datos['ciudad'],
      datos['pais'],
    ].map(ResumenRuta._texto).where((s) => s.isNotEmpty).join(', ');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AerotechTheme.inputFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AerotechTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, size: 20, color: AerotechTheme.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    etiqueta,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AerotechTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (iata.isNotEmpty) ...[
              Text(
                iata,
                style: const TextStyle(
                  color: AerotechTheme.blue,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              nombre.isEmpty ? 'Aeropuerto no disponible' : nombre,
              style: const TextStyle(
                color: AerotechTheme.navy,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (ubicacion.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                ubicacion,
                style: const TextStyle(color: AerotechTheme.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
