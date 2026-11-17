import 'package:flutter/material.dart';

import '../theme/aerotech_theme.dart';
import 'presentacion/dialogo_aerotech.dart';

/// Tarjeta de una salida concreta. No inventa promociones ni descuentos.
class TarjetaDestino extends StatelessWidget {
  const TarjetaDestino({super.key, required this.vuelo, this.onReservar});

  final Map<String, dynamic> vuelo;
  final VoidCallback? onReservar;

  @override
  Widget build(BuildContext context) {
    final ruta = vuelo['ruta'] as Map? ?? {};
    final origen = ruta['origen'] as Map? ?? {};
    final destino = ruta['destino'] as Map? ?? {};
    final avion = vuelo['avion'] as Map? ?? {};
    final base = (vuelo['precio_desde_centavos'] as num? ?? 0).toInt();
    final total = base + (base * 15 + 50) ~/ 100;
    final disponibles = vuelo['asientos_disponibles'] as num? ?? 0;
    final tarifas = vuelo['tarifas'] as List? ?? [];
    final internacional = origen['codigo_pais'] != destino['codigo_pais'];
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 160 * MediaQuery.textScalerOf(context).scale(1),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: internacional
                    ? const [Color(0xFF19314F), Color(0xFF2A7795)]
                    : const [Color(0xFF0C3551), Color(0xFF328A91)],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -5,
                  top: -14,
                  child: Icon(
                    internacional ? Icons.public : Icons.landscape_outlined,
                    color: Colors.white.withValues(alpha: .15),
                    size: 140,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.flight_takeoff, color: Color(0xFF90E3E3)),
                    const Spacer(),
                    Text(
                      '${origen['iata'] ?? ''}  →  ${destino['iata'] ?? ''}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 29,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                    Text(
                      internacional
                          ? 'DESCUBRE OTRO PAÍS'
                          : 'EXPLORA MÁS CERCA',
                      style: const TextStyle(
                        color: Color(0xFFC8F0ED),
                        fontSize: 10,
                        letterSpacing: 1.8,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Desde ${origen['ciudad'] ?? origen['iata'] ?? ''}',
                  style: const TextStyle(color: AerotechTheme.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  '${destino['ciudad'] ?? ''} (${destino['iata'] ?? ''})',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AerotechTheme.navy,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  fechaLegible(
                    vuelo['salida_local'],
                    zona: origen['zona_horaria']?.toString(),
                  ),
                ),
                Text(
                  'Llegada: ${fechaLegible(vuelo['llegada_local'], zona: destino['zona_horaria']?.toString())}',
                  style: const TextStyle(
                    color: AerotechTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _etiqueta('Vuelo directo', Icons.near_me_outlined),
                    _etiqueta(
                      '${vuelo['codigo'] ?? ''}',
                      Icons.confirmation_number_outlined,
                    ),
                    if (vuelo['frecuencia'] == 'diaria')
                      _etiqueta('Ruta diaria', Icons.repeat),
                    for (final tarifa in tarifas)
                      _etiqueta(
                        '${tarifa['clase_codigo']}',
                        Icons.event_seat_outlined,
                      ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1),
                ),
                const Text(
                  'Precio desde · por pasajero',
                  style: TextStyle(
                    color: AerotechTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                Text(
                  'USD ${(total / 100).toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 29,
                    fontWeight: FontWeight.w800,
                    color: AerotechTheme.navy,
                  ),
                ),
                Text(
                  'IVA incluido · $disponibles disponibles',
                  style: const TextStyle(
                    color: AerotechTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                if (avion['modelo'] != null)
                  Text(
                    '${avion['modelo']} · ${avion['matricula'] ?? ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AerotechTheme.textSecondary,
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: disponibles <= 0 ? null : onReservar,
                  icon: const Icon(Icons.airline_seat_recline_normal, size: 18),
                  label: const Text('Reservar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _etiqueta(String texto, IconData icono) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: AerotechTheme.inputFill,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 13, color: AerotechTheme.blue),
        const SizedBox(width: 5),
        Text(
          texto,
          style: const TextStyle(fontSize: 11, color: AerotechTheme.navy),
        ),
      ],
    ),
  );
}
