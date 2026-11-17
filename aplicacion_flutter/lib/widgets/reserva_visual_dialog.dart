import 'package:flutter/material.dart';

import '../models/vuelo.dart';
import '../services/api_service.dart';
import '../theme/aerotech_theme.dart';
import 'cabina_asientos.dart';
import 'mapa_ruta_vuelo.dart';

class ReservaVisualDialog extends StatefulWidget {
  const ReservaVisualDialog({
    super.key,
    required this.vuelo,
    required this.onConfirm,
    this.onDisponibilidadAgotada,
  });
  final Vuelo vuelo;
  final Future<String> Function(int cantidad) onConfirm;
  final VoidCallback? onDisponibilidadAgotada;
  @override
  State<ReservaVisualDialog> createState() => _ReservaVisualDialogState();
}

class _ReservaVisualDialogState extends State<ReservaVisualDialog> {
  bool _cabin = false;
  bool _sending = false;
  bool _conflictoDisponibilidad = false;
  bool get _bloqueado => _sending || _conflictoDisponibilidad;
  final Set<String> _seats = {};
  int get _maxSeleccion => widget.vuelo.asientosDisponibles < 0
      ? 0
      : widget.vuelo.asientosDisponibles;

  void _toggleSeat(String seat) {
    if (_bloqueado) return;
    setState(() {
      if (!_seats.remove(seat) && _seats.length < _maxSeleccion) {
        _seats.add(seat);
      }
    });
  }

  String? _error;

  Future<void> _confirm() async {
    if (_bloqueado || _seats.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final message = await widget.onConfirm(_seats.length);
      if (mounted) Navigator.of(context).pop(message);
    } catch (error) {
      if (!mounted) return;
      if (error is ExcepcionApi &&
          error.codigoError == 'asientos_insuficientes') {
        setState(() {
          _sending = false;
          _conflictoDisponibilidad = true;
        });
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (contextoAviso) => PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('Asientos no disponibles'),
              content: const Text(
                'Ya no hay suficientes asientos disponibles para esta reserva. '
                'Otra persona pudo reservar antes. '
                'Al aceptar actualizaremos la disponibilidad.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(contextoAviso).pop(),
                  child: const Text('Aceptar'),
                ),
              ],
            ),
          ),
        );
        if (!mounted) return;
        widget.onDisponibilidadAgotada?.call();
        Navigator.of(context).pop();
        return;
      }
      if (mounted) {
        setState(() {
          _sending = false;
          _error = error is ExcepcionApi
              ? error.mensaje
              : 'No se pudo confirmar la reserva. Inténtalo nuevamente.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final flight = widget.vuelo;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return PopScope(
      canPop: !_bloqueado,
      child: Dialog(
        backgroundColor: AerotechTheme.background,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _cabin ? '02 / EXPLORA LA CABINA' : '01 / DESCUBRE TU RUTA',
                  style: const TextStyle(
                    color: AerotechTheme.blue,
                    fontSize: 11,
                    letterSpacing: 1.7,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _cabin
                      ? 'Tu lugar para imaginar el viaje'
                      : 'Tu próxima aventura',
                  style: const TextStyle(
                    fontSize: 25,
                    height: 1.12,
                    color: AerotechTheme.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${flight.origen} → ${flight.destino}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: AerotechTheme.navy,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${flight.fecha} · ${flight.horaSalida} · ${_seats.length} pasajero${_seats.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: AerotechTheme.textSecondary),
                ),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 750),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: child.key == const ValueKey('cabin') ? .15 : 1.6,
                        end: 1,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.center,
                    children: [...previousChildren, ?currentChild],
                  ),
                  child: _cabin
                      ? CabinaAsientos(
                          key: const ValueKey('cabin'),
                          selectedSeats: _seats,
                          maxSeleccion: _maxSeleccion,
                          enabled: !_bloqueado,
                          onToggle: _toggleSeat,
                        )
                      : MapaRutaVuelo(
                          key: const ValueKey('route'),
                          origen: flight.origen,
                          destino: flight.destino,
                        ),
                ),
                const SizedBox(height: 12),
                if (_cabin) ...[
                  Text(
                    _seats.isEmpty
                        ? 'Selecciona al menos un asiento'
                        : 'Asientos seleccionados (${_seats.length}): ${(_seats.toList()..sort()).join(', ')}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AerotechTheme.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Subtotal: USD ${(flight.precio * _seats.length).toStringAsFixed(2)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AerotechTheme.navy,
                    ),
                  ),
                ] else
                  const Text(
                    'Sigue la ruta y acércate al avión para explorar su interior. Todavía no se realizará ninguna reserva.',
                    style: TextStyle(
                      color: AerotechTheme.textSecondary,
                      height: 1.5,
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      semanticsLabel: _error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  key: const ValueKey('confirm-booking'),
                  onPressed: _bloqueado
                      ? null
                      : _cabin
                      ? (_seats.isEmpty ? null : _confirm)
                      : () => setState(() => _cabin = true),
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _cabin
                              ? Icons.check_circle_outline
                              : Icons.zoom_in_rounded,
                        ),
                  label: Text(
                    _conflictoDisponibilidad
                        ? 'Disponibilidad actualizada'
                        : _sending
                        ? 'Confirmando…'
                        : _cabin
                        ? 'Confirmar reserva'
                        : 'Continuar a la cabina',
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _bloqueado
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
