import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/sistema_api.dart';
import '../../services/api_service.dart';
import '../../utils/checkout_operacion.dart';
import '../../utils/checkout_launcher.dart';
import 'cabina_sistema.dart';
import 'stripe_embebido.dart';
import 'autenticacion_compra.dart';
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
    final teniaSesion = widget.api.apiService.tieneSesion;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.api.get(
        '/vuelos/${widget.vuelo['id']}/asientos',
        requiereToken: teniaSesion,
      );
      if (mounted) setState(() => _mapa = data);
    } catch (e) {
      if (e is ExcepcionApi && e.codigo == 401 && mounted && teniaSesion) {
        widget.api.apiService.cerrarSesion();
        setState(() => _busy = false);
        await _cargar();
        return;
      }
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _comprar({bool reautenticar = true}) async {
    final codes = _seleccion.toList()..sort();
    if (codes.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!widget.api.apiService.tieneSesion) {
        setState(() => _busy = false);
        final ingreso = await autenticarCompra(context, widget.api.apiService);
        if (!mounted || !ingreso) return;
        setState(() => _busy = true);
        // La selección del invitado no retiene inventario; se revalida al entrar.
        final mapa = await widget.api.get(
          '/vuelos/${widget.vuelo['id']}/asientos',
        );
        if (!mounted) return;
        final libres = mapas(mapa['asientos'])
            .where((s) => s['estado'] == 'libre')
            .map((s) => s['codigo'])
            .toSet();
        setState(() => _mapa = mapa);
        if (codes.any((c) => !libres.contains(c))) {
          setState(() {
            _seleccion.removeWhere((c) => !libres.contains(c));
            _error = 'La disponibilidad cambió mientras ingresabas. Conservamos los asientos libres; revisa tu selección.';
          });
          _operacion.limpiar();
          widget.onRefresh();
          return;
        }
      }
      final key = _operacion.preparar(widget.vuelo['id'].toString(), codes);
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
      if (e is ExcepcionApi && e.codigo == 401) {
        widget.api.apiService.cerrarSesion();
        if (reautenticar) {
          setState(() => _busy = false);
          await _comprar(reautenticar: false);
        } else {
          setState(
            () => _error = 'La sesión no pudo validarse. Conservamos tu selección; vuelve a intentar iniciar sesión.',
          );
        }
      } else if (e is ExcepcionApi && e.codigo == 409) {
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
    onClose: () {
      if (!_busy) Navigator.pop(context);
    },
    actions: [
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
    this.stripeBuilder,
  });
  final SistemaApi api;
  final Map<String, dynamic> pedido;
  final CheckoutLauncher launcher;
  final VoidCallback onRefresh;
  final Widget Function(String secret, String key, VoidCallback onComplete)?
  stripeBuilder;
  @override
  State<PedidoSistema> createState() => _PedidoSistemaState();
}

class _PedidoSistemaState extends State<PedidoSistema> {
  late Map<String, dynamic> _pedido = widget.pedido;
  bool _busy = false;
  String? _error;
  final _abandonarKey = nuevaClaveOperacion();
  Timer? _poll;
  var _pollCount = 0;
  String? _clientSecret, _publishableKey;
  BuildContext? _pagoContext;
  bool _pagoAbierto = false;
  bool get _pendiente => [
    'preparando_pago',
    'pendiente_pago',
    'revision_pago',
  ].contains(_pedido['estado']);
  @override
  void initState() {
    super.initState();
    _programar();
  }

  void _programar() {
    _poll?.cancel();
    if (!_pendiente || !mounted) return;
    _poll = Timer(
      Duration(
        seconds: _pollCount < 6
            ? 5
            : _pollCount < 30
            ? 15
            : 30,
      ),
      () async {
        _pollCount++;
        await _actualizar(silencioso: true);
        _programar();
      },
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PedidoSistema old) {
    super.didUpdateWidget(old);
    if (old.pedido['id'] != widget.pedido['id']) {
      _pedido = widget.pedido;
      _clientSecret = null;
      _publishableKey = null;
      _pollCount = 0;
      _programar();
    } else if (_pendiente ||
        ![
          'preparando_pago',
          'pendiente_pago',
          'revision_pago',
        ].contains(widget.pedido['estado'])) {
      _pedido = widget.pedido;
      if (!_pendiente) _poll?.cancel();
    }
  }

  Future<void> _actualizar({
    bool abandonar = false,
    bool silencioso = false,
  }) async {
    if (_busy) return;
    final anterior = _pedido['estado'];
    setState(() {
      _busy = true;
      if (!silencioso) _error = null;
      if (abandonar) {
        _clientSecret = null;
        _publishableKey = null;
      }
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
      if (abandonar || anterior != _pedido['estado']) widget.onRefresh();
      if (!_pendiente &&
          _pagoAbierto &&
          _pagoContext?.mounted == true &&
          ModalRoute.of(_pagoContext!)?.isCurrent == true) {
        Navigator.of(_pagoContext!).pop();
      }
    } catch (e) {
      if (mounted && !silencioso) {
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
    if (_busy || _pagoAbierto) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.api.post(
        '/pedidos/${_pedido['id']}/pago-embebido',
      );
      if (!mounted) return;
      final secret = data['client_secret'];
      final key = data['publishable_key'];
      if (secret is! String || key is! String || !key.startsWith('pk_test_')) {
        throw const FormatException(
          'El formulario seguro no está disponible para este pedido.',
        );
      }
      setState(() {
        _clientSecret = secret;
        _publishableKey = key;
        _busy = false;
      });
      _pagoAbierto = true;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (modalContext) {
          _pagoContext = modalContext;
          final viewport = MediaQuery.sizeOf(modalContext);
          return Dialog(
            key: const ValueKey('modal-pago-stripe'),
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            insetPadding: EdgeInsets.all(viewport.width < 600 ? 8 : 24),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: SizedBox(
              width: 1080,
              height: (viewport.height - (viewport.width < 600 ? 16 : 48))
                  .clamp(240, 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Pago seguro · Stripe TEST',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 20,
                                  color: AerotechTheme.navy,
                                ),
                              ),
                              Text(
                                'Total: ${dinero(_pedido['total_centavos'])}',
                                style: const TextStyle(
                                  color: AerotechTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar pago',
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(modalContext),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child:
                        widget.stripeBuilder?.call(
                          _clientSecret!,
                          _publishableKey!,
                          () => _actualizar(),
                        ) ??
                        StripeEmbebido(
                          clientSecret: _clientSecret!,
                          publishableKey: _publishableKey!,
                          onComplete: () => _actualizar(),
                        ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      _pagoAbierto = false;
      _pagoContext = null;
      _clientSecret = null;
      _publishableKey = null;
      if (mounted) setState(() => _busy = false);
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
          if (pendiente)
            FilledButton.icon(
              onPressed: _busy ? null : _abrir,
              icon: const Icon(Icons.lock_outline, size: 18),
              label: const Text(
                'Pagar con Stripe TEST',
                textAlign: TextAlign.center,
              ),
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
              'El pago se verifica automáticamente con el servidor. Los asientos están retenidos temporalmente, no reservados hasta confirmar el pago. Puedes cerrar y continuar desde Pendientes de pago.',
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
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.delete_outline),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: _busy ? null : () => _actualizar(abandonar: true),
                label: const Text('Abandonar pedido'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
