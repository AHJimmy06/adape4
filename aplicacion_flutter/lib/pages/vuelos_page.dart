import 'package:flutter/material.dart';

import '../models/vuelo.dart';
import '../services/api_service.dart';
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
    try {
      final respuesta = await widget.apiService.reservarVuelo(
        vueloId: vuelo.id,
      );
      if (!mounted) return;
      final mensaje = respuesta['mensaje']?.toString() ?? 'Reserva confirmada.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensaje)));
      await _cargarVuelos();
    } on ExcepcionApi catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.mensaje)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo completar la reserva.')),
        );
      }
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buscar vuelos'),
        actions: [
          IconButton(
            onPressed: _cerrarSesion,
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _origen,
                    decoration: const InputDecoration(
                      labelText: 'Origen',
                      prefixIcon: Icon(Icons.flight_takeoff),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _destino,
                    decoration: const InputDecoration(
                      labelText: 'Destino',
                      prefixIcon: Icon(Icons.flight_land),
                    ),
                    onSubmitted: (_) => _cargarVuelos(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _cargando ? null : _cargarVuelos,
                  tooltip: 'Buscar',
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
          ),
          Expanded(child: _contenido()),
        ],
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
        padding: const EdgeInsets.all(12),
        itemCount: _vuelos.length,
        itemBuilder: (context, indice) => _tarjetaVuelo(_vuelos[indice]),
      ),
    );
  }

  Widget _tarjetaVuelo(Vuelo vuelo) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.flight)),
          title: Text('${vuelo.origen} → ${vuelo.destino}'),
          subtitle: Text(
            '${vuelo.fecha} · ${vuelo.horaSalida}'
            '${vuelo.horaLlegada.isEmpty ? '' : ' - ${vuelo.horaLlegada}'}\n'
            '\$${vuelo.precio.toStringAsFixed(2)} · '
            '${vuelo.asientosDisponibles} asientos disponibles',
          ),
          isThreeLine: true,
          trailing: FilledButton(
            onPressed: vuelo.asientosDisponibles > 0
                ? () => _reservar(vuelo)
                : null,
            child: const Text('Reservar'),
          ),
        ),
      ),
    );
  }
}
