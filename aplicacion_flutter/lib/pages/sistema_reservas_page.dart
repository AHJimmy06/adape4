import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/sistema_api.dart';
import '../utils/checkout_operacion.dart';
import '../utils/formateador_xml.dart';
import '../widgets/sistema_compra/compra_sistema_dialog.dart';

class SistemaReservasPage extends StatefulWidget {
  const SistemaReservasPage({super.key, required this.apiService});
  final ApiService apiService;
  @override
  State<SistemaReservasPage> createState() => _SistemaReservasPageState();
}

class _SistemaReservasPageState extends State<SistemaReservasPage> {
  late final _api = SistemaApi(widget.apiService);
  List<Map<String, dynamic>> _reservas = [];
  bool _busy = false;
  String? _error;
  final Map<String, String> _retryKeys = {};
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
      final data = await _api.lista('/reservas', 'reservas');
      if (mounted) setState(() => _reservas = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _xml(Map<String, dynamic> reserva) async {
    setState(() => _busy = true);
    try {
      final xml = await _api.xml('/reservas/${reserva['id']}/comprobante.xml');
      if (!mounted) return;
      setState(() => _busy = false);
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Comprobante académico · no fiscal'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: SelectableText(
                formatearXml(xml),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cerrar'),
            ),
          ],
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
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          if (!_busy && _reservas.isEmpty)
            const Text('Todavía no tienes reservas confirmadas.'),
          for (final r in _reservas) _reserva(r),
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
              '${vuelo['codigo'] ?? 'Reserva'} · ${r['estado']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              '${a['iata'] ?? vuelo['origen'] ?? ''} ${a['ciudad'] ?? ''} → ${b['iata'] ?? vuelo['destino'] ?? ''} ${b['ciudad'] ?? ''}',
            ),
            Text(
              'Salida: ${vuelo['salida_local'] ?? vuelo['salida_en'] ?? ''} · ${a['zona_horaria'] ?? ''}',
            ),
            Text(
              'Llegada: ${vuelo['llegada_local'] ?? vuelo['llegada_en'] ?? ''} · ${b['zona_horaria'] ?? ''}',
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
                      '${s['codigo']} · ${s['clase_codigo']} · ${s['estado']} · ${dinero(s['total_centavos'])}',
                    ),
                  ),
              ],
            ),
            for (final c in mapas(r['cancelaciones']))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Reembolso: ${c['estado']} · ${dinero(c['importe_centavos'])}',
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
        builder: (cxt) => AlertDialog(
          title: Text(
            ['completada', 'cancelado'].contains(c['estado'])
                ? 'Reembolso confirmado'
                : 'Solicitud de reembolso: ${c['estado']}',
          ),
          content: Text(
            'Importe: ${dinero(c['importe_centavos'])}. Solo el servidor confirma la liberación de asientos.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(cxt),
              child: const Text('Aceptar'),
            ),
          ],
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
    return AlertDialog(
      title: const Text('Cancelación parcial'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Selecciona de 1 a ${legacy ? max : _activos.length} asiento(s) activos. Reembolso TEST del 100%, sin penalización.',
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
                    subtitle: Text(dinero(s['total_centavos'])),
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
              if (!legacy) Text('Reembolso estimado: ${dinero(quote)}'),
              const Text(
                'El importe final se calcula en el servidor. Un reembolso pendiente no libera asientos.',
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, _sent),
          child: const Text('Cerrar'),
        ),
        FilledButton(
          onPressed: _busy || (!legacy && _selected.isEmpty) || max < 1
              ? null
              : _confirmar,
          child: Text(
            _sent ? 'Reintentar misma cancelación' : 'Confirmar cancelación',
          ),
        ),
      ],
    );
  }
}
