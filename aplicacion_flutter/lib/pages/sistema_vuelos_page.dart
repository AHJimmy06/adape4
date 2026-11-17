import 'package:flutter/material.dart';

import '../models/ruta_vuelo.dart';
import '../services/api_service.dart';
import '../services/sistema_api.dart';
import '../utils/checkout_launcher.dart';
import '../utils/checkout_operacion.dart';
import '../widgets/sistema_compra/compra_sistema_dialog.dart';
import '../widgets/sistema_compra/ruta_aeropuertos.dart';
import 'sistema_reservas_page.dart';
import 'sistema_admin_page.dart';
import 'login_page.dart';

class SistemaVuelosPage extends StatefulWidget {
  const SistemaVuelosPage({
    super.key,
    required this.apiService,
    this.checkoutLauncher = abrirCheckout,
    this.routeBuilder,
  });
  final ApiService apiService;
  final CheckoutLauncher checkoutLauncher;
  final ConstructorRutaSistema? routeBuilder;
  @override
  State<SistemaVuelosPage> createState() => _SistemaVuelosPageState();
}

class _SistemaVuelosPageState extends State<SistemaVuelosPage> {
  late final _api = SistemaApi(widget.apiService);
  List<Map<String, dynamic>> _aeropuertos = [], _vuelos = [], _pedidos = [];
  String? _origen, _destino, _fecha, _error;
  bool _busy = false;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _cargar(inicial: true);
  }

  Future<void> _cargar({bool inicial = false}) async {
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
    });
    final parametros = <String, String>{
      'origen_id': ?_origen,
      'destino_id': ?_destino,
      'fecha': ?_fecha,
    };
    try {
      final resultados = await Future.wait([
        _api.lista('/vuelos', 'vuelos', parametros: parametros),
        _api.lista('/pedidos', 'pedidos'),
        if (inicial) _api.lista('/aeropuertos', 'aeropuertos'),
      ]);
      if (mounted && request == _request) {
        setState(() {
          _vuelos = resultados[0];
          _pedidos = resultados[1];
          if (inicial) _aeropuertos = resultados[2];
        });
      }
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = e.toString());
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Future<void> _reservar(Map<String, dynamic> vuelo) async {
    final ruta = Map<String, dynamic>.from(vuelo['ruta'] as Map);
    final geo = RutaVuelo.desdeAeropuertos(
      Map<String, dynamic>.from(ruta['origen'] as Map),
      Map<String, dynamic>.from(ruta['destino'] as Map),
    );
    final continuar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Tu ruta AeroTech'),
        content: SizedBox(
          width: 650,
          child: (widget.routeBuilder ?? ((_, r) => RutaAeropuertos(ruta: r)))(
            c,
            geo,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Elegir asientos'),
          ),
        ],
      ),
    );
    if (continuar != true || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CompraSistemaDialog(
        api: _api,
        vuelo: vuelo,
        launcher: widget.checkoutLauncher,
        onRefresh: () => _cargar(),
      ),
    );
    if (mounted) _cargar();
  }

  Widget _filtro(String label, String? value, ValueChanged<String?> changed) =>
      SizedBox(
        width: 250,
        child: DropdownButtonFormField<String>(
          initialValue: value,
          decoration: InputDecoration(labelText: label),
          isExpanded: true,
          items: [
            const DropdownMenuItem(value: null, child: Text('Todos')),
            for (final a in _aeropuertos)
              DropdownMenuItem(
                value: a['id'].toString(),
                child: Text('${a['iata']} · ${a['ciudad']}'),
              ),
          ],
          onChanged: _busy ? null : changed,
        ),
      );
  String _airport(dynamic a) =>
      a is Map ? '${a['iata']} · ${a['nombre']} (${a['ciudad']})' : '';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('AeroTech · Vuelos'),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      SistemaReservasPage(apiService: widget.apiService),
                ),
              ).then((_) {
                if (mounted) _cargar();
              }),
          child: const Text('Mis reservas'),
        ),
        if (widget.apiService.esAdministrador)
          IconButton(
            tooltip: 'Administración',
            onPressed: () =>
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        SistemaAdminPage(apiService: widget.apiService),
                  ),
                ).then((_) {
                  if (mounted) _cargar(inicial: true);
                }),
            icon: const Icon(Icons.admin_panel_settings),
          ),
        IconButton(
          tooltip: 'Cerrar sesión',
          onPressed: () {
            widget.apiService.cerrarSesion();
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute<void>(
                builder: (_) => LoginPage(apiService: widget.apiService),
              ),
              (_) => false,
            );
          },
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: () => _cargar(inicial: true),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Tu próximo destino empieza aquí',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const Text(
            'Aeropuertos reales · Asientos a elección · Pago seguro en Stripe TEST',
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _filtro('Origen', _origen, (v) => setState(() => _origen = v)),
              _filtro('Destino', _destino, (v) => setState(() => _destino = v)),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final now = DateTime.now();
                        final date = await showDatePicker(
                          context: context,
                          firstDate: now,
                          lastDate: now.add(const Duration(days: 730)),
                        );
                        if (date != null && mounted) {
                          setState(
                            () => _fecha = date
                                .toIso8601String()
                                .split('T')
                                .first,
                          );
                        }
                      },
                icon: const Icon(Icons.calendar_month),
                label: Text(_fecha ?? 'Fecha de salida'),
              ),
              if (_fecha != null)
                IconButton(
                  tooltip: 'Quitar fecha',
                  onPressed: () => setState(() => _fecha = null),
                  icon: const Icon(Icons.clear),
                ),
              FilledButton(
                onPressed: _busy ? null : () => _cargar(),
                child: const Text('Buscar vuelos'),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          if (_pedidos.any(
            (p) => [
              'preparando_pago',
              'pendiente_pago',
              'revision_pago',
            ].contains(p['estado']),
          ))
            ExpansionTile(
              title: const Text(
                'Pedidos pendientes · continuar o actualizar pago',
              ),
              children: [
                for (final p in _pedidos.where(
                  (p) => [
                    'preparando_pago',
                    'pendiente_pago',
                    'revision_pago',
                  ].contains(p['estado']),
                ))
                  PedidoSistema(
                    key: ValueKey(p['id']),
                    api: _api,
                    pedido: p,
                    launcher: widget.checkoutLauncher,
                    onRefresh: () => _cargar(),
                  ),
              ],
            ),
          if (!_busy && _vuelos.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No hay vuelos para estos filtros.'),
            ),
          for (final v in _vuelos) _tarjeta(v),
        ],
      ),
    ),
  );
  Widget _tarjeta(Map<String, dynamic> v) {
    final r = v['ruta'] as Map? ?? {};
    final a = r['origen'] as Map? ?? {};
    final b = r['destino'] as Map? ?? {};
    final avion = v['avion'] as Map? ?? {};
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${v['codigo']} · ${a['iata']} → ${b['iata']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text('${_airport(a)} → ${_airport(b)}'),
            const SizedBox(height: 8),
            Text('Salida: ${v['salida_local']} · ${a['zona_horaria']}'),
            Text('Llegada: ${v['llegada_local']} · ${b['zona_horaria']}'),
            Text('${avion['modelo']} · ${avion['matricula']}'),
            const SizedBox(height: 8),
            Text(
              'Desde ${dinero(v['precio_desde_centavos'])} + IVA · ${v['asientos_disponibles']} disponibles',
            ),
            Wrap(
              spacing: 12,
              children: [
                for (final t in mapas(v['tarifas']))
                  Chip(
                    label: Text(
                      '${t['clase_codigo']}: ${dinero(t['precio_centavos'])} · ${t['disponibles']} libres',
                    ),
                  ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed:
                    _busy || (v['asientos_disponibles'] as num? ?? 0) <= 0
                    ? null
                    : () => _reservar(v),
                icon: const Icon(Icons.airline_seat_recline_normal),
                label: const Text('Reservar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
