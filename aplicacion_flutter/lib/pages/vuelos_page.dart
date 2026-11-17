import 'package:flutter/material.dart';

import '../models/vuelo.dart';
import '../services/api_service.dart';
import '../theme/aerotech_theme.dart';
import '../widgets/reserva_visual_dialog.dart';
import 'admin_page.dart';
import 'login_page.dart';
import 'reservas_page.dart';

class VuelosPage extends StatefulWidget {
  const VuelosPage({super.key, required this.apiService});

  final ApiService apiService;

  @override
  State<VuelosPage> createState() => _VuelosPageState();
}

class _VuelosPageState extends State<VuelosPage> {
  final _origen = TextEditingController();
  final _destino = TextEditingController();
  List<Vuelo> _vuelos = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarVuelos();
  }

  @override
  void dispose() {
    _origen.dispose();
    _destino.dispose();
    super.dispose();
  }

  Future<void> _cargarVuelos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final vuelos = await widget.apiService.buscarVuelos(
        origen: _origen.text,
        destino: _destino.text,
      );
      if (!mounted) return;
      setState(() => _vuelos = vuelos);
    } on ExcepcionApi catch (error) {
      if (!mounted) return;
      setState(() => _error = error.mensaje);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo cargar la lista de vuelos.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _reservar(Vuelo vuelo) async {
    var disponibilidadAgotada = false;
    final mensaje = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReservaVisualDialog(
        vuelo: vuelo,
        onDisponibilidadAgotada: () => disponibilidadAgotada = true,
        onConfirm: (cantidad) async {
          final respuesta = await widget.apiService.reservarVuelo(
            vueloId: vuelo.id,
            cantidad: cantidad,
          );
          return respuesta['mensaje']?.toString() ?? 'Reserva confirmada.';
        },
      ),
    );
    if (!mounted) return;
    if (disponibilidadAgotada) {
      await _cargarVuelos();
      return;
    }
    if (mensaje == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
    await _cargarVuelos();
  }

  Future<void> _cerrarSesion() async {
    widget.apiService.cerrarSesion();
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => LoginPage(apiService: widget.apiService),
      ),
      (_) => false,
    );
  }

  bool _actualizandoPermisos = false;

  Future<void> _actualizarPermisos() async {
    if (_actualizandoPermisos) return;
    setState(() => _actualizandoPermisos = true);
    try {
      await widget.apiService.obtenerPerfil();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Permisos actualizados.')));
    } on ExcepcionApi catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.mensaje)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudieron actualizar los permisos.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _actualizandoPermisos = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AerotechTheme.background,
      appBar: AppBar(
        title: const Text('Buscar vuelos'),
        actions: [
          IconButton(
            onPressed: _actualizandoPermisos ? null : _actualizarPermisos,
            tooltip: 'Actualizar permisos',
            icon: const Icon(Icons.sync),
          ),
          if (widget.apiService.esAdministrador)
            IconButton(
              tooltip: 'Administración',
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AdminPage(apiService: widget.apiService),
                  ),
                );
                if (mounted) {
                  setState(() {});
                  await _cargarVuelos();
                }
              },
            ),
          IconButton(
            onPressed: _cerrarSesion,
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compacto = constraints.maxWidth < 640;
          return Column(
            children: [
              _panelBusqueda(compacto: compacto),
              Expanded(child: _contenido()),
            ],
          );
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.flight), label: 'Vuelos'),
          NavigationDestination(
            icon: Icon(Icons.bookmark_outline),
            label: 'Mis reservas',
          ),
        ],
        onDestinationSelected: (indice) {
          if (indice == 1) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => ReservasPage(apiService: widget.apiService),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _panelBusqueda({required bool compacto}) {
    final origen = TextField(
      controller: _origen,
      decoration: const InputDecoration(
        labelText: 'Origen',
        prefixIcon: Icon(Icons.flight_takeoff_rounded),
      ),
      textInputAction: TextInputAction.next,
    );
    final destino = TextField(
      controller: _destino,
      decoration: const InputDecoration(
        labelText: 'Destino',
        prefixIcon: Icon(Icons.flight_land_rounded),
      ),
      onSubmitted: (_) => _cargarVuelos(),
    );
    final buscar = SizedBox(
      height: 52,
      child: FilledButton.icon(
        onPressed: _cargando ? null : _cargarVuelos,
        icon: const Icon(Icons.search_rounded),
        label: const Text('Buscar'),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Card(
            color: AerotechTheme.surface,
            shape: AerotechTheme.cardShape,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: compacto
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        origen,
                        const SizedBox(height: 12),
                        destino,
                        const SizedBox(height: 12),
                        buscar,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: origen),
                        const SizedBox(width: 12),
                        Expanded(child: destino),
                        const SizedBox(width: 12),
                        buscar,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _contenido() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _cargarVuelos,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    if (_vuelos.isEmpty) {
      return const Center(child: Text('No hay vuelos para mostrar.'));
    }
    return RefreshIndicator(
      onRefresh: _cargarVuelos,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        itemCount: _vuelos.length,
        itemBuilder: (context, indice) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: _tarjetaVuelo(_vuelos[indice]),
          ),
        ),
      ),
    );
  }

  Widget _detalleVuelo(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: AerotechTheme.blue),
      const SizedBox(width: 7),
      Flexible(
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AerotechTheme.textSecondary,
          ),
        ),
      ),
    ],
  );

  Widget _tarjetaVuelo(Vuelo vuelo) {
    return Card(
      color: AerotechTheme.surface,
      shape: AerotechTheme.cardShape,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AerotechTheme.cyan.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.flight_rounded,
                    color: AerotechTheme.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${vuelo.origen} → ${vuelo.destino}',
                    style: const TextStyle(
                      color: AerotechTheme.navy,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'DESCUBRE TU PRÓXIMO DESTINO',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w800,
                color: AerotechTheme.blue,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _detalleVuelo(Icons.calendar_today_outlined, vuelo.fecha),
                _detalleVuelo(
                  Icons.schedule_rounded,
                  '${vuelo.horaSalida}${vuelo.horaLlegada.isEmpty ? '' : ' — ${vuelo.horaLlegada}'}',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AerotechTheme.inputFill,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'POR PASAJERO',
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 1,
                            color: AerotechTheme.textSecondary,
                          ),
                        ),
                        Text(
                          '\$${vuelo.precio.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                            color: AerotechTheme.navy,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: Text(
                      '${vuelo.asientosDisponibles} asientos disponibles',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        color: AerotechTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: vuelo.asientosDisponibles > 0
                    ? () => _reservar(vuelo)
                    : null,
                icon: const Icon(Icons.event_available_rounded),
                label: const Text('Reservar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
