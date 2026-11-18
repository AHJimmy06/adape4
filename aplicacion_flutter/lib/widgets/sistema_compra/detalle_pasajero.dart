import 'package:flutter/material.dart';

import '../../utils/checkout_operacion.dart';
import 'pasajeros_asientos.dart';

/// Usa solamente el snapshot de la compra; no consulta cuentas de terceros.
class DetallePasajero extends StatelessWidget {
  const DetallePasajero({super.key, required this.asiento});
  final Map<String, dynamic> asiento;
  @override
  Widget build(BuildContext context) {
    final pasajero = asiento['pasajero'] as Map?;
    final equipaje = asiento['equipaje'] as Map?;
    if (pasajero == null && equipaje == null) return const SizedBox.shrink();
    final nombre = pasajero?['asignado'] == true
        ? (pasajero?['nombre'] ?? 'Usuario registrado')
        : (categoriasPasajero[pasajero?['categoria']] ?? 'Adulto');
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Asiento ${asiento["codigo"]} · $nombre'),
          if (pasajero?['asignado'] == true)
            Text(
              'Categoría: ${categoriasPasajero[pasajero?["categoria"]] ?? "Adulto"}',
            ),
          if (pasajero?['asignado'] == true && pasajero?['correo'] != null)
            Text(pasajero!['correo'].toString()),
          if (equipaje != null)
            Text(
              '${equipaje["cantidad"] ?? 0} maleta(s) adicional(es) · ${dinero(equipaje["total_centavos"])} · IVA incluido',
            ),
        ],
      ),
    );
  }
}
