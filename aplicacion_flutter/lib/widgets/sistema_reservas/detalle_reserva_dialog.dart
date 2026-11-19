import 'package:flutter/material.dart';

import '../../models/ruta_vuelo.dart';
import '../../utils/checkout_operacion.dart';
import '../presentacion/dialogo_aerotech.dart';
import '../sistema_compra/compra_sistema_dialog.dart';
import '../sistema_compra/detalle_pasajero.dart';
import '../sistema_compra/ruta_aeropuertos.dart';

/// Solo presenta el snapshot privado que ya recibió el comprador.
class DetalleReservaDialog extends StatelessWidget {
  const DetalleReservaDialog({
    super.key,
    required this.reserva,
    required this.onXml,
    required this.onReintentar,
    this.onAccesos,
    this.onCancelar,
  });

  final Map<String, dynamic> reserva;
  final VoidCallback onXml;
  final VoidCallback? onAccesos, onCancelar;
  final void Function(Map<String, dynamic>) onReintentar;

  String _importe(dynamic value) =>
      value is num ? dinero(value) : 'No disponible';

  Widget _montos(String titulo, Map datos, {String prefijo = ''}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text('Subtotal: ${_importe(datos['${prefijo}subtotal_centavos'])}'),
        Text('IVA: ${_importe(datos['${prefijo}iva_centavos'])}'),
        Text('Total: ${_importe(datos['${prefijo}total_centavos'])}'),
      ],
    ),
  );

  Widget _asiento(Map<String, dynamic> asiento) {
    final equipaje = asiento['equipaje'] as Map?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Asiento ${asiento['codigo']} · ${asiento['clase_codigo']}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            EtiquetaEstado(asiento['estado']),
            DetallePasajero(asiento: asiento),
            if (asiento['pasajero'] == null)
              const Text(
                'No se registró un detalle de pasajero en esta compra.',
              ),
            if (asiento['tarifa_total_centavos'] is num)
              _montos(
                'Tarifa original del asiento',
                asiento,
                prefijo: 'tarifa_',
              ),
            if (equipaje != null) ...[
              Text('Maletas adicionales: ${equipaje['cantidad'] ?? 0}'),
              Text(
                'Precio original por maleta: ${_importe(equipaje['precio_unitario_centavos'])} · IVA incluido',
              ),
              _montos(
                'Equipaje adicional incluido en el total del asiento',
                equipaje,
              ),
            ] else
              const Text(
                'Esta compra no conserva un desglose de equipaje adicional.',
              ),
            _montos('Total original del asiento y sus extras', asiento),
            if (asiento['estado'] == 'cancelado')
              const Text('Reembolso confirmado del asiento y sus extras.'),
            if (asiento['estado'] == 'reembolso_pendiente')
              const Text(
                'Reembolso pendiente: no se ha confirmado la devolución ni la liberación del asiento.',
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vuelo = reserva['vuelo'] as Map? ?? {};
    final ruta = vuelo['ruta'] as Map? ?? {};
    final origen = Map<String, dynamic>.from(ruta['origen'] as Map? ?? {});
    final destino = Map<String, dynamic>.from(ruta['destino'] as Map? ?? {});
    final coordenadas = [
      origen,
      destino,
    ].every((a) => a['latitud'] is num && a['longitud'] is num);
    final total = reserva['total_centavos'];
    final reembolsado = reserva['reembolsado_centavos'];
    return DialogoAerotech(
      maxWidth: 1000,
      title: 'Detalles de tu reserva',
      subtitle: 'Itinerario, pasajeros e importes originales de la compra. Moneda: USD.',
      icon: Icons.confirmation_number_outlined,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText('Referencia de reserva: ${reserva['id']}'),
          const SizedBox(height: 12),
          EtiquetaEstado(reserva['estado']),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${origen['iata'] ?? vuelo['origen'] ?? 'Origen no disponible'} ${origen['ciudad'] ?? ''}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Icon(Icons.arrow_forward, semanticLabel: 'hacia'),
              Text(
                '${destino['iata'] ?? vuelo['destino'] ?? 'Destino no disponible'} ${destino['ciudad'] ?? ''}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          Text('Vuelo: ${vuelo['codigo'] ?? 'No disponible'}'),
          Text(
            'Salida: ${fechaLegible(vuelo['salida_local'] ?? vuelo['salida_en'], zona: origen['zona_horaria']?.toString())}',
          ),
          Text(
            'Llegada: ${fechaLegible(vuelo['llegada_local'] ?? vuelo['llegada_en'], zona: destino['zona_horaria']?.toString())}',
          ),
          const SizedBox(height: 16),
          if (coordenadas)
            SizedBox(
              height: 220 + MediaQuery.textScalerOf(context).scale(14) * 14,
              child: RutaAeropuertos(
                ruta: RutaVuelo.desdeAeropuertos(origen, destino),
              ),
            )
          else
            const PanelMensaje(
              'No hay coordenadas de ambos aeropuertos para mostrar esta ruta en el mapa. El itinerario disponible se muestra arriba.',
            ),
          const SizedBox(height: 20),
          if (reserva['legada'] == true)
            const PanelMensaje(
              'Reserva anterior: no se asignaron etiquetas de asiento ni pagos de Stripe. Solo se muestran los datos conservados.',
            ),
          Text(
            'Asientos y extras',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            'Activos: ${reserva['cantidad_activa']} · Cancelados: ${reserva['cantidad_cancelada']}',
          ),
          for (final asiento in mapas(reserva['asientos'])) _asiento(asiento),
          const SizedBox(height: 16),
          Text(
            'Resumen de la compra',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text('El total incluye los extras seleccionados.'),
          _montos('Importes originales', reserva),
          Text('Reembolsado: ${_importe(reembolsado)}'),
          Text(
            'Importe restante: ${total is num && reembolsado is num ? dinero(total - reembolsado) : 'No disponible'}',
          ),
          const SizedBox(height: 12),
          for (final c in mapas(reserva['cancelaciones']))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Reembolso: ${estadoLegible(c['estado'])} · ${_importe(c['importe_centavos'])}',
                  ),
                  if ([
                    'pendiente',
                    'fallida',
                    'fallido',
                    'failed',
                    'pending',
                    'reembolso_pendiente',
                    'revision',
                  ].contains(c['estado']))
                    TextButton(
                      onPressed: () => onReintentar(c),
                      child: const Text('Reintentar reembolso'),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: onXml,
                child: const Text('Ver comprobante XML'),
              ),
              if (onAccesos != null)
                OutlinedButton.icon(
                  onPressed: onAccesos,
                  icon: const Icon(Icons.manage_accounts_outlined),
                  label: const Text('Gestionar accesos'),
                ),
              if (onCancelar != null)
                TextButton(
                  onPressed: onCancelar,
                  child: const Text('Cancelar asientos'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
