import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/checkout_operacion.dart';
import '../presentacion/dialogo_aerotech.dart';

const categoriasPasajero = <String, String>{
  'adulto': 'Adulto',
  'adulto_mayor': 'Adulto mayor',
  'nino': 'Niño',
};

class PasajeroAsiento {
  bool asignado = false;
  String correo = '', categoria = 'adulto', maletas = '0';
  int get cantidad => int.tryParse(maletas) ?? 0;
  int get equipajeCentavos => cantidad * 2000;
  String? get errorCorreo {
    if (asignado &&
        (correo.trim().length > 254 ||
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(correo.trim()))) {
      return 'Ingresa el correo de una cuenta registrada.';
    }
    return null;
  }

  String? get errorMaletas {
    if (!RegExp(r'^\d+$').hasMatch(maletas) || cantidad > 49999) {
      return 'Ingresa una cantidad entera de 0 a 49999.';
    }
    return null;
  }

  String? get error => errorCorreo ?? errorMaletas;

  Map<String, dynamic> datos(String asiento) => {
    'asiento': asiento,
    'correo_usuario': asignado ? correo.trim().toLowerCase() : null,
    'categoria': asignado ? 'adulto' : categoria,
    'maletas_adicionales': cantidad,
  };
}

class PasajerosAsientos extends StatelessWidget {
  const PasajerosAsientos({
    super.key,
    required this.configuraciones,
    required this.tarifasCentavos,
    required this.bloqueado,
    required this.onChanged,
  });
  final Map<String, PasajeroAsiento> configuraciones;
  final Map<String, int> tarifasCentavos;
  final bool bloqueado;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final codigos = configuraciones.keys.toList()..sort();
    final vuelo = tarifasCentavos.values.fold(0, (a, b) => a + b);
    final equipaje = configuraciones.values.fold(
      0,
      (a, b) => a + b.equipajeCentavos,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          'Pasajeros y equipaje',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'Cada asiento puede asignarse a una cuenta registrada. Las categorías no cambian la tarifa.',
        ),
        for (final codigo in codigos)
          Card(
            child: ExpansionTile(
              key: ValueKey('pasajero-$codigo'),
              initiallyExpanded: true,
              leading: const Icon(Icons.person_outline),
              title: Text('Asiento $codigo'),
              subtitle: Text(
                '${configuraciones[codigo]!.asignado ? 'Cuenta registrada' : categoriasPasajero[configuraciones[codigo]!.categoria]} · ${configuraciones[codigo]!.cantidad} maleta(s) adicional(es)',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                SwitchListTile.adaptive(
                  key: ValueKey('asignar-$codigo'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Asignar a un usuario registrado'),
                  value: configuraciones[codigo]!.asignado,
                  onChanged: bloqueado
                      ? null
                      : (v) {
                          configuraciones[codigo]!.asignado = v;
                          onChanged();
                        },
                ),
                if (configuraciones[codigo]!.asignado)
                  TextFormField(
                    key: ValueKey('correo-pasajero-$codigo'),
                    initialValue: configuraciones[codigo]!.correo,
                    enabled: !bloqueado,
                    keyboardType: TextInputType.emailAddress,
                    maxLength: 254,
                    decoration: const InputDecoration(
                      labelText: 'Correo de la cuenta registrada',
                      helperText: 'Se verificará al continuar. La compra permanece en tu cuenta.',
                    ),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (_) => configuraciones[codigo]!.errorCorreo,
                    onChanged: (v) {
                      configuraciones[codigo]!.correo = v;
                      onChanged();
                    },
                  )
                else
                  DropdownButtonFormField<String>(
                    key: ValueKey('categoria-$codigo'),
                    initialValue: configuraciones[codigo]!.categoria,
                    decoration: const InputDecoration(
                      labelText: 'Categoría del pasajero',
                    ),
                    items: [
                      for (final e in categoriasPasajero.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: bloqueado
                        ? null
                        : (v) {
                            configuraciones[codigo]!.categoria = v ?? 'adulto';
                            onChanged();
                          },
                  ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Quitar maleta de $codigo',
                      onPressed:
                          bloqueado || configuraciones[codigo]!.cantidad <= 0
                          ? null
                          : () {
                              configuraciones[codigo]!.maletas =
                                  '${configuraciones[codigo]!.cantidad - 1}';
                              onChanged();
                            },
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Expanded(
                      child: _CantidadMaletas(
                        key: ValueKey('cantidad-$codigo'),
                        codigo: codigo,
                        pasajero: configuraciones[codigo]!,
                        bloqueado: bloqueado,
                        onChanged: onChanged,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Agregar maleta a $codigo',
                      onPressed:
                          bloqueado ||
                              configuraciones[codigo]!.cantidad >= 49999
                          ? null
                          : () {
                              configuraciones[codigo]!.maletas =
                                  '${configuraciones[codigo]!.cantidad + 1}';
                              onChanged();
                            },
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                Text(
                  'Equipaje de $codigo: ${dinero(configuraciones[codigo]!.equipajeCentavos)}',
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        const Text('USD 20.00 finales por maleta adicional · IVA incluido'),
        Text('Tarifas de vuelo con IVA: ${dinero(vuelo)}'),
        Text('Equipaje adicional con IVA: ${dinero(equipaje)}'),
        Text(
          dinero(vuelo + equipaje),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const Text(
          'Total estimado. El servidor verificará los pasajeros y el importe antes del pago.',
        ),
        if (vuelo + equipaje > 99999999)
          const PanelMensaje(
            'El importe supera el máximo técnico permitido por Stripe. Reduce el equipaje o divide la compra.',
            error: true,
          ),
      ],
    );
  }
}

class _CantidadMaletas extends StatefulWidget {
  const _CantidadMaletas({
    super.key,
    required this.codigo,
    required this.pasajero,
    required this.bloqueado,
    required this.onChanged,
  });
  final String codigo;
  final PasajeroAsiento pasajero;
  final bool bloqueado;
  final VoidCallback onChanged;
  @override
  State<_CantidadMaletas> createState() => _CantidadMaletasState();
}

class _CantidadMaletasState extends State<_CantidadMaletas> {
  late final _controller = TextEditingController(text: widget.pasajero.maletas);
  @override
  void didUpdateWidget(covariant _CantidadMaletas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.pasajero.maletas) {
      _controller.value = TextEditingValue(
        text: widget.pasajero.maletas,
        selection: TextSelection.collapsed(
          offset: widget.pasajero.maletas.length,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    key: ValueKey('maletas-${widget.codigo}'),
    controller: _controller,
    enabled: !widget.bloqueado,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(5),
    ],
    decoration: const InputDecoration(labelText: 'Maletas adicionales'),
    autovalidateMode: AutovalidateMode.onUserInteraction,
    validator: (_) => widget.pasajero.errorMaletas,
    onChanged: (v) {
      widget.pasajero.maletas = v;
      widget.onChanged();
    },
  );
}
