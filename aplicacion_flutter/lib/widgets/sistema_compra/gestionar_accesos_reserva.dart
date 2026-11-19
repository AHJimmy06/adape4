import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/sistema_api.dart';
import '../presentacion/dialogo_aerotech.dart';

class GestionarAccesosReserva extends StatefulWidget {
  const GestionarAccesosReserva({
    super.key,
    required this.api,
    required this.reservaId,
  });

  final SistemaApi api;
  final String reservaId;

  @override
  State<GestionarAccesosReserva> createState() =>
      _GestionarAccesosReservaState();
}

class _GestionarAccesosReservaState extends State<GestionarAccesosReserva> {
  final _correos = <String, TextEditingController>{};
  List<Map<String, dynamic>> _asientos = [];
  bool _busy = true, _vigente = false;
  String? _error, _mensaje;
  String get _ruta => '/reservas/${widget.reservaId}/accesos';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final controller in _correos.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _recibir(Map<String, dynamic> data) {
    final asientos = (data['asientos'] as List)
        .map((s) => Map<String, dynamic>.from(s as Map))
        .toList();
    for (final s in asientos) {
      _correos.putIfAbsent(
        s['codigo'].toString(),
        () => TextEditingController(),
      );
    }
    setState(() {
      _asientos = asientos;
      _vigente = true;
    });
  }

  Future<void> _cargar({String? aviso}) async {
    setState(() {
      _busy = true;
      _vigente = false;
      _error = aviso;
    });
    try {
      final data = await widget.api.get(_ruta);
      if (mounted) _recibir(data);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '${aviso == null ? '' : '$aviso\n'}$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _guardar(
    Map<String, dynamic> asiento, {
    bool retirar = false,
  }) async {
    if (_busy || !_vigente || asiento['editable'] != true) return;
    final codigo = asiento['codigo'].toString();
    final correo = _correos[codigo]!.text.trim();
    if (!retirar && correo.isEmpty) {
      setState(() => _error = 'Escribe el correo de una cuenta registrada.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _mensaje = null;
    });
    try {
      final data = await widget.api.post(
        _ruta,
        body: {
          'asiento': codigo,
          'correo': retirar ? null : correo,
          'version': asiento['version'],
        },
      );
      if (!mounted) return;
      _recibir(data);
      _correos[codigo]!.clear();
      setState(
        () => _mensaje = retirar
            ? 'Acceso retirado del asiento $codigo.'
            : 'Acceso actualizado para el asiento $codigo.',
      );
    } catch (e) {
      if (!mounted) return;
      if (e is ExcepcionApi && e.codigo == 409) {
        await _cargar(
          aviso:
              '$e\nRevisa los accesos actuales antes de volver a guardar. Si la actualización falla, pulsa Actualizar accesos.',
        );
      } else {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: DialogoAerotech(
      title: 'Gestionar accesos',
      subtitle: 'Asigna cada asiento a una cuenta registrada. Puedes cambiar o retirar su acceso sin modificar la compra ni el pasajero original.',
      icon: Icons.manage_accounts_outlined,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => _cargar(),
          child: const Text('Actualizar accesos'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) PanelMensaje(_error!, error: true),
          if (_mensaje != null) PanelMensaje(_mensaje!),
          if (!_busy && _vigente && _asientos.isEmpty)
            const Text('No hay asientos activos disponibles para gestionar.'),
          for (final s in _asientos)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Asiento ${s['codigo']} · ${s['clase_codigo']}'),
                    const SizedBox(height: 8),
                    Text(
                      s['usuario'] is Map
                          ? 'Acceso actual: ${s['usuario']['nombre']} · ${s['usuario']['correo']}'
                          : 'Sin acceso compartido',
                    ),
                    if (s['editable'] != true)
                      const Text(
                        'Este asiento ya no permite cambios de acceso.',
                      )
                    else ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _correos[s['codigo'].toString()],
                        enabled: !_busy && _vigente,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Correo de la cuenta registrada',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton(
                            onPressed: _busy || !_vigente
                                ? null
                                : () => _guardar(s),
                            child: Text(
                              s['usuario'] == null
                                  ? 'Asignar acceso'
                                  : 'Cambiar acceso',
                            ),
                          ),
                          if (s['usuario'] != null)
                            TextButton(
                              onPressed: _busy || !_vigente
                                  ? null
                                  : () => _guardar(s, retirar: true),
                              child: const Text('Retirar acceso'),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
