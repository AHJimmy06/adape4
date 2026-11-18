import 'package:flutter/material.dart';

import '../../../models/usuario.dart';
import '../../../services/api_service.dart';
import '../../../theme/aerotech_theme.dart';

/// Desactivar conserva la cuenta y sus compras; no elimina registros.
class BotonEstadoUsuario extends StatefulWidget {
  const BotonEstadoUsuario({
    super.key,
    required this.apiService,
    required this.usuario,
    required this.currentUserId,
    required this.onCambio,
    this.habilitado = true,
  });
  final ApiService apiService;
  final Usuario usuario;
  final String? currentUserId;
  final VoidCallback onCambio;
  final bool habilitado;

  @override
  State<BotonEstadoUsuario> createState() => _BotonEstadoUsuarioState();
}

class _BotonEstadoUsuarioState extends State<BotonEstadoUsuario> {
  bool _guardando = false;

  Future<void> _confirmar() async {
    if (_guardando ||
        !widget.habilitado ||
        widget.usuario.id == widget.currentUserId) {
      return;
    }
    final desactivar = widget.usuario.activo;
    var dialogBusy = false;
    String? error;
    final cambio = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (c, actualizar) => PopScope(
          canPop: !dialogBusy,
          child: AlertDialog(
            icon: Icon(
              desactivar ? Icons.person_off_outlined : Icons.person_outline,
              color: desactivar ? Colors.red.shade700 : AerotechTheme.blue,
            ),
            title: Text(desactivar ? 'Desactivar cuenta' : 'Reactivar cuenta'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.usuario.nombre,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(widget.usuario.correo),
                  const SizedBox(height: 16),
                  Text(
                    desactivar
                        ? 'No podrá iniciar sesión ni usar sus sesiones actuales. Sus reservas e historial se conservan.'
                        : 'Podrá volver a iniciar sesión. Las sesiones anteriores seguirán revocadas.',
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: TextStyle(color: Theme.of(c).colorScheme.error),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: dialogBusy ? null : () => Navigator.pop(c, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: desactivar
                    ? FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                      )
                    : null,
                onPressed: dialogBusy
                    ? null
                    : () async {
                        actualizar(() {
                          dialogBusy = true;
                          error = null;
                        });
                        setState(() => _guardando = true);
                        try {
                          await widget.apiService.cambiarEstadoUsuario(
                            widget.usuario.id,
                            !desactivar,
                          );
                          if (c.mounted) Navigator.pop(c, true);
                        } catch (e) {
                          if (c.mounted) {
                            actualizar(() {
                              dialogBusy = false;
                              error = e is ExcepcionApi
                                  ? e.mensaje
                                  : 'No se pudo cambiar el estado. Reintenta.';
                            });
                          }
                        } finally {
                          if (mounted) setState(() => _guardando = false);
                        }
                      },
                child: Text(
                  dialogBusy
                      ? 'Guardando…'
                      : desactivar
                      ? 'Confirmar desactivación'
                      : 'Confirmar reactivación',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (cambio == true && mounted) widget.onCambio();
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Chip(
        label: Text(widget.usuario.activo ? 'Activo' : 'Inactivo'),
        avatar: Icon(
          widget.usuario.activo
              ? Icons.check_circle_outline
              : Icons.person_off_outlined,
          size: 16,
        ),
      ),
      OutlinedButton.icon(
        key: ValueKey('estado_${widget.usuario.id}'),
        onPressed:
            _guardando ||
                !widget.habilitado ||
                widget.usuario.id == widget.currentUserId
            ? null
            : _confirmar,
        icon: Icon(
          widget.usuario.activo
              ? Icons.person_off_outlined
              : Icons.person_outline,
        ),
        label: Text(widget.usuario.activo ? 'Desactivar' : 'Reactivar'),
      ),
    ],
  );
}
