import 'package:flutter/material.dart';

import '../../services/sistema_api.dart';
import '../../services/api_service.dart';
import '../../utils/checkout_operacion.dart';
import '../../utils/checkout_launcher.dart';
import 'cabina_sistema.dart';
import '../../theme/aerotech_theme.dart';
import '../presentacion/dialogo_aerotech.dart';

List<Map<String, dynamic>> mapas(dynamic values) => (values as List? ?? [])
    .map((v) => Map<String, dynamic>.from(v as Map))
    .toList();

class CompraSistemaDialog extends StatefulWidget {
  const CompraSistemaDialog({
    super.key,
    required this.api,
    required this.vuelo,
    required this.launcher,
    required this.onRefresh,
  });
  final SistemaApi api;
  final Map<String, dynamic> vuelo;
  final CheckoutLauncher launcher;
  final VoidCallback onRefresh;
  @override
  State<CompraSistemaDialog> createState() => _CompraSistemaDialogState();
}

class _CompraSistemaDialogState extends State<CompraSistemaDialog> {
  Map<String, dynamic>? _mapa, _pedido;
  final _seleccion = <String>{};
  final _operacion = CheckoutOperacion();
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.api.get(
        '/vuelos/${widget.vuelo['id']}/asientos',
      );
      if (mounted) setState(() => _mapa = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _comprar() async {
    final codes = _seleccion.toList()..sort();
    if (codes.isEmpty || _busy) return;
    final key = _operacion.preparar(widget.vuelo['id'].toString(), codes);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.api.post(
        '/pedidos',
        body: {
          'vuelo_id': widget.vuelo['id'],
          'asientos': codes,
          'clave_operacion': key,
        },
      );
      if (mounted) {
        setState(
          () => _pedido = Map<String, dynamic>.from(data['pedido'] as Map),
        );
      }
      widget.onRefresh();
    } catch (e) {
      if (!mounted) return;
      if (e is ExcepcionApi && e.codigo == 409) {
        setState(() => _busy = false);
        await showDialog<void>(
          context: context,
          builder: (c) => DialogoAerotech(
            title: 'La disponibilidad cambió',
            subtitle: 'Revisa la selección antes de continuar.',
            icon: Icons.event_seat_outlined,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Aceptar'),
              ),
            ],
            child: const PanelMensaje(
              'Otro pasajero eligió un asiento. Actualizaremos toda la cabina; elige nuevamente.',
            ),
          ),
        );
        _seleccion.clear();
        _operacion.limpiar();
        widget.onRefresh();
        await _cargar();
      } else {
        setState(
          () => _error = e is ExcepcionApi && e.codigo == 503
              ? 'Pagos no disponibles: falta configurar Stripe TEST o el proveedor no responde. No hay una reserva confirmada. Reintenta con la misma selección.'
              : e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DialogoAerotech(
    key: ValueKey(_pedido == null ? 'cabina' : 'pedido'),
    title: _pedido == null
        ? 'Elige tus asientos · ${widget.vuelo['codigo']}'
        : 'Pedido · Stripe TEST',
    subtitle: _pedido == null
        ? 'Selecciona tu lugar y revisa los detalles de tu viaje.'
        : 'Revisa tu pedido y continúa al pago seguro.',
    eyebrow: _pedido == null ? 'TU PRÓXIMO VIAJE' : 'RESUMEN DE COMPRA',
    icon: _pedido == null
        ? Icons.airline_seat_recline_normal
        : Icons.receipt_long_outlined,
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cerrar'),
      ),
      if (_pedido == null)
        FilledButton(
          onPressed: _busy || _seleccion.isEmpty ? null : _comprar,
          child: Text('Continuar con ${_seleccion.length} asiento(s)'),
        ),
    ],
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null) PanelMensaje(_error!, error: true),
        if (_busy) const LinearProgressIndicator(),
        if (_pedido != null)
          PedidoSistema(
            api: widget.api,
            pedido: _pedido!,
            launcher: widget.launcher,
            onRefresh: widget.onRefresh,
          )
        else if (_mapa != null)
          CabinaSistema(
            clases: mapas(_mapa!['clases']),
            asientos: mapas(_mapa!['asientos']),
            seleccionados: _seleccion,
            bloqueada: _busy,
            onChanged: (code) => setState(() {
              if (!_seleccion.add(code)) _seleccion.remove(code);
              _operacion.limpiar();
            }),
          ),
        if (_mapa == null && !_busy)
          TextButton(
            onPressed: _cargar,
            child: const Text('Reintentar cabina'),
          ),
      ],
    ),
  );
}

class PedidoSistema extends StatefulWidget {
  const PedidoSistema({
    super.key,
    required this.api,
    required this.pedido,
    required this.launcher,
    required this.onRefresh,
  });
  final SistemaApi api;
  final Map<String, dynamic> pedido;
  final CheckoutLauncher launcher;
  final VoidCallback onRefresh;
  @override
  State<PedidoSistema> createState() => _PedidoSistemaState();
}

class _PedidoSistemaState extends State<PedidoSistema> {
  late Map<String, dynamic> _pedido = widget.pedido;
  bool _busy = false;
  String? _error;
  final _abandonarKey = nuevaClaveOperacion();
  @override
  void didUpdateWidget(covariant PedidoSistema old) {
    super.didUpdateWidget(old);
    if (old.pedido != widget.pedido) _pedido = widget.pedido;
  }

  Future<void> _actualizar({bool abandonar = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = abandonar
          ? await widget.api.post(
              '/pedidos/${_pedido['id']}/abandonar',
              body: {'clave_operacion': _abandonarKey},
            )
          : await widget.api.get('/pedidos/${_pedido['id']}');
      if (mounted) {
        setState(
          () => _pedido = Map<String, dynamic>.from(data['pedido'] as Map),
        );
      }
      widget.onRefresh();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo verificar el pago. Los asientos no se liberan hasta confirmación del servidor. $e',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _abrir() async {
    final uri = Uri.tryParse(_pedido['checkout_url']?.toString() ?? '');
    try {
      if (uri == null || !esCheckoutSeguro(uri)) {
        throw const FormatException(
          'Enlace de pago no válido. Actualiza el pedido.',
        );
      }
      final opened = await widget.launcher(uri);
      if (!opened) {
        throw const FormatException(
          'El navegador bloqueó el pago. Permite la nueva pestaña y reintenta.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Widget _importe(String label, String value) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    spacing: 12,
    runSpacing: 4,
    children: [
      Text(
        '$label:',
        style: const TextStyle(color: AerotechTheme.textSecondary),
      ),
      Text(
        value,
        style: const TextStyle(
          color: AerotechTheme.navy,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final estado = _pedido['estado'];
    final pendiente = [
      'preparando_pago',
      'pendiente_pago',
      'revision_pago',
    ].contains(estado);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AerotechTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AerotechTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerLeft, child: EtiquetaEstado(estado)),
          const SizedBox(height: 16),
          const Text(
            'TUS ASIENTOS',
            style: TextStyle(
              color: AerotechTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final seat in mapas(_pedido['asientos']))
                Chip(
                  avatar: const Icon(Icons.event_seat_outlined, size: 18),
                  label: Text('${seat['codigo']} · ${seat['clase_codigo']}'),
                  backgroundColor: AerotechTheme.inputFill,
                  side: const BorderSide(color: AerotechTheme.border),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AerotechTheme.inputFill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AerotechTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _importe('Subtotal', dinero(_pedido['subtotal_centavos'])),
                const SizedBox(height: 8),
                _importe('IVA', dinero(_pedido['iva_centavos'])),
                const Divider(height: 20),
                const Text(
                  'TOTAL A PAGAR',
                  style: TextStyle(
                    color: AerotechTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  dinero(_pedido['total_centavos']),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: AerotechTheme.navy,
                    letterSpacing: -1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AccionesDialogo(
            children: [
              if (pendiente && _pedido['checkout_url'] != null)
                FilledButton.icon(
                  onPressed: _busy ? null : _abrir,
                  icon: const Icon(Icons.lock_outline, size: 18),
                  label: const Text(
                    'Pagar con Stripe TEST',
                    textAlign: TextAlign.center,
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _actualizar(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text(
                  'Actualizar pago',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          if (pendiente) ...[
            const SizedBox(height: 18),
            const Text(
              'Vencimiento del pedido',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AerotechTheme.navy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              fechaLegible(_pedido['vence_en'], horaEcuador: true),
              style: const TextStyle(color: AerotechTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Retención de asientos: 35 minutos',
              style: TextStyle(
                fontSize: 12,
                color: AerotechTheme.textSecondary,
              ),
            ),
            const PanelMensaje(
              'Pagar o volver de Stripe no confirma la reserva. Actualiza el pago para verificarlo.',
            ),
          ],
          if (_pedido['mensaje'] != null)
            PanelMensaje(_pedido['mensaje'].toString()),
          if (_error != null) PanelMensaje(_error!, error: true),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 16),
          if (pendiente) ...[
            const SizedBox(height: 14),
            const Divider(),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: _busy ? null : () => _actualizar(abandonar: true),
                child: const Text('Abandonar pedido'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
