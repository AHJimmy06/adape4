import '../widgets/sistema_compra/detalle_pasajero.dart';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/sistema_api.dart';
import '../utils/checkout_operacion.dart';
import '../utils/checkout_launcher.dart';
import '../utils/formateador_xml.dart';
import '../widgets/presentacion/dialogo_aerotech.dart';
import '../theme/aerotech_theme.dart';
import '../widgets/sistema_compra/compra_sistema_dialog.dart';
import '../widgets/sistema_compra/gestionar_accesos_reserva.dart';
import 'sistema_vuelos_page.dart';

class SistemaReservasPage extends StatefulWidget {
  const SistemaReservasPage({super.key, required this.apiService});
  final ApiService apiService;
  @override
  State<SistemaReservasPage> createState() => _SistemaReservasPageState();
}

class _SistemaReservasPageState extends State<SistemaReservasPage> {
  late final _api = SistemaApi(widget.apiService);
  List<Map<String, dynamic>> _reservas = [];
  List<Map<String, dynamic>> _pedidos = [];
  List<Map<String, dynamic>> _compartidos = [];
  bool _cargandoCompartidos = false;
  String? _errorCompartidos;
  bool _busy = false;
  String? _error;
  final Map<String, String> _retryKeys = {};
  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final compartidos = _cargarCompartidos();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await _api.lista('/reservas', 'reservas');
      if (mounted) setState(() => _reservas = data);
      final pedidos = await _api.lista('/pedidos', 'pedidos');
      if (mounted) {
        setState(
          () => _pedidos = pedidos
              .where(
                (p) => [
                  'preparando_pago',
                  'pendiente_pago',
                  'revision_pago',
                ].contains(p['estado']),
              )
              .toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      await compartidos;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cargarCompartidos() async {
    if (_cargandoCompartidos) return;
    setState(() {
      _cargandoCompartidos = true;
      _errorCompartidos = null;
      _compartidos = [];
    });
    try {
      final data = await _api.lista('/asientos-compartidos', 'asientos');
      if (mounted) setState(() => _compartidos = data);
    } catch (e) {
      if (mounted) setState(() => _errorCompartidos = e.toString());
    } finally {
      if (mounted) setState(() => _cargandoCompartidos = false);
    }
  }

  Future<void> _gestionarAccesos(Map<String, dynamic> reserva) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => GestionarAccesosReserva(
        api: _api,
        reservaId: reserva['id'].toString(),
      ),
    );
    if (mounted) await _cargar();
  }

  Widget _asientoCompartido(Map<String, dynamic> asiento) {
    final vuelo = asiento['vuelo'] as Map? ?? {};
    final ruta = vuelo['ruta'] as Map? ?? {};
    final origen = ruta['origen'] as Map? ?? {};
    final destino = ruta['destino'] as Map? ?? {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${vuelo['codigo']} · Asiento ${asiento['codigo']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${origen['iata']} ${origen['ciudad']} → ${destino['iata']} ${destino['ciudad']}',
            ),
            Text(
              'Salida: ${fechaLegible(vuelo['salida_local'], zona: origen['zona_horaria']?.toString())}',
            ),
            Text(
              'Llegada: ${fechaLegible(vuelo['llegada_local'], zona: destino['zona_horaria']?.toString())}',
            ),
            Text(
              'Clase: ${asiento['clase_codigo']} · Categoría: ${asiento['categoria']}',
            ),
            Text('Maletas adicionales: ${asiento['maletas_adicionales'] ?? 0}'),
          ],
        ),
      ),
    );
  }

  Future<void> _continuarPago(Map<String, dynamic> pedido) async {
    final abandonado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => DialogoAerotech(
        title: 'Tu pedido pendiente',
        subtitle: 'Continúa el pago sin volver a seleccionar tus asientos.',
        icon: Icons.payments_outlined,
        onClose: () => Navigator.pop(c),
        actions: const [],
        child: PedidoSistema(
          api: _api,
          pedido: pedido,
          launcher: abrirCheckout,
          onRefresh: _cargar,
          onAbandonado: () {
            if (c.mounted && ModalRoute.of(c)?.isCurrent == true) {
              Navigator.pop(c, true);
            }
          },
        ),
      ),
    );
    if (!mounted) return;
    if (abandonado == true) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (_) => SistemaVuelosPage(apiService: widget.apiService),
          ),
        );
      }
    } else {
      await _cargar();
    }
  }

  Widget _pendiente(Map<String, dynamic> p) {
    final vuelo = p['vuelo'] as Map? ?? {};
    final asientos = mapas(p['asientos']).map((s) => s['codigo']).join(', ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pedido · ${vuelo['codigo'] ?? p['codigo_vuelo'] ?? 'Tu vuelo'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Asientos: $asientos'),
            Text('Total: ${dinero(p['total_centavos'])}'),
            const SizedBox(height: 8),
            Text('Vence: ${fechaLegible(p['vence_en'], horaEcuador: true)}'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _continuarPago(p),
              icon: const Icon(Icons.lock_outline),
              label: const Text('Continuar pago'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _xml(Map<String, dynamic> reserva) async {
    setState(() => _busy = true);
    try {
      final xml = await _api.xml('/reservas/${reserva['id']}/comprobante.xml');
      if (!mounted) return;
      setState(() => _busy = false);
      await showDialog<void>(
        context: context,
        builder: (c) => DialogoAerotech(
          maxWidth: 800,
          title: 'Comprobante académico · no fiscal',
          subtitle: 'Consulta el documento XML de tu reserva. No constituye una factura electrónica.',
          eyebrow: 'DOCUMENTOS DE TU VIAJE',
          icon: Icons.description_outlined,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cerrar'),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AerotechTheme.inputFill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AerotechTheme.border),
            ),
            child: SelectableText(
              formatearXml(xml),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.65,
                color: AerotechTheme.navy,
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelar(Map<String, dynamic> reserva) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CancelacionSistemaDialog(api: _api, reserva: reserva),
    );
    if (changed == true && mounted) _cargar();
  }

  Future<void> _reintentar(
    Map<String, dynamic> r,
    Map<String, dynamic> c,
  ) async {
    final id = '${r['id']}/${c['id']}';
    final key = _retryKeys.putIfAbsent(id, nuevaClaveOperacion);
    setState(() => _busy = true);
    try {
      await _api.post(
        '/reservas/${r['id']}/cancelaciones/${c['id']}/reintentar',
        body: {'clave_operacion': key},
      );
      if (mounted) await _cargar();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Mis reservas AeroTech'),
      actions: [
        IconButton(
          onPressed: _busy ? null : _cargar,
          tooltip: 'Actualizar reservas',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) PanelMensaje(_error!, error: true),
          if (_pedidos.isNotEmpty) ...[
            Text(
              'Pendientes de pago',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Todavía no son reservas confirmadas. Continúa el pago o abandona el pedido para liberar sus asientos.',
            ),
            for (final p in _pedidos) _pendiente(p),
            const SizedBox(height: 24),
          ],
          if (!_busy && _reservas.isEmpty)
            const Text('Todavía no tienes reservas confirmadas.'),
          for (final r in _reservas) _reserva(r),
          const SizedBox(height: 24),
          Text(
            'Asientos compartidos conmigo',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const Text(
            'Solo consulta. El comprador puede cambiar o retirar tu acceso; actualiza para consultar los permisos vigentes.',
          ),
          TextButton.icon(
            onPressed: _cargandoCompartidos ? null : _cargarCompartidos,
            icon: const Icon(Icons.refresh),
            label: const Text('Actualizar asientos compartidos'),
          ),
          if (_cargandoCompartidos) const LinearProgressIndicator(),
          if (_errorCompartidos != null)
            PanelMensaje(_errorCompartidos!, error: true),
          if (!_cargandoCompartidos &&
              _errorCompartidos == null &&
              _compartidos.isEmpty)
            const Text('No tienes asientos compartidos vigentes.'),
          for (final s in _compartidos) _asientoCompartido(s),
        ],
      ),
    ),
  );
  Widget _reserva(Map<String, dynamic> r) {
    final vuelo = r['vuelo'] as Map? ?? {};
    final ruta = vuelo['ruta'] as Map? ?? {};
    final a = ruta['origen'] as Map? ?? {};
    final b = ruta['destino'] as Map? ?? {};
    final seats = mapas(r['asientos']);
    final salida = DateTime.tryParse(vuelo['salida_en']?.toString() ?? '');
    final antes = salida != null && DateTime.now().isBefore(salida);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${vuelo['codigo'] ?? 'Reserva'}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            EtiquetaEstado(r['estado']),
            const SizedBox(height: 16),
            Text(
              '${a['iata'] ?? vuelo['origen'] ?? ''} ${a['ciudad'] ?? ''} → ${b['iata'] ?? vuelo['destino'] ?? ''} ${b['ciudad'] ?? ''}',
            ),
            Text(
              'Salida: ${fechaLegible(vuelo['salida_local'] ?? vuelo['salida_en'], zona: a['zona_horaria']?.toString())}',
            ),
            Text(
              'Llegada: ${fechaLegible(vuelo['llegada_local'] ?? vuelo['llegada_en'], zona: b['zona_horaria']?.toString())}',
            ),
            if (r['legada'] == true)
              const Text(
                'Reserva anterior: no se asignaron etiquetas de asiento ni pagos de Stripe.',
              ),
            Text('Total original: ${dinero(r['total_centavos'])}'),
            Text('Reembolsado: ${dinero(r['reembolsado_centavos'])}'),
            Text(
              'Importe restante: ${dinero(((r['total_centavos'] as num?)?.toInt() ?? 0) - ((r['reembolsado_centavos'] as num?)?.toInt() ?? 0))}',
            ),
            Text(
              'Activos: ${r['cantidad_activa']} · Cancelados: ${r['cantidad_cancelada']}',
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final s in seats)
                  Chip(
                    label: Text(
                      '${s['codigo']} · ${s['clase_codigo']} · ${estadoLegible(s['estado'])} · ${dinero(s['total_centavos'])}',
                    ),
                  ),
              ],
            ),
            for (final s in seats) DetallePasajero(asiento: s),
            for (final c in mapas(r['cancelaciones']))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Reembolso: ${estadoLegible(c['estado'])} · ${dinero(c['importe_centavos'])}',
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
                        onPressed: _busy ? null : () => _reintentar(r, c),
                        child: const Text('Reintentar reembolso'),
                      ),
                  ],
                ),
              ),
            if (seats.any((s) => s['estado'] == 'reembolso_pendiente'))
              const Text(
                'El reembolso sigue pendiente. Los asientos no se liberan hasta la confirmación del servidor.',
              ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : () => _xml(r),
                  child: const Text('Ver comprobante XML'),
                ),
                if (antes &&
                    r['legada'] != true &&
                    seats.any((s) => s['estado'] == 'activo'))
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _gestionarAccesos(r),
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: const Text('Gestionar accesos'),
                  ),
                if (antes && ((r['cantidad_activa'] as num?) ?? 0) > 0)
                  TextButton(
                    onPressed: _busy ? null : () => _cancelar(r),
                    child: const Text('Cancelar asientos'),
                  ),
              ],
            ),
            if (!antes)
              const Text(
                'La cancelación está disponible únicamente antes de la salida.',
              ),
          ],
        ),
      ),
    );
  }
}

class CancelacionSistemaDialog extends StatefulWidget {
  const CancelacionSistemaDialog({
    super.key,
    required this.api,
    required this.reserva,
  });
  final SistemaApi api;
  final Map<String, dynamic> reserva;
  @override
  State<CancelacionSistemaDialog> createState() =>
      _CancelacionSistemaDialogState();
}

class _CancelacionSistemaDialogState extends State<CancelacionSistemaDialog> {
  final _selected = <String>{};
  final _operacion = CheckoutOperacion();
  bool _busy = false, _sent = false;
  String? _error;
  int _cantidad = 1;
  List<Map<String, dynamic>> get _activos =>
      mapas(widget.reserva['asientos'])
          .where((s) => s['estado'] == 'activo')
          .toList();
  Future<void> _confirmar() async {
    final legacy = widget.reserva['legada'] == true;
    final codes = _selected.toList()..sort();
    if (_busy || (!legacy && codes.isEmpty)) return;
    final key = _operacion.preparar(
      widget.reserva['id'].toString(),
      legacy ? ['cantidad:$_cantidad'] : codes,
    );
    setState(() {
      _busy = true;
      _error = null;
      _sent = true;
    });
    try {
      final data = await widget.api.post(
        '/reservas/${widget.reserva['id']}/cancelaciones',
        body: {
          if (legacy) 'cantidad': _cantidad else 'asientos': codes,
          'clave_operacion': key,
        },
      );
      if (!mounted) return;
      setState(() => _busy = false);
      final c = data['cancelacion'] as Map;
      await showDialog<void>(
        context: context,
        builder: (cxt) => DialogoAerotech(
          icon: Icons.currency_exchange,
          subtitle: 'El servidor verifica el resultado de la solicitud.',
          title: ['completada', 'cancelado'].contains(c['estado'])
              ? 'Reembolso confirmado'
              : 'Solicitud de reembolso: ${estadoLegible(c['estado'])}',
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(cxt),
              child: const Text('Aceptar'),
            ),
          ],
          child: PanelMensaje(
            'Importe: ${dinero(c['importe_centavos'])}. Solo el servidor confirma la liberación de asientos.',
          ),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo confirmar la cancelación. Reintenta la misma operación o actualiza tus reservas. $e',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final legacy = widget.reserva['legada'] == true;
    final max = (widget.reserva['cantidad_activa'] as num?)?.toInt() ?? 0;
    final quote = _activos
        .where((s) => _selected.contains(s['codigo']))
        .fold<int>(0, (sum, s) => sum + (s['total_centavos'] as num).toInt());
    return DialogoAerotech(
      maxWidth: 580,
      title: 'Cancelación parcial',
      subtitle: 'Elige únicamente los asientos que deseas cancelar.',
      eyebrow: 'ADMINISTRA TU RESERVA',
      icon: Icons.event_seat_outlined,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, _sent),
          child: const Text('Cerrar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: _busy || (!legacy && _selected.isEmpty) || max < 1
              ? null
              : _confirmar,
          child: Text(
            _sent ? 'Reintentar misma cancelación' : 'Confirmar cancelación',
          ),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Selecciona de 1 a ${legacy ? max : _activos.length} asiento(s) activos. Reembolso TEST del 100%, sin penalización.',
          ),
          if (_activos.any(
            (s) => ((s['equipaje'] as Map?)?['cantidad'] as num? ?? 0) > 0,
          ))
            const Text(
              'El reembolso de cada asiento incluye su equipaje adicional.',
            ),
          if (legacy)
            Row(
              children: [
                IconButton(
                  onPressed: _busy || _sent || _cantidad <= 1
                      ? null
                      : () => setState(() => _cantidad--),
                  icon: const Icon(Icons.remove),
                ),
                Text('$_cantidad'),
                IconButton(
                  onPressed: _busy || _sent || _cantidad >= max
                      ? null
                      : () => setState(() => _cantidad++),
                  icon: const Icon(Icons.add),
                ),
              ],
            )
          else
            for (final s in _activos)
              CheckboxListTile(
                title: Text('${s['codigo']} · ${s['clase_codigo']}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dinero(s['total_centavos'])),
                    DetallePasajero(asiento: s),
                  ],
                ),
                value: _selected.contains(s['codigo']),
                onChanged: _busy || _sent
                    ? null
                    : (v) => setState(() {
                        if (v == true) {
                          _selected.add(s['codigo'].toString());
                        } else {
                          _selected.remove(s['codigo']);
                        }
                      }),
              ),
          if (!legacy)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 16, bottom: 8),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AerotechTheme.inputFill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AerotechTheme.border),
              ),
              child: Text(
                'Reembolso estimado: ${dinero(quote)}',
                style: const TextStyle(
                  color: AerotechTheme.navy,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const PanelMensaje(
            'El importe final se calcula en el servidor. Un reembolso pendiente no libera asientos.',
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) PanelMensaje(_error!, error: true),
        ],
      ),
    );
  }
}
