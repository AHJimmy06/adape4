import 'package:flutter/material.dart';

import '../../services/sistema_api.dart';
import '../../services/api_service.dart';
import '../../utils/checkout_operacion.dart';
import '../../utils/checkout_launcher.dart';
import 'cabina_sistema.dart';

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
          builder: (c) => AlertDialog(
            title: const Text('La disponibilidad cambió'),
            content: const Text(
              'Otro pasajero eligió un asiento. Actualizaremos toda la cabina; elige nuevamente.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Aceptar'),
              ),
            ],
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
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _pedido == null
          ? 'Elige tus asientos · ${widget.vuelo['codigo']}'
          : 'Pedido · Stripe TEST',
    ),
    content: SizedBox(
      width: 680,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
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
      ),
    ),
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

  @override
  Widget build(BuildContext context) {
    final estado = _pedido['estado'];
    final pendiente = [
      'preparando_pago',
      'pendiente_pago',
      'revision_pago',
    ].contains(estado);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              estado == 'pagado'
                  ? 'Pago confirmado · reserva emitida'
                  : 'Pedido: $estado',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Asientos: ${mapas(_pedido['asientos']).map((s) => '${s['codigo']} (${s['clase_codigo']})').join(', ')}',
            ),
            Text(
              'Subtotal: ${dinero(_pedido['subtotal_centavos'])} · IVA: ${dinero(_pedido['iva_centavos'])}',
            ),
            Text('Total: ${dinero(_pedido['total_centavos'])}'),
            if (pendiente) ...[
              Text(
                'Vence: ${_pedido['vence_en'] ?? 'consulta el servidor'} · retención de 35 minutos',
              ),
              const Text(
                'Pagar o volver de Stripe no confirma la reserva. Actualiza el pago para verificarlo.',
              ),
            ],
            if (_pedido['mensaje'] != null) Text(_pedido['mensaje'].toString()),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            if (_busy) const LinearProgressIndicator(),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (pendiente && _pedido['checkout_url'] != null)
                  FilledButton(
                    onPressed: _busy ? null : _abrir,
                    child: const Text('Pagar con Stripe TEST'),
                  ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _actualizar(),
                  child: const Text('Actualizar pago'),
                ),
                if (pendiente)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _actualizar(abandonar: true),
                    child: const Text('Abandonar pedido'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
