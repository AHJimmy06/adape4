import 'package:flutter/material.dart';

import '../models/ruta_vuelo.dart';
import '../widgets/tarjeta_destino.dart';
import '../services/api_service.dart';
import '../services/sistema_api.dart';
import '../utils/checkout_launcher.dart';
import '../widgets/sistema_compra/compra_sistema_dialog.dart';
import '../widgets/sistema_compra/ruta_aeropuertos.dart';
import 'sistema_reservas_page.dart';
import 'sistema_admin_page.dart';
import '../widgets/sistema_compra/autenticacion_compra.dart';
import '../theme/aerotech_theme.dart';

class SistemaVuelosPage extends StatefulWidget {
  const SistemaVuelosPage({
    super.key,
    required this.apiService,
    this.checkoutLauncher = abrirCheckout,
    this.routeBuilder,
    this.vueloInicial,
  });
  final ApiService apiService;
  final CheckoutLauncher checkoutLauncher;
  final ConstructorRutaSistema? routeBuilder;
  final Map<String, dynamic>? vueloInicial;
  @override
  State<SistemaVuelosPage> createState() => _SistemaVuelosPageState();
}

class _SistemaVuelosPageState extends State<SistemaVuelosPage> {
  late final _api = SistemaApi(widget.apiService);
  List<Map<String, dynamic>> _aeropuertos = [], _vuelos = [], _pedidos = [];
  String? _origen, _destino, _fecha, _error;
  DateTimeRange? _rango;
  bool _busy = false;
  int _request = 0;
  bool _vueloInicialAtendido = false;
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
      if (_rango != null) 'fecha_desde': _dia(_rango!.start),
      if (_rango != null) 'fecha_hasta': _dia(_rango!.end),
    };
    try {
      final resultados = await Future.wait([
        _api.lista(
          '/vuelos',
          'vuelos',
          parametros: parametros,
          requiereToken: widget.apiService.tieneSesion,
        ),
        widget.apiService.tieneSesion
            ? _api.lista('/pedidos', 'pedidos')
            : Future.value(<Map<String, dynamic>>[]),
        if (inicial)
          _api.lista(
            '/aeropuertos',
            'aeropuertos',
            requiereToken: widget.apiService.tieneSesion,
          ),
      ]);
      if (mounted && request == _request) {
        setState(() {
          _vuelos = resultados[0];
          _pedidos = resultados[1];
          if (inicial) _aeropuertos = resultados[2];
        });
        _abrirVueloInicial();
      }
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = e.toString());
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  void _abrirVueloInicial() {
    final id = widget.vueloInicial?['id'];
    if (_vueloInicialAtendido || id == null) return;
    _vueloInicialAtendido = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final actuales = _vuelos.where(
        (v) =>
            v['id'] == id &&
            v['activo'] != false &&
            ((v['asientos_disponibles'] as num?)?.toInt() ?? 0) > 0,
      );
      if (actuales.isEmpty) {
        setState(
          () => _error = 'El vuelo seleccionado ya no está disponible. Elige otro vuelo del catálogo.',
        );
        return;
      }
      _reservar(actuales.first);
    });
  }

  Future<void> _reservar(Map<String, dynamic> vuelo) async {
    final ruta = Map<String, dynamic>.from(vuelo['ruta'] as Map);
    final geo = RutaVuelo.desdeAeropuertos(
      Map<String, dynamic>.from(ruta['origen'] as Map),
      Map<String, dynamic>.from(ruta['destino'] as Map),
    );
    final continuar = await showDialog<bool>(
      context: context,
      builder: (c) {
        if (geo.esInternacional) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 16,
            ),
            child: SizedBox(
              width: 1040,
              height: (MediaQuery.sizeOf(c).height - 32)
                  .clamp(0, 820)
                  .toDouble(),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Tu ruta AeroTech',
                      style: Theme.of(c).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child:
                          (widget.routeBuilder ??
                          ((_, r) => RutaAeropuertos(ruta: r)))(c, geo),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
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
                  ],
                ),
              ),
            ),
          );
        }
        return AlertDialog(
          title: const Text('Tu ruta AeroTech'),
          content: SizedBox(
            width: 650,
            child:
                (widget.routeBuilder ?? ((_, r) => RutaAeropuertos(ruta: r)))(
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
        );
      },
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

  String _dia(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

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
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('AeroTech · Vuelos'),
      actions: [
        if (widget.apiService.tieneSesion)
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
        if (!widget.apiService.tieneSesion)
          TextButton(
            onPressed: () async {
              if (await autenticarCompra(context, widget.apiService) &&
                  mounted) {
                await _cargar(inicial: true);
              }
            },
            child: const Text('Iniciar sesión'),
          ),
        if (widget.apiService.tieneSesion)
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () {
              widget.apiService.cerrarSesion();
              _cargar(inicial: true);
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
            style: TextStyle(
              fontFamily: 'AeroTechDisplay',
              fontFamilyFallback: const ['Times New Roman', 'serif'],
              fontSize: MediaQuery.sizeOf(context).width < 600 ? 42 : 58,
              height: 1.08,
              fontWeight: FontWeight.w400,
              letterSpacing: -1.8,
              color: AerotechTheme.navy,
            ),
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
                          setState(() {
                            _fecha = _dia(date);
                            _rango = null;
                          });
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
              OutlinedButton.icon(
                key: const ValueKey('filtro-rango-fechas'),
                onPressed: _busy
                    ? null
                    : () async {
                        final now = DateTime.now();
                        final range = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(now.year, now.month, now.day),
                          lastDate: DateTime(now.year + 2, 12, 31),
                          initialDateRange: _rango,
                          helpText: 'Salidas entre fechas',
                          confirmText: 'Aplicar rango',
                          saveText: 'Aplicar rango',
                          cancelText: 'Cancelar',
                          fieldStartLabelText: 'Desde',
                          fieldEndLabelText: 'Hasta',
                        );
                        if (range != null && mounted) {
                          setState(() {
                            _rango = range;
                            _fecha = null;
                          });
                        }
                      },
                icon: const Icon(Icons.date_range_outlined),
                label: Text(
                  _rango == null
                      ? 'Rango de fechas'
                      : '${_dia(_rango!.start)} → ${_dia(_rango!.end)}',
                ),
              ),
              if (_rango != null)
                IconButton(
                  tooltip: 'Quitar rango',
                  onPressed: () => setState(() => _rango = null),
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
              title: const Text('Pedidos pendientes · continuar con el pago'),
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
                    onAbandonado: () => _cargar(),
                  ),
              ],
            ),
          if (!_busy && _vuelos.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No hay vuelos para estos filtros.'),
            ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final columnas = constraints.maxWidth >= 1100
                  ? 3
                  : constraints.maxWidth >= 700
                  ? 2
                  : 1;
              final ancho =
                  (constraints.maxWidth - (columnas - 1) * 20) / columnas;
              return Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  for (final v in _vuelos)
                    SizedBox(
                      width: ancho,
                      child: TarjetaDestino(
                        vuelo: v,
                        onReservar: _busy ? null : () => _reservar(v),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}
