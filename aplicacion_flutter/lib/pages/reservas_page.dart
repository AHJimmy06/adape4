import 'package:flutter/material.dart';

import '../models/reserva.dart';
import '../models/vuelo.dart';
import '../services/api_service.dart';
import '../theme/aerotech_theme.dart';
import '../utils/formateador_xml.dart';
import 'vuelos_page.dart';

class ReservasPage extends StatefulWidget {
  const ReservasPage({super.key, required this.apiService});

  final ApiService apiService;

  @override
  State<ReservasPage> createState() => _ReservasPageState();
}

class _ReservasPageState extends State<ReservasPage> {
  List<Reserva> _reservas = [];
  Map<String, Vuelo> _vuelos = {};
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarReservas();
  }

  Future<void> _cargarReservas() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final reservas = await widget.apiService.obtenerReservas();
      if (!mounted) return;
      setState(() {
        _reservas = reservas;
        _cargando = false;
      });
      if (reservas.any((reserva) => reserva.vuelo == null)) {
        // El catálogo complementa la presentación, nunca la reserva o sus acciones.
        try {
          final vuelos = await widget.apiService.buscarVuelos();
          if (!mounted) return;
          setState(
            () => _vuelos = {for (final vuelo in vuelos) vuelo.id: vuelo},
          );
        } catch (_) {
          // Las reservas siguen disponibles si el catálogo no responde.
        }
      }
    } on ExcepcionApi catch (error) {
      if (!mounted) return;
      setState(() => _error = error.mensaje);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudieron cargar tus reservas.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cancelar(Reserva reserva) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar reserva'),
        content: const Text('¿Quieres cancelar esta reserva?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar reserva'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await widget.apiService.cancelarReserva(reserva.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Reserva cancelada.')));
      await _cargarReservas();
    } on ExcepcionApi catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.mensaje)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo cancelar la reserva.')),
        );
      }
    }
  }

  Future<void> _verComprobanteXml(Reserva reserva) async {
    try {
      final xml = await widget.apiService.obtenerComprobanteXml(reserva.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          constraints: const BoxConstraints(maxWidth: 460),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          scrollable: true,
          title: const Text('Comprobante XML'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                formatearXml(xml),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } on ExcepcionApi catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.mensaje)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo cargar el comprobante XML.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AerotechTheme.background,
      appBar: AppBar(title: const Text('Mis reservas')),
      body: _contenido(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 1,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.flight), label: 'Vuelos'),
          NavigationDestination(
            icon: Icon(Icons.bookmark_outline),
            label: 'Mis reservas',
          ),
        ],
        onDestinationSelected: (indice) {
          if (indice == 0) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => VuelosPage(apiService: widget.apiService),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _cargarReservas,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }
    if (_reservas.isEmpty) {
      return const Center(child: Text('Todavía no tienes reservas.'));
    }
    return RefreshIndicator(
      onRefresh: _cargarReservas,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        itemCount: _reservas.length,
        itemBuilder: (context, indice) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: _tarjetaReserva(_reservas[indice]),
          ),
        ),
      ),
    );
  }

  Widget _tarjetaReserva(Reserva reserva) {
    final vuelo = reserva.vuelo ?? _vuelos[reserva.vueloId];
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
                    Icons.confirmation_num_outlined,
                    color: AerotechTheme.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    vuelo == null
                        ? 'Vuelo no disponible'
                        : '${vuelo.origen} → ${vuelo.destino}',
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
              'Reserva #${reserva.id} · ${reserva.estado}\n'
              '${reserva.cantidad} pasajero(s)\n'
              'Subtotal: \$${reserva.subtotal.toStringAsFixed(2)} · '
              'IVA (${reserva.porcentajeIva.toStringAsFixed(0)}%): '
              '\$${reserva.iva.toStringAsFixed(2)}\n'
              'Total: \$${reserva.total.toStringAsFixed(2)}',
              style: const TextStyle(
                color: AerotechTheme.textSecondary,
                height: 1.55,
              ),
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Ver comprobante XML',
                  onPressed: () => _verComprobanteXml(reserva),
                  icon: const Icon(Icons.description_outlined),
                  color: AerotechTheme.blue,
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Cancelar reserva',
                  onPressed: () => _cancelar(reserva),
                  icon: const Icon(Icons.cancel_outlined),
                  style: IconButton.styleFrom(
                    foregroundColor: AerotechTheme.navy,
                    backgroundColor: AerotechTheme.cyan.withValues(alpha: 0.16),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
