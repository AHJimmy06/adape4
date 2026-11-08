import 'package:flutter/material.dart';

import '../models/reserva.dart';
import '../services/api_service.dart';
import 'vuelos_page.dart';

class ReservasPage extends StatefulWidget {
  const ReservasPage({super.key, required this.apiService});

  final ApiService apiService;

  @override
  State<ReservasPage> createState() => _ReservasPageState();
}

class _ReservasPageState extends State<ReservasPage> {
  List<Reserva> _reservas = [];
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
      setState(() => _reservas = reservas);
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
          title: const Text('Comprobante XML'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: SingleChildScrollView(child: SelectableText(xml)),
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
        padding: const EdgeInsets.all(12),
        itemCount: _reservas.length,
        itemBuilder: (context, indice) => _tarjetaReserva(_reservas[indice]),
      ),
    );
  }

  Widget _tarjetaReserva(Reserva reserva) {
    final vuelo = reserva.vuelo;
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.confirmation_num_outlined),
        ),
        title: Text(
          vuelo == null
              ? 'Vuelo #${reserva.vueloId}'
              : '${vuelo.origen} → ${vuelo.destino}',
        ),
        subtitle: Text(
          'Reserva #${reserva.id} · ${reserva.estado}\n'
          '${reserva.cantidad} pasajero(s)\n'
          'Subtotal: \$${reserva.subtotal.toStringAsFixed(2)} · '
          'IVA (${reserva.porcentajeIva.toStringAsFixed(0)}%): '
          '\$${reserva.iva.toStringAsFixed(2)}\n'
          'Total: \$${reserva.total.toStringAsFixed(2)}',
        ),
        isThreeLine: true,
        trailing: Wrap(
          spacing: 0,
          children: [
            IconButton(
              tooltip: 'Ver comprobante XML',
              onPressed: () => _verComprobanteXml(reserva),
              icon: const Icon(Icons.description_outlined),
            ),
            IconButton(
              tooltip: 'Cancelar reserva',
              onPressed: () => _cancelar(reserva),
              icon: const Icon(Icons.cancel_outlined),
            ),
          ],
        ),
      ),
    );
  }
}
